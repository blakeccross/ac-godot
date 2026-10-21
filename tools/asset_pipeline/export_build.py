"""Export step: Godot --export-release for Windows / macOS into ``out/``.

Requires matching presets in ``export_presets.cfg`` and Godot export templates
installed for the editor version (Editor → Manage Export Templates).
"""

from __future__ import annotations

import configparser
import os
import subprocess
from pathlib import Path
from typing import Any

from .config import PipelineConfig

## CLI ``--export`` value → preset name + path relative to the project root.
EXPORT_TARGETS: dict[str, dict[str, str]] = {
    "windows": {
        "preset": "Windows Desktop",
        "path": "out/windows/AC Godot.exe",
    },
    "macos": {
        "preset": "macOS",
        "path": "out/macos/AC Godot.zip",
    },
}


def list_preset_names(project_root: Path) -> list[str]:
    cfg_path = project_root / "export_presets.cfg"
    if not cfg_path.is_file():
        return []
    parser = configparser.ConfigParser()
    parser.read(cfg_path, encoding="utf-8")
    names: list[str] = []
    for section in parser.sections():
        if section.startswith("preset.") and not section.endswith(".options"):
            name = parser.get(section, "name", fallback="").strip().strip('"')
            if name:
                names.append(name)
    return names


def resolve_targets(export_arg: str) -> list[str]:
    """Map ``windows`` / ``macos`` / ``all`` to target keys."""
    if export_arg == "all":
        return list(EXPORT_TARGETS.keys())
    if export_arg in EXPORT_TARGETS:
        return [export_arg]
    raise ValueError(f"unknown --export value: {export_arg!r}")


def _godot_bin(cfg: PipelineConfig) -> str | None:
    return os.environ.get("GODOT_BIN") or cfg.godot_bin


def export_desktop_builds(cfg: PipelineConfig, export_arg: str) -> dict[str, Any]:
    """Run ``--export-release`` for each requested target. Returns a summary dict."""
    godot = _godot_bin(cfg)
    if not godot:
        return {
            "ok": False,
            "error": (
                "export needs Godot: set GODOT_BIN or `godot_bin` in tools/config.local.json"
            ),
            "results": [],
        }

    try:
        targets = resolve_targets(export_arg)
    except ValueError as exc:
        return {"ok": False, "error": str(exc), "results": []}

    presets = list_preset_names(cfg.project_root)
    results: list[dict[str, Any]] = []
    ok = True

    ## Import so .godot/ is warm; export-release fails on a never-opened project.
    import_result = subprocess.run(
        [godot, "--headless", "--path", str(cfg.project_root), "--import"],
        cwd=cfg.project_root,
        env={**os.environ, "GODOT_BIN": godot},
        check=False,
    )
    if import_result.returncode != 0:
        return {
            "ok": False,
            "error": f"godot --import exited {import_result.returncode}",
            "results": [],
        }

    for key in targets:
        info = EXPORT_TARGETS[key]
        preset = info["preset"]
        rel_path = info["path"]
        out_path = cfg.project_root / rel_path
        entry: dict[str, Any] = {
            "target": key,
            "preset": preset,
            "path": str(out_path),
            "ok": False,
            "error": "",
        }
        if preset not in presets:
            entry["error"] = (
                f"preset {preset!r} missing from export_presets.cfg "
                f"(have: {', '.join(presets) or 'none'})"
            )
            ok = False
            results.append(entry)
            continue

        out_path.parent.mkdir(parents=True, exist_ok=True)
        cmd = [
            godot,
            "--headless",
            "--path",
            str(cfg.project_root),
            "--export-release",
            preset,
            str(out_path),
        ]
        result = subprocess.run(
            cmd,
            cwd=cfg.project_root,
            env={**os.environ, "GODOT_BIN": godot},
            check=False,
        )
        if result.returncode != 0:
            entry["error"] = (
                f"godot --export-release exited {result.returncode} "
                "(install export templates for this Godot version if missing)"
            )
            ok = False
        elif not out_path.exists():
            ## Godot sometimes exits 0 while still failing; require an artefact.
            entry["error"] = f"export reported success but {out_path} was not written"
            ok = False
        else:
            entry["ok"] = True
        results.append(entry)

    return {"ok": ok, "error": "" if ok else "one or more exports failed", "results": results}
