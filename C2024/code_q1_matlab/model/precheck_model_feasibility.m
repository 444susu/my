function report = precheck_model_feasibility(data,cfg)
%PRECHECK_MODEL_FEASIBILITY Fast structural feasibility checks before Gurobi.
% These checks do not solve the MILP and do not relax any model assumption.
% MATLAB target: R2024a.

checks = cell(0,1);
passed = false(0,1);
actual = cell(0,1);
required = cell(0,1);

    function addcheck(name,ok,actualText,requiredText)
        checks{end+1,1} = name;
        passed(end+1,1) = logical(ok);
        actual{end+1,1} = actualText;
        required{end+1,1} = requiredText;
    end

% 1) Ordinary greenhouse second season must cover every greenhouse.
ordinaryCount = sum(strcmp(data.land.land_type,'普通大棚'));
fungiCount = numel(cfg.mushroomCrops);
fungiCoverage = fungiCount * cfg.NmaxFungi;
addcheck('普通大棚第二季食用菌覆盖能力', ...
    fungiCoverage >= ordinaryCount, ...
    sprintf('%d种食用菌 × NmaxFungi=%d => 最大覆盖%d个大棚', ...
        fungiCount,cfg.NmaxFungi,fungiCoverage), ...
    sprintf('至少覆盖%d个普通大棚',ordinaryCount));

% 2) Irrigated vegetable mode second season has exactly one of 35-37.
waterCount = sum(strcmp(data.land.land_type,'水浇地'));
waterSecondCropCount = numel(cfg.secondSeasonWaterVegetables);
waterCoverage = waterSecondCropCount * cfg.Nmax;
addcheck('水浇地第二季蔬菜覆盖能力', ...
    waterCoverage >= waterCount, ...
    sprintf('%d种第二季蔬菜 × Nmax=%d => 最大覆盖%d块水浇地', ...
        waterSecondCropCount,cfg.Nmax,waterCoverage), ...
    sprintf('若全部选择蔬菜模式，最多需要覆盖%d块水浇地',waterCount));

% 3) Ordinary greenhouse first season occupancy.
firstVegCount = numel(cfg.firstSeasonVegetables);
ordinaryFirstCoverage = firstVegCount * cfg.Nmax;
addcheck('普通大棚第一季蔬菜覆盖能力', ...
    ordinaryFirstCoverage >= ordinaryCount, ...
    sprintf('%d种第一季蔬菜 × Nmax=%d => 最大覆盖%d个大棚', ...
        firstVegCount,cfg.Nmax,ordinaryFirstCoverage), ...
    sprintf('至少覆盖%d个普通大棚',ordinaryCount));

% 4) Smart greenhouse occupancy, per season.
smartCount = sum(strcmp(data.land.land_type,'智慧大棚'));
smartCoverage = firstVegCount * cfg.Nmax;
addcheck('智慧大棚单季蔬菜覆盖能力', ...
    smartCoverage >= smartCount, ...
    sprintf('%d种蔬菜 × Nmax=%d => 最大覆盖%d个智慧大棚', ...
        firstVegCount,cfg.Nmax,smartCoverage), ...
    sprintf('每季至少覆盖%d个智慧大棚',smartCount));

report.table = table(checks,passed,actual,required, ...
    'VariableNames',{'check','passed','actual','required'});
report.passed = all(passed);

if ~report.passed
    bad = report.table(~report.table.passed,:);
    msg = sprintf('模型结构预检失败，共%d项。',height(bad));
    error('Q1:StructuralInfeasibility','%s',msg);
end
end
