function [model, vars, meta] = build_MILP(data, cfg, alpha)
%BUILD_MILP Build the sparse MILP for Problem 1.
% MATLAB target: R2024a. Gurobi MATLAB API target: 10.0.1.
% Index semantics are always i x j x t x k.

if nargin < 3
    alpha = cfg.alpha;
end

I = height(data.land);
J = 41;
T = numel(cfg.years);
K = 3;
allowed = data.allowed;

x_id = zeros(I,J,T,K);
z_id = zeros(I,J,T,K);
q_id = zeros(J,T,K);
e_id = zeros(J,T,K);
r_id = zeros(I,T);

obj = zeros(0,1);
lb = zeros(0,1);
ub = zeros(0,1);
vtype = char(zeros(0,1));
nvar = 0;

    function id = addvar(coef, lower, upper, typeChar)
        nvar = nvar + 1;
        id = nvar;
        obj(id,1) = coef;
        lb(id,1) = lower;
        ub(id,1) = upper;
        vtype(id,1) = typeChar;
    end

%% x,z: sparse variables only for allowed combinations
for i = 1:I
    for j = 1:J
        for t = 1:T
            for k = 1:K
                if allowed(i,j,k)
                    [~,~,costValue] = parameter_for(data,j,k,i,cfg);
                    x_id(i,j,t,k) = addvar(-costValue,0,data.land.area_mu(i),'C');
                    z_id(i,j,t,k) = addvar(0,0,1,'B');
                end
            end
        end
    end
end

%% q,e: all 59 demand-support crop-season pairs for every year
for j = 1:J
    for t = 1:T
        for k = 1:K
            drow = find(data.demand.crop_id == j & data.demand.season_idx == k,1,'first');
            if ~isempty(drow)
                % Use i=0 to ask parameter_for to pick any allowed plot safely.
                [priceValue,~,~] = parameter_for(data,j,k,0,cfg);
                q_id(j,t,k) = addvar(priceValue,0,inf,'C');
                e_id(j,t,k) = addvar(alpha*priceValue,0,inf,'C');
            end
        end
    end
end

%% Irrigated-land mode variables
waterPlots = find(strcmp(data.land.land_type,'水浇地'))';
for i = waterPlots
    for t = 1:T
        r_id(i,t) = addvar(0,0,1,'B');
    end
end

%% Sparse constraint accumulator
Ai = zeros(0,1);
Aj = zeros(0,1);
Av = zeros(0,1);
rhs = zeros(0,1);
sense = char(zeros(0,1));
cnames = cell(0,1);
ctypes = cell(0,1);
ncon = 0;
rotationPairs = zeros(0,3);

    function addcon(ids,vals,sgn,b,name)
        ids = ids(:);
        vals = vals(:);
        if isempty(ids)
            error('Q1:EmptyConstraint','约束 %s 意外为空。',name);
        end
        if numel(ids) ~= numel(vals)
            error('Q1:ConstraintSizeMismatch','约束 %s 的变量数和系数数不一致。',name);
        end
        if any(ids <= 0)
            error('Q1:InvalidVariableId','约束 %s 包含非正变量编号。',name);
        end
        ncon = ncon + 1;
        Ai = [Ai; repmat(ncon,numel(ids),1)]; %#ok<AGROW>
        Aj = [Aj; ids]; %#ok<AGROW>
        Av = [Av; vals]; %#ok<AGROW>
        rhs(ncon,1) = b;
        sense(ncon,1) = sgn;
        cnames{ncon,1} = sprintf('%s_%06d',name,ncon);
        ctypes{ncon,1} = name;
    end

    function addrot(a,b)
        if a > 0 && b > 0
            addcon([a;b],[1;1],'<',1,'C8_rotation');
            rotationPairs(end+1,:) = [a,b,0]; %#ok<AGROW>
        end
    end

    function addhist(i,j,k)
        firstDecision = z_id(i,j,1,k);
        if firstDecision > 0 && data.historyZ(i,j,k) > 0
            addcon(firstDecision,1,'<',0,'C9_history_boundary');
            rotationPairs(end+1,:) = [firstDecision,0,1]; %#ok<AGROW>
        end
    end

