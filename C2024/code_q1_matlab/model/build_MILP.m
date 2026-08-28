function [model, vars, meta] = build_MILP(data, cfg, alpha)
%BUILD_MILP Alpha=0 的稀疏变量 Gurobi MATLAB 矩阵模型；下标恒为 i×j×t×k.
if nargin<3, alpha=cfg.alpha; end
I=height(data.land); J=41; T=numel(cfg.years); K=3; allowed=data.allowed;
x_id=zeros(I,J,T,K); z_id=zeros(I,J,T,K); q_id=zeros(J,T,K); e_id=zeros(J,T,K); r_id=zeros(I,T);
obj=[]; lb=[]; ub=[]; vtype=''; nvar=0;
    function id=addvar(cost,lo,hi,typ)
        nvar=nvar+1; id=nvar; obj(id,1)=cost; lb(id,1)=lo; ub(id,1)=hi; vtype(id,1)=typ;
    end
for i=1:I, for j=1:J, for t=1:T, for k=1:K
    if allowed(i,j,k)
        [~,~,cost]=parameter_for(data,j,k,i,cfg);
        x_id(i,j,t,k)=addvar(-cost,0,data.land.area_mu(i),'C');
        z_id(i,j,t,k)=addvar(0,0,1,'B');
    end
end,end,end,end
for j=1:J, for t=1:T, for k=1:K
    d=find(data.demand.crop_id==j & data.demand.season_idx==k,1);
    if ~isempty(d)
        [price,~]=parameter_for(data,j,k,1,cfg);
        q_id(j,t,k)=addvar(price,0,inf,'C'); e_id(j,t,k)=addvar(alpha*price,0,inf,'C');
    end
end,end,end
water=find(strcmp(data.land.land_type,'水浇地'))';
for i=water, for t=1:T, r_id(i,t)=addvar(0,0,1,'B'); end,end
Ai=[]; Aj=[]; Av=[]; rhs=[]; sense=''; cnames={}; ctypes={}; ncon=0;
for i=1:I, for j=1:J, for t=1:T, for k=1:K
    id=x_id(i,j,t,k); zid=z_id(i,j,t,k);
    if id>0
        addcon([id,zid],[-1,cfg.beta*data.land.area_mu(i)],'<',0,'C2_xz_lower');
        addcon([id,zid],[1,-data.land.area_mu(i)],'<',0,'C2_xz_upper');
    end
end,end,end,end
for i=1:I, for t=1:T, for k=1:K
    ids=nonzeros(squeeze(x_id(i,:,t,k)))';
    if ~isempty(ids), addcon(ids,ones(size(ids)),'<',data.land.area_mu(i),'C1_capacity'); end
end,end,end
for i=water, for t=1:T
    rice=z_id(i,cfg.riceCrop,t,cfg.K_SINGLE); first=nonzeros(squeeze(z_id(i,cfg.firstSeasonVegetables,t,cfg.K_FIRST)))'; second=nonzeros(squeeze(z_id(i,cfg.secondSeasonWaterVegetables,t,cfg.K_SECOND)))';
    addcon([rice,r_id(i,t)],[1,-1],'=',0,'C4_water_rice_mode');
    addcon([first,r_id(i,t)],[-ones(1,numel(first)),-1],'<',-1,'C4_water_first_occupy');
    addcon([second,r_id(i,t)],[ones(1,numel(second)),1],'=',1,'C4_water_second_unique');
