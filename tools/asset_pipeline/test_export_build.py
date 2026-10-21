"""Unit tests for desktop export target / preset helpers (no Godot run)."""

from __future__ import annotations

import unittest
from pathlib import Path

from asset_pipeline.export_build import (
    EXPORT_TARGETS,
    list_preset_names,
    resolve_targets,
)

ROOT = Path(__file__).resolve().parents[2]


class ExportBuildTests(unittest.TestCase):
    def test_resolve_targets(self) -> None:
        self.assertEqual(resolve_targets("windows"), ["windows"])
        self.assertEqual(resolve_targets("macos"), ["macos"])
        self.assertEqual(resolve_targets("all"), ["windows", "macos"])
        with self.assertRaises(ValueError):
            resolve_targets("linux")

    def test_project_presets_include_desktop(self) -> None:
        names = list_preset_names(ROOT)
        for key, info in EXPORT_TARGETS.items():
            self.assertIn(
                info["preset"],
                names,
                msg=f"{key} preset {info['preset']!r} missing from export_presets.cfg",
            )


if __name__ == "__main__":
    unittest.main()
