function clean = read_clean_data(cfg)
%READ_CLEAN_DATA Read attachments 1/2 and reproduce the audited cleaning rules.
% MATLAB target: R2024a. Avoid chained indexing on function return values.

if ~isfile(cfg.attachment1) || ~isfile(cfg.attachment2)
    error('Q1:MissingAttachment', '找不到附件1或附件2，不能继续数据审计。');
end

rawLand = readtable(cfg.attachment1, 'Sheet', '乡村的现有耕地', ...
    'VariableNamingRule', 'preserve');
rawCrop = readtable(cfg.attachment1, 'Sheet', '乡村种植的农作物', ...
    'VariableNamingRule', 'preserve');
rawPlant = readtable(cfg.attachment2, 'Sheet', '2023年的农作物种植情况', ...
    'VariableNamingRule', 'preserve');
rawStat = readtable(cfg.attachment2, 'Sheet', '2023年统计的相关数据', ...
    'VariableNamingRule', 'preserve');

clean = struct();
clean.rawRowCounts = struct( ...
    'land', height(rawLand), ...
    'crop', height(rawCrop), ...
    'plant2023', height(rawPlant), ...
    'statistics2023', height(rawStat));

logStep = cell(0,1);
logAffected = zeros(0,1);
logRule = cell(0,1);

%% Attachment 1: land
landPlotAll = strip_cellstr(to_cellstr(rawLand.('地块名称')));
landTypeAll = strip_cellstr(to_cellstr(rawLand.('地块类型')));
landAreaAll = to_numeric(rawLand.('地块面积/亩'));
land = table(landPlotAll, landTypeAll, landAreaAll, ...
    'VariableNames', {'plot_id','land_type','area_mu'});

%% Attachment 1: crop master
cropIdAll = to_numeric(rawCrop.('作物编号'));
cropNameAll = strip_cellstr(to_cellstr(rawCrop.('作物名称')));
cropTypeAll = strip_cellstr(to_cellstr(rawCrop.('作物类型')));
cropMask = ~isnan(cropIdAll);

logStep{end+1,1} = '剔除附件1作物表中的说明/空白行';
logAffected(end+1,1) = sum(~cropMask);
logRule{end+1,1} = '仅保留数值作物编号；其他行均为说明或空白行。';

crop = table(cropIdAll(cropMask), cropNameAll(cropMask), cropTypeAll(cropMask), ...
    'VariableNames', {'crop_id','crop_name','crop_type'});

% Forward-fill crop type after filtering explanatory rows.
for r = 2:height(crop)
    if isempty(crop.crop_type{r})
        crop.crop_type{r} = crop.crop_type{r-1};
    end
end

%% Attachment 2: 2023 planting records
plantPlot = strip_cellstr(to_cellstr(rawPlant.('种植地块')));
fillCount = sum(cellfun(@isempty, plantPlot));
for r = 2:numel(plantPlot)
    if isempty(plantPlot{r})
        plantPlot{r} = plantPlot{r-1};
    end
end

logStep{end+1,1} = '填充2023种植表合并单元格地块名';
logAffected(end+1,1) = fillCount;
logRule{end+1,1} = '按连续合并单元格使用上一条有效地块名向下填充。';

plantCropId = to_numeric(rawPlant.('作物编号'));
plantCropName = strip_cellstr(to_cellstr(rawPlant.('作物名称')));
plantCropType = strip_cellstr(to_cellstr(rawPlant.('作物类型')));
plantArea = to_numeric(rawPlant.('种植面积/亩'));
plantSeason = strip_cellstr(to_cellstr(rawPlant.('种植季次')));

plant = table(plantPlot, plantCropId, plantCropName, plantCropType, ...
    plantArea, plantSeason, ...
    'VariableNames', {'plot_id','crop_id','crop_name','crop_type', ...
    'plant_area_mu','season'});

