"""构建未来七年复用的亩产、成本和价格参数。"""

from __future__ import annotations

import pandas as pd


def build_parameters(statistics: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    """补齐指南明确的“智慧大棚第一季=普通大棚第一季”参数继承。"""
    parameters = statistics.copy()
    ordinary_first = parameters.loc[
        (parameters["land_type"] == "普通大棚") & (parameters["season"] == "第一季")
    ].copy()
    inherited = ordinary_first.copy()
    inherited["land_type"] = "智慧大棚"
    inherited["parameter_source"] = "由普通大棚第一季按附件2注释继承"
    parameters["parameter_source"] = "附件2原始统计记录"
    parameters = pd.concat([parameters, inherited], ignore_index=True)
    return parameters, inherited

