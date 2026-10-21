"""Unit tests for bake-step Godot discovery (no Godot run)."""

from __future__ import annotations

import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from asset_pipeline.bake import resolve_godot_bin
from asset_pipeline.config import PipelineConfig


def _cfg(godot_bin: str | None = None) -> PipelineConfig:
    root = Path("/tmp")
    return PipelineConfig(
        project_root=root,
        game_files=root,
        work_root=root,
        godot_generated=root,
        dtk_path=root,
        godot_bin=godot_bin,
    )


def _executable(directory: Path, name: str) -> Path:
    path = directory / name
    path.write_text("#!/bin/sh\n")
    path.chmod(path.stat().st_mode | stat.S_IXUSR)
    return path


class ResolveGodotBinTests(unittest.TestCase):
    def test_env_wins_over_config_and_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            env_bin = _executable(folder, "from-env")
            cfg_bin = _executable(folder, "from-cfg")
            fallback = _executable(folder, "fallback")
            with mock.patch.dict(os.environ, {"GODOT_BIN": str(env_bin)}):
                found = resolve_godot_bin(_cfg(str(cfg_bin)), extra=(str(fallback),))
            self.assertEqual(found, str(env_bin))

    def test_config_wins_over_fallback(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            cfg_bin = _executable(folder, "from-cfg")
            fallback = _executable(folder, "fallback")
            with mock.patch.dict(os.environ, {"GODOT_BIN": ""}):
                found = resolve_godot_bin(_cfg(str(cfg_bin)), extra=(str(fallback),))
            self.assertEqual(found, str(cfg_bin))

    def test_fallback_when_config_omits_godot(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fallback = _executable(Path(tmp), "Godot")
            with mock.patch.dict(os.environ, {"GODOT_BIN": ""}):
                found = resolve_godot_bin(_cfg(None), extra=(str(fallback),))
            self.assertEqual(found, str(fallback))

    def test_missing_paths_do_not_invent_a_binary(self) -> None:
        with mock.patch.dict(os.environ, {"GODOT_BIN": ""}):
            with mock.patch("asset_pipeline.bake.shutil.which", return_value=None):
                found = resolve_godot_bin(_cfg(None), extra=("/no/such/godot",))
        self.assertIsNone(found)


if __name__ == "__main__":
    unittest.main()
