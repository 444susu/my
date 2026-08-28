"""问题 1 统一入口；当前仅允许执行模块 A。"""

from __future__ import annotations

import json
import shutil
import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

from config import load_config
from data.build_allowed import build_allowed
from data.build_history import build_history_and_demand
from data.build_parameters import build_parameters
from data.read_clean import clean_data, read_raw_excel
from data.pipeline import prepare_verified_data
from data.validate_data import AuditResult, validate_data


def _configure_matplotlib() -> None:
    plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "Arial Unicode MS", "DejaVu Sans"]
    plt.rcParams["axes.unicode_minus"] = False


def _save_frame(frame: pd.DataFrame, path: Path) -> None:
    frame.to_csv(path, index=False, encoding="utf-8-sig")


def _make_audit_plots(data: dict[str, pd.DataFrame], audit: AuditResult, out_dir: Path) -> None:
    """模块 A 所需的缺失、分布和异常可视化；不用于推导优化结论。"""
    _configure_matplotlib()
    frames = {name: data[name] for name in ["land", "crop", "plant_2023", "statistics_2023"]}
    missing = pd.DataFrame({name: frame.isna().sum() for name, frame in frames.items()}).fillna(0).sum(axis=1)
    fig, ax = plt.subplots(figsize=(11, 5))
    # 即使全部字段均无缺失，也保留全零柱状图作为可核验的审计证据。
    missing.sort_values(ascending=False).plot.bar(ax=ax, color="#4C78A8")
    ax.set_title("模块A：清洗后核心字段缺失值计数")
    ax.set_xlabel("字段")
    ax.set_ylabel("缺失值数量")
    fig.tight_layout()
    fig.savefig(out_dir / "missingness_after_cleaning.png", dpi=300)
    plt.close(fig)

    history = data["history_2023"]
    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    history["plant_area_mu"].plot.hist(ax=axes[0], bins=18, color="#72B7B2", edgecolor="white")
    axes[0].set_title("2023单条种植面积分布")
    axes[0].set_xlabel("种植面积（亩）")
    axes[0].set_ylabel("记录数")
    ordered_types = list(history.groupby("land_type")["plant_area_mu"].median().sort_values().index)
    history.boxplot(column="plant_area_mu", by="land_type", ax=axes[1], grid=False, rot=30, positions=range(1, len(ordered_types) + 1))
    axes[1].set_title("2023种植面积箱线图（按地块类型）")
    axes[1].set_xlabel("地块类型")
    axes[1].set_ylabel("种植面积（亩）")
    fig.suptitle("")
    fig.tight_layout()
    fig.savefig(out_dir / "plant_area_distribution.png", dpi=300)
    plt.close(fig)

    demand = data["demand"].sort_values("demand_jin", ascending=False)
    demand = demand.assign(label=demand["crop_id"].astype(str) + "-" + demand["season"])
    fig, ax = plt.subplots(figsize=(12, 5))
    demand.plot.bar(x="label", y="demand_jin", ax=ax, color="#F58518", legend=False)
    ax.set_title("问题1需求基准：2023实际产量汇总")
    ax.set_xlabel("作物编号—季次组合（按汇总表顺序）")
    ax.set_ylabel("需求基准（斤）")
    ax.tick_params(axis="x", labelrotation=0)
    fig.tight_layout()
    fig.savefig(out_dir / "demand_baseline_distribution.png", dpi=300)
    plt.close(fig)


