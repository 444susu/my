# Codex MATLAB 远程环境限制与本机执行协议

> 本文件是 `C2024/CODEX_问题1_MATLAB_Gurobi10_迁移与实现指令.md` 的补充约束。Codex 必须同时读取并遵守。

## 1. 已确认事实

用户本机 MATLAB 已能成功调用 Gurobi，最小测试模型得到：

- `status = 'OPTIMAL'`
- `objval = 1`
- `x = 1`

因此用户本机的 MATLAB、Gurobi MATLAB API 与 Gurobi 许可证链路视为有效。

Codex 远程环境启动 MATLAB 时出现：

```text
failed to load settings errors_warnings plugin
```

该错误属于 Codex 远程 MATLAB 运行环境，不得再据此判断用户本机 MATLAB 或 Gurobi 配置有问题。

## 2. 立即修改工作方式

从现在起：

1. Codex **不得把“能否在远程启动 MATLAB”作为继续开发的前置条件**；
2. Codex **不得再次要求用户修复本机 MATLAB 安装**，除非用户本机实际运行代码时出现新的错误；
3. Codex 负责：
   - 编写 MATLAB 代码；
   - 做静态审查；
   - 检查变量维度、索引、函数调用和 Gurobi 10.0.1 API 兼容性；
   - 提交代码到 GitHub；
4. 用户本机负责：
   - 实际启动 MATLAB；
   - 实际调用 Gurobi 10.0.1；
   - 实际运行模块 A、模块 B 和后续模型；
5. ChatGPT 负责：
   - 从 GitHub 审查 Codex 提交代码；
   - 根据用户本机运行日志、验证摘要和结果文件继续审查。

## 3. MATLAB 代码必须支持“本机运行后自动产生日志”

Codex 编写的 `main.m` 必须将关键执行信息自动写入：

```text
C2024/code_q1_matlab/results/run_log.txt
```

至少包含：

- MATLAB 版本；
- Gurobi 版本信息（若 API 可读取）；
- 数据审计 PASS/FAIL；
- 地块数、作物数、历史记录数、参数记录数；
- demand support 数、正需求数、零需求数；
- 变量总数；
- 连续变量数；
- 二进制变量数；
- 约束总数；
- Gurobi status；
- objective value；
- runtime；
- MIP gap（若有）；
- 解验证 PASS/FAIL；
- 所有异常或 WARNING。

建议使用：

```matlab
diary(logFile)
...
diary off
```

并确保异常时也能记录到日志。

## 4. 必须生成结构化验证摘要

除 `run_log.txt` 外，`validate_solution.m` 必须写出：

```text
C2024/code_q1_matlab/results/validation_summary.csv
```

至少逐项检查：

1. 面积容量；
2. x-z 上下界；
3. allowed；
4. 水浇地模式；
5. 普通大棚两季实际种植；
6. 智慧大棚两季实际种植；
7. 水浇地第二季唯一作物规则；
8. 连续重茬；
9. 2023→2024历史边界；
10. 三年豆类窗口；
11. Nmax；
12. q+e=总产量；
13. q<=demand；
14. 变量上下界与整数性；
15. 目标函数重算值与 Gurobi `objval` 是否一致。

每项至少输出：

```text
check_name, passed, max_violation, note
```

## 5. 如果本机求解出现错误

Codex 不得自行改模型含义。必须先让用户提供：

- `results/run_log.txt`
- `results/validation_summary.csv`（若已生成）
- MATLAB 报错完整堆栈
- 如 Gurobi 返回 infeasible：IIS 文件或 IIS 摘要

然后再根据实际错误修改代码。

## 6. 当前开发任务不变

继续按原迁移指令完成 MATLAB 项目：

```text
C2024/code_q1_matlab/
```

第一阶段仍然是：

1. 复现模块 A 审计结果；
2. 构建问题1 `alpha=0` 的 MATLAB + Gurobi 10.0.1 MILP；
3. 提交全部 MATLAB 源码；
4. 不要求 Codex 远程执行 MATLAB；
5. 等待用户本机运行并回传 `run_log.txt` 与验证摘要；
6. 通过审查后再继续 `alpha=0.5` 与敏感性分析。

## 7. 禁止事项

Codex 不得因为远程 MATLAB 插件错误而：

- 停止编码；
- 改回 Python；
- 改用其他求解器；
- 认定 Gurobi 许可证无效；
- 要求用户再次重装 MATLAB；
- 自行弱化约束以“保证能跑”。

远程 MATLAB 不能启动，仅意味着“远程无法动态执行 MATLAB”，不影响静态开发和 GitHub 提交。
