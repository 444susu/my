function [parameters, inherited] = build_parameters(statistics)
%BUILD_PARAMETERS 将智慧大棚第一季参数按附件说明继承自普通大棚。

statistics.parameter_source = repmat({'附件2原始统计记录'}, height(statistics), 1);
ordinaryFirst = statistics(strcmp(statistics.land_type, '普通大棚') & strcmp(statistics.season, '第一季'), :);
inherited = ordinaryFirst;
inherited.land_type = repmat({'智慧大棚'}, height(inherited), 1);
inherited.parameter_source = repmat({'由普通大棚第一季按附件2注释继承'}, height(inherited), 1);
parameters = [statistics; inherited];
end



