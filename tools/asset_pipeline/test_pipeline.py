"""Layout, prefix ownership, and map-index helpers for the asset pipeline."""

from __future__ import annotations

import unittest

from asset_pipeline.convert import _name_under_prefix, _owning_vtx_prefix, _static_jobs
from asset_pipeline.glb import _bake_wrap_group
from asset_pipeline.layout import (
    bti_output_path,
    output_folder_for_static,
    output_for_prefix,
    uses_shared_npc_anims,
)
from asset_pipeline.mapfile import MapSymbol, find_symbol, index_by_name
from asset_pipeline.texbank import GX_CLAMP, GX_REPEAT


def _sym(name: str, addr: int = 0, size: int = 4) -> MapSymbol:
    return MapSymbol(addr, size, 4, name, "dataobject.obj")


class LayoutTests(unittest.TestCase):
    def test_species_paths(self) -> None:
        self.assertTrue(uses_shared_npc_anims("cat_1"))
        self.assertFalse(uses_shared_npc_anims("boy_1"))
        self.assertEqual(output_for_prefix("cat_1"), "characters/villagers/cat_1.glb")
        self.assertEqual(output_for_prefix("boy_1"), "characters/player/boy_1.glb")
        self.assertEqual(output_for_prefix("int_kon_redclock"), "furniture/int_kon_redclock.glb")
        self.assertEqual(output_folder_for_static("grd_s_f_1"), "environment/acres")

    def test_bti_keeps_archive_subdir(self) -> None:
        self.assertEqual(bti_output_path("forest_2nd/data/boy1.bti"), "ui/forest_2nd/data/boy1.png")
        self.assertEqual(
            bti_output_path("forest_1st/data/foo.bti.szs"),
            "ui/forest_1st/data/foo.png",
        )


class PrefixOwnershipTests(unittest.TestCase):
    def test_digit_boundary(self) -> None:
        self.assertTrue(_name_under_prefix("grd_s_f_1_gfx_model", "grd_s_f_1"))
        self.assertFalse(_name_under_prefix("grd_s_f_10_gfx_model", "grd_s_f_1"))

    def test_t_overlay_longest_prefix(self) -> None:
        prefixes = {"obj_s_palm5", "obj_s_palm5_coco"}
        self.assertEqual(
            _owning_vtx_prefix("obj_s_palm5_cocoT_gfx_model", prefixes),
            "obj_s_palm5_coco",
        )
        self.assertEqual(
            _owning_vtx_prefix("obj_s_palm5_leafT_gfx_model", prefixes),
            "obj_s_palm5",
        )

    def test_static_jobs_prefer_gfx_and_test_set_override(self) -> None:
        symbols = [
            _sym("obj_s_tree5_v"),
            _sym("obj_s_tree5_leafT_gfx_model"),
            _sym("obj_s_tree5_trunkT_gfx_model"),
            _sym("grd_s_f_1_v", 1),
            _sym("grd_s_f_10_v", 2),
            _sym("grd_s_f_1_gfx_model", 3),
            _sym("grd_s_f_10_gfx_model", 4),
        ]
        jobs = {item["asset_id"]: item for item in _static_jobs(symbols)}
        self.assertEqual(
            jobs["obj_s_tree5"]["gfx"],
            ["obj_s_tree5_leafT_gfx_model", "obj_s_tree5_trunkT_gfx_model"],
        )
        self.assertEqual(jobs["grd_s_f_1"]["gfx"], ["grd_s_f_1_gfx_model"])
        self.assertEqual(jobs["grd_s_f_10"]["gfx"], ["grd_s_f_10_gfx_model"])
        self.assertEqual(jobs["obj_s_tree5"]["output"], "environment/trees/obj_s_tree5.glb")


class MapIndexTests(unittest.TestCase):
    def test_find_prefers_index(self) -> None:
        symbols = [_sym("a", 1), _sym("b", 2)]
        by_name = index_by_name(symbols)
        self.assertEqual(find_symbol(symbols, "b", by_name).address, 2)
        with self.assertRaises(KeyError):
            find_symbol(symbols, "missing", by_name)


class WrapBakeTests(unittest.TestCase):
    def test_acre_16_cell_repeat_is_baked(self) -> None:
        from io import BytesIO

        from PIL import Image

        buf = BytesIO()
        Image.new("RGBA", (8, 8), (0, 200, 0, 255)).save(buf, format="PNG")
        png = buf.getvalue()

        class _V:
            def __init__(self, u: float, v: float) -> None:
                self.u = u
                self.v = v

        class _Part:
            wrap_s = GX_REPEAT
            wrap_t = GX_REPEAT
            texture_png = png
            vertices = [_V(0.0, 0.0), _V(16.0, 16.0)]

        group = {
            "png": png,
            "name": "grd_grass",
            "wrap_s": GX_REPEAT,
            "wrap_t": GX_REPEAT,
            "parts": [_Part()],
        }
        _bake_wrap_group(group)
        baked = Image.open(BytesIO(group["png"]))
        self.assertEqual(baked.size, (8 * 16, 8 * 16))
        self.assertEqual(group["wrap_s"], GX_CLAMP)
        self.assertAlmostEqual(_Part.vertices[1].u, 1.0)
        self.assertAlmostEqual(_Part.vertices[1].v, 1.0)


if __name__ == "__main__":
    unittest.main()
