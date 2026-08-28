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


def _check(name: str, passed: bool, expected: str, actual: Any, impact: str, status: str = "PASS") -> dict[str, Any]:
    return {"check": name, "passed": bool(passed), "expected": expected, "actual": str(actual), "impact_if_failed": impact, "status": status}


def validate_data(data: dict[str, pd.DataFrame], cfg: Config) -> AuditResult:
    land, crop = data["land"], data["crop"]
    plant, statistics = data["plant_2023"], data["statistics_2023"]
    parameters, history = data["parameters"], data["history_2023"]
    allowed, demand, dispersal = data["allowed"], data["demand"], data["dispersal"]
    history_z, history_bean, adjacency = data["history_z_2023"], data["history_bean_2023"], data["adjacency_2023_to_2024"]
    checks: list[dict[str, Any]] = []
    details: dict[str, pd.DataFrame] = {}

    # 以下面积由附件1逐行汇总得到；露天耕地四类合计为题面所述的 1201 亩。
    expected_area = {"平旱地": 365.0, "梯田": 619.0, "山坡地": 108.0, "水浇地": 109.0, "普通大棚": 9.6, "智慧大棚": 2.4}
    area_by_type = land.groupby("land_type", as_index=False)["area_mu"].sum().sort_values("land_type")
    observed_area = dict(zip(area_by_type["land_type"], area_by_type["area_mu"]))
    details["area_by_land_type"] = area_by_type
    checks.append(_check("地块数量", len(land) == 54, "54", len(land), "地块集合错误会改变模型维度。"))
    valid_land_types = {"平旱地", "梯田", "山坡地", "水浇地", "普通大棚", "智慧大棚"}
    checks.append(_check("地块ID唯一且非空", land["plot_id"].notna().all() and land["plot_id"].nunique() == 54, "54个唯一、非空地块ID", f"非空={int(land['plot_id'].notna().sum())}，唯一={land['plot_id'].nunique()}", "地块索引会错误合并。"))
    checks.append(_check("地块面积与类型合法", (land["area_mu"] > 0).all() and set(land["land_type"]) <= valid_land_types, "面积>0，且仅六种题面地块类型", f"非正面积={int((land['area_mu'] <= 0).sum())}，非法类型={sorted(set(land['land_type']) - valid_land_types)}", "容量或适宜性约束不可用。"))
    checks.append(_check("作物数量", len(crop) == 41, "41", len(crop), "作物集合错误会改变适宜性和决策变量。"))
    crop_id_complete = set(crop["crop_id"]) == set(range(1, 42)) and crop["crop_id"].nunique() == 41
    checks.append(_check("作物编号集合完整", crop_id_complete, "编号1—41各一次", f"唯一数={crop['crop_id'].nunique()}，缺失={sorted(set(range(1,42)) - set(crop['crop_id']))}", "作物集合或固定豆类集合可能错误。"))
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

    positive_z = history_z.query("history_z_2023 == 1")
    expected_positive = plant[["plot_id", "crop_id", "season"]].drop_duplicates()
    state_complete = len(history_z) == len(allowed) and set(history_z["history_z_2023"]) <= {0, 1} and len(positive_z) == len(expected_positive)
    details["history_z_2023"] = history_z
    checks.append(_check("2023历史0-1种植状态", state_complete, "所有allowed键有0/1状态，87个历史正种植键", f"状态键={len(history_z)}，正状态={len(positive_z)}", "无法可靠建立2023→2024重茬边界。"))

    bean_state_complete = len(history_bean) == 54 and history_bean["plot_id"].nunique() == 54 and set(history_bean["history_bean_2023"]) <= {0, 1}
    details["history_bean_2023"] = history_bean
    checks.append(_check("2023地块豆类历史状态", bean_state_complete, "54个地块均有0/1豆类状态", f"记录={len(history_bean)}，种过豆类={int(history_bean['history_bean_2023'].sum())}", "第一个三年豆类窗口无法构建。"))

    valid_last_seasons = adjacency["last_season_2023"].isin({"单季", "第一季", "第二季"})
    adjacency_complete = len(adjacency) == 54 and adjacency["plot_id"].nunique() == 54 and valid_last_seasons.all() and adjacency["next_season_2024"].notna().all()
    details["adjacency_2023_to_2024"] = adjacency
    checks.append(_check("2023—2024历史邻接基础", adjacency_complete, "54块地均有最后实际季次及2024首季衔接", f"记录={len(adjacency)}，无最后季次={int(adjacency['last_season_2023'].isna().sum())}", "重茬约束无法按真实时间链构建。"))
    last_season_rules = {
        "平旱地": {"单季"}, "梯田": {"单季"}, "山坡地": {"单季"},
        "普通大棚": {"第二季"}, "智慧大棚": {"第二季"}, "水浇地": {"单季", "第二季"},
    }
    adjacency_consistency = adjacency.copy()
    adjacency_consistency["allowed_last_seasons"] = adjacency_consistency["land_type"].map(lambda x: "|".join(sorted(last_season_rules[x])))
    adjacency_consistency["consistent"] = adjacency_consistency.apply(
        lambda row: row["last_season_2023"] in last_season_rules[row["land_type"]], axis=1
    )
    adjacency_inconsistent = adjacency_consistency[~adjacency_consistency["consistent"]]
    details["adjacency_consistency"] = adjacency_consistency
    details["adjacency_inconsistent"] = adjacency_inconsistent
    checks.append(_check("2023最后实际季次与地块制度一致", adjacency_inconsistent.empty, "旱地/梯田/山坡地=单季；两类大棚=第二季；水浇地=单季或第二季", f"异常地块={len(adjacency_inconsistent)}", "历史时间链与种植制度不一致，不能建立重茬边界。"))

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
    demand_crops_complete = set(demand["crop_id"]) == set(range(1, 42))
    historical_demand = demand[demand["demand_source"] == "2023实际产量"]
    historical_demand_valid = not historical_demand.empty and (historical_demand["demand_jin"] > 0).all()
    checks.append(_check("需求计算", (demand["demand_jin"] >= 0).all() and not demand.empty and demand_crops_complete and historical_demand_valid, "41种作物均被覆盖；2023实际种植组合需求为正", f"组合数={len(demand)}，覆盖作物={demand['crop_id'].nunique()}，负需求={int((demand['demand_jin'] < 0).sum())}", "销售上限无法构建。"))
    demand_support = demand[["crop_id", "season"]].drop_duplicates()
    allowed_support = allowed[["crop_id", "season"]].drop_duplicates()
    zero_demand = demand[demand["demand_source"] == "2023未种植，按已确认口径置0"].copy()
    support_complete = (
        set(map(tuple, demand_support.to_numpy())) == set(map(tuple, allowed_support.to_numpy()))
        and len(demand_support) == len(demand)
        and (zero_demand["demand_jin"] == 0).all()
        and historical_demand_valid
    )
    details["demand_zero_support"] = zero_demand
    details["demand_support"] = demand
    checks.append(_check("未来可种植作物—季次需求support完整", support_complete, "需求键集=allowed键集；实际种植需求>0，未种植需求=0", f"support={len(demand_support)}，正需求={len(historical_demand)}，零需求={len(zero_demand)}", "q/e产量守恒和销售上限无法覆盖全部未来合法生产组合。"))

    planted_ratios = (history["plant_area_mu"] / history["area_mu"]).dropna()
    ratio_min = float(planted_ratios.min()) if not planted_ratios.empty else float("nan")
    details["historical_area_ratios"] = history[["plot_id", "crop_id", "season", "plant_area_mu", "area_mu"]].assign(area_ratio=planted_ratios)
    checks.append(_check("beta=0.5历史证据", abs(ratio_min - cfg.beta) < 1e-9 and (planted_ratios >= cfg.beta - 1e-9).all(), "历史正种植面积比例最小值=0.5，且无值低于0.5", f"最小值={ratio_min:.6g}", "beta 管理参数缺乏已确认的数据证据。"))
    details["dispersal_2023"] = dispersal
    checks.append(_check("2023分散地块数已构建", not dispersal.empty, "输出作物—季次的历史分散地块数", f"组合数={len(dispersal)}", "Nmax 的审计基线缺失。"))
    nmax_conflicts = dispersal[dispersal["plot_count_2023"] > cfg.nmax].sort_values(["plot_count_2023", "crop_id"], ascending=[False, True])
    details["nmax_historical_conflicts"] = nmax_conflicts
    checks.append(_check("Nmax=3与历史分散度比较", True, "识别历史分散度超过3块的组合，并保留Nmax=3", f"超过Nmax的组合={len(nmax_conflicts)}；{nmax_conflicts.to_dict('records')}", "异常但不改变模型方向：Nmax=3比部分2023实际经营更严格，后续必须重点做Nmax敏感性分析。", status="WARNING" if not nmax_conflicts.empty else "PASS"))

    allowed_key = allowed[["land_type", "crop_id", "season"]].drop_duplicates()
    parameter_values = parameters[["land_type", "crop_id", "season", "yield_jin_per_mu", "cost_yuan_per_mu", "price_mid", "parameter_source"]]
    allowed_parameters = allowed_key.merge(parameter_values, on=["land_type", "crop_id", "season"], how="left", validate="one_to_one")
    invalid_allowed_parameters = allowed_parameters[
        allowed_parameters[["yield_jin_per_mu", "cost_yuan_per_mu", "price_mid"]].isna().any(axis=1)
        | (allowed_parameters["yield_jin_per_mu"] <= 0)
        | (allowed_parameters["cost_yuan_per_mu"] < 0)
        | (allowed_parameters["price_mid"] <= 0)
    ]
    details["allowed_parameter_values"] = allowed_parameters
    details["allowed_invalid_parameters"] = invalid_allowed_parameters
    checks.append(_check("所有allowed组合的参数值合法", invalid_allowed_parameters.empty, "每个allowed组合：yield>0、cost>=0、price>0", f"allowed组合={len(allowed_parameters)}，非法参数={len(invalid_allowed_parameters)}", "合法决策变量没有完整有效的经济参数。"))
    price_consistency = (
        allowed_parameters.groupby(["crop_id", "season"], as_index=False)
        .agg(land_type_count=("land_type", "nunique"), price_mid_nunique=("price_mid", "nunique"), price_mid_values=("price_mid", lambda values: "|".join(map(str, sorted(set(values))))))
    )
    price_dimension_conflicts = price_consistency[price_consistency["price_mid_nunique"] != 1]
    details["price_by_crop_season"] = price_consistency
    details["price_dimension_conflicts"] = price_dimension_conflicts
    checks.append(_check("作物—季次销售价格可安全降维", price_dimension_conflicts.empty, "每个(crop_id, season)的price_mid唯一", f"组合={len(price_consistency)}，多价格组合={len(price_dimension_conflicts)}", "q/e按作物—年—季汇总时收入会失真，必须重定销售变量维度。"))

    return AuditResult(checks=pd.DataFrame(checks), details=details)

