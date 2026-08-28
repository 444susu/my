"""构建 2023 历史状态和问题 1 的需求基准。"""

from __future__ import annotations

import pandas as pd

from data.build_allowed import BEAN_CROPS


def build_history_and_demand(
    plant_2023: pd.DataFrame, land: pd.DataFrame, parameters: pd.DataFrame, allowed: pd.DataFrame
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """构建需求基准、历史0-1状态、豆类状态和2023—2024邻接基础。"""
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

    # 仅在题面允许的地块—作物—季次键上构造完整的 0/1 历史状态。
    planted_keys = plant_2023.groupby(["plot_id", "crop_id", "season"], as_index=False).size()
    planted_keys["history_z_2023"] = 1
    history_z = allowed[["plot_id", "land_type", "crop_id", "season"]].merge(
        planted_keys[["plot_id", "crop_id", "season", "history_z_2023"]],
        on=["plot_id", "crop_id", "season"],
        how="left",
        validate="one_to_one",
    )
    history_z["history_z_2023"] = history_z["history_z_2023"].fillna(0).astype(int)

    bean_status = (
        history_z.assign(is_bean=history_z["crop_id"].isin(BEAN_CROPS))
        .query("is_bean")
        .groupby("plot_id", as_index=False)["history_z_2023"]
        .max()
        .rename(columns={"history_z_2023": "history_bean_2023"})
    )
    history_bean = land[["plot_id", "land_type"]].merge(bean_status, on="plot_id", how="left", validate="one_to_one")
    history_bean["history_bean_2023"] = history_bean["history_bean_2023"].fillna(0).astype(int)

    # 保存每块地在2023年的最后实际季次；水浇地2024首季由后续模式变量决定，保留两种合法衔接。
    season_rank = {"单季": 1, "第一季": 1, "第二季": 2}
    observed_seasons = history[["plot_id", "season"]].drop_duplicates().assign(rank=lambda x: x["season"].map(season_rank))
    last_observed = observed_seasons.sort_values(["plot_id", "rank"]).groupby("plot_id", as_index=False).tail(1).drop(columns="rank")
    adjacency = land[["plot_id", "land_type"]].merge(last_observed, on="plot_id", how="left", validate="one_to_one").rename(columns={"season": "last_season_2023"})
    adjacency["next_season_2024"] = adjacency["land_type"].map({
        "平旱地": "单季", "梯田": "单季", "山坡地": "单季",
        "普通大棚": "第一季", "智慧大棚": "第一季", "水浇地": "单季|第一季",
    })
    adjacency["adjacency_scope"] = "2023历史末季→2024首个决策季"
    return history, demand, dispersal, history_z, history_bean, adjacency

