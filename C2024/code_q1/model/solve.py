"""Gurobi 求解与不可行 IIS 导出。"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import gurobipy as gp
from gurobipy import GRB, Model


def solve_model(model: Model, output_dir: Path) -> dict[str, Any]:
    output_dir.mkdir(parents=True, exist_ok=True)
    try:
        model.optimize()
    except gp.GurobiError as error:
        return {"feasible": False, "reason": "GurobiError", "error_code": int(error.errno), "error_message": str(error)}
    result: dict[str, Any] = {"status_code": int(model.Status), "status": str(model.Status), "sol_count": int(model.SolCount)}
    if model.Status == GRB.INFEASIBLE:
        iis_path = output_dir / "infeasible.ilp"
        model.computeIIS()
        model.write(str(iis_path))
        result.update({"feasible": False, "iis_path": str(iis_path)})
        return result
    if model.Status not in {GRB.OPTIMAL, GRB.TIME_LIMIT} or model.SolCount == 0:
        result.update({"feasible": False, "reason": "未取得可验证解"})
        return result
    result.update({"feasible": True, "objective": float(model.ObjVal), "mip_gap": float(model.MIPGap), "runtime_seconds": float(model.Runtime)})
    return result

