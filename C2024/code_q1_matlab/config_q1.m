function cfg = config_q1()
%CONFIG_Q1 问题1 MATLAB实现的唯一配置入口。
% 本文件不读取或修改原始附件；所有固定口径来自已审查通过的 Python 模块A。

here = fileparts(mfilename('fullpath'));
cfg = struct();
cfg.projectRoot = fileparts(here);
cfg.codeRoot = here;
cfg.attachment1 = fullfile(cfg.projectRoot, '附件1.xlsx');
cfg.attachment2 = fullfile(cfg.projectRoot, '附件2.xlsx');
cfg.resultsDir = fullfile(here, 'results');
cfg.auditDir = fullfile(cfg.resultsDir, 'data_audit');
cfg.alpha0Dir = fullfile(cfg.resultsDir, 'alpha_0');

cfg.years = 2024:2030;
cfg.seasons = {'单季', '第一季', '第二季'};
cfg.K_SINGLE = 1;
cfg.K_FIRST = 2;
cfg.K_SECOND = 3;
cfg.beta = 0.5;
cfg.Nmax = 3;
cfg.alpha = 0.0;                 % 第一阶段仅情形1。
cfg.seed = 42;
cfg.tolerance = 1e-6;

cfg.grainCrops = 1:15;
cfg.riceCrop = 16;
cfg.firstSeasonVegetables = 17:34;
cfg.secondSeasonWaterVegetables = 35:37;
cfg.mushroomCrops = 38:41;
cfg.beanCrops = [1 2 3 4 5 17 18 19];

% 保守默认值；用户可在不改变模型含义的前提下按本机资源调整。
cfg.gurobi.OutputFlag = 1;
cfg.gurobi.MIPGap = 1e-4;
cfg.gurobi.TimeLimit = 3600;
cfg.gurobi.Threads = 0;
cfg.gurobi.Seed = cfg.seed;
end



