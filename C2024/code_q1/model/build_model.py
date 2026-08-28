"""问题 1 的稀疏 MILP：变量、约束和目标函数。"""

from __future__ import annotations

from collections import defaultdict
from typing import Any

import gurobipy as gp
from gurobipy import GRB

from config import Config
from data.build_allowed import BEAN_CROPS


def _add_rotation_constraints(model: gp.Model, z: gp.tupledict, data: dict[str, Any], cfg: Config) -> tuple[list[dict[str, Any]], int]:
    """以真实季次链建立仅对相同作物生效的相邻重茬约束。"""
    land = data["land"]
    history_z = data["history_z_2023"]
    adjacency = data["adjacency_2023_to_2024"].set_index("plot_id")
    allowed = data["allowed"]
    allowed_sets = {
        (plot_id, season): set(group["crop_id"])
        for (plot_id, season), group in allowed.groupby(["plot_id", "season"])
    }
    history_positive = {
        (row.plot_id, row.crop_id, row.season)
        for row in history_z.query("history_z_2023 == 1").itertuples(index=False)
    }
    pairs: list[dict[str, Any]] = []
    count = 0

    def add_history_to_future(plot_id: str, historical_season: str, future_season: str) -> None:
        nonlocal count
        common = allowed_sets.get((plot_id, historical_season), set()) & allowed_sets.get((plot_id, future_season), set())
        for crop_id in common:
            if (plot_id, crop_id, historical_season) in history_positive:
                model.addConstr(z[plot_id, crop_id, 2024, future_season] <= 0, name=f"rotation_hist[{plot_id},{crop_id},{historical_season},{future_season}]")
                count += 1
                pairs.append({"plot_id": plot_id, "crop_id": crop_id, "from": f"2023-{historical_season}", "to": f"2024-{future_season}", "source": "history"})

    def add_future_pair(plot_id: str, year: int, from_season: str, next_year: int, to_season: str) -> None:
        nonlocal count
        common = allowed_sets.get((plot_id, from_season), set()) & allowed_sets.get((plot_id, to_season), set())
        for crop_id in common:
            model.addConstr(z[plot_id, crop_id, year, from_season] + z[plot_id, crop_id, next_year, to_season] <= 1, name=f"rotation[{plot_id},{crop_id},{year},{from_season},{next_year},{to_season}]")
            count += 1
            pairs.append({"plot_id": plot_id, "crop_id": crop_id, "from": f"{year}-{from_season}", "to": f"{next_year}-{to_season}", "source": "future"})

    for land_row in land.itertuples(index=False):
        plot_id, land_type = land_row.plot_id, land_row.land_type
        historical_last = adjacency.loc[plot_id, "last_season_2023"]
        if land_type in {"平旱地", "梯田", "山坡地"}:
            add_history_to_future(plot_id, historical_last, "单季")
            for year in cfg.years[:-1]:
                add_future_pair(plot_id, year, "单季", year + 1, "单季")
        elif land_type in {"普通大棚", "智慧大棚"}:
            add_history_to_future(plot_id, historical_last, "第一季")
            for year in cfg.years:
                add_future_pair(plot_id, year, "第一季", year, "第二季")
            for year in cfg.years[:-1]:
                add_future_pair(plot_id, year, "第二季", year + 1, "第一季")
        else:  # 水浇地：水稻单季可跨年连续；蔬菜两季的作物编号集合彼此不交叉。
            add_history_to_future(plot_id, historical_last, "单季")
            add_history_to_future(plot_id, historical_last, "第一季")
            for year in cfg.years[:-1]:
                add_future_pair(plot_id, year, "单季", year + 1, "单季")
    return pairs, count


