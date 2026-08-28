# 2024 全国大学生数学建模竞赛 C 题——问题1 MATLAB + Gurobi 10.0.1 迁移与实现指令

> 本文件供 Codex 直接读取并执行。
>
> **重要：立即停止继续开发 Python 模块 B。后续问题1统一改为 MATLAB + Gurobi 10.0.1。**
>
> Python 版本的模块 A 已经经过多轮审查并正式放行，其建模口径、数据清洗逻辑、审计结论、历史状态、需求 support、参数定义等均视为当前基准真值。MATLAB 版本不得自行重新解释题意或改变这些口径。

---

# 1. 技术栈与版本约束

固定使用：

- MATLAB；
- Gurobi Optimizer 10.0.1；
- MATLAB Gurobi API；
- Excel 读取使用 `readtable` / `readcell` / `detectImportOptions` 等 MATLAB 原生方法；
- 结果输出使用 `writetable` / `writematrix`；
- 不再依赖 Python、gurobipy、conda 或 Python 虚拟环境。

求解必须使用 Gurobi MATLAB 原生矩阵接口：

```matlab
result = gurobi(model, params);
```

模型结构使用：

```matlab
model.A
model.obj
model.rhs
model.sense
model.vtype
model.lb
model.ub
model.modelsense = 'max';
```

不得改用 `intlinprog` 作为最终求解器。

---

# 2. 必须先读取的仓库文件

开始编码前必须读取：

1. `cumcm-modeling-workflow/SKILL.md`
2. `C2024/CODEX_问题1_Python_Gurobi_建模与代码实现指南.md`
3. `C2024/REVIEW_ChatGPT_模块A_第四轮.md`（若该文件实际位于 `C2024/code_q1/`，以仓库现有路径为准）
4. `C2024/code_q1/` 下已经审查通过的 Python 模块 A 代码
5. `C2024/code_q1/results/data_audit/audit_report.md`
6. `C2024/C题.pdf`
7. `C2024/附件1.xlsx`
8. `C2024/附件2.xlsx`

Python 模块 A 的作用不是继续运行，而是作为 MATLAB 迁移时的数据口径与逻辑参考。

---

# 3. MATLAB 项目目录

新建：

```text
C2024/code_q1_matlab/
├── main.m
├── config_q1.m
├── README.md
├── data/
│   ├── read_clean_data.m
│   ├── build_allowed.m
│   ├── build_parameters.m
│   ├── build_history.m
│   └── validate_data.m
├── model/
│   ├── build_MILP.m
│   ├── solve_model.m
│   └── validate_solution.m
├── output/
│   ├── output_results.m
│   └── plot_results.m
├── sensitivity/
│   └── sensitivity_analysis.m
└── results/
```

不要覆盖现有 `code_q1/` Python 工程；MATLAB 版本必须独立放在 `code_q1_matlab/`。

---

# 4. MATLAB 模块 A 必须复现的审计结果

MATLAB 模块 A 不能重新猜测数据规则，必须复现 Python 模块 A 已审核通过的结果。

至少必须得到：

```text
地块数 = 54
作物数 = 41
2023种植记录 = 87
原始统计参数记录 = 107
allowed 的地块类型-作物-季次参数组合 = 125
未来作物-季次 demand support = 59
正需求组合 = 47
零需求组合 = 12
history_z_2023 正状态 = 87
2023种过豆类的地块数 = 19
Nmax=3 的历史冲突组合数 = 3
```

Nmax 历史冲突应明确复现：

```text
crop 41 第二季：7块
crop 6 单季：4块
crop 17 第一季：4块
```

MATLAB 审计不满足上述结果时，不得进入 MILP。

---

# 5. 数据清洗口径

必须复现以下清洗：

1. 文本字段去首尾空格；
2. 2023种植表中合并单元格导致的空地块名按上一有效值向下填充；
3. 附件1作物表只保留数值作物编号记录；
4. 附件2统计表只保留数值作物编号记录；
5. 价格区间解析为 `low/high/mid`，问题1取中点；
6. 智慧大棚第一季参数继承普通大棚第一季；
7. 检查 `(crop_id, land_type, season)` 参数键唯一；
8. 检查所有历史种植记录都能匹配参数；
9. 检查所有 allowed 组合参数 `yield>0, cost>=0, price>0`；
10. 验证同一 `(crop_id, season)` 跨地块类型售价一致，可安全降维为 `price(j,k)`。

---

# 6. 固定集合与统一维度

统一维度顺序必须始终为：

```text
i × j × t × k
```

其中：

```matlab
I = 54;
J = 41;
T = 7;
K = 3;
years = 2024:2030;
```

季次建议固定编码：

```matlab
K_SINGLE = 1;
K_FIRST  = 2;
K_SECOND = 3;
```

