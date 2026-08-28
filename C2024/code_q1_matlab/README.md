# C2024 问题1：MATLAB + Gurobi 10.0.1

本目录是独立 MATLAB 工程；不会覆盖 `../code_q1/` Python 工程。

## 本机运行

在 MATLAB 中切换至本目录后执行：

```matlab
main
```

前提：MATLAB 已配置 Gurobi 10.0.1 MATLAB API，且可调用 `gurobi`。本机运行自动写入：

- `results/run_log.txt`
- `results/data_audit/audit_checks.csv`
- `results/data_audit/audit_summary.csv`
- `results/alpha_0/model_summary.csv`
- `results/alpha_0/validation_summary.csv`（仅求解成功后）
- `results/alpha_0/result1_1.xlsx`（仅独立验证 PASS 后）

## 严格门控

1. 模块 A 复现 54 地块、41 作物、87 历史记录、107 参数记录、59 demand support（47 正、12 零）等基准；
2. 审计失败时不进入 MILP；
3. 仅建立并求解 alpha=0；
4. Gurobi 非最优或独立验证失败时不输出最终方案，也不自动修改 beta、Nmax 或任何约束；
5. alpha=0 审查通过前，`plot_results` 与 `sensitivity_analysis` 明确停止。

模型使用 Gurobi MATLAB 原生矩阵接口 `gurobi(model, params)`，并维护稀疏的 `x_id(i,j,t,k)`、`z_id(i,j,t,k)`、`q_id(j,t,k)`、`e_id(j,t,k)`、`r_id(i,t)` 映射。


