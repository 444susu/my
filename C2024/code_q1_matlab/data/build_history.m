function historyData = build_history(plant, land, parameters, allowed, cfg)
%BUILD_HISTORY 构建需求、2023种植状态、豆类历史和2023→2024邻接基础。

I = height(land); J = 41; K = 3;
nPlant = height(plant);
landIdx = zeros(nPlant,1); paramIdx = zeros(nPlant,1);
yieldValue = nan(nPlant,1); costValue = nan(nPlant,1); priceValue = nan(nPlant,1);
landType = cell(nPlant,1); area = nan(nPlant,1); seasonIdx = zeros(nPlant,1);
for r = 1:nPlant
    landIdx(r) = find(strcmp(land.plot_id, plant.plot_id{r}), 1);
    if isempty(landIdx(r)), landIdx(r) = 0; landType{r} = '';
    else, landType{r} = land.land_type{landIdx(r)}; area(r) = land.area_mu(landIdx(r)); end
    seasonIdx(r) = find(strcmp(cfg.seasons, plant.season{r}), 1);
    if isempty(seasonIdx(r)), seasonIdx(r) = 0; end
    if landIdx(r)>0 && seasonIdx(r)>0
        paramIdx(r) = find(parameters.crop_id==plant.crop_id(r) & strcmp(parameters.land_type,landType{r}) & strcmp(parameters.season,plant.season{r}),1);
    end
    if paramIdx(r)>0
        yieldValue(r)=parameters.yield_jin_per_mu(paramIdx(r));
        costValue(r)=parameters.cost_yuan_per_mu(paramIdx(r));
        priceValue(r)=parameters.price_mid(paramIdx(r));
    end
end
history = plant;
history.land_index=landIdx; history.land_type=landType; history.area_mu=area;
history.season_idx=seasonIdx; history.yield_jin_per_mu=yieldValue;
history.cost_yuan_per_mu=costValue; history.price_mid=priceValue;
history.production_jin=history.plant_area_mu.*yieldValue;

historyZ=zeros(I,J,K);
for r=1:nPlant
    if landIdx(r)>0 && seasonIdx(r)>0 && plant.crop_id(r)>=1 && plant.crop_id(r)<=J
        historyZ(landIdx(r),plant.crop_id(r),seasonIdx(r))=1;
    end
end
historyZ(~allowed)=0;
historyBean=zeros(I,1);
for i=1:I, historyBean(i)=any(historyZ(i,cfg.beanCrops,:),'all'); end

rows={};
for j=1:J
    for k=1:K
        if any(allowed(:,j,k))
            mask=history.crop_id==j & history.season_idx==k;
            if any(mask), d=sum(history.production_jin(mask),'omitnan'); src='2023实际产量';
            else, d=0; src='2023未种植，按已确认口径置0'; end
            rows(end+1,:)={j,k,cfg.seasons{k},d,src}; %#ok<AGROW>
        end
    end
end
demand=cell2table(rows,'VariableNames',{'crop_id','season_idx','season','demand_jin','demand_source'});
demand.crop_id=cell2mat(demand.crop_id); demand.season_idx=cell2mat(demand.season_idx); demand.demand_jin=cell2mat(demand.demand_jin);

dispRows=[];
for j=1:J
    for k=1:K
        mask=history.crop_id==j & history.season_idx==k;
        if any(mask), dispRows(end+1,:)=[j,k,numel(unique(history.plot_id(mask)))]; end %#ok<AGROW>
    end
end
dispersal=array2table(dispRows,'VariableNames',{'crop_id','season_idx','plot_count_2023'});
dispersal.season=cell(height(dispersal),1);
for r=1:height(dispersal), dispersal.season{r}=cfg.seasons{dispersal.season_idx(r)}; end

lastSeason=zeros(I,1);
for r=1:nPlant
    i=landIdx(r);
    if i>0 && seasonIdx(r)>0 && season_rank(seasonIdx(r),cfg)>=season_rank(lastSeason(i),cfg)
        lastSeason(i)=seasonIdx(r);
    end
end
lastText=cell(I,1); nextText=cell(I,1);
for i=1:I
    lastText{i}=cfg.seasons{lastSeason(i)};
    if strcmp(land.land_type{i},'水浇地'), nextText{i}='单季|第一季';
    elseif any(strcmp(land.land_type{i},{'平旱地','梯田','山坡地'})), nextText{i}='单季';
    else, nextText{i}='第一季'; end
end
adjacency=table(land.plot_id,land.land_type,lastText,nextText,repmat({'2023历史末季→2024首个决策季'},I,1),...
    'VariableNames',{'plot_id','land_type','last_season_2023','next_season_2024','adjacency_scope'});
historyData=struct('history',history,'demand',demand,'dispersal',dispersal,'historyZ',historyZ,'historyBean',historyBean,'adjacency',adjacency);
end

function rank=season_rank(k,cfg)
if k==0, rank=0; elseif k==cfg.K_SECOND, rank=2; else, rank=1; end
end

