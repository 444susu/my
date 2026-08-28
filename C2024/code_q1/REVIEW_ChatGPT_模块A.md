# ChatGPT 审查意见：C2024 问题1 模块 A

## 结论

当前提交只完成了 **模块 A：数据读取、机械清洗、参数构建和数据审计**，尚未实现模块 B 的 Gurobi MILP。总体方向正确，现有 15 项审计均 PASS，但按照既定 Skill 与实现指南，**模块 A 还不能视为完全闭环**。建议修正/补强以下项目后再进入模块 B。

状态建议：**异常但不改变模型方向，需要补强后通过门控。**

---

## A. 必须修正后再进入模块 B

### A1. 缺少 2023 历史 0-1 状态 `history_z_2023`

当前 `build_history_and_demand()` 只返回：

- history 明细；
- demand；
- dispersal。

但后续重茬约束必须显式知道：

`history_z_2023[(plot_id,crop_id,season)] = 1/0`

否则无法可靠建立“2023 -> 2024”的历史边界约束。

要求：在 `build_history.py` 中生成并保存 2023 种植状态表/字典，并在 `validate_data.py` 中增加门控检查。

### A2. 缺少 `history_bean_2023[i]`

三年豆类第一个滑动窗口是 2023—2025，必须知道每个地块 2023 是否已经种过豆类。

要求生成：

`history_bean_2023[plot_id] in {0,1}`

豆类集合固定：`{1,2,3,4,5,17,18,19}`。

并验证 54 个地块全部有明确状态。

### A3. 缺少后续重茬所需的历史“最后实际种植时段”/ adjacency 基础

实现指南要求预处理阶段建立真实种植时间链。当前没有保存 2023 每块地最后实际种植季，也没有 adjacency 数据结构。

模块 B 前至少应形成可直接使用的基础信息，例如：

- 单季土地：2023单季 -> 2024单季；
- 普通/智慧大棚：2023第二季 -> 2024第一季；
- 水浇地：按 2023 实际模式判断最后季次，再与 2024 的真实相邻季衔接。

不能到模型函数中再临时猜测。

### A4. “所有 allowed 组合均有参数”的检查不够严格

当前检查只比较 `(land_type,crop_id,season)` 键是否存在。即使某 allowed 参数行存在但 `yield/cost/price` 为 NaN，也可能通过。

要求对所有 allowed 组合进一步验证：

- `yield_jin_per_mu` 非空且 > 0；
- `cost_yuan_per_mu` 非空且 >= 0；
- `price_mid` 非空且 > 0；
- 继承后的智慧大棚第一季参数同样满足。

### A5. Nmax=3 与 2023 历史分散度存在冲突证据，但当前报告没有展示

根据附件2实际记录统计，至少存在：

- 作物 41，第二季：2023 分布于 7 个地块；
- 作物 17，第一季：4 个地块；
- 作物 6，单季：4 个地块。

因此 `Nmax=3` 比部分 2023 历史经营方式更严格。

这里**不要求修改 Nmax=3**，因为这是用户明确选定的基准参数；但必须在审计报告中标记为：

**“异常但不改变模型方向：当前基准约束比历史实际更严格，后续必须重点做 Nmax 敏感性分析。”**

不能只检查“dispersal 表已生成”就直接 PASS 而不展示与 Nmax 的比较。

---

## B. 应补强的审计项

### B1. 地块 ID 唯一性和面积合法性

增加：

- `plot_id` 唯一；
- 54 个地块 ID 无空值；
- `area_mu > 0`；
- land_type 仅属于六种题面类型。

### B2. 作物编号集合完整性

当前仅检查 41 行和名称/类别冲突，但“41 行”不能完全证明编号就是 1—41 且无重复。

增加：

`set(crop_id) == set(range(1,42))`

以及 `crop_id.nunique()==41`。

### B3. demand 覆盖所有 41 种作物

当前检查只保证“已经出现的 crop-season 组合 demand>0”。建议再检查：

`set(demand.crop_id) == {1,...,41}`

确保 2023 历史需求基准覆盖所有作物。

### B4. 2023 历史面积最好同时检查“利用率”

目前仅检查未超容量。建议额外输出：

`utilization = plant_area_mu / area_mu`

并标明哪些真实季次达到 1、哪些低于 1。该结果可为后续是否允许闲置土地提供数据证据。

### B5. 保留原 Excel 行号

清洗后建议增加 `source_row`，方便任何异常追溯到附件原始行。这符合 Skill 的可追溯要求。

---

## C. 输出与可视化需要修正

### C1. 审计报告中的文件名与实际代码不一致

报告写：

- `parameters_with_inheritance.csv`
- `demand_baseline.csv`

实际代码保存的是：

- `clean_parameters.csv`
- `clean_demand.csv`
- `parameter_inheritance_smart_greenhouse_first_season.csv`

请统一文档和真实输出名。

### C2. 需求图 x 轴标签不准确

`demand` 有 47 个“作物—季次”组合，但图中 x 轴实际只传了 `crop_id`，同一作物不同季次会出现重复编号。

建议使用：

`label = f"{crop_id}-{season}"`

或按季次分图。

### C3. 缺失值图建议按数据表分别展示

当前把四张表同名字段汇总到一个 Series，会降低可追溯性。建议保存一张“表名×字段”的缺失明细表，并按表分组作图。

### C4. 价格检查实际值显示为“有效=1”不够直观

当前 `price_valid` 是单个布尔值，所以报告出现“有效=1”。建议输出：

- 有效记录数 / 107；
- 解析失败记录数；
- 非法区间数。

---

## D. 仓库审查材料

仓库当前只提交了：

- `audit_checks.csv`
- `audit_report.md`
- `audit_summary.json`

Codex 表示完整清洗 CSV 和 PNG 保存在本地。为了后续 ChatGPT 能复核真实数据结果，建议至少把以下基准审计产物提交到仓库：

- `clean_land.csv`
- `clean_crop.csv`
- `clean_plant_2023.csv`
- `clean_statistics_2023.csv`
- `clean_parameters.csv`
- `clean_allowed.csv`
- `clean_history_2023.csv`
- `clean_demand.csv`
- `clean_dispersal.csv`
- `detail_historical_area_ratios.csv`
- `detail_plot_season_capacity.csv`
- 3 张审计 PNG。

如果不希望长期提交大量结果，可以单独建立 `results/data_audit/baseline/` 保存这一版基准证据。

---

## E. 当前认可的部分

以下实现方向正确，可保留：

1. Excel 按原始 sheet 名读取；
2. 文本首尾空格清理；
3. 合并单元格地块名 `ffill`；
4. 价格区间中点解析；
5. `allowed` 的土地—作物—季次规则总体正确；
6. 智慧大棚第一季参数继承普通大棚第一季；
7. demand 使用 2023 实际种植面积 × 对应参数亩产量计算；
8. `beta=0.5` 的历史最小面积比例证据正确；
9. 当前没有提前进入 MILP，符合门控流程。

---

## F. 下一步门控

Codex 请先完成 A1—A5 和 B1—B3，重新运行模块 A，并提交新的：

- `audit_report.md`；
- `audit_checks.csv`；
- 基准审计 CSV/PNG；
- 新增的 2023 历史状态与 adjacency 结果。

只有新的模块 A 审查通过后，再进入模块 B 的 Gurobi MILP。