%% C2 x-z linking and minimum planting area
for i = 1:I
    area_i = data.land.area_mu(i);
    for j = 1:J
        for t = 1:T
            for k = 1:K
                xid = x_id(i,j,t,k);
                zid = z_id(i,j,t,k);
                if xid > 0
                    % beta*A*z <= x  <=> -x + beta*A*z <= 0
                    addcon([xid;zid],[-1;cfg.beta*area_i],'<',0,'C2_xz_lower');
                    % x <= A*z  <=> x - A*z <= 0
                    addcon([xid;zid],[1;-area_i],'<',0,'C2_xz_upper');
                end
            end
        end
    end
end

%% C1 plot-season capacity
for i = 1:I
    for t = 1:T
        for k = 1:K
            ids = nonzeros(squeeze(x_id(i,:,t,k)));
            if ~isempty(ids)
                addcon(ids,ones(numel(ids),1),'<',data.land.area_mu(i),'C1_capacity');
            end
        end
    end
end

%% C4 irrigated mode: rice OR two-season vegetables
for i = waterPlots
    for t = 1:T
        riceId = z_id(i,cfg.riceCrop,t,cfg.K_SINGLE);
        firstIds = nonzeros(squeeze(z_id(i,cfg.firstSeasonVegetables,t,cfg.K_FIRST)));
        secondIds = nonzeros(squeeze(z_id(i,cfg.secondSeasonWaterVegetables,t,cfg.K_SECOND)));
        modeId = r_id(i,t);

        % z_rice = r
        addcon([riceId;modeId],[1;-1],'=',0,'C4_water_rice_mode');
        % sum(first) >= 1-r  <=> -sum(first)-r <= -1
        addcon([firstIds;modeId],[-ones(numel(firstIds),1);-1],'<',-1,'C4_water_first_occupy');
        % exactly one second-season crop in vegetable mode
        addcon([secondIds;modeId],[ones(numel(secondIds),1);1],'=',1,'C4_water_second_unique');
    end
end

%% C5/C6 greenhouse mandatory occupancy
for i = 1:I
    lt = data.land.land_type{i};
    for t = 1:T
        if strcmp(lt,'普通大棚')
            firstIds = nonzeros(squeeze(z_id(i,cfg.firstSeasonVegetables,t,cfg.K_FIRST)));
            secondIds = nonzeros(squeeze(z_id(i,cfg.mushroomCrops,t,cfg.K_SECOND)));
            addcon(firstIds,-ones(numel(firstIds),1),'<',-1,'C5_ordinary_first_occupy');
            addcon(secondIds,-ones(numel(secondIds),1),'<',-1,'C5_ordinary_second_occupy');
        elseif strcmp(lt,'智慧大棚')
            firstIds = nonzeros(squeeze(z_id(i,cfg.firstSeasonVegetables,t,cfg.K_FIRST)));
            secondIds = nonzeros(squeeze(z_id(i,cfg.firstSeasonVegetables,t,cfg.K_SECOND)));
            addcon(firstIds,-ones(numel(firstIds),1),'<',-1,'C6_smart_first_occupy');
            addcon(secondIds,-ones(numel(secondIds),1),'<',-1,'C6_smart_second_occupy');
        end
    end
end

%% C8/C9 chronological no-repeat + 2023 boundary
for i = 1:I
    lt = data.land.land_type{i};

    if any(strcmp(lt,{'平旱地','梯田','山坡地'}))
        for j = cfg.grainCrops
            addhist(i,j,cfg.K_SINGLE);
            for t = 1:T-1
                addrot(z_id(i,j,t,cfg.K_SINGLE),z_id(i,j,t+1,cfg.K_SINGLE));
            end
        end

    elseif strcmp(lt,'智慧大棚')
        for j = cfg.firstSeasonVegetables
            % 2023 second season -> 2024 first season
            if data.historyZ(i,j,cfg.K_SECOND) > 0
                first2024 = z_id(i,j,1,cfg.K_FIRST);
                if first2024 > 0
                    addcon(first2024,1,'<',0,'C9_history_boundary');
                    rotationPairs(end+1,:) = [first2024,0,1]; %#ok<AGROW>
                end
            end
            for t = 1:T
                addrot(z_id(i,j,t,cfg.K_FIRST),z_id(i,j,t,cfg.K_SECOND));
                if t < T
                    addrot(z_id(i,j,t,cfg.K_SECOND),z_id(i,j,t+1,cfg.K_FIRST));
                end
            end
        end

    elseif strcmp(lt,'水浇地')
        % Only rice can repeat across adjacent years in rice mode.
        j = cfg.riceCrop;
        addhist(i,j,cfg.K_SINGLE);
        for t = 1:T-1
            addrot(z_id(i,j,t,cfg.K_SINGLE),z_id(i,j,t+1,cfg.K_SINGLE));
        end
    end
    % Ordinary greenhouse and irrigated vegetable seasons have disjoint
    % adjacent crop sets, so same-crop chronological repeat is impossible.
