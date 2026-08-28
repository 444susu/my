# C2024 问题 1：模块 A

当前提交仅实现、运行并保存模块 A（数据读取、机械性清洗、参数构建和数据审计）。

在 `C2024/code_q1` 目录运行：

```powershell
python main.py
```

运行结果保存在 `results/data_audit/`。当且仅当 `audit_report.md` 中所有检查均为 `PASS` 时，才可以根据既定门控进入模块 B 的 Gurobi MILP。

