"""Layout, prefix ownership, and map-index helpers for the asset pipeline."""

from __future__ import annotations

import unittest

from asset_pipeline.ckf import _mat_model_name, select_bind_anim
from asset_pipeline.convert import WATER_STATIC_NEEDLES, _name_under_prefix, _owning_vtx_prefix, _static_jobs
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
        self.assertEqual(output_for_prefix("tol_net_1"), "items/tol_net_1.glb")
        self.assertEqual(output_folder_for_static("grd_s_f_1"), "environment/acres")
        self.assertEqual(output_folder_for_static("obj_s_stump5"), "environment/trees")
        self.assertEqual(output_folder_for_static("obj_hole0"), "environment/holes")
        self.assertEqual(output_folder_for_static("tol_axe_1"), "items")

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
        self.assertTrue(_name_under_prefix("int_ari_isu01_00T_model", "int_ari_isu01"))
        self.assertTrue(_name_under_prefix("int_ari_reizou01_01_model", "int_ari_reizou01"))
        self.assertTrue(_name_under_prefix("int_sum_chair01_on_model", "int_sum_chair01"))
        self.assertTrue(_name_under_prefix("int_ike_art_fel01_on_model", "int_ike_art_fel"))

    def test_t_overlay_longest_prefix(self) -> None:
        prefixes = {"obj_s_palm5", "obj_s_palm5_coco"}
        self.assertEqual(
            _owning_vtx_prefix("obj_s_palm5_cocoT_gfx_model", prefixes),
            "obj_s_palm5_coco",
        )
        self.assertEqual(
            _owning_vtx_prefix("int_ike_art_fel01_onT_model", {"int_ike_art_fel"}),
            "int_ike_art_fel",
        )

    def test_hardwood_stump_drops_season_infix(self) -> None:
        prefixes = {"obj_s_stump5", "obj_s_tree5"}
        self.assertEqual(
            _owning_vtx_prefix("obj_stump5T_gfx_model", prefixes),
            "obj_s_stump5",
        )

    def test_static_jobs_prefer_gfx_and_test_set_override(self) -> None:
        symbols = [
            _sym("obj_s_tree5_v"),
            _sym("obj_s_tree5_leafT_gfx_model"),
            _sym("obj_s_tree5_trunkT_gfx_model"),
            _sym("obj_s_stump5_v"),
            _sym("obj_stump5T_gfx_model"),
            _sym("grd_s_f_1_v", 1),
            _sym("grd_s_f_10_v", 2),
            _sym("grd_s_f_1_gfx_model", 3),
            _sym("grd_s_f_10_gfx_model", 4),
            _sym("obj_s_kouban_shadow_v", 5),
            _sym("obj_s_kouban_shadow_model", 6),
            _sym("grd_s_r1_1_v", 7),
            _sym("grd_s_r1_1_model", 8),
            _sym("grd_s_r1_1_modelT", 9),
        ]
        jobs = {item["asset_id"]: item for item in _static_jobs(symbols)}
        self.assertNotIn("obj_s_kouban_shadow", jobs)
        self.assertEqual(
            jobs["obj_s_tree5"]["gfx"],
            ["obj_s_tree5_leafT_gfx_model", "obj_s_tree5_trunkT_gfx_model"],
        )
        self.assertEqual(jobs["grd_s_f_1"]["gfx"], ["grd_s_f_1_gfx_model"])
        self.assertEqual(jobs["grd_s_f_10"]["gfx"], ["grd_s_f_10_gfx_model"])
        self.assertEqual(jobs["obj_s_tree5"]["output"], "environment/trees/obj_s_tree5.glb")
        self.assertEqual(jobs["obj_s_stump5"]["gfx"], ["obj_stump5T_gfx_model"])
        self.assertEqual(jobs["obj_s_stump5"]["output"], "environment/trees/obj_s_stump5.glb")
        self.assertEqual(
            jobs["grd_s_r1_1"]["gfx"],
            ["grd_s_r1_1_model", "grd_s_r1_1_modelT"],
        )

    def test_water_needles_skip_rail_and_museum(self) -> None:
        self.assertTrue(any(n in "grd_s_r1_1" for n in WATER_STATIC_NEEDLES))
        self.assertTrue(any(n in "grd_s_m_1" for n in WATER_STATIC_NEEDLES))
        self.assertTrue(any(n in "grd_s_e2_o_1" for n in WATER_STATIC_NEEDLES))
        self.assertTrue(any(n in "grd_s_e3_m_1" for n in WATER_STATIC_NEEDLES))
        self.assertFalse(any(n in "grd_s_rail_1" for n in WATER_STATIC_NEEDLES))
        self.assertFalse(any(n in "grd_s_mh_1" for n in WATER_STATIC_NEEDLES))

    def test_beach_marine_strips_ocean_keeps_wet_sand(self) -> None:
        from asset_pipeline.convert import _is_beach_marine_asset, _strip_beach_water_parts
        from asset_pipeline.gfx import MeshPart, Vertex

        self.assertTrue(_is_beach_marine_asset("grd_s_m_1"))
        self.assertTrue(_is_beach_marine_asset("grd_s_m_r1_b_3"))
        self.assertTrue(_is_beach_marine_asset("grd_s_e3_m_1"))
        self.assertFalse(_is_beach_marine_asset("grd_s_o_2"))
        self.assertFalse(_is_beach_marine_asset("grd_s_e2_o_1"))
        self.assertFalse(_is_beach_marine_asset("grd_s_mh_1"))
        vert = Vertex(0, 0, 0, 0, 0, 255, 255, 255, 255)
        sand = MeshPart(name="sand", vertices=[vert], triangles=[(0, 0, 0)], water_kind="")
        wet = MeshPart(
            name="wet:mFM_grd_beachA_tex",
            vertices=[vert],
            triangles=[(0, 0, 0)],
            texture_name="mFM_grd_beachA_tex",
            water_kind="beach_wet",
            beach_prim=(206, 189, 148),
        )
        bed = MeshPart(
            name="bed:mFM_grd_beachB_tex",
            vertices=[vert],
            triangles=[(0, 0, 0)],
            texture_name="mFM_grd_beachB_tex",
            water_kind="beach_wet",
            beach_prim=(32, 48, 144),
        )
        ocean = MeshPart(name="ocean", vertices=[vert], triangles=[(0, 0, 0)], water_kind="ocean")
        splash = MeshPart(name="splash", vertices=[vert], triangles=[(0, 0, 0)], water_kind="splash")
        kept = _strip_beach_water_parts([sand, wet, bed, ocean, splash], "grd_s_m_1")
        self.assertEqual([p.name.split(":")[0] for p in kept], ["sand", "wet", "bed", "splash"])
        open_kept = _strip_beach_water_parts([sand, wet, bed, ocean], "grd_s_o_2")
        self.assertEqual(
            [p.name.split(":")[0] for p in open_kept], ["sand", "wet", "bed", "ocean"]
        )


