function [allowed, allowedRows] = build_allowed(land, cfg)
%BUILD_ALLOWED 构建 I×J×K 的题面适宜性矩阵，非法组合保持0。

I = height(land); J = 41; K = 3;
allowed = false(I, J, K);
plot = {}; landType = {}; cropId = []; seasonIdx = []; season = {};
for i = 1:I
    for k = 1:K
        crops = allowed_crop_ids(land.land_type{i}, k, cfg);
        for j = crops
            allowed(i,j,k) = true;
            plot{end+1,1} = land.plot_id{i}; %#ok<AGROW>
            landType{end+1,1} = land.land_type{i}; %#ok<AGROW>
            cropId(end+1,1) = j; %#ok<AGROW>
            seasonIdx(end+1,1) = k; %#ok<AGROW>
            season{end+1,1} = cfg.seasons{k}; %#ok<AGROW>
        end
    end
end
allowedRows = table(plot, landType, cropId, seasonIdx, season, ...
    'VariableNames', {'plot_id','land_type','crop_id','season_idx','season'});
end

function crops = allowed_crop_ids(landType, k, cfg)
crops = [];
if any(strcmp(landType, {'平旱地','梯田','山坡地'})) && k == cfg.K_SINGLE
    crops = cfg.grainCrops;
elseif strcmp(landType, '水浇地')
    if k == cfg.K_SINGLE
        crops = cfg.riceCrop;
    elseif k == cfg.K_FIRST
        crops = cfg.firstSeasonVegetables;
    elseif k == cfg.K_SECOND
        crops = cfg.secondSeasonWaterVegetables;
    end
elseif strcmp(landType, '普通大棚')
    if k == cfg.K_FIRST
        crops = cfg.firstSeasonVegetables;
    elseif k == cfg.K_SECOND
        crops = cfg.mushroomCrops;
    end
elseif strcmp(landType, '智慧大棚') && any(k == [cfg.K_FIRST cfg.K_SECOND])
    crops = cfg.firstSeasonVegetables;
end
end



