function sensitivity_analysis(~,~)
%SENSITIVITY_ANALYSIS 防止在 alpha=0 审查前擅自启动敏感性分析。
error('Q1:Deferred','alpha=0尚待审查；不得运行Nmax或beta敏感性分析。');
end