end

%% C10 rolling three-year bean requirement, including 2023-2025
for i = 1:I
    % Window 2023-2025: historical indicator + decision years 2024,2025.
    ids = zeros(0,1);
    for t = 1:2
        for j = cfg.beanCrops
            for k = 1:K
                id = z_id(i,j,t,k);
                if id > 0
                    ids(end+1,1) = id; %#ok<AGROW>
                end
            end
        end
    end
    requiredDecisionBeans = 1 - data.historyBean(i);
    if requiredDecisionBeans > 0
        addcon(ids,-ones(numel(ids),1),'<',-requiredDecisionBeans,'C10_bean_2023_2025');
    end

    % Pure decision windows: 2024-2026 through 2028-2030.
    for startYear = 1:T-2
        ids = zeros(0,1);
        for t = startYear:startYear+2
            for j = cfg.beanCrops
                for k = 1:K
                    id = z_id(i,j,t,k);
                    if id > 0
                        ids(end+1,1) = id; %#ok<AGROW>
                    end
                end
            end
        end
        addcon(ids,-ones(numel(ids),1),'<',-1,'C10_bean_window');
    end
end

%% C11 Nmax dispersal, C12 production split, C13 demand cap
for j = 1:J
    for t = 1:T
        for k = 1:K
            zIds = nonzeros(squeeze(z_id(:,j,t,k)));
            if ~isempty(zIds)
                addcon(zIds,ones(numel(zIds),1),'<',cfg.Nmax,'C11_nmax');
            end

            qid = q_id(j,t,k);
            if qid > 0
                eid = e_id(j,t,k);
                xIds = nonzeros(squeeze(x_id(:,j,t,k)));
                productionCoeff = zeros(numel(xIds),1);
                cursor = 0;
                for i = 1:I
                    xid = x_id(i,j,t,k);
                    if xid > 0
                        cursor = cursor + 1;
                        [~,yieldValue,~] = parameter_for(data,j,k,i,cfg);
                        productionCoeff(cursor) = -yieldValue;
                    end
                end
                addcon([qid;eid;xIds],[1;1;productionCoeff],'=',0,'C12_production_balance');

                drow = find(data.demand.crop_id==j & data.demand.season_idx==k,1,'first');
                demandValue = data.demand.demand_jin(drow);
                addcon(qid,1,'<',demandValue,'C13_demand_cap');
            end
        end
    end
end

%% Gurobi model
model = struct();
model.A = sparse(Ai,Aj,Av,ncon,nvar);
model.obj = obj;
model.rhs = rhs;
model.sense = sense;
model.vtype = vtype;
model.lb = lb;
model.ub = ub;
model.modelsense = 'max';

vars = struct();
vars.x_id = x_id;
vars.z_id = z_id;
vars.q_id = q_id;
vars.e_id = e_id;
vars.r_id = r_id;

meta = struct();
meta.constraint_names = cnames;
meta.constraint_types = ctypes;
meta.rotation_pairs = rotationPairs;
meta.nvar = nvar;
meta.ncon = ncon;
meta.binary_variables = sum(vtype=='B');
meta.continuous_variables = sum(vtype=='C');
meta.alpha = alpha;
end

function [priceValue,yieldValue,costValue] = parameter_for(data,j,k,i,cfg)
% Return the unique parameter row for a feasible plot/crop/season.
if i == 0
    i = find(data.allowed(:,j,k),1,'first');
    if isempty(i)
        error('Q1:NoAllowedPlot','作物%d 季次%d没有allowed地块。',j,k);
    end
end

lt = data.land.land_type{i};
mask = data.parameters.crop_id == j & ...
    strcmp(data.parameters.land_type,lt) & ...
    strcmp(data.parameters.season,cfg.seasons{k});
rows = find(mask);
if numel(rows) ~= 1
    error('Q1:ParameterLookup','参数键应唯一：crop=%d land=%s season=%s，实际匹配=%d。', ...
        j,lt,cfg.seasons{k},numel(rows));
end
r = rows(1);
priceValue = data.parameters.price_mid(r);
yieldValue = data.parameters.yield_jin_per_mu(r);
costValue = data.parameters.cost_yuan_per_mu(r);
end
