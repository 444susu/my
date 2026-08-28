function cfg = config_q1()
%CONFIG_Q1 问题1 MATLAB实现的唯一配置入口。
% MATLAB target: R2024a. Gurobi MATLAB API target: 10.0.1.

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

% 分散度管理参数：
% 普通作物仍采用 Nmax=3；普通大棚第二季食用菌单独采用 NmaxFungi=4。
% 原因：16个普通大棚每年第二季均需实际种植，而食用菌仅4种；
% 若每种最多3个地块，则最多覆盖12个大棚，模型必然不可行。
cfg.Nmax = 3;
cfg.NmaxFungi = 4;

cfg.alpha = 0.0;                 % 第一阶段仅情形1。
cfg.seed = 42;
cfg.tolerance = 1e-6;

cfg.grainCrops = 1:15;
cfg.riceCrop = 16;
cfg.firstSeasonVegetables = 17:34;
cfg.secondSeasonWaterVegetables = 35:37;
cfg.mushroomCrops = 38:41;
cfg.beanCrops = [1 2 3 4 5 17 18 19];

% 后续敏感性分析建议。
cfg.NmaxSensitivity = 3:7;
cfg.NmaxFungiSensitivity = 4:7;
cfg.betaSensitivity = [0.3 0.4 0.5 0.6];

% 保守默认值；用户可按本机资源调整，但不得改变模型含义。
cfg.gurobi.OutputFlag = 1;
cfg.gurobi.MIPGap = 1e-4;
cfg.gurobi.TimeLimit = 3600;
cfg.gurobi.Threads = 0;
cfg.gurobi.Seed = cfg.seed;
end