def _write_report(data: dict[str, pd.DataFrame], audit: AuditResult, out_dir: Path) -> None:
    summary = audit.checks.copy()
    summary["status"] = np.where(summary["passed"], summary["status"], "FAIL")
    _save_frame(summary, out_dir / "audit_checks.csv")
    payload = {
        "module": "A 数据读取、清洗、参数构建和数据审计",
        "passed": audit.passed,
        "check_count": int(len(summary)),
        "pass_count": int(summary["passed"].sum()),
        "fail_count": int((~summary["passed"]).sum()),
        "raw_row_counts": data["raw_row_counts"],
        "cleaning_log": data["cleaning_log"],
    }
    (out_dir / "audit_summary.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = ["# 问题1 模块A数据审计报告", "", f"**总体状态：{'PASS' if audit.passed else 'FAIL'}**", "", "## 审计检查", "", "| 检查项 | 状态 | 预期 | 实际 | 失败影响 |", "|---|---|---|---|---|"]
    for row in summary.itertuples(index=False):
        lines.append(f"| {row.check} | {row.status} | {row.expected} | {row.actual} | {row.impact_if_failed} |")
    lines += ["", "## 已执行的机械性清洗", "", "| 步骤 | 影响记录数 | 规则 |", "|---|---:|---|"]
    for entry in data["cleaning_log"]:
        lines.append(f"| {entry['step']} | {entry['affected_rows']} | {entry['rule']} |")
    zero_demand = data["demand"].query("demand_source == '2023未种植，按已确认口径置0'")
    lines += ["", "## 零需求组合", "", "这些组合未来允许种植、但2023未实际种植；按已确认口径其预期销售量为0。", "", "| 作物编号 | 季次 | 需求（斤） | 来源 |", "|---:|---|---:|---|"]
    for row in zero_demand.itertuples(index=False):
        lines.append(f"| {row.crop_id} | {row.season} | {row.demand_jin:.1f} | {row.demand_source} |")
    lines += ["", "## 输出说明", "", "- `clean_*.csv`：清洗后的可复用数据。", "- `clean_parameters.csv`：含智慧大棚第一季的参数；其继承明细见 `parameter_inheritance_smart_greenhouse_first_season.csv`。", "- `clean_demand.csv`：按作物—季次由2023实际产量构建的需求基准。", "- `clean_history_z_2023.csv`、`clean_history_bean_2023.csv` 与 `clean_adjacency_2023_to_2024.csv`：后续重茬与三年豆类约束的历史基础。", "- `audit_checks.csv` 和本报告：可逐项复核的门控证据。", "- 三张 PNG：缺失、种植面积分布和需求基准的审计图。", "", "模块 B 的 MILP 调用未被实现或执行；仅当全部硬检查通过、仅保留不改变模型方向的WARNING时才可进入。"]
    (out_dir / "audit_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def run_module_a() -> AuditResult:
    cfg = load_config()
    np.random.seed(cfg.random_seed)
    if cfg.audit_dir.exists():
        shutil.rmtree(cfg.audit_dir)
    cfg.audit_dir.mkdir(parents=True, exist_ok=True)

    raw = read_raw_excel(cfg)
    clean = clean_data(raw, cfg)
    parameters, inherited = build_parameters(clean.statistics_2023)
    allowed = build_allowed(clean.land, cfg.seasons)
    history, demand, dispersal, history_z, history_bean, adjacency = build_history_and_demand(
        clean.plant_2023, clean.land, parameters, allowed
    )
    data: dict[str, object] = {
        "land": clean.land, "crop": clean.crop, "plant_2023": clean.plant_2023,
        "statistics_2023": clean.statistics_2023, "parameters": parameters, "allowed": allowed,
        "history_2023": history, "demand": demand, "dispersal": dispersal,
        "history_z_2023": history_z, "history_bean_2023": history_bean, "adjacency_2023_to_2024": adjacency,
        "raw_row_counts": clean.raw_row_counts, "cleaning_log": clean.cleaning_log,
    }
    audit = validate_data(data, cfg)  # type: ignore[arg-type]

    for name in ["land", "crop", "plant_2023", "statistics_2023", "parameters", "allowed", "history_2023", "history_z_2023", "history_bean_2023", "adjacency_2023_to_2024", "demand", "dispersal"]:
        _save_frame(data[name], cfg.audit_dir / f"clean_{name}.csv")  # type: ignore[arg-type]
    _save_frame(inherited, cfg.audit_dir / "parameter_inheritance_smart_greenhouse_first_season.csv")
    for name, detail in audit.details.items():
        _save_frame(detail, cfg.audit_dir / f"detail_{name}.csv")
    _make_audit_plots(data, audit, cfg.audit_dir)  # type: ignore[arg-type]
    _write_report(data, audit, cfg.audit_dir)  # type: ignore[arg-type]

    print("模块 A：数据读取、清洗、参数构建和数据审计")
    print(f"审计状态：{'PASS' if audit.passed else 'FAIL'}；{int(audit.checks['passed'].sum())}/{len(audit.checks)} 项通过")
    print(audit.checks[["check", "passed", "actual"]].to_string(index=False))
    print(f"审计结果目录：{cfg.audit_dir}")
    if not audit.passed:
        raise RuntimeError("模块 A 数据审计未通过；根据门控要求，未进入 MILP 求解。")
    return audit


def run_alpha0_baseline() -> None:
    """模块 A 通过后，运行 alpha=0 基准 MILP 与独立验证。"""
    from model.build_model import build_model
    from model.solve import solve_model
    from model.validate_solution import validate_solution

    cfg = load_config()
    run_module_a()
    data, audit = prepare_verified_data(cfg)
    if not audit.passed:
        raise RuntimeError("模块 A 未通过，禁止构建 MILP。")
    output_dir = cfg.project_root / "code_q1" / "results" / "alpha_0"
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    model, variables, meta = build_model(data, cfg, cfg.baseline_alpha)
    model.write(str(output_dir / "alpha_0_model.lp"))
    _save_frame(pd.DataFrame(meta["rotation_pairs"]), output_dir / "rotation_adjacency_constraints.csv")
    (output_dir / "constraint_counts.json").write_text(json.dumps(meta["constraint_counts"], ensure_ascii=False, indent=2), encoding="utf-8")
    result = solve_model(model, output_dir)
    result["model_size"] = meta["model_size"]
    if not result["feasible"]:
        (output_dir / "solver_summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        raise RuntimeError(f"alpha=0 基准模型未得到可验证解：{result}")
    passed, validation = validate_solution(data, cfg, cfg.baseline_alpha, model, variables, meta)
    _save_frame(validation, output_dir / "solution_validation_failures.csv")
    result["solution_validation_passed"] = passed
    (output_dir / "solver_summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    if not passed:
        raise RuntimeError("alpha=0 解独立验证未通过；禁止继续情形2。")
    print(f"模块 B alpha=0：PASS；目标值={result['objective']:.2f}，MIPGap={result['mip_gap']:.6g}，用时={result['runtime_seconds']:.2f}秒")
    print(f"基准结果目录：{output_dir}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="C2024问题1：模块A审计与alpha=0基准MILP")
    parser.add_argument("--alpha0", action="store_true", help="在模块A通过后运行alpha=0基准MILP")
    args = parser.parse_args()
    if args.alpha0:
        run_alpha0_baseline()
    else:
        run_module_a()

