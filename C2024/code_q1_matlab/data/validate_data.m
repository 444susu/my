function audit = validate_data(data, cfg)
%VALIDATE_DATA Module A hard gate. Any hard failure blocks MILP.
% MATLAB target: R2024a.

land = data.land;
crop = data.crop;
plant = data.plant2023;
statistics = data.statistics2023;
parameters = data.parameters;
allowed = data.allowed;
allowedRows = data.allowedRows;
history = data.history;
demand = data.demand;
dispersal = data.dispersal;
historyZ = data.historyZ;

names = cell(0,1);
ok = false(0,1);
expected = cell(0,1);
actual = cell(0,1);
impact = cell(0,1);
state = cell(0,1);

    function addcheck(name, passed, expText, actualText, impactText, requestedStatus)
        names{end+1,1} = name;
        ok(end+1,1) = logical(passed);
        expected{end+1,1} = expText;
        actual{end+1,1} = actualText;
        impact{end+1,1} = impactText;
        if passed
            state{end+1,1} = requestedStatus;
        else
            state{end+1,1} = 'FAIL';
        end
    end

%% Basic dimensions and master data
validTypes = {'平旱地','梯田','山坡地','水浇地','普通大棚','智慧大棚'};

addcheck('地块数量', height(land) == 54, '54', num2str(height(land)), ...
    '地块集合错误会改变模型维度。', 'PASS');

plotNonempty = all(~cellfun(@isempty, land.plot_id));
plotUnique = numel(unique(land.plot_id)) == 54;
addcheck('地块ID唯一且非空', plotNonempty && plotUnique, ...
    '54个唯一、非空地块ID', ...
    sprintf('非空=%d，唯一=%d', sum(~cellfun(@isempty,land.plot_id)), numel(unique(land.plot_id))), ...
    '地块索引会错误合并。', 'PASS');

validAreaType = all(~isnan(land.area_mu)) && all(land.area_mu > 0) && ...
    all(ismember(land.land_type, validTypes));
addcheck('地块面积与类型合法', validAreaType, ...
    '面积>0且仅六种题面类型', ...
    sprintf('非正/缺失面积=%d，非法类型=%d', ...
    sum(isnan(land.area_mu) | land.area_mu <= 0), sum(~ismember(land.land_type,validTypes))), ...
    '容量或适宜性约束不可用。', 'PASS');

addcheck('作物数量', height(crop) == 41, '41', num2str(height(crop)), ...
    '作物集合错误会改变适宜性和决策变量。', 'PASS');

