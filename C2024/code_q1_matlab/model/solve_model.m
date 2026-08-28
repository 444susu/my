function result = solve_model(model, meta, cfg, outDir)
%SOLVE_MODEL 调用 Gurobi 10 MATLAB API；不可行时导出诊断，不改变模型。
%
% Gurobi 在默认 DualReductions=1 时，某些不可行模型会先返回
% INF_OR_UNBD。此函数会自动用 DualReductions=0 重求一次，以区分
% INFEASIBLE 与 UNBOUNDED，并在确认不可行时导出 IIS。

if ~isfolder(outDir)
    mkdir(outDir);
end

params = cfg.gurobi;

try
    result = gurobi(model, params);
catch ME
    result = struct( ...
        'status', 'ERROR', ...
        'error_identifier', ME.identifier, ...
        'error_message', ME.message);
    return;
end

% 对 Gurobi 10 的 INF_OR_UNBD 做自动消歧。
if isfield(result, 'status') && strcmp(result.status, 'INF_OR_UNBD')
    fprintf('Gurobi returned INF_OR_UNBD. Re-solving with DualReductions=0...\n');
    params2 = params;
    params2.DualReductions = 0;

    try
        result2 = gurobi(model, params2);
        result2.initial_status = result.status;
        result = result2;
    catch ME
        result.diagnostic_error = ME.message;
        return;
    end
end

if isfield(result, 'status') && strcmp(result.status, 'INFEASIBLE')
    fprintf('Model confirmed INFEASIBLE. Computing IIS...\n');

    try
        iis = gurobi_iis(model);
        save(fullfile(outDir, 'infeasible_iis.mat'), 'iis');

        if isfield(iis, 'Arows')
            rows = find(iis.Arows);
            T = table( ...
                rows, ...
                meta.constraint_names(rows), ...
                meta.constraint_types(rows), ...
                'VariableNames', { ...
                'constraint_index', 'constraint_name', 'constraint_type'});
            writetable(T, fullfile(outDir, 'iis_constraints.csv'));
        end
    catch ME
        result.iis_error = ME.message;
    end

    try
        gurobi_write(model, fullfile(outDir, 'infeasible_model.lp'));
    catch ME
        result.model_export_error = ME.message;
    end
end

end
