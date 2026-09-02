"""Layout, prefix ownership, and map-index helpers for the asset pipeline."""

from __future__ import annotations

import struct
import unittest

from asset_pipeline.ckf import _mat_model_name, _vtx_sym_for_gfx, select_bind_anim
from asset_pipeline.convert import BUG_STATIC_NEEDLES, FISH_STATIC_NEEDLES, INTRO_ROVER_NPC_ANIMS, INTRO_SLEEP_NPC_ANIMS, WATER_STATIC_NEEDLES, _intro_rover_anims, _intro_sleep_npc_anims, _name_under_prefix, _owning_vtx_prefix, _static_jobs
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
    def test_xct_1_test_set_includes_intro_rover_clips(self) -> None:
        names = set(INTRO_ROVER_NPC_ANIMS) | {"cKF_ba_r_npc_1_run1"}
        intro = _intro_rover_anims(names)
        self.assertEqual(intro, INTRO_ROVER_NPC_ANIMS)
        self.assertIn("cKF_ba_r_npc_1_sitdown_d1", intro)

    def test_kab_1_test_set_includes_sleep_clips(self) -> None:
        names = set(INTRO_SLEEP_NPC_ANIMS) | {"cKF_ba_r_npc_1_wait1"}
        sleep = _intro_sleep_npc_anims(names)
        self.assertIn("cKF_ba_r_npc_1_wait_nemu1", sleep)
        self.assertIn("cKF_ba_r_npc_1_kokkuri_d1", sleep)

    def test_face_frame_offsets_cover_eyes_then_mouths(self) -> None:
        from asset_pipeline.faces import MOUTH_BASE, frame_offsets

        frames = frame_offsets()
        self.assertEqual(len(frames), 14)
        self.assertEqual(frames[0], ("eye0", 0x000))
        self.assertEqual(frames[7], ("eye7", 0x700))
        # `face_*.bin` face 0 puts the six mouths straight after the eight eyes.
        self.assertEqual(frames[8], ("mouth0", MOUTH_BASE))
        self.assertEqual(frames[13], ("mouth5", MOUTH_BASE + 5 * 0x100))
        offsets = [off for _name, off in frames]
        self.assertEqual(len(set(offsets)), len(offsets))

    def test_discover_villager_prefixes_picks_lowest_variant(self) -> None:
        from asset_pipeline.faces import discover_villager_prefixes, species_code_from_prefix
        from pathlib import Path
        import tempfile

        self.assertEqual(species_code_from_prefix("cat_12"), "cat")
        with tempfile.TemporaryDirectory() as tmp:
            rel = Path(tmp)
            for prefix in ("cat_2", "cat_1", "xct_1"):
                (rel / f"{prefix}_eye1_TA_tex_txt.png").write_bytes(b"png")
            found = discover_villager_prefixes(rel)
            self.assertEqual(found["cat"], "cat_1")
            self.assertEqual(found["xct"], "xct_1")

    def test_species_paths(self) -> None:
        self.assertTrue(uses_shared_npc_anims("cat_1"))
        self.assertTrue(uses_shared_npc_anims("xct_1"))
        self.assertTrue(uses_shared_npc_anims("kab_1"))
        self.assertFalse(uses_shared_npc_anims("boy_1"))
        self.assertEqual(output_for_prefix("cat_1"), "characters/villagers/cat_1.glb")
        self.assertEqual(output_for_prefix("xct_1"), "characters/villagers/xct_1.glb")
        self.assertEqual(output_for_prefix("kab_1"), "characters/villagers/kab_1.glb")
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

    def test_kanban_sign_uses_sign_model_display_list(self) -> None:
        symbols = [
            _sym("obj_s_kanban_v"),
            _sym("obj_w_kanban_v"),
            _sym("obj_sign_s_model"),
            _sym("obj_sign_w_model"),
            _sym("obj_shop_kanban_v"),
            _sym("obj_shop_kanbanT_gfx_model"),
        ]
        jobs = {item["asset_id"]: item for item in _static_jobs(symbols)}
        self.assertEqual(jobs["obj_s_kanban"]["gfx"], ["obj_sign_s_model"])
        self.assertEqual(jobs["obj_w_kanban"]["gfx"], ["obj_sign_w_model"])
        self.assertEqual(jobs["obj_shop_kanban"]["gfx"], ["obj_shop_kanbanT_gfx_model"])

    def test_explicit_entry_survives_unmatchable_gfx_name(self) -> None:
        # The bobber's display list is `tol_uki1_model`, which no prefix rule will pair
        # with `tol_uki_1_v`. The explicit TEST_STATIC row has to win over the inference,
        # or the asset is dropped before anyone looks at it.
        symbols = [_sym("tol_uki_1_v", 0x601B40, 384), _sym("tol_uki1_model", 0x601CC0, 136)]
        jobs = {item["asset_id"]: item for item in _static_jobs(symbols)}
        self.assertIn("tol_uki_1", jobs)
        self.assertEqual(jobs["tol_uki_1"]["gfx"], ["tol_uki1_model"])
        self.assertEqual(jobs["tol_uki_1"]["output"], "items/tol_uki_1.glb")

    def test_duplicate_vtx_name_yields_one_job(self) -> None:
        # `dataobject.obj` ships `tol_uki_1_v` twice (inventory icon and in-world model).
        symbols = [
            _sym("tol_uki_1_v", 0x4441F0, 384),
            _sym("inv_uki_model", 0x444370, 288),
            _sym("tol_uki_1_v", 0x601B40, 384),
            _sym("tol_uki1_model", 0x601CC0, 136),
        ]
        jobs = [item for item in _static_jobs(symbols) if item["asset_id"] == "tol_uki_1"]
        self.assertEqual(len(jobs), 1)

    def test_water_needles_skip_rail_and_museum(self) -> None:
        self.assertTrue(any(n in "grd_s_r1_1" for n in WATER_STATIC_NEEDLES))
        self.assertTrue(any(n in "grd_s_m_1" for n in WATER_STATIC_NEEDLES))
        self.assertTrue(any(n in "grd_s_e2_o_1" for n in WATER_STATIC_NEEDLES))
        self.assertTrue(any(n in "grd_s_e3_m_1" for n in WATER_STATIC_NEEDLES))
        self.assertFalse(any(n in "grd_s_rail_1" for n in WATER_STATIC_NEEDLES))
        self.assertFalse(any(n in "grd_s_mh_1" for n in WATER_STATIC_NEEDLES))

    def test_fish_needles_cover_every_species_and_only_the_a_pose(self) -> None:
        ## Two poses per `aGYO_TYPE_*` up to `aGYO_TYPE_NUM`. `dl_c` is unreachable, because
        ## `aGYO_actor_draw_fish` halves `aGYO_anime_frame`'s 0/1/2 into just `a` and `b`.
        self.assertEqual(len(FISH_STATIC_NEEDLES), 80)
        for asset_id in ("act_f01_funa_a", "act_f01_funa_b", "act_f34_piraluku_a"):
            self.assertTrue(any(n in asset_id for n in FISH_STATIC_NEEDLES), asset_id)
        self.assertFalse(any(n in "act_f01_funa_c" for n in FISH_STATIC_NEEDLES))

    def test_ef_s_cedar_job_uses_modelT_not_numbered_shake(self) -> None:
        symbols = [
            _sym("ef_s_cedar_v"),
            _sym("ef_s_cedar_modelT"),
            _sym("ef_s_cedar3_shake_model"),
            _sym("ef_s_cedar3_cutL_leaf_model"),
        ]
        jobs = {item["asset_id"]: item for item in _static_jobs(symbols)}
        self.assertEqual(jobs["ef_s_cedar"]["gfx"], ["ef_s_cedar_modelT"])

    def test_static_jobs_skip_overlay_vtx_not_in_dataobject(self) -> None:
        symbols = [
            MapSymbol(0x51080, 160, 8, "tol_sponge_1_v", "m_player.o"),
            MapSymbol(0x5370, 128, 8, "tol_sponge_1_model", "dataobject.obj"),
            MapSymbol(0x1000, 64, 8, "mbg_v", "ac_mbg.o"),
        ]
        jobs = {item["asset_id"] for item in _static_jobs(symbols)}
        self.assertNotIn("tol_sponge_1", jobs)
        self.assertNotIn("mbg", jobs)

    def test_fish_gfx_names_come_from_the_display_list_table(self) -> None:
        ## `aGYO_displayList` is not regular: the coelacanth's `b` pose display list has no
        ## pose letter, though its vertex array does. Appending `_bT_model` would KeyError.
        from asset_pipeline.test_set import TEST_STATIC

        kaseki = {i["asset_id"]: i for i in TEST_STATIC if "kaseki" in i["asset_id"]}
        self.assertEqual(kaseki["act_f32_kaseki_b"]["gfx"], ["act_f32_kasekiT_model"])
        self.assertEqual(kaseki["act_f32_kaseki_b"]["vtx"], "act_f32_kaseki_b_v")
        self.assertEqual(kaseki["act_f32_kaseki_a"]["gfx"], ["act_f32_kaseki_aT_model"])

    def test_bug_gfx_names_use_shared_vtx_and_numbered_display_lists(self) -> None:
        from asset_pipeline.test_set import TEST_STATIC

        bugs = {i["asset_id"]: i for i in TEST_STATIC if i["asset_id"].startswith("act_m_")}
        self.assertEqual(len(BUG_STATIC_NEEDLES), 80)
        self.assertEqual(bugs["act_m_hirata_a"]["vtx"], "act_m_hirata_v")
        self.assertEqual(bugs["act_m_hirata_a"]["gfx"], ["act_m_hirata1T_model"])
        self.assertEqual(bugs["act_m_hirata_b"]["vtx"], "act_m_hirata_v")
        self.assertEqual(bugs["act_m_hirata_b"]["gfx"], ["act_m_hirata2T_model"])
        ## `aINS_actor_draw` submits both DL slots each pose (`pose<<1` and +1).
        self.assertEqual(
            bugs["act_m_minmin_a"]["gfx"],
            ["act_m_minmin1_1T_model", "act_m_minmin1_2T_model"],
        )
        self.assertEqual(
            bugs["act_m_minmin_b"]["gfx"],
            ["act_m_minmin1_1T_model", "act_m_minmin2_2T_model"],
        )
        self.assertEqual(bugs["act_m_genji_a"]["vtx"], "act_m_genji2_v")
        self.assertEqual(
            bugs["act_m_genji_a"]["gfx"],
            ["act_m_genji2_a_model", "act_m_genji2_b_model"],
        )
        self.assertEqual(
            bugs["act_m_genji_b"]["gfx"],
            ["act_m_genji2_c_model", "act_m_genji2_d_model"],
        )

    def test_ocean_material_carries_tile1_and_shore_clamp(self) -> None:
        ## Shore acres draw wave1+wave2 (CLAMP T); open water draws wave1+wave3 (REPEAT).
        ## The runtime shader picks its T wrap off `wave2_clamp_t`.
        from asset_pipeline.glb import _material
        from asset_pipeline.texbank import GX_CLAMP, GX_REPEAT

        shore = _material(
            "ocean_mFM_grd_wave1_tex",
            0,
            water_kind="ocean",
            layer1_texture_index=1,
            layer1_wrap_t=GX_CLAMP,
        )
        self.assertEqual(shore["extras"]["water_kind"], "ocean")
        self.assertTrue(shore["extras"]["wave2_clamp_t"])
        self.assertEqual(shore["occlusionTexture"]["index"], 1)

        open_sea = _material(
            "ocean_mFM_grd_wave1_tex",
            0,
            water_kind="ocean",
            layer1_texture_index=1,
            layer1_wrap_t=GX_REPEAT,
        )
        self.assertFalse(open_sea["extras"]["wave2_clamp_t"])

    def test_waterfall_material_carries_layer_and_wrap(self) -> None:
        from asset_pipeline.glb import _material
        from asset_pipeline.texbank import GX_CLAMP, GX_MIRROR, GX_REPEAT

        bt = _material(
            "waterfall_obj_fallCA1_tex",
            0,
            water_kind="waterfall",
            waterfall_layer="bt",
            wrap_s=GX_MIRROR,
            wrap_t=GX_REPEAT,
            layer1_texture_index=1,
            layer1_wrap_s=GX_MIRROR,
            layer1_wrap_t=GX_REPEAT,
        )
        self.assertEqual(bt["extras"]["water_kind"], "waterfall")
        self.assertEqual(bt["extras"]["waterfall_layer"], "bt")
        self.assertTrue(bt["extras"]["tile0_mirror_s"])
        self.assertFalse(bt["extras"]["tile0_clamp_v"])

        at = _material(
            "waterfall_obj_fallA2_tex",
            0,
            water_kind="waterfall",
            waterfall_layer="at",
            wrap_s=GX_REPEAT,
            wrap_t=GX_CLAMP,
            layer1_texture_index=1,
            layer1_wrap_s=GX_REPEAT,
            layer1_wrap_t=GX_REPEAT,
        )
        self.assertTrue(at["extras"]["tile0_clamp_v"])


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

    def test_duplicate_vtx_resolves_via_display_list(self) -> None:
        # Two `tol_uki_1_v` copies; only the second is the one `tol_uki1_model` draws.
        # By-name lookup returns the first, which decodes zero triangles.
        inventory = _sym("tol_uki_1_v", 0x4441F0, 384)
        in_world = _sym("tol_uki_1_v", 0x601B40, 384)
        model = _sym("tol_uki1_model", 0x601CC0, 16)
        symbols = [inventory, _sym("inv_uki_model", 0x444370, 288), in_world, model]
        by_name = index_by_name(symbols)
        self.assertEqual(find_symbol(symbols, "tol_uki_1_v", by_name).address, inventory.address)

        class _Rel:
            def slice_at(self, addr: int, size: int) -> bytes:
                assert addr == model.address
                # G_VTX (0x01) pointing at the in-world copy, then G_ENDDL.
                return struct.pack(">IIII", 0x01018030, in_world.address, 0xDF000000, 0)

        chosen = _vtx_sym_for_gfx(_Rel(), symbols, by_name, "tol_uki_1_v", ["tol_uki1_model"])
        self.assertEqual(chosen.address, in_world.address)


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
        from asset_pipeline.gfx import (
            beach_wet_kind,
            is_ocean_bed_part,
            waterfall_layer_from_part,
            waterfall_surface_kind,
            water_surface_kind,
        )

        self.assertEqual(water_surface_kind("mFM_grd_water1_tex", "mFM_grd_water2_tex"), "river")
        self.assertEqual(water_surface_kind("mFM_grd_wave1_tex", "mFM_grd_wave2_tex"), "ocean")
        self.assertEqual(water_surface_kind("mFM_grd_sprashC_tex", "mFM_grd_sprashA_tex"), "splash")
        self.assertEqual(water_surface_kind("obj_stump5T_gfx_model"), "")
        self.assertEqual(
            water_surface_kind(
                "obj_s_shrine_t3_tex_txt",
                "obj_s_shrine_water_model",
                "obj_s_shrine_trunk_model",
            ),
            "",
        )
        self.assertEqual(
            water_surface_kind("obj_s_shrine_t4_tex_txt", "", "obj_s_shrine_water_model"),
            "river",
        )
        self.assertEqual(
            waterfall_surface_kind("obj_fallA2_tex_rgb_i4", "obj_fallC3_tex_rgb_i4"),
            "waterfall",
        )
        self.assertEqual(waterfall_surface_kind("obj_fallCA1_tex_rgb_ia8", "obj_fallCA1_tex_rgb_ia8"), "waterfall")
        self.assertEqual(waterfall_surface_kind("mFM_grd_water1_tex", "mFM_grd_water2_tex"), "")
        self.assertEqual(waterfall_layer_from_part("obj_fallS_grpBT_model"), "bt")
        self.assertEqual(waterfall_layer_from_part("obj_fallSE_grpCT_model"), "ct")
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

    def test_ia4_alpha_is_high_nibble(self) -> None:
        ## GX IA4 is AAAAIIII. Reading it as IIIIAAAA made the wave maps bright and
        ## near-transparent instead of dark and half-opaque, so the XLU ocean washed
        ## out to thin white cracks over the bed instead of tinting it blue.
        from asset_pipeline.bti import IA4, decode_gx_image

        img = decode_gx_image(bytes([0xF0, 0x0F] + [0x00] * 30), 8, 4, IA4)
        self.assertEqual(img.getpixel((0, 0)), (0, 0, 0, 255))
        self.assertEqual(img.getpixel((1, 0)), (255, 255, 255, 0))

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
        self.assertEqual(
            select_bind_anim(
                "kab_1",
                [
                    "cKF_ba_r_npc_1_wait_nemu1",
                    "cKF_ba_r_npc_1_kokkuri_d1",
                    "cKF_ba_r_npc_1_kokkuri_d2",
                ],
            ),
            "cKF_ba_r_npc_1_wait_nemu1",
        )
        self.assertEqual(
            select_bind_anim(
                "kab_1",
                [
                    "cKF_ba_r_npc_1_wait1",
                    "cKF_ba_r_npc_1_wait_nemu1",
                ],
            ),
            "cKF_ba_r_npc_1_wait_nemu1",
        )