end,end
for i=1:I, for t=1:T
    if strcmp(data.land.land_type{i},'普通大棚')
        addcon(nonzeros(squeeze(z_id(i,cfg.firstSeasonVegetables,t,cfg.K_FIRST)))',-ones(1,numel(cfg.firstSeasonVegetables)),'<',-1,'C5_ordinary_first_occupy');
        addcon(nonzeros(squeeze(z_id(i,cfg.mushroomCrops,t,cfg.K_SECOND)))',-ones(1,numel(cfg.mushroomCrops)),'<',-1,'C5_ordinary_second_occupy');
    elseif strcmp(data.land.land_type{i},'智慧大棚')
        addcon(nonzeros(squeeze(z_id(i,cfg.firstSeasonVegetables,t,cfg.K_FIRST)))',-ones(1,numel(cfg.firstSeasonVegetables)),'<',-1,'C6_smart_first_occupy');
        addcon(nonzeros(squeeze(z_id(i,cfg.firstSeasonVegetables,t,cfg.K_SECOND)))',-ones(1,numel(cfg.firstSeasonVegetables)),'<',-1,'C6_smart_second_occupy');
    end
end,end
rotationPairs=[];
for i=1:I
    lt=data.land.land_type{i};
    if any(strcmp(lt,{'平旱地','梯田','山坡地'}))
        for j=cfg.grainCrops, addhist(i,j,cfg.K_SINGLE); for t=1:T-1, addrot(z_id(i,j,t,cfg.K_SINGLE),z_id(i,j,t+1,cfg.K_SINGLE)); end,end
    elseif strcmp(lt,'智慧大棚')
        for j=cfg.firstSeasonVegetables, addhist(i,j,cfg.K_SECOND); for t=1:T, addrot(z_id(i,j,t,cfg.K_FIRST),z_id(i,j,t,cfg.K_SECOND)); if t<T, addrot(z_id(i,j,t,cfg.K_SECOND),z_id(i,j,t+1,cfg.K_FIRST)); end,end,end
    elseif strcmp(lt,'水浇地')
        j=cfg.riceCrop; addhist(i,j,cfg.K_SINGLE); for t=1:T-1, addrot(z_id(i,j,t,cfg.K_SINGLE),z_id(i,j,t+1,cfg.K_SINGLE)); end
    end
end
for i=1:I
    ids=[]; for t=1:2, for j=cfg.beanCrops, for k=1:K, if z_id(i,j,t,k)>0, ids(end+1)=z_id(i,j,t,k); end,end,end,end
    addcon(ids,-ones(1,numel(ids)),'<',-(1-data.historyBean(i)),'C10_bean_2023_2025');
    for s=1:T-2
        ids=[]; for t=s:s+2, for j=cfg.beanCrops, for k=1:K, if z_id(i,j,t,k)>0, ids(end+1)=z_id(i,j,t,k); end,end,end,end
        addcon(ids,-ones(1,numel(ids)),'<',-1,'C10_bean_window');
    end
end
for j=1:J, for t=1:T, for k=1:K
    ids=nonzeros(squeeze(z_id(:,j,t,k)))'; if ~isempty(ids), addcon(ids,ones(size(ids)),'<',cfg.Nmax,'C11_nmax'); end
    q=q_id(j,t,k); if q>0
        e=e_id(j,t,k); xids=nonzeros(squeeze(x_id(:,j,t,k)))'; coeff=[1,1]; for i=1:I, if x_id(i,j,t,k)>0, [~,y]=parameter_for(data,j,k,i,cfg); coeff(end+1)=-y; end,end
        addcon([q,e,xids],coeff,'=',0,'C12_production_balance');
        d=data.demand.demand_jin(data.demand.crop_id==j & data.demand.season_idx==k); addcon(q,1,'<',d,'C13_demand_cap');
    end
end,end,end
model.A=sparse(Ai,Aj,Av,ncon,nvar); model.obj=obj; model.rhs=rhs; model.sense=sense; model.vtype=vtype; model.lb=lb; model.ub=ub; model.modelsense='max';
vars=struct('x_id',x_id,'z_id',z_id,'q_id',q_id,'e_id',e_id,'r_id',r_id);
meta=struct('constraint_names',{cnames},'constraint_types',{ctypes},'rotation_pairs',rotationPairs,'nvar',nvar,'ncon',ncon,'binary_variables',sum(vtype=='B'),'continuous_variables',sum(vtype=='C'),'alpha',alpha);
    function addrot(a,b)
        if a>0 && b>0, addcon([a,b],[1,1],'<',1,'C8_rotation'); rotationPairs(end+1,:)=[a,b,0]; end
    end
    function addhist(i,j,k)
        a=z_id(i,j,1,k); if a>0 && data.historyZ(i,j,k)>0, addcon(a,1,'<',0,'C9_history_boundary'); rotationPairs(end+1,:)=[a,0,1]; end
    end
    function addcon(ids,vals,sgn,b,name)
        if isempty(ids), error('Q1:EmptyConstraint','约束%s意外为空。',name); end
        ncon=ncon+1; Ai=[Ai;repmat(ncon,numel(ids),1)]; Aj=[Aj;ids(:)]; Av=[Av;vals(:)]; rhs(ncon,1)=b; sense(ncon,1)=sgn; cnames{ncon,1}=sprintf('%s_%06d',name,ncon); ctypes{ncon,1}=name;
    end
end
function [price,yieldValue,costValue]=parameter_for(data,j,k,i,cfg)
if i==0, i=find(data.allowed(:,j,k),1); end
lt=data.land.land_type{i}; m=data.parameters.crop_id==j & strcmp(data.parameters.land_type,lt) & strcmp(data.parameters.season,cfg.seasons{k});
price=data.parameters.price_mid(find(m,1)); yieldValue=data.parameters.yield_jin_per_mu(find(m,1)); costValue=data.parameters.cost_yuan_per_mu(find(m,1));
end

