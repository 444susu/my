# 2024 全国大学生数学建模竞赛 C 题——问题 1 Python + Gurobi 建模与 Codex 实现指南

> 本文档供 Codex 直接读取并据此编写求解代码。
>
> **开始编码前，先阅读仓库中的 `cumcm-modeling-workflow/SKILL.md`。** 本文档是 C2024 问题 1 的当前已确认建模口径。若与用户后续明确指示冲突，以用户最新明确指示为准。
>
> 正式比赛口径：禁止用网络公开题解替代题面、附件和用户确认。只允许使用：`C题.pdf`、`附件1.xlsx`、`附件2.xlsx`、`附件3/`、本指南以及用户后续确认。

---

# 0. 当前任务边界与总思路

当前只解决 **问题 1**。

模型确定为：

**确定性、多年份、多地块、多作物、带 0-1 逻辑约束的单目标混合整数线性规划（MILP）**。

唯一主目标：

**最大化 2024—2030 七年总利润。**

问题 1 两种情形使用完全相同的模型结构，仅改变超产部分的销售折价系数：

- 情形 1：超出预期销售量部分全部滞销，`alpha = 0`；
- 情形 2：超出部分按正常售价 50% 出售，`alpha = 0.5`。

最终应分别输出 `result1_1.xlsx` 与 `result1_2.xlsx`，并比较两种销售机制下的种植结构、利润、超产量和土地利用情况。

当前不采用多目标规划；“不能太分散”“单块面积不宜太小”等要求作为约束进入 MILP。

整体逻辑：

```text
附件1：土地、作物、地块类型、种植适宜性和补充规则
                         +
附件2：2023实际种植记录 + 2023亩产量/成本/价格
                         ↓
                数据清洗和跨表审计
                         ↓
构建 area / allowed / yield / cost / price / history_2023
                         ↓
       2023实际面积 × 对应地块类型/季次亩产量
                         ↓
              得到 demand(j,k)
                         ↓
创建 x(i,j,t,k), z(i,j,t,k), q(j,t,k), e(j,t,k), r(i,t)
                         ↓
             最大化 2024—2030 总利润
                         ↓
土地容量 + 适宜性 + 最小面积 + 水浇地模式 + 特殊作物季次
+ 连续重茬 + 三年豆类 + 分散度 + 产量/销售守恒
                         ↓
                  Gurobi MILP
                         ↓
             alpha=0       alpha=0.5
                ↓             ↓
           result1_1     result1_2
                  \       /
                   结果比较
                      ↓
              beta、Nmax 敏感性分析
```

---

# 1. 已确认的参数口径

以下内容已经由用户确认，Codex 不得自行更改。

## 1.1 未来预期销售量

附件 2 没有直接给出“2023 年销量”字段，因此按 2023 年实际种植面积和对应亩产量计算 2023 年各作物、各季实际产量，并把它作为 2024—2030 每年的预期销售量基准：

\[
D_{jk}=\sum_i A^{2023}_{ijk}Y_{ijk}.
\]

问题 1 中未来七年保持不变：

\[
D_{jtk}=D_{jk},\quad t=2024,\ldots,2030.
\]

重要：亩产量必须按“作物 + 地块类型 + 季次”匹配，不能给每种作物只用一个统一亩产量。

## 1.2 销售价格

附件 2 销售单价为区间时，采用区间中点作为问题 1 的确定价格：

\[
P=\frac{P_{low}+P_{high}}2.
\]

## 1.3 最小种植面积比例 beta

依据 2023 实际种植数据：

\[
\rho=\frac{\text{该作物在该地块的实际种植面积}}{\text{该地块面积}}.
\]

正种植记录中的历史最小比例为 0.5，因此问题 1 基准值：

`beta = 0.5`。

一旦种植，使用比例型最小面积约束：

\[
\beta A_i z_{ijtk}\le x_{ijtk}\le A_i z_{ijtk}.
\]

`beta=0.5` 是历史数据推导的管理参数，不是题面硬常数；必须进入后续敏感性分析。

## 1.4 种植不能太分散

当前管理参数基准：

`Nmax = 3`

按“每种作物在同一年、同一季最多分布在 3 个地块”实现：

\[
\sum_i z_{ijtk}\le N_{max}.
\]

