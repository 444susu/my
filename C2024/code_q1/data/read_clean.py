"""读取附件 1、附件 2，并执行已确认的机械性清洗。"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import pandas as pd

from config import Config


LAND_SHEET = "乡村的现有耕地"
CROP_SHEET = "乡村种植的农作物"
PLANT_SHEET = "2023年的农作物种植情况"
STAT_SHEET = "2023年统计的相关数据"


@dataclass
class RawData:
    land: pd.DataFrame
    crop: pd.DataFrame
    plant_2023: pd.DataFrame
    statistics_2023: pd.DataFrame


@dataclass
class CleanData(RawData):
    cleaning_log: list[dict[str, Any]]
    raw_row_counts: dict[str, int]


def _strip_text(frame: pd.DataFrame) -> pd.DataFrame:
    result = frame.copy()
    for column in result.select_dtypes(include="object").columns:
        result[column] = result[column].map(
            lambda value: value.strip() if isinstance(value, str) else value
        )
    return result


def read_raw_excel(cfg: Config) -> RawData:
    """原始附件只读；sheet 名与题目附件一一对应。"""
    return RawData(
        land=pd.read_excel(cfg.attachment_1, sheet_name=LAND_SHEET),
        crop=pd.read_excel(cfg.attachment_1, sheet_name=CROP_SHEET),
        plant_2023=pd.read_excel(cfg.attachment_2, sheet_name=PLANT_SHEET),
        statistics_2023=pd.read_excel(cfg.attachment_2, sheet_name=STAT_SHEET),
    )


def _parse_price_interval(value: object) -> tuple[float, float, float]:
    """将题目已确认的价格区间解析为下界、上界和中点。"""
    if not isinstance(value, str):
        raise ValueError(f"销售单价不是字符串区间：{value!r}")
    normalized = value.replace("—", "-").replace("–", "-").strip()
    pieces = [piece.strip() for piece in normalized.split("-")]
    if len(pieces) != 2:
        raise ValueError(f"销售单价区间无法解析：{value!r}")
    low, high = map(float, pieces)
    if low < 0 or high < low:
        raise ValueError(f"销售单价区间不合法：{value!r}")
    return low, high, (low + high) / 2


def clean_data(raw: RawData, cfg: Config) -> CleanData:
    """只执行指南 3.2 明确列出的机械性清洗，所有影响均记录。"""
    log: list[dict[str, Any]] = []
    raw_row_counts = {
        "land": len(raw.land),
        "crop": len(raw.crop),
        "plant_2023": len(raw.plant_2023),
        "statistics_2023": len(raw.statistics_2023),
    }

    land = _strip_text(raw.land).rename(
        columns={"地块名称": "plot_id", "地块类型": "land_type", "地块面积/亩": "area_mu"}
    )[["plot_id", "land_type", "area_mu"]]
    land["area_mu"] = pd.to_numeric(land["area_mu"], errors="coerce")

    crop_source = _strip_text(raw.crop).rename(
        columns={"作物编号": "crop_id", "作物名称": "crop_name", "作物类型": "crop_type"}
    )
    crop_source["crop_id"] = pd.to_numeric(crop_source["crop_id"], errors="coerce")
    crop_mask = crop_source["crop_id"].notna()
    log.append({
        "step": "剔除附件1作物表中的说明/空白行",
        "affected_rows": int((~crop_mask).sum()),
        "rule": "仅保留具有数值作物编号的记录；被剔除行均为附件说明或空白行。",
    })
    crop = crop_source.loc[crop_mask, ["crop_id", "crop_name", "crop_type"]].copy()
    crop["crop_id"] = crop["crop_id"].astype(int)
    crop["crop_type"] = crop["crop_type"].ffill()

    plant = _strip_text(raw.plant_2023).rename(
        columns={
            "种植地块": "plot_id", "作物编号": "crop_id", "作物名称": "crop_name",
            "作物类型": "crop_type", "种植面积/亩": "plant_area_mu", "种植季次": "season",
        }
    )
    fill_count = int(plant["plot_id"].isna().sum())
    plant["plot_id"] = plant["plot_id"].ffill()
    plant["crop_id"] = pd.to_numeric(plant["crop_id"], errors="coerce")
    plant["plant_area_mu"] = pd.to_numeric(plant["plant_area_mu"], errors="coerce")
    log.append({
        "step": "填充2023种植表合并单元格地块名",
        "affected_rows": fill_count,
        "rule": "按附件中的连续合并单元格，使用上一条有效地块名向下填充。",
    })

    stat_source = _strip_text(raw.statistics_2023).rename(
        columns={
            "序号": "row_id", "作物编号": "crop_id", "作物名称": "crop_name",
            "地块类型": "land_type", "种植季次": "season", "亩产量/斤": "yield_jin_per_mu",
            "种植成本/(元/亩)": "cost_yuan_per_mu", "销售单价/(元/斤)": "price_interval",
        }
    )
    stat_source["crop_id"] = pd.to_numeric(stat_source["crop_id"], errors="coerce")
    stat_mask = stat_source["crop_id"].notna()
    log.append({
        "step": "剔除附件2统计表中的说明/空白行",
        "affected_rows": int((~stat_mask).sum()),
        "rule": "仅保留具有数值作物编号的统计参数记录；被剔除行均为附件说明或空白行。",
    })
    statistics = stat_source.loc[
        stat_mask,
        ["crop_id", "crop_name", "land_type", "season", "yield_jin_per_mu", "cost_yuan_per_mu", "price_interval"],
    ].copy()
    statistics["crop_id"] = statistics["crop_id"].astype(int)
    for column in ["yield_jin_per_mu", "cost_yuan_per_mu"]:
        statistics[column] = pd.to_numeric(statistics[column], errors="coerce")

    parsed = statistics["price_interval"].map(_parse_price_interval)
    statistics[["price_low", "price_high", "price_mid"]] = pd.DataFrame(
        parsed.tolist(), index=statistics.index
    )
    log.append({
        "step": "解析销售价格区间",
        "affected_rows": len(statistics),
        "rule": "将 low-high 拆为下界、上界，并按已确认口径计算价格中点。",
    })

    return CleanData(
        land=land,
        crop=crop,
        plant_2023=plant,
        statistics_2023=statistics,
        cleaning_log=log,
        raw_row_counts=raw_row_counts,
    )

