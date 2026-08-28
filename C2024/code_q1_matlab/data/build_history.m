function historyData = build_history(plant, land, parameters, allowed, cfg)
%BUILD_HISTORY Build 2023 demand, history states and 2023->2024 adjacency.
% MATLAB target: R2024a.

I = height(land);
J = 41;
K = 3;
nPlant = height(plant);

landIdx = zeros(nPlant,1);
paramIdx = zeros(nPlant,1);
yieldValue = nan(nPlant,1);
costValue = nan(nPlant,1);
priceValue = nan(nPlant,1);
landType = cell(nPlant,1);
area = nan(nPlant,1);
seasonIdx = zeros(nPlant,1);

for r = 1:nPlant
    foundLand = find(strcmp(land.plot_id, plant.plot_id{r}), 1, 'first');
    if isempty(foundLand)
        landIdx(r) = 0;
        landType{r} = '';
    else
        landIdx(r) = foundLand;
        landType{r} = land.land_type{foundLand};
        area(r) = land.area_mu(foundLand);
    end

    foundSeason = find(strcmp(cfg.seasons, plant.season{r}), 1, 'first');
    if isempty(foundSeason)
        seasonIdx(r) = 0;
    else
        seasonIdx(r) = foundSeason;
    end

    if landIdx(r) > 0 && seasonIdx(r) > 0
        mask = parameters.crop_id == plant.crop_id(r) & ...
            strcmp(parameters.land_type, landType{r}) & ...
            strcmp(parameters.season, plant.season{r});
        foundParam = find(mask, 1, 'first');
        if ~isempty(foundParam)
            paramIdx(r) = foundParam;
            yieldValue(r) = parameters.yield_jin_per_mu(foundParam);
            costValue(r) = parameters.cost_yuan_per_mu(foundParam);
            priceValue(r) = parameters.price_mid(foundParam);
        end
    end
end

history = plant;
history.land_index = landIdx;
history.land_type = landType;
history.area_mu = area;
history.season_idx = seasonIdx;
history.yield_jin_per_mu = yieldValue;
history.cost_yuan_per_mu = costValue;
history.price_mid = priceValue;
history.production_jin = history.plant_area_mu .* yieldValue;

%% 2023 binary planting state
historyZ = zeros(I,J,K);
for r = 1:nPlant
    i = landIdx(r);
    j = plant.crop_id(r);
    k = seasonIdx(r);
    if i > 0 && k > 0 && j >= 1 && j <= J
        historyZ(i,j,k) = 1;
    end
end
historyZ(~allowed) = 0;

%% 2023 bean state per plot
historyBean = zeros(I,1);
for i = 1:I
    beanSlice = historyZ(i,cfg.beanCrops,:);
    historyBean(i) = any(beanSlice(:) > 0);
end

%% Complete demand support: all future allowed crop-season pairs
cropIdCol = zeros(0,1);
seasonIdxCol = zeros(0,1);
seasonCol = cell(0,1);
demandCol = zeros(0,1);
sourceCol = cell(0,1);

for j = 1:J
    for k = 1:K
        if any(allowed(:,j,k))
            mask = history.crop_id == j & history.season_idx == k;
            if any(mask)
                d = sum(history.production_jin(mask), 'omitnan');
                src = '2023实际产量';
            else
                d = 0;
                src = '2023未种植，按已确认口径置0';
            end
            cropIdCol(end+1,1) = j;
            seasonIdxCol(end+1,1) = k;
            seasonCol{end+1,1} = cfg.seasons{k};
            demandCol(end+1,1) = d;
            sourceCol{end+1,1} = src;
        end
    end
end

demand = table(cropIdCol, seasonIdxCol, seasonCol, demandCol, sourceCol, ...
    'VariableNames', {'crop_id','season_idx','season','demand_jin','demand_source'});

%% 2023 dispersal by crop-season
cropIdDisp = zeros(0,1);
seasonIdxDisp = zeros(0,1);
countDisp = zeros(0,1);
seasonDisp = cell(0,1);
for j = 1:J
    for k = 1:K
        mask = history.crop_id == j & history.season_idx == k;
        if any(mask)
            cropIdDisp(end+1,1) = j;
            seasonIdxDisp(end+1,1) = k;
            countDisp(end+1,1) = numel(unique(history.plot_id(mask)));
            seasonDisp{end+1,1} = cfg.seasons{k};
        end
    end
end

dispersal = table(cropIdDisp, seasonIdxDisp, countDisp, seasonDisp, ...
    'VariableNames', {'crop_id','season_idx','plot_count_2023','season'});

%% Last actual 2023 season for each plot
lastSeason = zeros(I,1);
for r = 1:nPlant
    i = landIdx(r);
    k = seasonIdx(r);
    if i > 0 && k > 0
        if season_rank(k,cfg) >= season_rank(lastSeason(i),cfg)
            lastSeason(i) = k;
        end
    end
end

lastText = cell(I,1);
nextText = cell(I,1);
for i = 1:I
    if lastSeason(i) > 0
        lastText{i} = cfg.seasons{lastSeason(i)};
    else
        lastText{i} = '';
    end

    lt = land.land_type{i};
    if strcmp(lt,'水浇地')
        nextText{i} = '单季|第一季';
    elseif any(strcmp(lt,{'平旱地','梯田','山坡地'}))
        nextText{i} = '单季';
    else
        nextText{i} = '第一季';
    end
end

adjacencyScope = repmat({'2023历史末季→2024首个决策季'}, I, 1);
adjacency = table(land.plot_id, land.land_type, lastText, nextText, adjacencyScope, ...
    'VariableNames', {'plot_id','land_type','last_season_2023', ...
    'next_season_2024','adjacency_scope'});

historyData = struct();
historyData.history = history;
historyData.demand = demand;
historyData.dispersal = dispersal;
historyData.historyZ = historyZ;
historyData.historyBean = historyBean;
historyData.adjacency = adjacency;
end

function rankValue = season_rank(k,cfg)
if k == 0
    rankValue = 0;
elseif k == cfg.K_SECOND
    rankValue = 2;
else
    rankValue = 1;
end
end
