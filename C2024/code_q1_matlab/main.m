function main()
%MAIN Problem 1 alpha=0 full workflow.
% MATLAB target: R2024a. Gurobi MATLAB API target: 10.0.1.
%
% Recommended first local test:
%   run_module_A
% Only run main after Module A passes.

cfg = config_q1();
addpath(cfg.codeRoot);
addpath(fullfile(cfg.codeRoot,'data'));
addpath(fullfile(cfg.codeRoot,'model'));
addpath(fullfile(cfg.codeRoot,'output'));
addpath(fullfile(cfg.codeRoot,'sensitivity'));

if ~isfolder(cfg.resultsDir)
    mkdir(cfg.resultsDir);
end
if ~isfolder(cfg.alpha0Dir)
    mkdir(cfg.alpha0Dir);
end

logFile = fullfile(cfg.resultsDir,'run_log.txt');
diary(logFile);
cleanupObj = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('============================================================\n');
fprintf('C2024 Q1 MATLAB full run, alpha=0\n');
fprintf('MATLAB version: %s\n',version);
fprintf('Started: %s\n',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
fprintf('Gurobi function: %s\n',which('gurobi'));
fprintf('beta=%.3f, Nmax=%d, NmaxFungi=%d\n',cfg.beta,cfg.Nmax,cfg.NmaxFungi);
fprintf('============================================================\n');
rng(cfg.seed,'twister');

try
    %% Module A
    fprintf('\n[Module A] Reading and auditing data...\n');
    clean = read_clean_data(cfg);
    [parameters,inherited] = build_parameters(clean.statistics2023);
    [allowed,allowedRows] = build_allowed(clean.land,cfg);
    historyData = build_history(clean.plant2023,clean.land,parameters,allowed,cfg);

    data = struct();
    data.land = clean.land;
    data.crop = clean.crop;
    data.plant2023 = clean.plant2023;
    data.statistics2023 = clean.statistics2023;
    data.parameters = parameters;
    data.inherited = inherited;
    data.allowed = allowed;
    data.allowedRows = allowedRows;
    data.history = historyData.history;
    data.demand = historyData.demand;
    data.dispersal = historyData.dispersal;
    data.historyZ = historyData.historyZ;
    data.historyBean = historyData.historyBean;
    data.adjacency = historyData.adjacency;

    audit = validate_data(data,cfg);
    write_audit(clean,data,audit,cfg);

    fprintf('AUDIT_PASS=%d\n',audit.passed);
    fprintf('plots=%d crops=%d plant=%d statistics=%d support=%d positive=%d zero=%d\n', ...
        audit.summary.plot_count, ...
        audit.summary.crop_count, ...
        audit.summary.plant_records, ...
        audit.summary.statistics_records, ...
        audit.summary.demand_support, ...
        audit.summary.positive_demand, ...
        audit.summary.zero_demand);

    if ~audit.passed
        error('Q1:AuditFailed','MATLAB模块A审计未通过，已停止MILP。');
    end

    %% Structural feasibility precheck
    fprintf('\n[Precheck] Checking obvious structural feasibility...\n');
    precheck = precheck_model_feasibility(data,cfg);
    writetable(precheck.table,fullfile(cfg.alpha0Dir,'structural_feasibility_precheck.csv'));
    disp(precheck.table);
    fprintf('STRUCTURAL_PRECHECK_PASS=%d\n',precheck.passed);

    %% Module B: build alpha=0 MILP
    fprintf('\n[Module B] Building MILP...\n');
    [model,vars,meta] = build_MILP(data,cfg,0);
    save(fullfile(cfg.alpha0Dir,'model_summary.mat'),'meta');

    summaryTable = table( ...
        meta.nvar,meta.continuous_variables,meta.binary_variables,meta.ncon, ...
        meta.Nmax,meta.NmaxFungi, ...
        'VariableNames',{'variables','continuous_variables','binary_variables','constraints','Nmax','NmaxFungi'});
    writetable(summaryTable,fullfile(cfg.alpha0Dir,'model_summary.csv'));

    fprintf('MODEL variables=%d continuous=%d binary=%d constraints=%d\n', ...
        meta.nvar,meta.continuous_variables,meta.binary_variables,meta.ncon);

    %% Solve
    fprintf('\n[Gurobi] Solving alpha=0 model...\n');
    result = solve_model(model,meta,cfg,cfg.alpha0Dir);
    if ~isfield(result,'status')
        error('Q1:NoSolverStatus','Gurobi结果中没有status字段。');
    end
    fprintf('GUROBI_STATUS=%s\n',result.status);

    if ~strcmp(result.status,'OPTIMAL')
        save(fullfile(cfg.alpha0Dir,'solver_result.mat'),'result');
        error('Q1:SolverStop', ...
            'Gurobi未返回OPTIMAL；诊断已保存，模型参数未被自动放宽。');
    end

    fprintf('OBJECTIVE=%.12g\n',result.objval);
    if isfield(result,'runtime')
        fprintf('RUNTIME=%.12g\n',result.runtime);
    end
    if isfield(result,'mipgap')
        fprintf('MIP_GAP=%.12g\n',result.mipgap);
    end

    %% Independent validation
    fprintf('\n[Validation] Recomputing solution checks...\n');
    validation = validate_solution(data,cfg,model,vars,meta,result,cfg.alpha0Dir);
    fprintf('VALIDATION_PASS=%d MAX_VIOLATION=%.12g\n', ...
        validation.passed,validation.max_violation);

    if ~validation.passed
        error('Q1:ValidationFailed', ...
            '独立验证失败，未输出最终种植方案。');
    end

    %% Output
    fprintf('\n[Output] Writing result1_1.xlsx...\n');
    output_results(data,cfg,vars,result,cfg.alpha0Dir);

    fprintf('\nCOMPLETE alpha=0\n');

catch ME
    fprintf(2,'\nERROR [%s] %s\n',ME.identifier,ME.message);
    fprintf(2,'Error location:\n');
    for s = 1:numel(ME.stack)
        fprintf(2,'  %s, line %d\n',ME.stack(s).name,ME.stack(s).line);
    end
    rethrow(ME);
end
end

function write_audit(clean,data,audit,cfg)
if ~isfolder(cfg.auditDir)
    mkdir(cfg.auditDir);
end

writetable(audit.checks,fullfile(cfg.auditDir,'audit_checks.csv'));
writetable(clean.cleaningLog,fullfile(cfg.auditDir,'cleaning_log.csv'));
writetable(data.demand,fullfile(cfg.auditDir,'clean_demand.csv'));
writetable(data.dispersal,fullfile(cfg.auditDir,'clean_dispersal.csv'));
writetable(data.adjacency,fullfile(cfg.auditDir,'clean_adjacency_2023_to_2024.csv'));
writetable(audit.nmaxConflicts,fullfile(cfg.auditDir,'nmax_history_conflicts.csv'));
writetable(struct2table(audit.summary),fullfile(cfg.auditDir,'audit_summary.csv'));

fid = fopen(fullfile(cfg.auditDir,'audit_report.md'),'w');
if fid < 0
    error('Q1:AuditReportWrite','无法创建audit_report.md。');
end
fileCleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

if audit.passed
    overall = 'PASS';
else
    overall = 'FAIL';
end
fprintf(fid,'# MATLAB 模块 A 审计报告\n\n');
fprintf(fid,'总体状态：**%s**\n\n',overall);
fprintf(fid,'关键计数：地块=%d；作物=%d；2023记录=%d；参数=%d；support=%d；正需求=%d；零需求=%d。\n', ...
    audit.summary.plot_count, ...
    audit.summary.crop_count, ...
    audit.summary.plant_records, ...
    audit.summary.statistics_records, ...
    audit.summary.demand_support, ...
    audit.summary.positive_demand, ...
    audit.summary.zero_demand);
fprintf(fid,'\n基准分散度参数：普通作物 Nmax=%d；普通大棚第二季食用菌 NmaxFungi=%d。\n', ...
    cfg.Nmax,cfg.NmaxFungi);
end
