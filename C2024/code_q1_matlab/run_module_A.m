function audit = run_module_A()
%RUN_MODULE_A One-click data/audit test for MATLAB R2024a.
% This function does NOT call Gurobi.

cfg = config_q1();
addpath(cfg.codeRoot);
addpath(fullfile(cfg.codeRoot,'data'));

if ~isfolder(cfg.resultsDir)
    mkdir(cfg.resultsDir);
end
if ~isfolder(cfg.auditDir)
    mkdir(cfg.auditDir);
end

logFile = fullfile(cfg.auditDir,'module_A_run_log.txt');
diary(logFile);
cleanupObj = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('============================================================\n');
fprintf('C2024 Q1 - MATLAB Module A audit only\n');
fprintf('MATLAB version: %s\n', version);
fprintf('Started: %s\n', char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')));
fprintf('Attachment 1: %s\n', cfg.attachment1);
fprintf('Attachment 2: %s\n', cfg.attachment2);
fprintf('============================================================\n');

try
    fprintf('\n[1/5] Reading and cleaning Excel attachments...\n');
    clean = read_clean_data(cfg);
    fprintf('  raw land rows       = %d\n', clean.rawRowCounts.land);
    fprintf('  raw crop rows       = %d\n', clean.rawRowCounts.crop);
    fprintf('  raw planting rows   = %d\n', clean.rawRowCounts.plant2023);
    fprintf('  raw statistics rows = %d\n', clean.rawRowCounts.statistics2023);

    fprintf('\n[2/5] Building inherited parameters...\n');
    [parameters,inherited] = build_parameters(clean.statistics2023);
    fprintf('  original parameter rows = %d\n', height(clean.statistics2023));
    fprintf('  inherited rows          = %d\n', height(inherited));
    fprintf('  combined parameter rows = %d\n', height(parameters));

    fprintf('\n[3/5] Building allowed matrix...\n');
    [allowed,allowedRows] = build_allowed(clean.land,cfg);
    fprintf('  allowed plot-crop-season keys = %d\n', height(allowedRows));

    fprintf('\n[4/5] Building 2023 history and demand support...\n');
    historyData = build_history(clean.plant2023,clean.land,parameters,allowed,cfg);
    fprintf('  demand support = %d\n', height(historyData.demand));
    fprintf('  positive demand combinations = %d\n', sum(historyData.demand.demand_jin > 0));
    fprintf('  zero demand combinations     = %d\n', sum(historyData.demand.demand_jin == 0));
    fprintf('  history z positive states    = %d\n', sum(historyData.historyZ(:)));
    fprintf('  plots with 2023 beans        = %d\n', sum(historyData.historyBean));

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

    fprintf('\n[5/5] Running hard-gate audit...\n');
    audit = validate_data(data,cfg);

    % Save compact, inspectable outputs.
    writetable(audit.checks, fullfile(cfg.auditDir,'audit_checks.csv'));
    writetable(clean.cleaningLog, fullfile(cfg.auditDir,'cleaning_log.csv'));
    writetable(data.demand, fullfile(cfg.auditDir,'clean_demand.csv'));
    writetable(data.dispersal, fullfile(cfg.auditDir,'clean_dispersal.csv'));
    writetable(data.adjacency, fullfile(cfg.auditDir,'clean_adjacency_2023_to_2024.csv'));
    writetable(audit.nmaxConflicts, fullfile(cfg.auditDir,'nmax_history_conflicts.csv'));
    writetable(struct2table(audit.summary), fullfile(cfg.auditDir,'audit_summary.csv'));

    fprintf('\n---------------- AUDIT RESULTS ----------------\n');
    for r = 1:height(audit.checks)
        fprintf('%-8s | %s | actual: %s\n', ...
            audit.checks.status{r}, ...
            audit.checks.check{r}, ...
            audit.checks.actual{r});
    end

    fprintf('\n---------------- KEY COUNTS -------------------\n');
    fprintf('plots                         = %d (expected 54)\n', audit.summary.plot_count);
    fprintf('crops                         = %d (expected 41)\n', audit.summary.crop_count);
    fprintf('2023 planting records         = %d (expected 87)\n', audit.summary.plant_records);
    fprintf('raw statistics records        = %d (expected 107)\n', audit.summary.statistics_records);
    fprintf('allowed parameter combos      = %d (expected 125)\n', audit.summary.allowed_parameter_combinations);
    fprintf('demand support                = %d (expected 59)\n', audit.summary.demand_support);
    fprintf('positive demand               = %d (expected 47)\n', audit.summary.positive_demand);
    fprintf('zero demand                   = %d (expected 12)\n', audit.summary.zero_demand);
    fprintf('history z positive            = %d (expected 87)\n', audit.summary.history_z_positive);
    fprintf('plots with 2023 beans         = %d (expected 19)\n', audit.summary.history_bean_plots);
    fprintf('Nmax historical conflicts     = %d (expected 3)\n', audit.summary.nmax_conflicts);

    if audit.passed
        fprintf('\nMODULE_A_PASS = 1\n');
        fprintf('Module A passed. It is safe to proceed to MILP testing.\n');
    else
        fprintf('\nMODULE_A_PASS = 0\n');
        error('Q1:AuditFailed','MATLAB模块A审计未通过。请查看 audit_checks.csv。');
    end

catch ME
    fprintf(2,'\nMODULE_A_ERROR [%s]\n%s\n',ME.identifier,ME.message);
    fprintf(2,'Error location:\n');
    for s = 1:numel(ME.stack)
        fprintf(2,'  %s, line %d\n',ME.stack(s).name,ME.stack(s).line);
    end
    rethrow(ME);
end
end