主决策变量语义：

```matlab
x(i,j,t,k) >= 0
z(i,j,t,k) binary
```

即使实际采用稀疏变量编号，也必须保留 `x_id(i,j,t,k)` 与 `z_id(i,j,t,k)` 映射，非法组合编号为 0。

---

# 7. 作物集合

固定：

```matlab
grainCrops = 1:15;
riceCrop = 16;
firstSeasonVegetables = 17:34;
secondSeasonWaterVegetables = 35:37;
mushroomCrops = 38:41;
beanCrops = [1 2 3 4 5 17 18 19];
```

不得自行改变豆类集合。

---

# 8. allowed 规则

必须复现：

### 平旱地 / 梯田 / 山坡地

- 仅单季；
- 仅 1—15；
- 水稻16不允许。

### 水浇地

- 单季：仅水稻16；
- 第一季：17—34；
- 第二季：35—37。

### 普通大棚

- 第一季：17—34；
- 第二季：38—41。

### 智慧大棚

- 第一季：17—34；
- 第二季：17—34。

### 全局排他

- 35—37 只能水浇地第二季；
- 38—41 只能普通大棚第二季；
- 16 只能水浇地单季。

---

# 9. 需求基准

问题1未来需求固定使用2023实际产量：

```math
D_{jk}=Q^{2023}_{jk}
```

未来七年不变。

必须使用所有未来 allowed 的 `(crop_id, season)` 作为完整 support。

因此：

- 47 个2023实际出现的组合：按2023实际产量计算正需求；
- 12 个未来 allowed 但2023未种植组合：明确设为 `D=0`。

不得遗漏零需求组合。

---

# 10. 基准管理参数

固定：

```matlab
beta = 0.5;
Nmax = 3;
```

其中：

```math
beta A_i z_{ijtk} <= x_{ijtk} <= A_i z_{ijtk}
```

Nmax：

```math
sum_i z_{ijtk} <= Nmax
```

注意：`Nmax=3` 是管理假设，不是题面硬常数，且比2023部分实际经营更严格。后续必须做：

```matlab
NmaxList = 3:7;
```

的敏感性分析。

beta 后续建议：

```matlab
betaList = [0.3 0.4 0.5 0.6];
```

---

# 11. 决策变量

至少建立：

### 11.1 种植面积

```math
x_{ijtk} >= 0
```

### 11.2 是否种植

```math
z_{ijtk} in {0,1}
```

### 11.3 正常销售量

```math
q_{jtk} >= 0
```

对 59 个 demand support 组合 × 7年建立。

### 11.4 超产量

```math
e_{jtk} >= 0
```

对 59 个 demand support 组合 × 7年建立。

### 11.5 水浇地模式变量

```math
r_{it} in {0,1}
```

仅水浇地建立：

- `r=1`：该年采用单季水稻；
- `r=0`：该年采用两季蔬菜。

---

# 12. 目标函数

总产量：

```math
Q_{jtk}=sum_i Y_{ijk}x_{ijtk}
```

销售拆分：

```math
q_{jtk}+e_{jtk}=Q_{jtk}
```

```math
0 <= q_{jtk} <= D_{jk}
```

目标：

```math
max Z = sum_{j,t,k} P_{jk}(q_{jtk}+alpha e_{jtk})
        - sum_{i,j,t,k} C_{ijk}x_{ijtk}
```

两种情形：

```matlab
alpha = 0;      % 情形1：超产滞销
alpha = 0.5;    % 情形2：超产半价销售
```

禁止使用 `min()` 或 `max()` 直接写非线性目标。

---

# 13. 必须实现的约束完整清单

## C1 地块面积容量

```math
sum_j x_{ijtk} <= A_i
```

只对有效地块-季次建立。

不要默认改成等式。

---

## C2 x-z 关联与最小面积

```math
beta A_i z_{ijtk} <= x_{ijtk} <= A_i z_{ijtk}
```

---

## C3 allowed

非法组合不得创建变量；或等价固定为0。

优先采用稀疏变量，只对 `allowed=1` 建 `x,z`。

---

## C4 水浇地水稻 / 两季蔬菜模式互斥

必须严格使用 `r(i,t)`。

建议：

```math
z_{i,16,t,single} = r_{it}
```

```math
sum_{j=17}^{34} z_{ij,t,first} >= 1-r_{it}
```

```math
sum_{j=35}^{37} z_{ij,t,second} = 1-r_{it}
```

这组约束确保“选择某模式”就实际种植，而不是只允许但空置。

面积容量仍使用 `<=A_i`，不要强制整块面积必须用满。

---

## C5 普通大棚实际两季种植

每年：

```math
sum_{j=17}^{34} z_{ij,t,first} >= 1
```

