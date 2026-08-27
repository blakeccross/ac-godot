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
    scale: float = 0.001
    test_set_only: bool = True

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
    return PipelineConfig(
        project_root=root,
        game_files=_resolve(root, data["game_files"]),
        work_root=_resolve(root, data["work_root"]),
        godot_generated=_resolve(root, data.get("godot_generated", "assets/generated")),
        dtk_path=_resolve(root, data.get("dtk_path", "tools/.cache/dtk")),
        scale=float(data.get("scale", 0.001)),
        test_set_only=bool(data.get("test_set_only", True)),
    )