%% Attachment 2: parameter table and price intervals
statIdAll = to_numeric(rawStat.('作物编号'));
statNameAll = strip_cellstr(to_cellstr(rawStat.('作物名称')));
statLandTypeAll = strip_cellstr(to_cellstr(rawStat.('地块类型')));
statSeasonAll = strip_cellstr(to_cellstr(rawStat.('种植季次')));
statYieldAll = to_numeric(rawStat.('亩产量/斤'));
statCostAll = to_numeric(rawStat.('种植成本/(元/亩)'));
statIntervalAll = strip_cellstr(to_cellstr(rawStat.('销售单价/(元/斤)')));

statMask = ~isnan(statIdAll);
logStep{end+1,1} = '剔除附件2统计表中的说明/空白行';
logAffected(end+1,1) = sum(~statMask);
logRule{end+1,1} = '仅保留数值作物编号；其他行均为说明或空白行。';

statId = statIdAll(statMask);
statName = statNameAll(statMask);
statLandType = statLandTypeAll(statMask);
statSeason = statSeasonAll(statMask);
statYield = statYieldAll(statMask);
statCost = statCostAll(statMask);
interval = statIntervalAll(statMask);

nStat = numel(statId);
priceLow = zeros(nStat,1);
priceHigh = zeros(nStat,1);
priceMid = zeros(nStat,1);
for r = 1:nStat
    [priceLow(r), priceHigh(r), priceMid(r)] = parse_price_interval(interval{r});
end

logStep{end+1,1} = '解析销售价格区间';
logAffected(end+1,1) = nStat;
logRule{end+1,1} = '解析low/high并按问题1确认口径使用区间中点。';

statistics = table(statId, statName, statLandType, statSeason, ...
    statYield, statCost, interval, priceLow, priceHigh, priceMid, ...
    'VariableNames', {'crop_id','crop_name','land_type','season', ...
    'yield_jin_per_mu','cost_yuan_per_mu','price_interval', ...
    'price_low','price_high','price_mid'});

clean.land = land;
clean.crop = crop;
clean.plant2023 = plant;
clean.statistics2023 = statistics;
clean.cleaningLog = table(logStep, logAffected, logRule, ...
    'VariableNames', {'step','affected_rows','rule'});
end

function out = to_cellstr(value)
% Convert common readtable output types to a column cell array of char.
if iscell(value)
    out = cell(size(value));
    for ii = 1:numel(value)
        out{ii} = char_or_empty(value{ii});
    end
elseif isstring(value)
    out = cellstr(value);
elseif iscategorical(value)
    out = cellstr(value);
elseif isnumeric(value)
    out = arrayfun(@num2str, value, 'UniformOutput', false);
else
    out = cellstr(string(value));
end
out = out(:);
end

function s = char_or_empty(value)
if isempty(value)
    s = '';
elseif isnumeric(value) && isscalar(value) && isnan(value)
    s = '';
elseif ischar(value)
    s = value;
elseif isstring(value)
    if ismissing(value)
        s = '';
    else
        s = char(value);
    end
else
    s = char(string(value));
end
end

function out = strip_cellstr(in)
out = cell(size(in));
for ii = 1:numel(in)
    out{ii} = strtrim(in{ii});
end
out = out(:);
end

function out = to_numeric(value)
if isnumeric(value)
    out = double(value(:));
else
    text = to_cellstr(value);
    out = nan(numel(text),1);
    for ii = 1:numel(text)
        out(ii) = str2double(strtrim(text{ii}));
    end
end
end

function [low, high, mid] = parse_price_interval(value)
text = strtrim(strrep(strrep(value, '—', '-'), '–', '-'));
parts = regexp(text, ...
    '^\s*([0-9]+(?:\.[0-9]+)?)\s*-\s*([0-9]+(?:\.[0-9]+)?)\s*$', ...
    'tokens', 'once');
if isempty(parts)
    error('Q1:InvalidPriceInterval', '销售价格区间无法解析：%s', value);
end
low = str2double(parts{1});
high = str2double(parts{2});
if isnan(low) || isnan(high) || low < 0 || high < low
    error('Q1:InvalidPriceInterval', '销售价格区间不合法：%s', value);
end
mid = (low + high) / 2;
end