```math
sum_{j=38}^{41} z_{ij,t,second} >= 1
```

允许混种。

禁止擅自增加“第二季食用菌只能一种”。

---

## C6 智慧大棚实际两季种植

每年：

```math
sum_{j=17}^{34} z_{ij,t,first} >= 1
```

```math
sum_{j=17}^{34} z_{ij,t,second} >= 1
```

允许混种。

---

## C7 同地同季允许混种

绝对禁止建立通用：

```math
sum_j z_{ijtk} <= 1
```

附件2明确存在同地同季混种。

唯一“只能一种”的规则是水浇地第二季 35—37，且已由模式等式实现。

---

## C8 连续重茬约束

不得简单写所有作物“同一季跨年不能重复”。

必须按真实时间链建立 chronological adjacency。

### 平旱地 / 梯田 / 山坡地

相邻年份单季：

```math
z_{ij,t,single}+z_{ij,t+1,single} <= 1
```

### 智慧大棚

同年第一季→第二季：

```math
z_{ij,t,first}+z_{ij,t,second} <= 1
```

跨年第二季→下一年第一季：

```math
z_{ij,t,second}+z_{ij,t+1,first} <= 1
```

### 普通大棚

第一季蔬菜与第二季菌类作物集合不重叠，因此不应机械禁止“第一季同作物跨年重复”。中间有菌类季，不属于连续重茬。

### 水浇地

- 水稻模式连续年份水稻不得重茬；
- 蔬菜模式第一季17—34与第二季35—37集合不重叠，因此同一第一季蔬菜跨年一般不是连续重茬；
- 必须依据真实相邻季次和作物可行集合判断。

优先编写统一 adjacency 生成逻辑，而不是散落硬编码。

---

## C9 2023→2024 历史重茬边界

使用已经审计通过的：

```text
history_z_2023
adjacency_2023_to_2024
```

2023最后实际种植时段和2024首个决策时段若同一作物在两端均可行，则：

```math
history_z_2023 + z_2024 <= 1
```

不得忽略2023历史状态。

---

## C10 三年豆类约束

豆类集合固定：

```matlab
beanCrops = [1 2 3 4 5 17 18 19];
```

任意连续三年：

```math
sum_{tau=t}^{t+2} sum_{j in bean} sum_k z_{ij tau k} >= 1
```

对于第一个窗口 2023—2025：

```math
historyBean2023(i) +
sum_{tau=2024}^{2025} sum_{j in bean} sum_k z_{ij tau k} >= 1
```

后续窗口：

```text
2024-2026
2025-2027
2026-2028
2027-2029
2028-2030
```

必须全部建立。

---

## C11 分散度

```math
sum_i z_{ijtk} <= Nmax
```

基准 `Nmax=3`。

---

## C12 产量守恒

```math
q_{jtk}+e_{jtk}=sum_i Y_{ijk}x_{ijtk}
```

对全部 59 个未来作物-季次 support、全部7年建立。

---

## C13 正常销量上限

```math
q_{jtk} <= D_{jk}
```

12个零需求组合必须因此自动得到 `q=0`。

情形2中这些组合仍可能通过 `e` 半价销售，这与当前模型口径一致。

---

# 14. 稀疏变量编号要求

为了 Gurobi 10.0.1 求解效率，禁止无脑给所有 `54×41×7×3` 组合创建 x/z。

要求：

```matlab
x_id = zeros(I,J,T,K);
z_id = zeros(I,J,T,K);
```

遍历 allowed：

```matlab
if allowed(i,j,k)
    % 分配变量编号
end
```

非法组合保持0。

q/e 可以按 59 个 support 稀疏建变量映射，例如：

```matlab
q_id(j,t,k)
e_id(j,t,k)
```

仅 support 中存在的 `(j,k)` 分配编号。

r 仅对8块水浇地 × 7年分配。

---

# 15. Gurobi 10.0.1 模型实现要求

使用稀疏矩阵逐步添加约束。

推荐自行维护：

```matlab
A_i = [];
A_j = [];
A_v = [];
rhs = [];
sense = '';
constraint_names = {};
```

最终：

```matlab
model.A = sparse(A_i,A_j,A_v,nConstr,nVar);
```

变量类型：

```matlab
'C' % x,q,e
'B' % z,r
```

模型：

```matlab
model.modelsense = 'max';
```

Gurobi 参数至少配置化：

```matlab
params.OutputFlag = 1;
params.MIPGap = ...;
params.TimeLimit = ...;
params.Threads = ...;
params.Seed = 42;
```

不要使用 Gurobi 13 专属接口或语法。

---

# 16. 求解顺序

第一阶段只完成：

```matlab
alpha = 0;
```

即情形1。