class OverlayMatTests(unittest.TestCase):
    def test_stone_b_e_share_stone_a_mat(self) -> None:
        by_name = {
            "obj_s_stoneA_mat_model": _sym("obj_s_stoneA_mat_model"),
            "obj_w_stoneA_mat_model": _sym("obj_w_stoneA_mat_model"),
        }
        self.assertEqual(_mat_model_name("obj_s_stoneA_gfx_model", by_name), "obj_s_stoneA_mat_model")
        self.assertEqual(_mat_model_name("obj_s_stoneB_gfx_model", by_name), "obj_s_stoneA_mat_model")
        self.assertEqual(_mat_model_name("obj_s_stoneE_gfx_model", by_name), "obj_s_stoneA_mat_model")
        self.assertEqual(_mat_model_name("obj_w_stoneB_gfx_model", by_name), "obj_w_stoneA_mat_model")
        self.assertIsNone(_mat_model_name("obj_s_stoneB_gfx_model", {}))

    def test_hole_gfx_shares_hole0_g_mat(self) -> None:
        by_name = {
            "obj_hole0T_g_mat_model": _sym("obj_hole0T_g_mat_model"),
            "obj_hole0T_s_mat_model": _sym("obj_hole0T_s_mat_model"),
        }
        self.assertEqual(_mat_model_name("obj_hole0T_gfx_model", by_name), "obj_hole0T_g_mat_model")
        self.assertEqual(_mat_model_name("obj_hole12T_gfx_model", by_name), "obj_hole0T_g_mat_model")
        self.assertIsNone(_mat_model_name("obj_hole0T_gfx_model", {}))


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

    def test_water_repeat_is_not_baked(self) -> None:
        from io import BytesIO

        from PIL import Image

        buf = BytesIO()
        Image.new("RGBA", (8, 8), (0, 100, 200, 128)).save(buf, format="PNG")
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
            "name": "river_mFM_grd_water1_tex",
            "wrap_s": GX_REPEAT,
            "wrap_t": GX_REPEAT,
            "water_kind": "river",
            "parts": [_Part()],
        }
        _bake_wrap_group(group)
        self.assertEqual(group["wrap_s"], GX_REPEAT)
        self.assertAlmostEqual(_Part.vertices[1].u, 16.0)


