"""模块 A 数据审计。任一关键检查失败时，调用方必须停止在 MILP 之前。"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import pandas as pd

from config import Config
from data.build_allowed import build_allowed


@dataclass
class AuditResult:
    checks: pd.DataFrame
    details: dict[str, pd.DataFrame]

    @property
    def passed(self) -> bool:
        return bool(self.checks["passed"].all())


def _check(name: str, passed: bool, expected: str, actual: Any, impact: str) -> dict[str, Any]:
    return {"check": name, "passed": bool(passed), "expected": expected, "actual": str(actual), "impact_if_failed": impact}


def validate_data(data: dict[str, pd.DataFrame], cfg: Config) -> AuditResult:
    land, crop = data["land"], data["crop"]
    plant, statistics = data["plant_2023"], data["statistics_2023"]
    parameters, history = data["parameters"], data["history_2023"]
    allowed, demand, dispersal = data["allowed"], data["demand"], data["dispersal"]
    checks: list[dict[str, Any]] = []
    details: dict[str, pd.DataFrame] = {}

    # 以下面积由附件1逐行汇总得到；露天耕地四类合计为题面所述的 1201 亩。
    expected_area = {"平旱地": 365.0, "梯田": 619.0, "山坡地": 108.0, "水浇地": 109.0, "普通大棚": 9.6, "智慧大棚": 2.4}
    area_by_type = land.groupby("land_type", as_index=False)["area_mu"].sum().sort_values("land_type")
    observed_area = dict(zip(area_by_type["land_type"], area_by_type["area_mu"]))
    details["area_by_land_type"] = area_by_type
    checks.append(_check("地块数量", len(land) == 54, "54", len(land), "地块集合错误会改变模型维度。"))
    checks.append(_check("作物数量", len(crop) == 41, "41", len(crop), "作物集合错误会改变适宜性和决策变量。"))
    checks.append(_check("各地块类型面积", observed_area == expected_area, str(expected_area), observed_area, "面积容量约束可能错误。"))

    crop_conflicts = crop.groupby("crop_id").agg(crop_name_nunique=("crop_name", "nunique"), crop_type_nunique=("crop_type", "nunique")).reset_index()
    crop_conflicts = crop_conflicts.query("crop_name_nunique != 1 or crop_type_nunique != 1")
    details["crop_id_conflicts"] = crop_conflicts
    checks.append(_check("作物类别与编号一致性", crop_conflicts.empty and crop["crop_type"].notna().all(), "每个作物编号对应唯一名称和类别", f"冲突={len(crop_conflicts)}", "作物分类和豆类集合可能错误。"))

    duplicate_parameter_keys = parameters[parameters.duplicated(["crop_id", "land_type", "season"], keep=False)].sort_values(["crop_id", "land_type", "season"])
    details["duplicate_parameter_keys"] = duplicate_parameter_keys
    checks.append(_check("2023种植记录数", len(plant) == 87, "87", len(plant), "历史状态和需求基准可能不完整。"))
    checks.append(_check("原始参数记录数", len(statistics) == 107, "107", len(statistics), "附件参数表读取可能错误。"))
    checks.append(_check("参数编号键冲突", duplicate_parameter_keys.empty, "0 个重复(crop, land_type, season)键", len(duplicate_parameter_keys), "亩产、成本或价格可能存在歧义。"))

    unmatched_history = history[history[["land_type", "yield_jin_per_mu", "cost_yuan_per_mu", "price_mid"]].isna().any(axis=1)].copy()
    details["unmatched_history_parameters"] = unmatched_history
    checks.append(_check("所有2023记录匹配参数", unmatched_history.empty, "0 条未匹配", len(unmatched_history), "不能计算需求，必须停止。"))

    history_allowed = plant.merge(allowed[["plot_id", "crop_id", "season"]], on=["plot_id", "crop_id", "season"], how="left", indicator=True)
    historical_disallowed = history_allowed.query("_merge != 'both'").drop(columns="_merge")
    details["historical_disallowed"] = historical_disallowed
    checks.append(_check("2023历史种植适宜性", historical_disallowed.empty, "0 条 allowed=0 历史记录", len(historical_disallowed), "题面适宜性规则或历史编码存在冲突。"))

    capacity = history.groupby(["plot_id", "season"], as_index=False)["plant_area_mu"].sum().merge(land[["plot_id", "area_mu"]], on="plot_id", how="left")
    over_capacity = capacity[capacity["plant_area_mu"] > capacity["area_mu"] + 1e-9]
    details["plot_season_capacity"] = capacity
    details["over_capacity"] = over_capacity
    checks.append(_check("2023面积未超地块容量", over_capacity.empty, "0 个地块—季次超容量", len(over_capacity), "历史口径或数据存在冲突。"))

    price_valid = (statistics["price_low"] >= 0).all() and (statistics["price_high"] >= statistics["price_low"]).all() and statistics[["price_low", "price_high", "price_mid"]].notna().all().all()
    checks.append(_check("价格区间解析", price_valid, "107 条均为有效 low<=high 区间", f"有效={int(price_valid)}", "价格参数不能进入目标函数。"))
    checks.append(_check("需求计算", (demand["demand_jin"] > 0).all() and not demand.empty, "每个出现的作物—季次需求为正", f"组合数={len(demand)}，非正数={int((demand['demand_jin'] <= 0).sum())}", "销售上限无法构建。"))

    planted_ratios = (history["plant_area_mu"] / history["area_mu"]).dropna()
    ratio_min = float(planted_ratios.min()) if not planted_ratios.empty else float("nan")
    details["historical_area_ratios"] = history[["plot_id", "crop_id", "season", "plant_area_mu", "area_mu"]].assign(area_ratio=planted_ratios)
    checks.append(_check("beta=0.5历史证据", abs(ratio_min - cfg.beta) < 1e-9 and (planted_ratios >= cfg.beta - 1e-9).all(), "历史正种植面积比例最小值=0.5，且无值低于0.5", f"最小值={ratio_min:.6g}", "beta 管理参数缺乏已确认的数据证据。"))
    details["dispersal_2023"] = dispersal
    checks.append(_check("2023分散地块数已构建", not dispersal.empty, "输出作物—季次的历史分散地块数", f"组合数={len(dispersal)}", "Nmax 的审计基线缺失。"))

    allowed_key = allowed[["land_type", "crop_id", "season"]].drop_duplicates()
    parameter_key = parameters[["land_type", "crop_id", "season"]].drop_duplicates()
    missing_allowed_parameters = allowed_key.merge(parameter_key, on=["land_type", "crop_id", "season"], how="left", indicator=True).query("_merge != 'both'").drop(columns="_merge")
    details["allowed_without_parameters"] = missing_allowed_parameters
    checks.append(_check("所有allowed组合均有参数", missing_allowed_parameters.empty, "0 个 allowed=1 组合缺亩产/成本/价格参数", len(missing_allowed_parameters), "合法决策变量没有完整经济参数。"))

    return AuditResult(checks=pd.DataFrame(checks), details=details)

