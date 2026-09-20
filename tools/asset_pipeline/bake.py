"""Bake step: turn the converted acre GLBs into project scenes.

The runtime has no GLB path for field acres. `tools/bake_acre_scenes.gd` (driven by
`tools/bake_acre_scenes.sh`, which runs Godot headless) writes one scene per `grd_*` acre
into `scenes/world/acres/` and everything those scenes reference into
`assets/generated/environment/acre_scenes/`.
"""

from __future__ import annotations

import os
import subprocess
from typing import Any

from .config import PipelineConfig


def bake_acre_scenes(cfg: PipelineConfig, acre_ids: list[str] | None = None) -> dict[str, Any]:
    godot = os.environ.get("GODOT_BIN") or cfg.godot_bin
    if not godot:
        return {
            "ok": False,
            "error": (
                "acre scenes need Godot: set GODOT_BIN or `godot_bin` in tools/config.local.json "
                "(the game cannot load field acres without them)"
            ),
        }
    script = cfg.project_root / "tools" / "bake_acre_scenes.sh"
    result = subprocess.run(
        [str(script), *(acre_ids or [])],
        cwd=cfg.project_root,
        env={**os.environ, "GODOT_BIN": godot},
        check=False,
    )
    return {"ok": result.returncode == 0, "error": "" if result.returncode == 0 else f"bake exited {result.returncode}"}