`Nmax=3` 不是题面硬常数；若导致无解或明显不合理，Codex 不得自行修改，必须输出异常证据并请求用户决定。

## 1.5 技术栈

固定为：

- Python 3；
- `pandas`：Excel 读取与数据清洗；
- `numpy`：数值处理；
- `gurobipy`：MILP 建模与求解；
- `openpyxl`：Excel 输出和模板写入；
- `matplotlib`：论文级图形；
- 可选 `pathlib`、`dataclasses`、`logging`。

不要使用 `scipy.optimize`、遗传算法、模拟退火等替代 Gurobi 的 MILP 求解。

---

# 2. 集合、索引和统一维度

统一下标顺序：

- `i`：地块；
- `j`：作物；
- `t`：年份；
- `k`：季次。

主面积变量始终表示为：

`x[i,j,t,k]`

不要在不同模块中换成 `i,j,k,t`。

集合：

- `I = 54`：54 个地块；
- `J = 41`：41 种作物；
- `T = {2024,...,2030}`：7 年；
- `K = {'单季','第一季','第二季'}`。

Python 中推荐：

```python
SEASONS = ["单季", "第一季", "第二季"]
YEARS = list(range(2024, 2031))
```

---

# 3. 数据读取与审计要求

## 3.1 原始文件

只读：

- `C2024/附件1.xlsx`
- `C2024/附件2.xlsx`
- `C2024/附件3/`

禁止覆盖原始附件。

## 3.2 必做机械清洗

1. 文本字段去首尾空格；
2. 合并单元格造成的空地块名按上一有效值 `ffill()`；
3. 作物名称、地块类型、作物类型、季次统一编码；
4. 销售价格区间解析为上下界和中点；
5. 面积、亩产量、成本等统一数值型；
6. 检查作物编号与名称一一对应；
7. 检查 2023 每条种植记录是否都能匹配 `(作物,地块类型,季次)` 参数；
8. 检查参数键是否重复；
9. 检查 2023 每个 `(地块,季次)` 面积和是否超过地块面积；
10. 输出处理前后样本数与异常明细，禁止静默修正。

## 3.3 建议统一 DataFrame

- `land_df`
- `crop_df`
- `plant2023_df`
- `stat2023_df`
- `param_df`
- `demand_df`

---

# 4. 模型参数

至少构建：

- `area[i]`
- `land_type[i]`
- `crop_name[j]`
- `crop_type[j]`
- `allowed[i,j,k]`
- `yield_[i,j,k]`
- `cost[i,j,k]`
- `price[j,k]`（若数据确实因地块不同则保留 `price[i,j,k]`）
- `demand[j,k]`
- `bean_crops = {1,2,3,4,5,17,18,19}`
- `history_z_2023`
- `history_bean_2023[i]`
- `adjacency`

---

# 5. 决策变量

\[
x_{ijtk}\ge 0
\]

种植面积。

\[
z_{ijtk}\in\{0,1\}
\]

是否种植。

\[
q_{jtk}\ge0
\]

正常售价销售量。

\[
e_{jtk}\ge0
\]

超产量。

水浇地：

\[
r_{it}\in\{0,1\}
\]

- `r=1`：单季水稻；
- `r=0`：两季蔬菜。

---

# 6. 目标函数与销售线性化

总产量：

\[
Q_{jtk}=\sum_iY_{ijk}x_{ijtk}.
\]

销售拆分：

\[
q_{jtk}+e_{jtk}=Q_{jtk}
\]

\[
0\le q_{jtk}\le D_{jk},\quad e_{jtk}\ge0.
\]

目标：

\[
\max Z=\sum_{j,t,k}P_{jk}(q_{jtk}+\alpha e_{jtk})
-\sum_{i,j,t,k}C_{ijk}x_{ijtk}.
\]

- `alpha=0`
- `alpha=0.5`

禁止直接使用 `min()`/`max()` 非线性表达。

---

# 7. 约束—附件原意—数学形式—Python 实现逐条对照表