class WindowDlTests(unittest.TestCase):
    def test_spill_vs_pane_names(self) -> None:
        from asset_pipeline.gfx import is_window_pane_dl, is_window_spill_dl

        self.assertTrue(is_window_spill_dl("obj_s_shop1_window_model"))
        self.assertTrue(is_window_spill_dl("obj_s_house1_windowL_model"))
        self.assertTrue(is_window_spill_dl("obj_s_museum_windowT_model"))
        self.assertTrue(is_window_spill_dl("obj_s_tailor_window_model"))
        self.assertFalse(is_window_spill_dl("obj_s_shop1_light_model"))
        self.assertFalse(is_window_spill_dl("obj_s_museum_lightT_model"))
        self.assertTrue(is_window_pane_dl("obj_s_shop1_light_model"))
        self.assertTrue(is_window_pane_dl("obj_s_museum_lightT_model"))
        self.assertFalse(is_window_pane_dl("obj_s_shop1_window_model"))
        self.assertFalse(is_window_spill_dl("room01_grp_room01__edge"))
        self.assertFalse(is_window_spill_dl("room_window"))
        self.assertFalse(is_window_spill_dl("rom_myhome_window_tex"))
        ## Parent `*_model` + window tex must not become outdoor I4 spill.
        self.assertFalse(is_window_spill_dl("room01_model:room_window"))
        self.assertFalse(is_window_spill_dl("room01_model"))

    def test_room_outdoor_view_names(self) -> None:
        from asset_pipeline.gfx import is_room_outdoor_view_dl

        self.assertTrue(is_room_outdoor_view_dl("room01_grp_room_out01"))
        self.assertFalse(is_room_outdoor_view_dl("room01_grp_room01__edge"))
        self.assertFalse(is_room_outdoor_view_dl("room_window"))

    def test_i4_png_becomes_alpha(self) -> None:
        from io import BytesIO

        from PIL import Image

        from asset_pipeline.texbank import i4_png_as_alpha

        src = Image.new("RGB", (2, 1), (0, 0, 0))
        src.putpixel((1, 0), (128, 128, 128))
        buf = BytesIO()
        src.save(buf, format="PNG")
        out = Image.open(BytesIO(i4_png_as_alpha(buf.getvalue()))).convert("RGBA")
        self.assertEqual(out.getpixel((0, 0))[3], 0)
        self.assertEqual(out.getpixel((1, 0))[3], 128)

    def test_beach_wet_bake_keeps_i_in_alpha(self) -> None:
        from io import BytesIO

        from PIL import Image

        from asset_pipeline.texbank import bake_beach_wet_png

        src = Image.new("RGB", (2, 1), (0, 0, 0))
        src.putpixel((1, 0), (255, 255, 255))
        buf = BytesIO()
        src.save(buf, format="PNG")
        out = Image.open(
            BytesIO(bake_beach_wet_png(buf.getvalue(), (206, 189, 148, 255), (144, 128, 96)))
        ).convert("RGBA")
        self.assertEqual(out.getpixel((0, 0)), (144, 128, 96, 0))
        self.assertEqual(out.getpixel((1, 0)), (206, 189, 148, 255))