def build_model(data: dict[str, Any], cfg: Config, alpha: float) -> tuple[gp.Model, dict[str, Any], dict[str, Any]]:
    """建立已获批准的确定性单目标 MILP；不在此函数中求解。"""
    model = gp.Model(f"C2024_Q1_alpha_{alpha:g}")
    land, allowed, parameters, demand = data["land"], data["allowed"], data["parameters"], data["demand"]
    land_area = dict(zip(land["plot_id"], land["area_mu"]))
    land_type = dict(zip(land["plot_id"], land["land_type"]))
    allowed_keys = [(row.plot_id, int(row.crop_id), row.season) for row in allowed.itertuples(index=False)]
    x_keys = [(plot_id, crop_id, year, season) for plot_id, crop_id, season in allowed_keys for year in cfg.years]
    demand_keys = [(int(row.crop_id), row.season) for row in demand.itertuples(index=False)]
    q_keys = [(crop_id, year, season) for crop_id, season in demand_keys for year in cfg.years]
    water_plots = land.loc[land["land_type"] == "水浇地", "plot_id"].tolist()

    x = model.addVars(x_keys, lb=0.0, vtype=GRB.CONTINUOUS, name="x")
    z = model.addVars(x_keys, vtype=GRB.BINARY, name="z")
    q = model.addVars(q_keys, lb=0.0, vtype=GRB.CONTINUOUS, name="q")
    e = model.addVars(q_keys, lb=0.0, vtype=GRB.CONTINUOUS, name="e")
    r = model.addVars([(plot_id, year) for plot_id in water_plots for year in cfg.years], vtype=GRB.BINARY, name="r")
    constraints: dict[str, int] = defaultdict(int)

    for plot_id, crop_id, year, season in x_keys:
        model.addConstr(x[plot_id, crop_id, year, season] >= cfg.beta * land_area[plot_id] * z[plot_id, crop_id, year, season], name=f"link_lb[{plot_id},{crop_id},{year},{season}]")
        model.addConstr(x[plot_id, crop_id, year, season] <= land_area[plot_id] * z[plot_id, crop_id, year, season], name=f"link_ub[{plot_id},{crop_id},{year},{season}]")
        constraints["x_z_link"] += 2

    keys_by_plot_year_season: dict[tuple[str, int, str], list[tuple[str, int, int, str]]] = defaultdict(list)
    keys_by_crop_year_season: dict[tuple[int, int, str], list[tuple[str, int, int, str]]] = defaultdict(list)
    for key in x_keys:
        plot_id, crop_id, year, season = key
        keys_by_plot_year_season[plot_id, year, season].append(key)
        keys_by_crop_year_season[crop_id, year, season].append(key)
    for (plot_id, year, season), keys in keys_by_plot_year_season.items():
        model.addConstr(gp.quicksum(x[key] for key in keys) <= land_area[plot_id], name=f"capacity[{plot_id},{year},{season}]")
        constraints["land_capacity"] += 1

    for plot_id in water_plots:
        for year in cfg.years:
            rice_key = (plot_id, 16, year, "单季")
            first_keys = [(plot_id, crop_id, year, "第一季") for crop_id in range(17, 35)]
            second_keys = [(plot_id, crop_id, year, "第二季") for crop_id in range(35, 38)]
            model.addConstr(x[rice_key] <= land_area[plot_id] * r[plot_id, year], name=f"water_rice_mode[{plot_id},{year}]")
            model.addConstr(gp.quicksum(x[key] for key in first_keys) <= land_area[plot_id] * (1 - r[plot_id, year]), name=f"water_first_mode[{plot_id},{year}]")
            model.addConstr(gp.quicksum(x[key] for key in second_keys) <= land_area[plot_id] * (1 - r[plot_id, year]), name=f"water_second_mode[{plot_id},{year}]")
            model.addConstr(gp.quicksum(z[key] for key in second_keys) <= 1, name=f"water_second_unique[{plot_id},{year}]")
            constraints["water_mode"] += 3
            constraints["water_second_unique"] += 1

    rotation_pairs, rotation_count = _add_rotation_constraints(model, z, data, cfg)
    constraints["rotation"] = rotation_count

    bean_keys_by_plot_year: dict[tuple[str, int], list[tuple[str, int, int, str]]] = defaultdict(list)
    for key in x_keys:
        if key[1] in BEAN_CROPS:
            bean_keys_by_plot_year[key[0], key[2]].append(key)
    history_bean = dict(zip(data["history_bean_2023"]["plot_id"], data["history_bean_2023"]["history_bean_2023"]))
    for plot_id in land["plot_id"]:
        model.addConstr(history_bean[plot_id] + gp.quicksum(z[key] for year in (2024, 2025) for key in bean_keys_by_plot_year[plot_id, year]) >= 1, name=f"bean_window[2023-2025,{plot_id}]")
        constraints["bean_window"] += 1
        for start_year in range(2024, 2029):
            model.addConstr(gp.quicksum(z[key] for year in range(start_year, start_year + 3) for key in bean_keys_by_plot_year[plot_id, year]) >= 1, name=f"bean_window[{start_year}-{start_year + 2},{plot_id}]")
            constraints["bean_window"] += 1

    for (crop_id, year, season), keys in keys_by_crop_year_season.items():
        model.addConstr(gp.quicksum(z[key] for key in keys) <= cfg.nmax, name=f"dispersal[{crop_id},{year},{season}]")
        constraints["dispersal"] += 1

    parameter_index = parameters.set_index(["land_type", "crop_id", "season"])
    demand_index = demand.set_index(["crop_id", "season"])
    price = {(crop_id, season): float(parameter_index.loc[(land_type_name, crop_id, season), "price_mid"]) for crop_id, season in demand_keys for land_type_name in [next(land_type[key[0]] for key in keys_by_crop_year_season[crop_id, cfg.years[0], season])]} 
    for crop_id, year, season in q_keys:
        production = gp.quicksum(float(parameter_index.loc[(land_type[plot_id], crop_id, season), "yield_jin_per_mu"]) * x[plot_id, crop_id, year, season] for plot_id, _, _, _ in keys_by_crop_year_season[crop_id, year, season])
        model.addConstr(q[crop_id, year, season] + e[crop_id, year, season] == production, name=f"sales_balance[{crop_id},{year},{season}]")
        model.addConstr(q[crop_id, year, season] <= float(demand_index.loc[(crop_id, season), "demand_jin"]), name=f"demand_cap[{crop_id},{year},{season}]")
        constraints["sales_balance"] += 1
        constraints["demand_cap"] += 1

    revenue = gp.quicksum(price[crop_id, season] * (q[crop_id, year, season] + alpha * e[crop_id, year, season]) for crop_id, year, season in q_keys)
    cost = gp.quicksum(float(parameter_index.loc[(land_type[plot_id], crop_id, season), "cost_yuan_per_mu"]) * x[plot_id, crop_id, year, season] for plot_id, crop_id, year, season in x_keys)
    model.setObjective(revenue - cost, GRB.MAXIMIZE)
    model.update()
    return model, {"x": x, "z": z, "q": q, "e": e, "r": r}, {"constraint_counts": dict(constraints), "rotation_pairs": rotation_pairs, "x_keys": x_keys, "q_keys": q_keys, "price": price, "model_size": {"variables": model.NumVars, "constraints": model.NumConstrs, "binary_variables": model.NumBinVars}}