| 编号 | 规则 | 数学形式 | Python/Gurobi 实现要求 |
|---|---|---|---|
| C1 | 每块土地面积有限 | `sum_j x <= A_i` | 只对真实有效季次建约束 |
| C2 | 单块面积不宜太小 | `beta*A_i*z <= x <= A_i*z` | `beta=0.5` 配置化 |
| C3 | 平旱地/梯田/山坡地一年一季粮食且不能水稻 | 只允许 1—15、单季 | 仅创建合法变量 |
| C4 | 水浇地一季水稻或两季蔬菜 | 模式互斥 | 用 `r[i,t]` |
| C5 | 水浇地第一季蔬菜 | 17—34 | allowed |
| C6 | 水浇地第二季只能 35—37 中一种 | `sum z <=1` | 仅水浇地第二季 |
| C7 | 35—37 只能水浇地第二季 | 其他 allowed=0 | 全局排他 |
| C8 | 普通大棚第一季蔬菜 | 17—34 | 可混种 |
| C9 | 普通大棚第二季食用菌 | 38—41 | **不要擅自限制只能一种菌** |
| C10 | 食用菌只能普通大棚第二季 | 其他 allowed=0 | 智慧大棚也不允许 |
| C11 | 智慧大棚两季蔬菜 | 17—34 | 35—37 不允许 |
| C12 | 智慧大棚第一季参数与普通大棚相同 | 参数继承 | 附件明确规则 |
| C13 | 水稻只能水浇地单季 | 仅 `(水浇地,16,单季)` | 其他不创建 |
| C14 | 同地块不能连续重茬 | `z_current+z_next<=1` | 按真实时间链 |
| C15 | 2023 是历史状态 | 2023 与 2024 相邻时段约束 | 读取附件2 |
| C16 | 两季土地第一季→第二季→下一年第一季 | 同年跨季+跨年 | 构造 adjacency |
| C17 | 任意连续三年至少一次豆类 | `sum z_bean >=1` | 豆类固定集合 |
| C18 | 第一个窗口含 2023 | `bean2023 + 2024:2025 >=1` | 单独处理 |
| C19 | 每种作物不能太分散 | `sum_i z <= Nmax` | 基准 Nmax=3 |
| C20 | 同地同季允许合种 | 不建立通用 `sum_j z<=1` | 保留混种 |
| C21 | 正常销售量有限 | `q<=demand` | demand 来自 2023 产量 |
| C22 | 总产量守恒 | `q+e=sum yield*x` | 等式约束 |
| C23 | 情形1滞销 | alpha=0 | 模型不变 |
| C24 | 情形2半价 | alpha=0.5 | 模型不变 |
| C25 | 问题1参数稳定 | 七年复用 2023 参数 | 不预测、不随机化 |

---

# 8. allowed 构造

平旱地、梯田、山坡地：
- 单季 1—15。

水浇地：
- 单季 16；
- 第一季 17—34；
- 第二季 35—37。

普通大棚：
- 第一季 17—34；
- 第二季 38—41。

智慧大棚：
- 第一季 17—34；
- 第二季 17—34。

---

# 9. 水浇地模式约束

\[
x_{i,16,t,单季}\le A_ir_{it}
\]

\[
\sum_{j=17}^{34}x_{ijt,第一季}\le A_i(1-r_{it})
\]

\[
\sum_{j=35}^{37}x_{ijt,第二季}\le A_i(1-r_{it})
\]

以及：

\[
\sum_{j=35}^{37}z_{ijt,第二季}\le1.
\]

当前不要擅自增加“两季模式必须两季都种满”等额外硬约束。

---

# 10. 连续重茬

先构造每块地的真实种植时段 adjacency。

单季：

```text
2023单季 -> 2024单季 -> ... -> 2030单季
```

两季：

```text
2023最后实际季 -> 2024第一季 -> 2024第二季
-> 2025第一季 -> 2025第二季 -> ...
```

对同一作物：

\[
z_{current}+z_{next}\le1.
\]

必须输出 adjacency 数量和重茬约束数量。

---

# 11. 三年豆类

```python
BEAN_CROPS = {1,2,3,4,5,17,18,19}
```

滑动窗口：

- 2023—2025
- 2024—2026
- 2025—2027
- 2026—2028
- 2027—2029
- 2028—2030

采用：

\[
\sum z_{bean}\ge1.
\]

不擅自强化成三年豆类面积必须覆盖整个地块。

---

# 12. 稀疏变量

推荐只创建合法变量：

