"""Bake step: turn the converted acre GLBs into project scenes.

The runtime has no GLB path for field acres. `tools/bake_acre_scenes.gd` (run headless by
`bake_acre_scenes`; `tools/bake_acre_scenes.sh` does the same by hand on macOS/Linux) writes one scene per `grd_*` acre
into `scenes/world/acres/` and everything those scenes reference into
`assets/generated/environment/acre_scenes/`.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from typing import Any

from .config import PipelineConfig

## Same installs `tools/test.sh` and `tools/capture.sh` accept when config omits `godot_bin`.
_GODOT_FALLBACKS: tuple[str, ...] = (
    "/Applications/Godot.app/Contents/MacOS/Godot",
    "/Applications/Godot_4.app/Contents/MacOS/Godot",
    "/opt/godot/godot",
)


def resolve_godot_bin(cfg: PipelineConfig, extra: tuple[str, ...] | None = None) -> str | None:
    """Godot for the bake step: `GODOT_BIN`, then config, then the usual app paths."""
    candidates: list[str] = []
    env = os.environ.get("GODOT_BIN")
    if env:
        candidates.append(env)
    if cfg.godot_bin:
        candidates.append(cfg.godot_bin)
    candidates.extend(_GODOT_FALLBACKS if extra is None else extra)
    for raw in candidates:
        path = Path(raw)
        if path.is_file() and os.access(path, os.X_OK):
            return str(path)
    return shutil.which("godot") or shutil.which("godot4")


def bake_acre_scenes(cfg: PipelineConfig, acre_ids: list[str] | None = None) -> dict[str, Any]:
    godot = resolve_godot_bin(cfg)
    if not godot:
        return {
            "ok": False,
            "error": (
                "acre scenes need Godot: set GODOT_BIN or `godot_bin` in tools/config.local.json "
                "(the game cannot load field acres without them)"
            ),
        }
    ## Same four Godot runs as `tools/bake_acre_scenes.sh`, driven from here so the pipeline
    ## does not need a POSIX shell (Windows cannot execute a `.sh`).
    root = str(cfg.project_root)
    ids = list(acre_ids or [])
    steps: list[list[str]] = [
        [godot, "--headless", "--path", root, "--import"],
        [godot, "--headless", "--path", root, "res://tools/bake_acre_scenes.tscn", "--", "textures", *ids],
        [godot, "--headless", "--path", root, "--import"],
        [godot, "--headless", "--path", root, "res://tools/bake_acre_scenes.tscn", "--", "scenes", *ids],
    ]
    for cmd in steps:
        result = subprocess.run(cmd, cwd=cfg.project_root, env={**os.environ, "GODOT_BIN": godot}, check=False)
        if result.returncode != 0:
            return {"ok": False, "error": f"bake exited {result.returncode}"}
    return {"ok": True, "error": ""}
