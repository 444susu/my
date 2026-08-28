"""根据题面和实现指南第 8 节构建适宜性矩阵。"""

from __future__ import annotations

import pandas as pd


GRAIN_CROPS = set(range(1, 16))
RICE_CROPS = {16}
FIRST_SEASON_VEGETABLES = set(range(17, 35))
SECOND_SEASON_WATER_VEGETABLES = set(range(35, 38))
MUSHROOM_CROPS = set(range(38, 42))
BEAN_CROPS = {1, 2, 3, 4, 5, 17, 18, 19}


def allowed_crop_ids(land_type: str, season: str) -> set[int]:
    """返回一个地块类型、季次下题面允许种植的作物编号。"""
    if land_type in {"平旱地", "梯田", "山坡地"} and season == "单季":
        return GRAIN_CROPS
    if land_type == "水浇地":
        if season == "单季":
            return RICE_CROPS
        if season == "第一季":
            return FIRST_SEASON_VEGETABLES
        if season == "第二季":
            return SECOND_SEASON_WATER_VEGETABLES
    if land_type == "普通大棚":
        if season == "第一季":
            return FIRST_SEASON_VEGETABLES
        if season == "第二季":
            return MUSHROOM_CROPS
    if land_type == "智慧大棚" and season in {"第一季", "第二季"}:
        return FIRST_SEASON_VEGETABLES
    return set()


def build_allowed(land: pd.DataFrame, seasons: tuple[str, ...]) -> pd.DataFrame:
    """以地块—作物—季次为行，显式给出 allowed=1 的组合。"""
    rows: list[dict[str, object]] = []
    for land_row in land.itertuples(index=False):
        for season in seasons:
            for crop_id in sorted(allowed_crop_ids(land_row.land_type, season)):
                rows.append({
                    "plot_id": land_row.plot_id,
                    "land_type": land_row.land_type,
                    "crop_id": crop_id,
                    "season": season,
                    "allowed": 1,
                })
    return pd.DataFrame(rows)

