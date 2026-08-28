function validation = validate_solution(data, cfg, model, vars, meta, result, outDir)
%VALIDATE_SOLUTION 由 result.x 独立重算变量约束残差、整数性和目标值。
if ~isfolder(outDir), mkdir(outDir); end
tol=cfg.tolerance; x=result.x(:); rows=(1:meta.ncon)';
activity=model.A*x; violation=zeros(meta.ncon,1);
for r=1:meta.ncon
    if model.sense(r)=='<', violation(r)=max(0,activity(r)-model.rhs(r));
    elseif model.sense(r)=='>', violation(r)=max(0,model.rhs(r)-activity(r));
    else, violation(r)=abs(activity(r)-model.rhs(r)); end
end
types=meta.constraint_types; names={'面积容量','x-z上下界','allowed','水浇地模式','普通大棚两季实际种植','智慧大棚两季实际种植','水浇地第二季唯一作物','连续重茬','2023→2024历史边界','三年豆类窗口','Nmax','q+e=总产量','q<=demand','变量上下界与整数性','目标函数重算'};
map={{'C1_capacity'},{'C2_xz_lower','C2_xz_upper'},{'allowed_sparse_mapping'},{'C4_water_rice_mode','C4_water_first_occupy'},{'C5_ordinary_first_occupy','C5_ordinary_second_occupy'},{'C6_smart_first_occupy','C6_smart_second_occupy'},{'C4_water_second_unique'},{'C8_rotation'},{'C9_history_boundary'},{'C10_bean_2023_2025','C10_bean_window'},{'C11_nmax'},{'C12_production_balance'},{'C13_demand_cap'}};
maxV=zeros(numel(names),1); note=cell(numel(names),1);
for i=1:13
    idx=false(meta.ncon,1); for q=1:numel(map{i}), idx=idx|strcmp(types,map{i}{q}); end
    if any(idx), maxV(i)=max(violation(idx)); else, maxV(i)=inf; end
    note{i}='按求解向量重算对应矩阵约束残差';
end
illegalPositive=0; for i=1:size(vars.x_id,1), for j=1:size(vars.x_id,2), for t=1:size(vars.x_id,3), for k=1:size(vars.x_id,4)
    if vars.x_id(i,j,t,k)==0 && vars.z_id(i,j,t,k)~=0, illegalPositive=inf; end
end,end,end,end
maxV(3)=illegalPositive; note{3}='非法组合没有变量编号；合法性由稀疏映射保证';
binaryIds=[nonzeros(vars.z_id(:));nonzeros(vars.r_id(:))]; bounds=max([max(0,-x);max(0,x-model.ub);max(abs(x(binaryIds)-round(x(binaryIds))))]);
maxV(14)=bounds; note{14}='连续变量下界、二进制变量整数性及全部变量上下界';
recalc=model.obj(:)'*x; if isfield(result,'objval'), maxV(15)=abs(recalc-result.objval); else, maxV(15)=inf; end
note{15}=sprintf('重算=%.10g',recalc);
passed=maxV<=tol; validation.table=table(names',passed,maxV,note,'VariableNames',{'check_name','passed','max_violation','note'});
validation.passed=all(passed); validation.objective_recalculated=recalc; validation.max_violation=max(maxV);
writetable(validation.table,fullfile(outDir,'validation_summary.csv'));
fid=fopen(fullfile(outDir,'solution_validation_summary.txt'),'w'); fprintf(fid,'PASS=%d\nmax_violation=%.12g\nobjective_recalculated=%.12g\n',validation.passed,validation.max_violation,recalc); fclose(fid);
end


