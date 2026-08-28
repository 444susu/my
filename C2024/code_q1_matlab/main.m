function main()
%MAIN 问题1第一阶段入口：模块A PASS → alpha=0 MILP → 独立验证 → 输出。
cfg=config_q1(); addpath(cfg.codeRoot); addpath(fullfile(cfg.codeRoot,'data')); addpath(fullfile(cfg.codeRoot,'model')); addpath(fullfile(cfg.codeRoot,'output')); addpath(fullfile(cfg.codeRoot,'sensitivity'));
if ~isfolder(cfg.resultsDir), mkdir(cfg.resultsDir); end
logFile=fullfile(cfg.resultsDir,'run_log.txt'); diary(logFile); cleanup=onCleanup(@() diary('off')); %#ok<NASGU>
fprintf('Q1 MATLAB alpha=0 started: %s\n',datestr(now,31)); fprintf('MATLAB=%s\n',version); rng(cfg.seed,'twister');
try, fprintf('Gurobi API=%s\n',which('gurobi')); catch, end
try
    clean=read_clean_data(cfg); [params,inherited]=build_parameters(clean.statistics2023);
    [allowed,allowedRows]=build_allowed(clean.land,cfg);
    h=build_history(clean.plant2023,clean.land,params,allowed,cfg);
    data=struct('land',clean.land,'crop',clean.crop,'plant2023',clean.plant2023,'statistics2023',clean.statistics2023,'parameters',params,'inherited',inherited,'allowed',allowed,'allowedRows',allowedRows,'history',h.history,'demand',h.demand,'dispersal',h.dispersal,'historyZ',h.historyZ,'historyBean',h.historyBean,'adjacency',h.adjacency);
    audit=validate_data(data,cfg); write_audit(clean,data,audit,cfg);
    fprintf('AUDIT_PASS=%d plots=%d crops=%d plant=%d parameters=%d demand=%d positive=%d zero=%d\n',audit.passed,audit.summary.plot_count,audit.summary.crop_count,audit.summary.plant_records,audit.summary.statistics_records,audit.summary.demand_support,audit.summary.positive_demand,audit.summary.zero_demand);
    if ~audit.passed, error('Q1:AuditFailed','MATLAB模块A审计未通过，已停止MILP。'); end
    if ~isfolder(cfg.alpha0Dir), mkdir(cfg.alpha0Dir); end
    [model,vars,meta]=build_MILP(data,cfg,0); save(fullfile(cfg.alpha0Dir,'model_summary.mat'),'meta');
    writetable(table(meta.nvar,meta.continuous_variables,meta.binary_variables,meta.ncon,'VariableNames',{'variables','continuous_variables','binary_variables','constraints'}),fullfile(cfg.alpha0Dir,'model_summary.csv'));
    fprintf('MODEL variables=%d continuous=%d binary=%d constraints=%d\n',meta.nvar,meta.continuous_variables,meta.binary_variables,meta.ncon);
    result=solve_model(model,meta,cfg,cfg.alpha0Dir); fprintf('GUROBI_STATUS=%s\n',result.status);
    if ~strcmp(result.status,'OPTIMAL'), save(fullfile(cfg.alpha0Dir,'solver_result.mat'),'result'); error('Q1:SolverStop','Gurobi未返回OPTIMAL；已保存诊断，未修改模型。'); end
    fprintf('OBJECTIVE=%.12g RUNTIME=%.12g\n',result.objval,result.runtime); if isfield(result,'mipgap'), fprintf('MIP_GAP=%.12g\n',result.mipgap); end
    validation=validate_solution(data,cfg,model,vars,meta,result,cfg.alpha0Dir); fprintf('VALIDATION_PASS=%d MAX_VIOLATION=%.12g\n',validation.passed,validation.max_violation);
    if ~validation.passed, error('Q1:ValidationFailed','独立验证失败，未输出最终种植方案。'); end
    output_results(data,cfg,vars,result,cfg.alpha0Dir); fprintf('COMPLETE alpha=0\n');
catch ME
    fprintf(2,'ERROR [%s] %s\n',ME.identifier,ME.message); rethrow(ME);
end
end
function write_audit(clean,data,audit,cfg)
if ~isfolder(cfg.auditDir), mkdir(cfg.auditDir); end
writetable(audit.checks,fullfile(cfg.auditDir,'audit_checks.csv')); writetable(clean.cleaningLog,fullfile(cfg.auditDir,'cleaning_log.csv'));
writetable(data.demand,fullfile(cfg.auditDir,'clean_demand.csv')); writetable(data.dispersal,fullfile(cfg.auditDir,'clean_dispersal.csv')); writetable(audit.nmaxConflicts,fullfile(cfg.auditDir,'nmax_history_conflicts.csv'));
T=struct2table(audit.summary); writetable(T,fullfile(cfg.auditDir,'audit_summary.csv'));
fid=fopen(fullfile(cfg.auditDir,'audit_report.md'),'w'); fprintf(fid,'# MATLAB 模块 A 审计报告\n\n总体状态：**%s**\n\n',ternary(audit.passed,'PASS','FAIL')); fprintf(fid,'关键计数：地块=%d；作物=%d；2023记录=%d；参数=%d；support=%d；正需求=%d；零需求=%d。\n',audit.summary.plot_count,audit.summary.crop_count,audit.summary.plant_records,audit.summary.statistics_records,audit.summary.demand_support,audit.summary.positive_demand,audit.summary.zero_demand); fclose(fid);
end
function s=ternary(x,a,b), if x,s=a;else,s=b;end,end

