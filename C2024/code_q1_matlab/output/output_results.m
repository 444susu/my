function output_results(data,cfg,vars,result,outDir)
%OUTPUT_RESULTS 仅在独立验证PASS后导出 alpha=0 的逐地块与年度摘要。
rows={}; annual=zeros(numel(cfg.years),4);
for i=1:size(vars.x_id,1), for j=1:41, for t=1:numel(cfg.years), for k=1:3
    id=vars.x_id(i,j,t,k); if id==0 || result.x(id)<=cfg.tolerance, continue; end
    area=result.x(id); m=data.parameters.crop_id==j & strcmp(data.parameters.land_type,data.land.land_type{i}) & strcmp(data.parameters.season,cfg.seasons{k}); y=data.parameters.yield_jin_per_mu(m); c=data.parameters.cost_yuan_per_mu(m); p=data.parameters.price_mid(m); production=area*y;
    q=result.x(vars.q_id(j,t,k)); e=result.x(vars.e_id(j,t,k)); total=0;
    for ii=1:size(vars.x_id,1)
        xid=vars.x_id(ii,j,t,k);
        if xid>0
            mm=data.parameters.crop_id==j & strcmp(data.parameters.land_type,data.land.land_type{ii}) & strcmp(data.parameters.season,cfg.seasons{k});
            total=total+result.x(xid)*data.parameters.yield_jin_per_mu(mm);
        end
    end
    share=production/total; qPlot=q*share; ePlot=e*share; revenue=p*(qPlot); cost=c*area; profit=revenue-cost;
    rows(end+1,:)={cfg.years(t),cfg.seasons{k},data.land.plot_id{i},data.land.land_type{i},j,data.crop.crop_name{j},area,y,production,qPlot,ePlot,p,c,cost,revenue,profit}; %#ok<AGROW>
    annual(t,:)=annual(t,:)+[profit,qPlot,ePlot,area];
end,end,end,end
T=cell2table(rows,'VariableNames',{'year','season','plot_id','land_type','crop_id','crop_name','area_mu','yield_jin_per_mu','production_jin','normal_sales_jin','excess_jin','price_yuan_per_jin','cost_yuan_per_mu','cost_yuan','revenue_yuan','profit_yuan'});
S=array2table([cfg.years',annual],'VariableNames',{'year','total_profit_yuan','normal_sales_jin','excess_jin','planted_area_mu'});
file=fullfile(outDir,'result1_1.xlsx'); writetable(T,file,'Sheet','planting_detail'); writetable(S,file,'Sheet','annual_summary');
end