class SeasonRoleTests(unittest.TestCase):
    def test_field_and_tree_role_needles(self) -> None:
        from asset_pipeline.seasons import FIELD_ROLE_NEEDLES, TREE_ROLE_NEEDLES, _role_for_name

        self.assertEqual(_role_for_name("grass_tex_dummy", FIELD_ROLE_NEEDLES), "grass")
        self.assertEqual(_role_for_name("earth_pal_dummy", FIELD_ROLE_NEEDLES), "earth")
        self.assertEqual(_role_for_name("bush_a_tex", FIELD_ROLE_NEEDLES), "bush_a")
        self.assertEqual(_role_for_name("bush_a_tex_dummy", FIELD_ROLE_NEEDLES), "bush_a")
        self.assertEqual(_role_for_name("bush_b_tex_dummy", FIELD_ROLE_NEEDLES), "bush_b")
        self.assertEqual(_role_for_name("earth_tex_dummy", FIELD_ROLE_NEEDLES), "earth")
        self.assertEqual(_role_for_name("sand_tex_dummy", FIELD_ROLE_NEEDLES), "sand")
        self.assertEqual(_role_for_name("beach1_tex_dummy2", FIELD_ROLE_NEEDLES), "beach_wet")
        self.assertEqual(_role_for_name("river_tex_dummy", FIELD_ROLE_NEEDLES), "river_edge")
        self.assertEqual(_role_for_name("river_mFM_grd_water1_tex", FIELD_ROLE_NEEDLES), "")
        self.assertEqual(_role_for_name("obj_s_tree_leaf_tex", TREE_ROLE_NEEDLES), "tree_leaf")
        self.assertEqual(_role_for_name("obj_w_tree_trunk_tex", TREE_ROLE_NEEDLES), "tree_trunk")
        self.assertEqual(_role_for_name("grd_water1_tex", FIELD_ROLE_NEEDLES), "")

    def test_glb_material_field_role_extras(self) -> None:
        from asset_pipeline.glb import _field_role_for_material_name, _material

        self.assertEqual(_field_role_for_material_name("grass_tex_dummy"), "grass")
        self.assertEqual(_field_role_for_material_name("bush_a_tex_dummy"), "bush_a")
        self.assertEqual(_field_role_for_material_name("river_tex_dummy"), "river_edge")
        self.assertEqual(_field_role_for_material_name("river_mFM_grd_water1_tex", "river"), "")
        mat = _material("grass_tex_dummy", None)
        self.assertEqual(mat.get("extras", {}).get("field_role"), "grass")

    def test_grass_pattern_export_count(self) -> None:
        from asset_pipeline.seasons import GRASS_PATTERN_COUNT

        self.assertEqual(GRASS_PATTERN_COUNT, 3)

    def test_grass_pattern_symbol_order(self) -> None:
        from asset_pipeline.seasons import _GRASS_TEX_SYMBOLS

        self.assertIn("mFM_grd_s_grass_3_tex", _GRASS_TEX_SYMBOLS["s"][1])
        self.assertIn("mFM_grd_s_grass_2_tex", _GRASS_TEX_SYMBOLS["s"][2])


if __name__ == "__main__":
    unittest.main()