```python
x_keys = [(i,j,t,k) for ... if allowed[i,j,k]]
x = model.addVars(x_keys, lb=0.0, vtype=GRB.CONTINUOUS, name="x")
z = model.addVars(x_keys, vtype=GRB.BINARY, name="z")
```

q/e 只对可能产出的 `(j,t,k)` 创建，r 只对水浇地创建。

---

# 13. Python 工程结构

```text
C2024/code_q1/
├─ main.py
├─ config.py
├─ requirements.txt
├─ data/
│  ├─ __init__.py
│  ├─ read_clean.py
│  ├─ build_allowed.py
│  ├─ build_history.py
│  ├─ build_parameters.py
│  └─ validate_data.py
├─ model/
│  ├─ __init__.py
│  ├─ build_model.py
│  ├─ solve.py
│  └─ validate_solution.py
├─ output/
│  ├─ __init__.py
│  ├─ export_results.py
│  └─ plots.py
├─ sensitivity/
│  ├─ __init__.py
│  └─ run_sensitivity.py
└─ results/
   ├─ data_audit/
   ├─ alpha_0/
   ├─ alpha_05/
   └─ sensitivity/
```

---

# 14. 模块 A：数据清洗与审计

必须先完成和运行。

`config.py`：

```python
YEARS = list(range(2024, 2031))
SEASONS = ["单季", "第一季", "第二季"]
BETA = 0.5
NMAX = 3
ALPHA_LIST = [0.0, 0.5]
RANDOM_SEED = 42
```

`validate_data.py` 必须检查：

1. 54 地块；
2. 41 作物；
3. 各类型面积；
4. 作物类别；
5. 2023 记录数；
6. 参数记录数；
7. 编号冲突；
8. 所有 2023 记录匹配参数；
9. 是否有 allowed=0 的历史种植；
10. 面积是否超容；
11. price 区间解析；
12. demand 计算；
13. beta=0.5 历史证据；
14. 2023 分散地块数；
15. allowed=1 是否有对应参数。

如果失败，停止，不进入模型。

---

# 15. 模块 B：Gurobi MILP

接口建议：

```python
def build_model(data, cfg, alpha: float):
    ...
    return model, vars_dict, meta
```

约束添加顺序：

1. x-z 关联；
2. 土地面积；
3. 水浇地模式；
4. 特殊第二季唯一性；
5. 重茬；
6. 三年豆类；
7. 分散度；
8. 销售守恒；
9. 需求上限；
10. 目标函数。

每类约束必须命名和计数，便于 IIS。

Gurobi 参数集中配置，`MIPFocus` 不要盲目设置。

若 infeasible：

```python
model.computeIIS()
model.write("infeasible.ilp")
```

然后报告冲突，不自行删约束。

---

# 16. 求解后独立验证

至少检查：

- x 非负；
- z 为 0/1；
- 面积约束；
- x-z 关联；
- allowed；
- 水浇地模式；
- 第二季唯一特殊蔬菜；
- 重茬；
- 三年豆类；
- Nmax；
- q+e 守恒；
- q<=demand；
- 手工重算利润 = Gurobi ObjVal；
- MIPGap；
- 求解时间。

任何核心约束违反则 FAIL。

---

# 17. 模块 C：结果导出

种植明细至少：

- 年份
- 季次
- 地块
- 地块类型
- 作物编号
- 作物名称
- 种植面积
- 亩产量
- 产量
- 销售价格
- 单亩成本
- 种植成本

q/e 是 `(作物,年份,季次)` 汇总变量，不能复制到每块地导致重复统计。

读取 `附件3/` 模板，使用 openpyxl 写入新文件，不覆盖模板。

输出：

- `result1_1.xlsx`
- `result1_2.xlsx`

---

# 18. 可视化

至少：

1. 七年利润折线；
2. 两种 alpha 总利润对比；
3. 作物类别面积结构；
4. 土地利用率；
5. 正常销量 vs 超产量；
6. 年度种植结构变化；
7. 分散地块数；
8. 必要时种植热力图。

300 DPI，中文字体正常，保存图对应数据表。

---

# 19. 模块 D：敏感性/稳健性

只有基准模型通过后运行。

```python
beta_list = [0.3, 0.4, 0.5, 0.6]
nmax_list = [2, 3, 4, 5, 6]
```

每个组合重新完整求解。

比较：