class WaterNameTests(unittest.TestCase):
    def test_river_ocean_beach_kinds(self) -> None:
        from asset_pipeline.gfx import beach_wet_kind, is_ocean_bed_part, water_surface_kind

        self.assertEqual(water_surface_kind("mFM_grd_water1_tex", "mFM_grd_water2_tex"), "river")
        self.assertEqual(water_surface_kind("mFM_grd_wave1_tex", "mFM_grd_wave2_tex"), "ocean")
        self.assertEqual(water_surface_kind("mFM_grd_sprashC_tex", "mFM_grd_sprashA_tex"), "splash")
        self.assertEqual(water_surface_kind("obj_stump5T_gfx_model"), "")
        self.assertEqual(beach_wet_kind("mFM_grd_beachB_tex"), "beach_wet")
        self.assertEqual(beach_wet_kind("mFM_grd_beachA_tex"), "beach_wet")
        self.assertEqual(beach_wet_kind("mFM_grd_s_beach_tex"), "")
        from asset_pipeline.gfx import MeshPart, Vertex

        vert = Vertex(0, 0, 0, 0, 0, 255, 255, 255, 255)
        self.assertTrue(
            is_ocean_bed_part(
                MeshPart(
                    name="bed",
                    vertices=[vert],
                    triangles=[(0, 0, 0)],
                    texture_name="mFM_grd_beachB_tex",
                    water_kind="beach_wet",
                )
            )
        )
        self.assertFalse(
            is_ocean_bed_part(
                MeshPart(
                    name="wet",
                    vertices=[vert],
                    triangles=[(0, 0, 0)],
                    texture_name="mFM_grd_beachA_tex",
                    water_kind="beach_wet",
                )
            )
        )

    def test_rel_ia_wave_dims(self) -> None:
        from asset_pipeline.convert import _REL_IA_WAVE_DIMS

        self.assertEqual(_REL_IA_WAVE_DIMS["mFM_grd_wave1_tex"], (32, 32))
        self.assertEqual(_REL_IA_WAVE_DIMS["mFM_grd_wave2_tex"], (32, 64))
        self.assertEqual(_REL_IA_WAVE_DIMS["mFM_grd_wave3_tex"], (32, 32))

    def test_ocean_layer1_keeps_tile1_clamp_t(self) -> None:
        ## Decomp wave2: GX_REPEAT S / GX_CLAMP T. Convert used to force REPEAT/REPEAT.
        from asset_pipeline.glb import _group_parts, _material
        from asset_pipeline.gfx import MeshPart, Vertex
        from asset_pipeline.texbank import GX_CLAMP, GX_REPEAT, GLTF_CLAMP, wrap_to_gltf

        part = MeshPart(
            name="grd_s_m_1_modelT:mFM_grd_wave1_tex",
            vertices=[Vertex(0, 0, 0, 0, 0, 255, 255, 255, 255)],
            triangles=[(0, 0, 0)],
            texture_name="mFM_grd_wave1_tex",
            texture_png=b"wave1",
            wrap_s=GX_REPEAT,
            wrap_t=GX_REPEAT,
            alpha_mode="BLEND",
            layer1_png=b"wave2",
            layer1_name="mFM_grd_wave2_tex",
            layer1_wrap_s=GX_REPEAT,
            layer1_wrap_t=GX_CLAMP,
            water_kind="ocean",
        )
        groups = _group_parts([part])
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0]["layer1_wrap_s"], GX_REPEAT)
        self.assertEqual(groups[0]["layer1_wrap_t"], GX_CLAMP)
        mat = _material(
            groups[0]["name"],
            0,
            water_kind="ocean",
            layer1_texture_index=1,
            layer1_wrap_t=GX_CLAMP,
        )
        self.assertTrue(mat["extras"]["wave2_clamp_t"])
        open_mat = _material(
            "ocean_open",
            0,
            water_kind="ocean",
            layer1_texture_index=1,
            layer1_wrap_t=GX_REPEAT,
        )
        self.assertFalse(open_mat["extras"]["wave2_clamp_t"])
        self.assertEqual(wrap_to_gltf(GX_CLAMP), GLTF_CLAMP)

    def test_beach_wet_group_is_opaque(self) -> None:
        from asset_pipeline.glb import _group_alpha_mode, _group_parts
        from asset_pipeline.gfx import MeshPart, Vertex
        from asset_pipeline.texbank import GX_CLAMP, GX_REPEAT

        part = MeshPart(
            name="wet:mFM_grd_beachA_tex",
            vertices=[Vertex(0, 0, 0, 0, 0, 255, 255, 255, 255)],
            triangles=[(0, 0, 0)],
            texture_name="mFM_grd_beachA_tex",
            texture_png=b"wet",
            wrap_s=GX_REPEAT,
            wrap_t=GX_CLAMP,
            alpha_mode="BLEND",
            water_kind="beach_wet",
            beach_prim=(206, 189, 148, 255),
        )
        groups = _group_parts([part])
        self.assertEqual(_group_alpha_mode(groups[0]), "OPAQUE")


class BindAnimTests(unittest.TestCase):
    def test_furniture_bakes_own_closed_clip(self) -> None:
        self.assertEqual(
            select_bind_anim("int_sum_log_chest01", ["cKF_ba_r_int_sum_log_chest01"]),
            "cKF_ba_r_int_sum_log_chest01",
        )
        self.assertEqual(
            select_bind_anim("boy_1", ["cKF_ba_r_ply_1_walk1", "cKF_ba_r_ply_1_wait1"]),
            "cKF_ba_r_ply_1_wait1",
        )
        self.assertIsNone(select_bind_anim("tol_net_1", ["cKF_ba_r_tol_net_1_swing"]))
        self.assertIsNone(select_bind_anim("cat_1", []))


if __name__ == "__main__":
    unittest.main()
