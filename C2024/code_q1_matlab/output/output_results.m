function output_results(data,cfg,vars,result,outDir)
%OUTPUT_RESULTS Export alpha=0 result after validation passes.
% MATLAB target: R2024a.

rows = cell(0,16);
annual = zeros(numel(cfg.years),4);

I = size(vars.x_id,1);
J = size(vars.x_id,2);
T = size(vars.x_id,3);
K = size(vars.x_id,4);

for i = 1:I
    for j = 1:J
        cropRow = find(data.crop.crop_id == j,1,'first');
        if isempty(cropRow)
            error('Q1:CropNameLookup','找不到作物编号%d。',j);
        end
        cropName = data.crop.crop_name{cropRow};

        for t = 1:T
            for k = 1:K
                xid = vars.x_id(i,j,t,k);
                if xid == 0 || result.x(xid) <= cfg.tolerance
                    continue;
                end

                area = result.x(xid);
                paramMask = data.parameters.crop_id == j & ...
                    strcmp(data.parameters.land_type,data.land.land_type{i}) & ...
                    strcmp(data.parameters.season,cfg.seasons{k});
                paramRows = find(paramMask);
                if numel(paramRows) ~= 1
                    error('Q1:OutputParameterLookup', ...
                        '输出时参数匹配不唯一：plot=%s crop=%d season=%s。', ...
                        data.land.plot_id{i},j,cfg.seasons{k});
                end
                pr = paramRows(1);
                yieldValue = data.parameters.yield_jin_per_mu(pr);
                costPerMu = data.parameters.cost_yuan_per_mu(pr);
                price = data.parameters.price_mid(pr);
                production = area * yieldValue;

                qid = vars.q_id(j,t,k);
                eid = vars.e_id(j,t,k);
                qTotal = result.x(qid);
                eTotal = result.x(eid);

                totalProduction = 0;
                for ii = 1:I
                    otherXid = vars.x_id(ii,j,t,k);
                    if otherXid > 0
                        otherMask = data.parameters.crop_id == j & ...
                            strcmp(data.parameters.land_type,data.land.land_type{ii}) & ...
                            strcmp(data.parameters.season,cfg.seasons{k});
                        otherRow = find(otherMask,1,'first');
                        totalProduction = totalProduction + ...
                            result.x(otherXid) * data.parameters.yield_jin_per_mu(otherRow);
                    end
                end

                if totalProduction <= cfg.tolerance
                    error('Q1:OutputProduction','正种植面积对应总产量非正。');
                end

                share = production / totalProduction;
                qPlot = qTotal * share;
                ePlot = eTotal * share;
                revenue = price * qPlot; % alpha=0: excess has no revenue.
                cost = costPerMu * area;
                profit = revenue - cost;

                rows(end+1,:) = { ...
                    cfg.years(t), ...
                    cfg.seasons{k}, ...
                    data.land.plot_id{i}, ...
                    data.land.land_type{i}, ...
                    j, ...
                    cropName, ...
                    area, ...
                    yieldValue, ...
                    production, ...
                    qPlot, ...
                    ePlot, ...
                    price, ...
                    costPerMu, ...
                    cost, ...
                    revenue, ...
                    profit}; %#ok<AGROW>

                annual(t,:) = annual(t,:) + [profit,qPlot,ePlot,area];
            end
        end
    end
end

variableNames = { ...
    'year','season','plot_id','land_type','crop_id','crop_name', ...
    'area_mu','yield_jin_per_mu','production_jin','normal_sales_jin', ...
    'excess_jin','price_yuan_per_jin','cost_yuan_per_mu','cost_yuan', ...
    'revenue_yuan','profit_yuan'};

if isempty(rows)
    Tdetail = cell2table(cell(0,numel(variableNames)), 'VariableNames', variableNames);
else
    Tdetail = cell2table(rows,'VariableNames',variableNames);
end

Tsummary = array2table([cfg.years',annual], ...
    'VariableNames', {'year','total_profit_yuan','normal_sales_jin', ...
    'excess_jin','planted_area_mu'});

file = fullfile(outDir,'result1_1.xlsx');
if isfile(file)
    delete(file);
end
writetable(Tdetail,file,'Sheet','planting_detail');
writetable(Tsummary,file,'Sheet','annual_summary');
end
