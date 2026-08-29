from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional


@dataclass
class PipelineConfig:
    """Paths are resolved relative to the Godot project root unless absolute."""

    project_root: Path
    game_files: Path
    work_root: Path
    godot_generated: Path
    dtk_path: Path
    # Same Vtx multiplier for every mesh. Not the in-game draw scale: actors use
    # 0.01 (m_actor.c), acre DLs use 0.0625 (ac_field_draw.c). Godot maps both
    # into meters with FieldCatalog (40 GX = 2 m).
    scale: float = 0.001
    test_set_only: bool = True
    decomp_root: Optional[Path] = None

    @property
    def extracted_disc(self) -> Path:
        return self.work_root / "extracted" / "disc"

    @property
    def extracted_archives(self) -> Path:
        return self.work_root / "extracted" / "archives"

    @property
    def converted(self) -> Path:
        return self.work_root / "converted"

    @property
    def manifests(self) -> Path:
        return self.work_root / "manifests"

    @property
    def rel_path(self) -> Path:
        return self.extracted_disc / "files" / "foresta.rel"

    @property
    def map_path(self) -> Path:
        return self.extracted_disc / "files" / "foresta.map"


def _resolve(project_root: Path, value: str) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = project_root / path
    return path.resolve()


def load_config(project_root: Optional[Path] = None, config_path: Optional[Path] = None) -> PipelineConfig:
    root = (project_root or Path.cwd()).resolve()
    path = config_path or root / "tools" / "config.local.json"
    example = root / "tools" / "config.example.json"
    if not path.exists():
        path = example
    data: dict[str, Any] = json.loads(path.read_text())
    decomp_raw = data.get("decomp_root") or ""
    return PipelineConfig(
        project_root=root,
        game_files=_resolve(root, data["game_files"]),
        work_root=_resolve(root, data["work_root"]),
        godot_generated=_resolve(root, data.get("godot_generated", "assets/generated")),
        dtk_path=_resolve(root, data.get("dtk_path", "tools/.cache/dtk")),
        scale=float(data.get("scale", 0.001)),
        test_set_only=bool(data.get("test_set_only", True)),
        decomp_root=_resolve(root, decomp_raw) if str(decomp_raw).strip() else None,
    )
