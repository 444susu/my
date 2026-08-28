"""构建 2023 历史状态和问题 1 的需求基准。"""

from __future__ import annotations

import pandas as pd


def build_history_and_demand(
    plant_2023: pd.DataFrame, land: pd.DataFrame, parameters: pd.DataFrame
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """用作物+地块类型+季次的实际亩产量计算各季预期销售量。"""
    history = plant_2023.merge(
        land[["plot_id", "land_type", "area_mu"]], on="plot_id", how="left", validate="many_to_one"
    )
    parameter_columns = ["crop_id", "land_type", "season", "yield_jin_per_mu", "cost_yuan_per_mu", "price_mid"]
    history = history.merge(
        parameters[parameter_columns], on=["crop_id", "land_type", "season"], how="left", validate="many_to_one"
    )
    history["production_jin"] = history["plant_area_mu"] * history["yield_jin_per_mu"]
    demand = (
        history.groupby(["crop_id", "season"], as_index=False)["production_jin"]
        .sum()
        .rename(columns={"production_jin": "demand_jin"})
    )
    dispersal = (
        history.groupby(["crop_id", "season"], as_index=False)["plot_id"]
        .nunique()
        .rename(columns={"plot_id": "plot_count_2023"})
    )
    return history, demand, dispersal

