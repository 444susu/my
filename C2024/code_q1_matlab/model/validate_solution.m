function validation = validate_solution(data, cfg, model, vars, meta, result, outDir)
%VALIDATE_SOLUTION Recompute matrix residuals, integrality and objective.
% MATLAB target: R2024a.

if ~isfolder(outDir)
    mkdir(outDir);
end

tol = cfg.tolerance;
x = result.x(:);
activity = model.A * x;
violation = zeros(meta.ncon,1);

for r = 1:meta.ncon
    if model.sense(r) == '<'
        violation(r) = max(0, activity(r) - model.rhs(r));
    elseif model.sense(r) == '>'
        violation(r) = max(0, model.rhs(r) - activity(r));
    else
        violation(r) = abs(activity(r) - model.rhs(r));
    end
end

types = meta.constraint_types;
names = { ...
    '面积容量'; ...
    'x-z上下界'; ...
    'allowed'; ...
    '水浇地模式'; ...
    '普通大棚两季实际种植'; ...
    '智慧大棚两季实际种植'; ...
    '水浇地第二季唯一作物'; ...
    '连续重茬'; ...
    '2023→2024历史边界'; ...
    '三年豆类窗口'; ...
    '分散度Nmax'; ...
    'q+e=总产量'; ...
    'q<=demand'; ...
    '变量上下界与整数性'; ...
    '目标函数重算'};

map = { ...
    {'C1_capacity'}; ...
    {'C2_xz_lower','C2_xz_upper'}; ...
    {'allowed_sparse_mapping'}; ...
    {'C4_water_rice_mode','C4_water_first_occupy'}; ...
    {'C5_ordinary_first_occupy','C5_ordinary_second_occupy'}; ...
    {'C6_smart_first_occupy','C6_smart_second_occupy'}; ...
    {'C4_water_second_unique'}; ...
    {'C8_rotation'}; ...
    {'C9_history_boundary'}; ...
    {'C10_bean_2023_2025','C10_bean_window'}; ...
    {'C11_nmax','C11_nmax_fungi'}; ...
    {'C12_production_balance'}; ...
    {'C13_demand_cap'}};

maxV = zeros(numel(names),1);
note = cell(numel(names),1);
for i = 1:13
    idx = false(meta.ncon,1);
    for q = 1:numel(map{i})
        idx = idx | strcmp(types,map{i}{q});
    end
    if any(idx)
        maxV(i) = max(violation(idx));
    else
        maxV(i) = inf;
    end
    note{i} = '按求解向量重算对应矩阵约束残差';
end

% allowed is enforced structurally: illegal combinations have no variable IDs.
illegalMapping = 0;
for i = 1:size(vars.x_id,1)
    for j = 1:size(vars.x_id,2)
        for t = 1:size(vars.x_id,3)
            for k = 1:size(vars.x_id,4)
                if ~data.allowed(i,j,k)
                    if vars.x_id(i,j,t,k) ~= 0 || vars.z_id(i,j,t,k) ~= 0
                        illegalMapping = inf;
                    end
                end
            end
        end
    end
end
maxV(3) = illegalMapping;
note{3} = '非法组合必须同时满足 x_id=0 且 z_id=0';

binaryIds = [nonzeros(vars.z_id(:)); nonzeros(vars.r_id(:))];
lowerViolation = max(max(0,-x));
upperViolation = max(max(0,x-model.ub));
integerViolation = max(abs(x(binaryIds)-round(x(binaryIds))));
maxV(14) = max([lowerViolation, upperViolation, integerViolation]);
note{14} = '连续变量上下界、二进制变量整数性';

recalc = model.obj(:)' * x;
if isfield(result,'objval')
    maxV(15) = abs(recalc-result.objval);
else
    maxV(15) = inf;
end
note{15} = sprintf('重算=%.10g',recalc);

passed = maxV <= tol;
validation.table = table(names,passed,maxV,note, ...
    'VariableNames',{'check_name','passed','max_violation','note'});
validation.passed = all(passed);
validation.objective_recalculated = recalc;
validation.max_violation = max(maxV);

writetable(validation.table,fullfile(outDir,'validation_summary.csv'));
fid = fopen(fullfile(outDir,'solution_validation_summary.txt'),'w');
if fid >= 0
    fprintf(fid,'PASS=%d\n',validation.passed);
    fprintf(fid,'max_violation=%.12g\n',validation.max_violation);
    fprintf(fid,'objective_recalculated=%.12g\n',recalc);
    fprintf(fid,'Nmax=%d\n',cfg.Nmax);
    fprintf(fid,'NmaxFungi=%d\n',cfg.NmaxFungi);
    fclose(fid);
end
end