cropIdOK = isequal(sort(crop.crop_id(:))', 1:41);
addcheck('作物编号集合完整', cropIdOK, '编号1—41各一次', ...
    sprintf('唯一数=%d', numel(unique(crop.crop_id))), ...
    '作物集合或固定豆类集合可能错误。', 'PASS');

typeOrder = {'平旱地','梯田','山坡地','水浇地','普通大棚','智慧大棚'};
wantArea = [365,619,108,109,9.6,2.4];
gotArea = zeros(1,6);
for ii = 1:6
    gotArea(ii) = sum(land.area_mu(strcmp(land.land_type,typeOrder{ii})));
end
addcheck('各地块类型面积', max(abs(gotArea-wantArea)) < 1e-9, ...
    mat2str(wantArea), mat2str(gotArea), ...
    '面积容量约束可能错误。', 'PASS');

%% Raw record counts and parameter keys
addcheck('2023种植记录数', height(plant) == 87, '87', num2str(height(plant)), ...
    '历史状态和需求基准可能不完整。', 'PASS');
addcheck('原始参数记录数', height(statistics) == 107, '107', num2str(height(statistics)), ...
    '附件参数表读取可能错误。', 'PASS');

pkey = strcat(string(parameters.crop_id), "|", string(parameters.land_type), "|", string(parameters.season));
parameterKeyOK = numel(unique(pkey)) == numel(pkey);
addcheck('参数编号键冲突', parameterKeyOK, '0个重复参数键', ...
    num2str(numel(pkey)-numel(unique(pkey))), ...
    '亩产、成本或价格存在歧义。', 'PASS');

% Do not use table brace extraction across heterogeneous cell/numeric columns.
unmatched = cellfun(@isempty, history.land_type) | ...
    isnan(history.yield_jin_per_mu) | ...
    isnan(history.cost_yuan_per_mu) | ...
    isnan(history.price_mid);
addcheck('所有2023记录匹配参数', ~any(unmatched), '0条未匹配', ...
    num2str(sum(unmatched)), '不能计算需求，必须停止。', 'PASS');

%% Historical binary states
historyZOK = sum(historyZ(:)) == 87 && all(ismember(historyZ(:),[0,1]));
addcheck('2023历史0-1种植状态', historyZOK, '87个历史正种植键', ...
    sprintf('正状态=%d', sum(historyZ(:))), ...
    '无法可靠建立2023→2024重茬边界。', 'PASS');

beanOK = numel(data.historyBean) == 54 && sum(data.historyBean) == 19 && ...
    all(ismember(data.historyBean,[0,1]));
addcheck('2023地块豆类历史状态', beanOK, '54个地块；种过豆类=19', ...
    sprintf('记录=%d，种过豆类=%d', numel(data.historyBean), sum(data.historyBean)), ...
    '第一个三年豆类窗口无法构建。', 'PASS');

adjBasicOK = height(data.adjacency) == 54 && ...
    all(~cellfun(@isempty,data.adjacency.last_season_2023));
addcheck('2023—2024历史邻接基础', adjBasicOK, '54块地均有最后实际季次', ...
    sprintf('记录=%d，空末季=%d', height(data.adjacency), ...
    sum(cellfun(@isempty,data.adjacency.last_season_2023))), ...
    '重茬约束无法按真实时间链构建。', 'PASS');

lastSeasonRules = containers.Map();
lastSeasonRules('平旱地') = {'单季'};
lastSeasonRules('梯田') = {'单季'};
lastSeasonRules('山坡地') = {'单季'};
lastSeasonRules('普通大棚') = {'第二季'};
lastSeasonRules('智慧大棚') = {'第二季'};
lastSeasonRules('水浇地') = {'单季','第二季'};
adjConsistent = true(height(data.adjacency),1);
for r = 1:height(data.adjacency)
    allowedLast = lastSeasonRules(data.adjacency.land_type{r});
    adjConsistent(r) = any(strcmp(data.adjacency.last_season_2023{r}, allowedLast));
end
addcheck('2023最后实际季次与地块制度一致', all(adjConsistent), ...
    '旱地/梯田/山坡地=单季；两类大棚=第二季；水浇地=单季或第二季', ...
    sprintf('异常地块=%d',sum(~adjConsistent)), ...
    '历史时间链与种植制度不一致，不能建立重茬边界。', 'PASS');

%% Historical suitability and capacity
historyAllowed = true(height(plant),1);
for r = 1:height(plant)
    i = find(strcmp(land.plot_id,plant.plot_id{r}),1,'first');
    k = find(strcmp(cfg.seasons,plant.season{r}),1,'first');
    j = plant.crop_id(r);
    historyAllowed(r) = ~isempty(i) && ~isempty(k) && ...
        j >= 1 && j <= 41 && allowed(i,j,k);
end
addcheck('2023历史种植适宜性', all(historyAllowed), '0条allowed=0历史记录', ...
    num2str(sum(~historyAllowed)), ...
    '题面适宜性规则或历史编码存在冲突。', 'PASS');

overCapacity = 0;
for i = 1:height(land)
    for k = 1:3
        mask = strcmp(plant.plot_id,land.plot_id{i}) & strcmp(plant.season,cfg.seasons{k});
        planted = sum(plant.plant_area_mu(mask));
        if planted > land.area_mu(i) + cfg.tolerance
            overCapacity = overCapacity + 1;
        end
    end
end
addcheck('2023面积未超地块容量', overCapacity == 0, ...
    '0个地块—季次超容量', num2str(overCapacity), ...
    '历史口径或数据存在冲突。', 'PASS');

%% Price and demand support
priceValid = all(~isnan(statistics.price_low)) && all(~isnan(statistics.price_high)) && ...
    all(~isnan(statistics.price_mid)) && all(statistics.price_low >= 0) && ...
    all(statistics.price_high >= statistics.price_low) && all(statistics.price_mid > 0);
addcheck('价格区间解析', priceValid, '107条有效low<=high区间', ...
    sprintf('有效=%d',sum(statistics.price_mid>0)), ...
    '价格参数不能进入目标函数。', 'PASS');

positiveDemand = sum(demand.demand_jin > 0);
zeroDemand = sum(demand.demand_jin == 0);
allowedSupportCount = 0;
supportOK = true;
for j = 1:41
    for k = 1:3
        if any(allowed(:,j,k))
            allowedSupportCount = allowedSupportCount + 1;
            matchCount = sum(demand.crop_id == j & demand.season_idx == k);
            supportOK = supportOK && (matchCount == 1);
        end
    end
end

demandBasicOK = height(demand) == 59 && numel(unique(demand.crop_id)) == 41 && ...
    all(~isnan(demand.demand_jin)) && all(demand.demand_jin >= 0);
addcheck('需求计算', demandBasicOK, '59键且覆盖41作物', ...
    sprintf('组合=%d，覆盖=%d，负/缺失=%d',height(demand),numel(unique(demand.crop_id)), ...
    sum(demand.demand_jin<0 | isnan(demand.demand_jin))), ...
    '销售上限无法构建。', 'PASS');

supportComplete = supportOK && allowedSupportCount == 59 && ...
    positiveDemand == 47 && zeroDemand == 12;
addcheck('未来可种植作物—季次需求support完整', supportComplete, ...
    'support=59，正需求=47，零需求=12', ...
    sprintf('support=%d，正需求=%d，零需求=%d',allowedSupportCount,positiveDemand,zeroDemand), ...
    'q/e产量守恒和销售上限无法覆盖全部未来合法生产组合。', 'PASS');

%% beta and Nmax evidence
ratios = history.plant_area_mu ./ history.area_mu;
betaOK = all(~isnan(ratios)) && abs(min(ratios)-cfg.beta) < cfg.tolerance && ...
    all(ratios >= cfg.beta-cfg.tolerance);
addcheck('beta=0.5历史证据', betaOK, '最小值=0.5且无值更低', ...
    sprintf('最小值=%.6g',min(ratios)), ...
    'beta管理参数缺乏已确认的数据证据。', 'PASS');

conflicts = dispersal(dispersal.plot_count_2023 > cfg.Nmax,:);
conflictOK = height(conflicts) == 3 && ...
    any(conflicts.crop_id==41 & conflicts.season_idx==3 & conflicts.plot_count_2023==7) && ...
    any(conflicts.crop_id==6 & conflicts.season_idx==1 & conflicts.plot_count_2023==4) && ...
    any(conflicts.crop_id==17 & conflicts.season_idx==2 & conflicts.plot_count_2023==4);
addcheck('Nmax=3与历史分散度比较', conflictOK, ...
    '3个冲突：41第二季=7；6单季=4；17第一季=4', ...
    sprintf('超过Nmax组合=%d',height(conflicts)), ...
    'WARNING：Nmax=3比部分2023经营更严格。', 'WARNING');

%% Allowed parameter values and safe price dimension reduction
% Use explicit key iteration rather than heterogeneous cell concatenation.
uniqueTypeCropSeason = unique(allowedRows(:,{'land_type','crop_id','season'}),'rows');
validParam = true(height(uniqueTypeCropSeason),1);
for r = 1:height(uniqueTypeCropSeason)
    lt = uniqueTypeCropSeason.land_type{r};
    j = uniqueTypeCropSeason.crop_id(r);
    season = uniqueTypeCropSeason.season{r};
    m = parameters.crop_id == j & strcmp(parameters.land_type,lt) & strcmp(parameters.season,season);
    if sum(m) ~= 1
        validParam(r) = false;
    else
        validParam(r) = parameters.yield_jin_per_mu(m) > 0 && ...
            parameters.cost_yuan_per_mu(m) >= 0 && ...
            parameters.price_mid(m) > 0;
    end
end

priceOK = true;
for j = 1:41
    for k = 1:3
        if any(allowed(:,j,k))
            values = zeros(0,1);
            allowedPlots = find(allowed(:,j,k));
            for idx = 1:numel(allowedPlots)
                i = allowedPlots(idx);
                m = parameters.crop_id == j & ...
                    strcmp(parameters.land_type,land.land_type{i}) & ...
                    strcmp(parameters.season,cfg.seasons{k});
                if sum(m) ~= 1
                    priceOK = false;
                else
                    values(end+1,1) = parameters.price_mid(m);
                end
            end
            if isempty(values) || numel(unique(values)) ~= 1
                priceOK = false;
            end
        end
    end
end

allowedParamCount = height(uniqueTypeCropSeason);
addcheck('所有allowed组合的参数值合法', all(validParam) && allowedParamCount == 125, ...
    '125个组合均yield>0,cost>=0,price>0', ...
    sprintf('组合=%d，非法=%d',allowedParamCount,sum(~validParam)), ...
    '合法决策变量没有完整有效参数。', 'PASS');
addcheck('作物—季次销售价格可安全降维', priceOK, ...
    '每个(crop_id,season)价格唯一', sprintf('组合=%d',height(demand)), ...
    'q/e按作物—年—季汇总时收入会失真。', 'PASS');

%% Output
audit.checks = table(names,ok,expected,actual,impact,state, ...
    'VariableNames', {'check','passed','expected','actual','impact_if_failed','status'});
audit.nmaxConflicts = conflicts;
audit.passed = all(ok);
audit.summary = struct( ...
    'plot_count',height(land), ...
    'crop_count',height(crop), ...
    'plant_records',height(plant), ...
    'statistics_records',height(statistics), ...
    'allowed_parameter_combinations',allowedParamCount, ...
    'demand_support',height(demand), ...
    'positive_demand',positiveDemand, ...
    'zero_demand',zeroDemand, ...
    'history_z_positive',sum(historyZ(:)), ...
    'history_bean_plots',sum(data.historyBean), ...
    'nmax_conflicts',height(conflicts));
end
