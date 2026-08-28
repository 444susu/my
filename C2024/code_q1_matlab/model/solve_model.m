function result = solve_model(model, meta, cfg, outDir)
%SOLVE_MODEL 调用 Gurobi 10 MATLAB API；不可行时导出诊断，不改变模型。
if ~isfolder(outDir), mkdir(outDir); end
try
    result = gurobi(model, cfg.gurobi);
catch ME
    result=struct('status','ERROR','error_identifier',ME.identifier,'error_message',ME.message);
    return
end
if isfield(result,'status') && strcmp(result.status,'INFEASIBLE')
    try
        iis=gurobi_iis(model); save(fullfile(outDir,'infeasible_iis.mat'),'iis');
        if isfield(iis,'Arows')
            rows=find(iis.Arows); T=table(rows,meta.constraint_names(rows),meta.constraint_types(rows),'VariableNames',{'constraint_index','constraint_name','constraint_type'});
            writetable(T,fullfile(outDir,'iis_constraints.csv'));
        end
    catch ME
        result.iis_error=ME.message;
    end
    try, gurobi_write(model,fullfile(outDir,'infeasible_model.lp')); catch ME, result.model_export_error=ME.message; end
end
end


