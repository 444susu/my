function audit = validate_data(data, cfg)
%VALIDATE_DATA 模块A硬门控：任一失败时 main.m 不得进入 MILP。

land=data.land; crop=data.crop; plant=data.plant2023; statistics=data.statistics2023;
parameters=data.parameters; allowed=data.allowed; allowedRows=data.allowedRows;
history=data.history; demand=data.demand; dispersal=data.dispersal; historyZ=data.historyZ;
names={}; ok=[]; expected={}; actual={}; impact={}; state={};
    function addcheck(n,p,e,a,i,s)
        names{end+1,1}=n; ok(end+1,1)=logical(p); expected{end+1,1}=e; actual{end+1,1}=a; impact{end+1,1}=i; state{end+1,1}=s;
    end

validTypes={'平旱地','梯田','山坡地','水浇地','普通大棚','智慧大棚'};
addcheck('地块数量',height(land)==54,'54',num2str(height(land)),'地块集合错误会改变模型维度。','PASS');
addcheck('地块ID唯一且非空',all(~cellfun(@isempty,land.plot_id)) && numel(unique(land.plot_id))==54,'54个唯一、非空地块ID',sprintf('非空=%d，唯一=%d',sum(~cellfun(@isempty,land.plot_id)),numel(unique(land.plot_id))),'地块索引会错误合并。','PASS');
addcheck('地块面积与类型合法',all(land.area_mu>0) && all(ismember(land.land_type,validTypes)),'面积>0且仅六种题面类型',sprintf('非正面积=%d，非法类型=%d',sum(land.area_mu<=0),sum(~ismember(land.land_type,validTypes))),'容量或适宜性约束不可用。','PASS');
addcheck('作物数量',height(crop)==41,'41',num2str(height(crop)),'作物集合错误会改变适宜性和决策变量。','PASS');
addcheck('作物编号集合完整',isequal(sort(crop.crop_id(:))',1:41),'编号1—41各一次',sprintf('唯一数=%d',numel(unique(crop.crop_id))),'作物集合或固定豆类集合可能错误。','PASS');

typeOrder={'平旱地','梯田','山坡地','水浇地','普通大棚','智慧大棚'}; want=[365,619,108,109,9.6,2.4]; got=zeros(1,6);
for i=1:6, got(i)=sum(land.area_mu(strcmp(land.land_type,typeOrder{i}))); end
addcheck('各地块类型面积',max(abs(got-want))<1e-9,mat2str(want),mat2str(got),'面积容量约束可能错误。','PASS');

addcheck('2023种植记录数',height(plant)==87,'87',num2str(height(plant)),'历史状态和需求基准可能不完整。','PASS');
addcheck('原始参数记录数',height(statistics)==107,'107',num2str(height(statistics)),'附件参数表读取可能错误。','PASS');
pkey=strcat(string(parameters.crop_id),'|',string(parameters.land_type),'|',string(parameters.season));
addcheck('参数编号键冲突',numel(unique(pkey))==numel(pkey),'0个重复参数键',num2str(numel(pkey)-numel(unique(pkey))),'亩产、成本或价格存在歧义。','PASS');
unmatched=any(ismissing(history{:,{'land_type','yield_jin_per_mu','cost_yuan_per_mu','price_mid'}}),2);
addcheck('所有2023记录匹配参数',~any(unmatched),'0条未匹配',num2str(sum(unmatched)),'不能计算需求，必须停止。','PASS');
addcheck('2023历史0-1种植状态',sum(historyZ(:))==87 && all(ismember(historyZ(:),[0,1])),'87个历史正种植键',sprintf('正状态=%d',sum(historyZ(:))),'无法可靠建立2023→2024重茬边界。','PASS');
addcheck('2023地块豆类历史状态',numel(data.historyBean)==54 && sum(data.historyBean)==19,'54个地块；种过豆类=19',sprintf('记录=%d，种过豆类=%d',numel(data.historyBean),sum(data.historyBean)),'第一个三年豆类窗口无法构建。','PASS');
addcheck('2023—2024历史邻接基础',height(data.adjacency)==54 && all(~cellfun(@isempty,data.adjacency.last_season_2023)),'54块地均有最后实际季次',num2str(height(data.adjacency)),'重茬约束无法按真实时间链构建。','PASS');

historyAllowed=true(height(plant),1);
for r=1:height(plant)
    i=find(strcmp(land.plot_id,plant.plot_id{r}),1); k=find(strcmp(cfg.seasons,plant.season{r}),1);
    historyAllowed(r)=~isempty(i) && ~isempty(k) && allowed(i,plant.crop_id(r),k);
end
addcheck('2023历史种植适宜性',all(historyAllowed),'0条allowed=0历史记录',num2str(sum(~historyAllowed)),'题面适宜性规则或历史编码存在冲突。','PASS');
over=0;
for i=1:height(land), for k=1:3
    over=over+(sum(plant.plant_area_mu(strcmp(plant.plot_id,land.plot_id{i}) & strcmp(plant.season,cfg.seasons{k})))>land.area_mu(i)+cfg.tolerance);
end,end
addcheck('2023面积未超地块容量',over==0,'0个地块—季次超容量',num2str(over),'历史口径或数据存在冲突。','PASS');
addcheck('价格区间解析',all(statistics.price_low>=0 & statistics.price_high>=statistics.price_low & statistics.price_mid>0),'107条有效low<=high区间',sprintf('有效=%d',sum(statistics.price_mid>0)),'价格参数不能进入目标函数。','PASS');

pos=sum(demand.demand_jin>0); zero=sum(demand.demand_jin==0); support=0; supportOK=true;
for j=1:41, for k=1:3
    if any(allowed(:,j,k)), support=support+1; supportOK=supportOK && any(demand.crop_id==j & demand.season_idx==k); end
end,end
addcheck('需求计算',height(demand)==59 && numel(unique(demand.crop_id))==41 && all(demand.demand_jin>=0),'59键且覆盖41作物',sprintf('组合=%d，覆盖=%d，负需求=%d',height(demand),numel(unique(demand.crop_id)),sum(demand.demand_jin<0)),'销售上限无法构建。','PASS');
addcheck('未来可种植作物—季次需求support完整',supportOK && support==59 && pos==47 && zero==12,'support=59，正需求=47，零需求=12',sprintf('support=%d，正需求=%d，零需求=%d',support,pos,zero),'q/e产量守恒和销售上限无法覆盖全部未来合法生产组合。','PASS');
ratios=history.plant_area_mu./history.area_mu;
addcheck('beta=0.5历史证据',abs(min(ratios)-cfg.beta)<cfg.tolerance && all(ratios>=cfg.beta-cfg.tolerance),'最小值=0.5且无值更低',sprintf('最小值=%.6g',min(ratios)),'beta管理参数缺乏已确认的数据证据。','PASS');
conflicts=dispersal(dispersal.plot_count_2023>cfg.Nmax,:);
conflictOK=height(conflicts)==3 && any(conflicts.crop_id==41 & conflicts.season_idx==3 & conflicts.plot_count_2023==7) && any(conflicts.crop_id==6 & conflicts.season_idx==1 & conflicts.plot_count_2023==4) && any(conflicts.crop_id==17 & conflicts.season_idx==2 & conflicts.plot_count_2023==4);
addcheck('Nmax=3与历史分散度比较',conflictOK,'3个冲突：41第二季=7；6单季=4；17第一季=4',sprintf('超过Nmax组合=%d',height(conflicts)),'WARNING：Nmax=3比部分2023经营更严格。','WARNING');

keys=unique([allowedRows.land_type,num2cell(allowedRows.crop_id),allowedRows.season],'rows'); validParam=true(size(keys,1),1); priceOK=true;
for r=1:size(keys,1)
    m=parameters.crop_id==keys{r,2} & strcmp(parameters.land_type,keys{r,1}) & strcmp(parameters.season,keys{r,3});
    validParam(r)=sum(m)==1 && parameters.yield_jin_per_mu(m)>0 && parameters.cost_yuan_per_mu(m)>=0 && parameters.price_mid(m)>0;
end
for j=1:41, for k=1:3
    if any(allowed(:,j,k))
        p=[]; for i=find(allowed(:,j,k))', m=parameters.crop_id==j & strcmp(parameters.land_type,land.land_type{i}) & strcmp(parameters.season,cfg.seasons{k}); p=[p;parameters.price_mid(m)]; end %#ok<AGROW>
        priceOK=priceOK && numel(unique(p))==1;
    end
end,end
addcheck('所有allowed组合的参数值合法',all(validParam) && size(keys,1)==125,'125个组合均yield>0,cost>=0,price>0',sprintf('组合=%d，非法=%d',size(keys,1),sum(~validParam)),'合法决策变量没有完整有效参数。','PASS');
addcheck('作物—季次销售价格可安全降维',priceOK,'每个(crop_id,season)价格唯一',sprintf('组合=%d',height(demand)),'q/e按作物—年—季汇总时收入会失真。','PASS');

audit.checks=table(names,ok,expected,actual,impact,state,'VariableNames',{'check','passed','expected','actual','impact_if_failed','status'});
audit.nmaxConflicts=conflicts; audit.passed=all(ok);
audit.summary=struct('plot_count',height(land),'crop_count',height(crop),'plant_records',height(plant),'statistics_records',height(statistics),'allowed_parameter_combinations',size(keys,1),'demand_support',height(demand),'positive_demand',pos,'zero_demand',zero,'history_z_positive',sum(historyZ(:)),'history_bean_plots',sum(data.historyBean),'nmax_conflicts',height(conflicts));
end


