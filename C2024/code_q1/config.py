"""问题 1 的统一配置：模块 A 只读取、清洗和审计数据，不调用 MILP。"""

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Config:
    project_root: Path
    years: tuple[int, ...] = tuple(range(2024, 2031))
    seasons: tuple[str, ...] = ("单季", "第一季", "第二季")
    beta: float = 0.5
    nmax: int = 3
    alpha_list: tuple[float, ...] = (0.0, 0.5)
    baseline_alpha: float = 0.0
    random_seed: int = 42

    @property
    def attachment_1(self) -> Path:
        return self.project_root / "附件1.xlsx"

    @property
    def attachment_2(self) -> Path:
        return self.project_root / "附件2.xlsx"

    @property
    def audit_dir(self) -> Path:
        return self.project_root / "code_q1" / "results" / "data_audit"


def load_config() -> Config:
    return Config(project_root=Path(__file__).resolve().parent.parent)

