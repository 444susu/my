# Gurobi 10.0.1 兼容性说明

当前问题1代码必须以 **Gurobi 10.0.1** 为目标版本，不得按 Gurobi 13.x 专有行为或新 API 编写。

## 固定环境

- Gurobi Optimizer: 10.0.1
- Python: 建议 3.10 或 3.11（Gurobi 10.0 支持 Python 3.7–3.11）
- Python API: `gurobipy==10.0.1`
- 用户本机已有可用的 Gurobi 10.0.1 许可证，并已用于 MATLAB 接口。

## 安装

```powershell
python -m pip uninstall -y gurobipy
python -m pip install gurobipy==10.0.1
```

验证 Python 接口版本：

```python
import gurobipy as gp
print(gp.gurobi.version())
```

应输出 `(10, 0, 1)`。

## 许可证

许可证属于 Gurobi Optimizer，不是 MATLAB 专用接口许可证。同一机器上 Python 的 `gurobipy==10.0.1` 可以使用同一有效许可证，只要 Python 进程能够找到该许可证。

Windows 默认搜索位置包括：

- `C:\gurobi\gurobi.lic`
- 当前用户主目录，例如 `C:\Users\用户名\gurobi.lic`

如果许可证在其他位置，设置系统环境变量：

```text
GRB_LICENSE_FILE=完整的gurobi.lic文件路径
```

注意变量必须指向具体文件，而不是目录。

可在命令行先检查：

```powershell
gurobi_cl --license
```

再用 Python 测试：

```python
import gurobipy as gp

print("Gurobi version:", gp.gurobi.version())
m = gp.Model("license_test")
x = m.addVar(lb=0, name="x")
m.setObjective(x, gp.GRB.MAXIMIZE)
m.addConstr(x <= 1)
m.optimize()
print("status:", m.Status)
print("x:", x.X)
```

若此小模型能正常求解，说明 Python 已成功复用现有许可证。

## Codex 模块B要求

1. 所有 Gurobi 代码必须兼容 10.0.1。
2. 禁止把 `gurobipy` 升级到 11/12/13。
3. 不使用只有更新版本才存在的 API。
4. 继续优先使用稳定接口：`Model`、`addVar/addVars`、`addConstr/addConstrs`、`quicksum`、`setObjective`、`GRB.*`、`computeIIS()`、`write()`。
5. 模块B首先实现并验证 `alpha=0` 基准模型，再扩展到 `alpha=0.5`。
6. 若 Codex 所在远程环境没有用户本机许可证，不得把“远程环境无法求解”误判为代码错误；代码应提交到仓库，由用户在本机 Gurobi 10.0.1 环境执行求解，并提交日志/摘要供审查。