不要在第一版同时实现 alpha=0.5、全部图形、敏感性分析。

先完成：

1. MATLAB 模块 A 复现并 PASS；
2. `build_MILP.m`；
3. `solve_model.m`；
4. alpha=0 成功求解；
5. `validate_solution.m` 独立复核；
6. 保存求解日志和关键摘要；
7. 提交 GitHub，等待 ChatGPT 审查。

只有 alpha=0 通过审查后再做 alpha=0.5。

---

# 17. 求解状态与 IIS

求解后必须检查：

```matlab
result.status
```

若 infeasible：

不得自行放宽约束。

应使用 Gurobi IIS 功能或导出模型诊断，并停止向用户汇报冲突证据。

不得自行修改 beta、Nmax、豆类约束或模式逻辑来“让模型有解”。

---

# 18. validate_solution.m 必须独立验证

不要只相信 Gurobi `OPTIMAL`。

从 `result.x` 重新还原并检查：

- x,z关联；
- 面积容量；
- allowed；
- 水浇地模式；
- 大棚两季实际占用；
- 水浇地第二季唯一作物；
- chronological no-repeat；
- 2023历史边界；
- 三年豆类窗口；
- Nmax；
- q/e产量守恒；
- q<=demand；
- 目标函数重新计算；
- 最大约束残差。

输出：

```text
solution_validation.csv
solution_validation_summary.txt
```

任何硬约束违反大于容差时，不得继续输出最终种植方案。

建议容差：

```matlab
tol = 1e-6;
```

---

# 19. 情形1结果输出

alpha=0 通过验证后，输出：

```text
result1_1.xlsx
```

至少包含：

- 年份；
- 季次；
- 地块；
- 地块类型；
- 作物编号；
- 作物名称；
- 种植面积；
- 亩产量；
- 产量；
- 正常销售量；
- 超产量；
- 销售价格；
- 单位面积成本；
- 成本；
- 收入；
- 利润贡献。

同时输出年度摘要：

- 总利润；
- 正常销售量；
- 超产量；
- 土地利用率；
- 各作物种植面积；
- 每作物分散地块数。

---

# 20. 后续情形2

情形1审查通过后，只改变：

```matlab
alpha = 0.5;
```

重新构建和求解新模型。

输出：

```text
result1_2.xlsx
```

不要复用上一次 `result.x` 或通过修改结果计算情形2。

---

# 21. 敏感性分析

必须真实重新求解模型，不得只改标签。

至少：

```matlab
NmaxList = [3 4 5 6 7];
betaList = [0.3 0.4 0.5 0.6];
```

比较：

- 总利润；
- 超产量；
- 土地利用率；
- 模型状态；
- MIP Gap；
- 求解时间；
- 种植结构变化。

---

# 22. 当前禁止事项

Codex 不得：

1. 继续开发 Python 模块 B；
2. 修改已通过的需求定义；
3. 把 12 个零需求组合删除；
4. 把 `Nmax=3` 解释成题面硬常数；
5. 擅自改 `Nmax` 解决 infeasible；
6. 擅自改 `beta` 解决 infeasible；
7. 建立通用 `sum_j z<=1`；
8. 强制所有地块面积等于满种；
9. 限制普通大棚第二季只能一种菌；
10. 用“同季跨年禁止重复”替代真实 chronological 重茬；
11. 忽略2023历史状态；
12. 使用 Gurobi 13 专属接口；
13. 因本地/连接器无法上传大CSV或PNG而省略生成逻辑。

---

# 23. 本地衍生结果上传限制

若连接器无法上传附件衍生的大 CSV / PNG：

- 仍必须在本地生成；
- 在 GitHub 提交生成代码；
- 在仓库提交可公开的摘要报告、关键计数、异常记录和文件清单；
- 不得声称“没有生成”；
- 后续 ChatGPT 如需逐行核验，用户可手动上传指定文件。

---

# 24. 当前 Codex 第一阶段任务

现在只执行以下工作：

```text
A. 创建 code_q1_matlab 项目结构
B. 将已审核通过的 Python 模块A完整迁移为 MATLAB
C. 实际运行 MATLAB 模块A并复现全部关键审计数字
D. 实现 MATLAB + Gurobi 10.0.1 的 build_MILP.m
E. 只求解 alpha=0
F. 实现并运行 validate_solution.m
G. 提交代码、审计摘要、模型摘要、求解状态与验证摘要
H. 停止，等待 ChatGPT 审查
```

如果在任何阶段遇到：

- 数据审计数字与 Python 基准不一致；
- Gurobi 10.0.1 API 不兼容；
- 模型 infeasible；
- 约束解释不明确；
- 需要改变模型含义；

必须停止并汇报证据，不得自行改变建模口径。