- 可行性
- 总利润
- 利润相对变化
- 总面积
- 土地利用率
- 超产量
- 分散度
- 结构变化率
- 求解时间
- MIPGap

---

# 20. main.py 推荐顺序

```python
def main():
    cfg = load_config()
    np.random.seed(cfg.RANDOM_SEED)

    raw = read_raw_excel(cfg)
    clean = clean_data(raw, cfg)
    data = build_all_parameters(clean, cfg)

    audit = validate_data(data, cfg)
    if not audit.passed:
        raise RuntimeError("数据审计未通过")

    solutions = {}

    for alpha in [0.0, 0.5]:
        model, vars_dict, meta = build_model(data, cfg, alpha)
        result = solve_model(model, cfg, alpha)
        check = validate_solution(data, cfg, alpha, model, vars_dict, result)

        if not check.passed:
            raise RuntimeError(f"alpha={alpha} 解验证未通过")

        export_results(...)
        make_plots(...)
        solutions[alpha] = ...

    compare_scenarios(solutions, cfg)
    run_sensitivity(data, cfg)

if __name__ == "__main__":
    main()
```

---

# 21. 强制检查点

A 数据审计通过后才能 B。

B 中先做小规模结构测试，但不能改变约束含义。

完整 alpha=0 通过后再 alpha=0.5。

两个基准情形都通过后才能运行敏感性。

---

# 22. 禁止的常见错误

1. 维度混乱；
2. 文本写入数值参数；
3. 价格区间没解析；
4. 普通大棚第二季错误限制只能一种菌；
5. 所有地块都 `sum_j z<=1`；
6. 漏 2023 历史；
7. 重茬只做同季跨年；
8. 智慧大棚第一季参数当缺失；
9. 35—37 到处可种；
10. 食用菌进入智慧大棚；
11. demand 用统一亩产量；
12. q/e 重复统计；
13. 无解后自行删约束；
14. 私自改 beta/Nmax；
15. 不做独立结果复核；
16. 擅自加“必须种满”等硬约束；
17. 用网络题解参数覆盖附件；
18. 只生成代码不实际运行审计和验证。

---

# 23. 无解/异常处理

`GRB.INFEASIBLE` 时：

1. computeIIS；
2. 写出 `.ilp`；
3. 汇总冲突约束类型；
4. 优先检查 Nmax、beta、三年豆类、2023 边界、水浇地模式；
5. 报告用户，等待决定。

可行但出现大面积闲置、利润异常、大量超产、某类作物完全消失等，也要诊断。

---

# 24. 论文—代码映射

| 论文内容 | Python 模块 |
|---|---|
| 数据清洗与描述 | `data/read_clean.py`, `data/validate_data.py` |
| 适宜性矩阵 | `data/build_allowed.py` |
| 2023 历史与 demand | `data/build_history.py` |
| 参数 | `data/build_parameters.py` |
| 决策变量/目标/约束 | `model/build_model.py` |
| 求解 | `model/solve.py` |
| 约束和利润复核 | `model/validate_solution.py` |
| Excel | `output/export_results.py` |
| 图形 | `output/plots.py` |
| 敏感性 | `sensitivity/run_sensitivity.py` |

---

# 25. 参数状态

| 项目 | 当前值/规则 |
|---|---|
| 模型 | 单目标 MILP |
| 目标 | 七年总利润最大 |
| 需求 | 2023 实际产量 |
| 价格 | 区间中点 |
| alpha1 | 0 |
| alpha2 | 0.5 |
| beta | 0.5 |
| Nmax | 最多 3 块 |
| 豆类 | 1,2,3,4,5,17,18,19 |
| 技术栈 | Python + gurobipy |

---

# 26. Codex 最终执行要求

1. 先读 `cumcm-modeling-workflow/SKILL.md` 和本文档；
2. 读取原始题目和 Excel，不参考网络题解；
3. 先实现并运行模块 A；
4. 向用户展示真实审计结果；
5. A 通过后再 B；
6. B 基准通过后再 C；
7. D 最后运行；
8. 不确定/冲突/无解必须暂停并请求用户决定；
9. 原附件只读；
10. 详细中文注释；
11. 函数输入输出明确；
12. 关键约束必须命名；
13. 最终提供一键 `main.py`；
14. 结果包含 `result1_1.xlsx`、`result1_2.xlsx`、审计、验证、图形。
