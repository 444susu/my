"""对 Gurobi 解进行独立的约束与目标函数复核。"""

from __future__ import annotations

from typing import Any

import pandas as pd

from config import Config
from data.build_allowed import BEAN_CROPS


def validate_solution(data: dict[str, Any], cfg: Config, alpha: float, model: Any, variables: dict[str, Any], meta: dict[str, Any]) -> tuple[bool, pd.DataFrame]:
    """复核面积、模式、重茬、豆类、分散度、销售守恒与目标函数。"""
    x, z, q, e, r = variables["x"], variables["z"], variables["q"], variables["e"], variables["r"]
    land, demand, parameters = data["land"], data["demand"], data["parameters"]
    area = dict(zip(land["plot_id"], land["area_mu"]))
    land_type = dict(zip(land["plot_id"], land["land_type"]))
    parameter_index = parameters.set_index(["land_type", "crop_id", "season"])
    failures: list[dict[str, Any]] = []
    tol = 1e-6
    x_values = {key: x[key].X for key in meta["x_keys"]}
    z_values = {key: z[key].X for key in meta["x_keys"]}
    for key in meta["x_keys"]:
        plot_id, crop_id, year, season = key
        if x_values[key] < -tol or abs(z_values[key] - round(z_values[key])) > tol:
            failures.append({"check": "variable_domain", "key": str(key), "value": x_values[key]})
        if x_values[key] + tol < cfg.beta * area[plot_id] * z_values[key] or x_values[key] - tol > area[plot_id] * z_values[key]:
            failures.append({"check": "x_z_link", "key": str(key), "value": x_values[key]})
    for plot_id in land["plot_id"]:
        for year in cfg.years:
            for season in cfg.seasons:
                used = sum(value for (i, _, t, k), value in x_values.items() if i == plot_id and t == year and k == season)
                if used > area[plot_id] + tol:
                    failures.append({"check": "land_capacity", "key": f"{plot_id},{year},{season}", "value": used})
    for plot_id in land.loc[land["land_type"] == "水浇地", "plot_id"]:
        for year in cfg.years:
            rice = x_values[plot_id, 16, year, "单季"]
            first = sum(x_values[plot_id, crop_id, year, "第一季"] for crop_id in range(17, 35))
            second = sum(x_values[plot_id, crop_id, year, "第二季"] for crop_id in range(35, 38))
            second_z = sum(z_values[plot_id, crop_id, year, "第二季"] for crop_id in range(35, 38))
            if rice > area[plot_id] * r[plot_id, year].X + tol or first > area[plot_id] * (1 - r[plot_id, year].X) + tol or second > area[plot_id] * (1 - r[plot_id, year].X) + tol or second_z > 1 + tol:
                failures.append({"check": "water_mode", "key": f"{plot_id},{year}", "value": "mode violation"})
    for pair in meta["rotation_pairs"]:
        if pair["source"] == "future":
            from_year, from_season = pair["from"].split("-", 1)
            to_year, to_season = pair["to"].split("-", 1)
            total = z_values[pair["plot_id"], pair["crop_id"], int(from_year), from_season] + z_values[pair["plot_id"], pair["crop_id"], int(to_year), to_season]
            if total > 1 + tol:
                failures.append({"check": "rotation", "key": str(pair), "value": total})
        elif z_values[pair["plot_id"], pair["crop_id"], 2024, pair["to"].split("-", 1)[1]] > tol:
            failures.append({"check": "rotation_history", "key": str(pair), "value": 1})
    history_bean = dict(zip(data["history_bean_2023"]["plot_id"], data["history_bean_2023"]["history_bean_2023"]))
    for plot_id in land["plot_id"]:
        for start in range(2023, 2029):
            years = (2024, 2025) if start == 2023 else range(start, start + 3)
            total = history_bean[plot_id] if start == 2023 else 0
            total += sum(value for (i, crop_id, year, _), value in z_values.items() if i == plot_id and crop_id in BEAN_CROPS and year in years)
            if total < 1 - tol:
                failures.append({"check": "bean_window", "key": f"{plot_id},{start}", "value": total})
    for crop_id, year, season in meta["q_keys"]:
        spread = sum(value for (i, j, t, k), value in z_values.items() if j == crop_id and t == year and k == season)
        if spread > cfg.nmax + tol:
            failures.append({"check": "dispersal", "key": f"{crop_id},{year},{season}", "value": spread})
        production = sum(float(parameter_index.loc[(land_type[i], crop_id, season), "yield_jin_per_mu"]) * value for (i, j, t, k), value in x_values.items() if j == crop_id and t == year and k == season)
        if abs(q[crop_id, year, season].X + e[crop_id, year, season].X - production) > tol:
            failures.append({"check": "sales_balance", "key": f"{crop_id},{year},{season}", "value": production})
        limit = float(demand.set_index(["crop_id", "season"]).loc[(crop_id, season), "demand_jin"])
        if q[crop_id, year, season].X > limit + tol:
            failures.append({"check": "demand_cap", "key": f"{crop_id},{year},{season}", "value": q[crop_id, year, season].X})
    revenue = sum(meta["price"][crop_id, season] * (q[crop_id, year, season].X + alpha * e[crop_id, year, season].X) for crop_id, year, season in meta["q_keys"])
    cost = sum(float(parameter_index.loc[(land_type[i], crop_id, season), "cost_yuan_per_mu"]) * value for (i, crop_id, _, season), value in x_values.items())
    if abs(revenue - cost - model.ObjVal) > 1e-4:
        failures.append({"check": "objective_recalculation", "key": "ObjVal", "value": revenue - cost - model.ObjVal})
    report = pd.DataFrame(failures, columns=["check", "key", "value"])
    return report.empty, report

