"""统一构建模块 A 已验证、可直接供模块 B 使用的数据对象。"""

from __future__ import annotations

from typing import Any

from config import Config
from data.build_allowed import build_allowed
from data.build_history import build_history_and_demand
from data.build_parameters import build_parameters
from data.read_clean import clean_data, read_raw_excel
from data.validate_data import AuditResult, validate_data


def prepare_verified_data(cfg: Config) -> tuple[dict[str, Any], AuditResult]:
    """严格复用模块 A 清洗、参数构建和门控，不重新解释附件。"""
    raw = read_raw_excel(cfg)
    clean = clean_data(raw, cfg)
    parameters, inherited = build_parameters(clean.statistics_2023)
    allowed = build_allowed(clean.land, cfg.seasons)
    history, demand, dispersal, history_z, history_bean, adjacency = build_history_and_demand(
        clean.plant_2023, clean.land, parameters, allowed
    )
    data: dict[str, Any] = {
        "land": clean.land, "crop": clean.crop, "plant_2023": clean.plant_2023,
        "statistics_2023": clean.statistics_2023, "parameters": parameters, "allowed": allowed,
        "history_2023": history, "history_z_2023": history_z,
        "history_bean_2023": history_bean, "adjacency_2023_to_2024": adjacency,
        "demand": demand, "dispersal": dispersal, "inherited_parameters": inherited,
        "raw_row_counts": clean.raw_row_counts, "cleaning_log": clean.cleaning_log,
    }
    audit = validate_data(data, cfg)
    return data, audit

