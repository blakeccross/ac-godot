"""Layout, prefix ownership, and map-index helpers for the asset pipeline."""

from __future__ import annotations

import struct
import unittest

from asset_pipeline.ckf import (
    _sits_on_y,
    _vtx_sym_for_gfx,
    _mat_model_name,
    select_bind_anim,
    select_close_bind,
)
from asset_pipeline.convert import BUG_STATIC_NEEDLES, FISH_STATIC_NEEDLES, INTRO_KK_NPC_ANIMS, INTRO_NOOK_NPC_ANIMS, INTRO_ROVER_NPC_ANIMS, INTRO_SLEEP_NPC_ANIMS, WATER_STATIC_NEEDLES, _intro_kk_anims, _intro_nook_anims, _intro_rover_anims, _intro_sleep_npc_anims, _name_under_prefix, _owning_vtx_prefix, _static_jobs
from asset_pipeline.glb import _bake_wrap_group
from asset_pipeline.layout import (
    bti_output_path,
    output_folder_for_static,
    output_for_prefix,
    uses_shared_npc_anims,
)
from asset_pipeline.mapfile import MapSymbol, find_symbol, index_by_name
from asset_pipeline.texbank import (
    GX_CLAMP,
    GX_REPEAT,
    _kanban_bulletin_palette,
)


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

    def test_rcn_1_test_set_includes_nook_manpu_clips(self) -> None:
        names = set(INTRO_NOOK_NPC_ANIMS) | {"cKF_ba_r_npc_1_walk1"}
        nook = _intro_nook_anims(names)
        self.assertIn("cKF_ba_r_npc_1_smile1", nook)
        self.assertIn("cKF_ba_r_npc_1_hate1", nook)

    def test_end_1_test_set_includes_kk_opening_clips(self) -> None:
        names = set(INTRO_KK_NPC_ANIMS) | {"cKF_ba_r_npc_1_run1"}
        kk = _intro_kk_anims(names)
        self.assertEqual(kk, INTRO_KK_NPC_ANIMS)
        self.assertIn("cKF_ba_r_npc_1_wait1", kk)
        self.assertIn("cKF_ba_r_npc_1_4haku_e1", kk)
        self.assertIn("cKF_ba_r_npc_1_wait_e1", kk)
        ## Wait1 must be present so bind is upright (seated clips alone → ckf_basis sideways).
        self.assertEqual(select_bind_anim("end_1", kk), "cKF_ba_r_npc_1_wait1")

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
        self.assertEqual(output_for_prefix("rcn_1"), "characters/villagers/rcn_1.glb")
        self.assertEqual(output_for_prefix("rcc_1"), "characters/villagers/rcc_1.glb")
        self.assertEqual(output_for_prefix("rcs_1"), "characters/villagers/rcs_1.glb")
        self.assertEqual(output_for_prefix("rcd_1"), "characters/villagers/rcd_1.glb")
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

    def test_rom_museum1_job_includes_modelT_mado(self) -> None:
        ## Entrance stained glass is XLU `rom_museum1_modelT` (`*_mado*_tex`).
        symbols = [
            _sym("rom_museum1_v"),
            _sym("rom_museum1_model"),
            _sym("rom_museum1_modelT"),
        ]
        jobs = {item["asset_id"]: item for item in _static_jobs(symbols)}
        self.assertEqual(
            jobs["rom_museum1"]["gfx"],
            ["rom_museum1_model", "rom_museum1_modelT"],
        )

    def test_kanban_sign_uses_sign_model_display_list(self) -> None:
        symbols = [
            _sym("obj_s_kanban_v"),
            _sym("obj_w_kanban_v"),
            _sym("write_model"),
            _sym("obj_sign_s_model"),
            _sym("obj_sign_w_model"),
            _sym("obj_shop_kanban_v"),
            _sym("obj_shop_kanbanT_gfx_model"),
        ]
        jobs = {item["asset_id"]: item for item in _static_jobs(symbols)}
        self.assertEqual(jobs["obj_s_kanban"]["gfx"], ["write_model", "obj_sign_s_model"])
        self.assertEqual(jobs["obj_w_kanban"]["gfx"], ["write_model", "obj_sign_w_model"])
        self.assertEqual(jobs["obj_shop_kanban"]["gfx"], ["obj_shop_kanbanT_gfx_model"])

    def test_attention_dock_sign_uses_attention_display_list(self) -> None:
        symbols = [
            _sym("obj_s_attention_v"),
            _sym("obj_w_attention_v"),
            _sym("obj_s_attentionT_model"),
            _sym("obj_w_attentionT_model"),
        ]
        jobs = {item["asset_id"]: item for item in _static_jobs(symbols)}
        self.assertEqual(jobs["obj_s_attention"]["gfx"], ["obj_s_attentionT_model"])
        self.assertEqual(jobs["obj_w_attention"]["gfx"], ["obj_w_attentionT_model"])
        self.assertEqual(jobs["obj_s_attention"]["output"], "environment/obj_s_attention.glb")

    def test_kanban_bulletin_palette_remaps_paper_ink_tack(self) -> None:
        from asset_pipeline.texbank import encode_bulletin_paper_ci4

        base = bytes([0xFF, 0xFF] * 16)
        pal = _kanban_bulletin_palette(base)

        def rgb555(idx: int) -> tuple[int, int, int]:
            w = (pal[idx * 2] << 8) | pal[idx * 2 + 1]
            return (
                ((w >> 10) & 0x1F) * 255 // 31,
                ((w >> 5) & 0x1F) * 255 // 31,
                (w & 0x1F) * 255 // 31,
            )

        self.assertEqual(rgb555(5), (255, 255, 255))
        self.assertEqual(rgb555(7), (213, 32, 32))
        self.assertEqual(rgb555(8), (32, 32, 74))
        tex, paper_pal = encode_bulletin_paper_ci4()
        self.assertEqual(len(tex), 512)
        self.assertEqual(len(paper_pal), 32)
        ## Paper should be mostly white (index 5), with ink (8) and tack (7).
        idxs = []
        for b in tex:
            idxs.append(b >> 4)
            idxs.append(b & 0xF)
        self.assertGreater(idxs.count(5), 500)
        self.assertGreater(idxs.count(8), 10)
        self.assertGreater(idxs.count(7), 0)

    def test_explicit_entry_survives_unmatchable_gfx_name(self) -> None:
        # The bobber's display list is `tol_uki1_model`, which no prefix rule will pair
        # with `tol_uki_1_v`. The explicit TEST_STATIC row has to win over the inference,
        # or the asset is dropped before anyone looks at it.
        symbols = [_sym("tol_uki_1_v", 0x601B40, 384), _sym("tol_uki1_model", 0x601CC0, 136)]
        jobs = {item["asset_id"]: item for item in _static_jobs(symbols)}
        self.assertIn("tol_uki_1", jobs)
        self.assertEqual(jobs["tol_uki_1"]["gfx"], ["tol_uki1_model"])
        self.assertEqual(jobs["tol_uki_1"]["output"], "items/tol_uki_1.glb")

    def test_gre_counter_explicit_gfx_alias(self) -> None:
        ## Vtx/textures keep `gre_`; OPA/XLU Gfx drop it (`int_sum_counter01_on*`).
        symbols = [
            _sym("int_sum_gre_counter01_v", 0x1000, 1024),
            _sym("int_sum_counter01_on_model", 0x2000, 256),
            _sym("int_sum_counter01_onT_model", 0x2100, 256),
        ]
        jobs = {item["asset_id"]: item for item in _static_jobs(symbols)}
        self.assertIn("int_sum_gre_counter01", jobs)
        self.assertEqual(
            jobs["int_sum_gre_counter01"]["gfx"],
            ["int_sum_counter01_on_model", "int_sum_counter01_onT_model"],
        )
        self.assertEqual(jobs["int_sum_gre_counter01"]["output"], "furniture/int_sum_gre_counter01.glb")

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

    def test_clamp_uv_span_outside_unit_tile_is_fitted(self) -> None:
        """Train tunnel S lands at U=1..4 with GX_CLAMP — fit onto the brick sheet."""
        from io import BytesIO

        from PIL import Image

        buf = BytesIO()
        Image.new("RGBA", (8, 8), (40, 30, 30, 255)).save(buf, format="PNG")
        png = buf.getvalue()

        class _V:
            def __init__(self, u: float, v: float) -> None:
                self.u = u
                self.v = v

        class _Part:
            wrap_s = GX_CLAMP
            wrap_t = GX_REPEAT
            texture_png = png
            vertices = [_V(1.0, -1.0), _V(4.0, 1.0)]

        group = {
            "png": png,
            "name": "rom_train_tunnel_tex",
            "wrap_s": GX_CLAMP,
            "wrap_t": GX_REPEAT,
            "parts": [_Part()],
        }
        _bake_wrap_group(group)
        self.assertAlmostEqual(_Part.vertices[0].u, 0.0)
        self.assertAlmostEqual(_Part.vertices[1].u, 1.0)
        ## V still wrap-bakes across two tiles then normalizes.
        self.assertAlmostEqual(_Part.vertices[0].v, 0.0)
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

    def test_player_select_spot_bake_is_yellow_xlu(self) -> None:
        from io import BytesIO

        from PIL import Image

        from asset_pipeline.texbank import bake_player_select_shade_png, bake_player_select_spot_png

        src = Image.new("RGB", (2, 1), (0, 0, 0))
        src.putpixel((1, 0), (255, 255, 255))
        buf = BytesIO()
        src.save(buf, format="PNG")
        spot = Image.open(BytesIO(bake_player_select_spot_png(buf.getvalue()))).convert("RGBA")
        ## I=0 → env yellow; lod 150 → alpha 0.
        self.assertEqual(spot.getpixel((0, 0)), (255, 255, 130, 0))
        ## I=255 → prim white; alpha ≈ 150.
        self.assertEqual(spot.getpixel((1, 0)), (255, 255, 255, 150))
        shade = Image.open(BytesIO(bake_player_select_shade_png(buf.getvalue()))).convert("RGBA")
        self.assertEqual(shade.getpixel((0, 0)), (0, 0, 0, 0))
        self.assertEqual(shade.getpixel((1, 0)), (0, 0, 0, 255))


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

    def test_mixed_alpha_modes_split_into_separate_meshes(self) -> None:
        """MASK cutouts must not share a mesh with OPAQUE or Godot draws both translucent."""
        import json
        import struct
        import tempfile
        from io import BytesIO
        from pathlib import Path

        from PIL import Image

        from asset_pipeline.glb import write_glb
        from asset_pipeline.gfx import MeshPart, Vertex
        from asset_pipeline.texbank import GX_CLAMP

        def _png(rgb: tuple[int, int, int, int]) -> bytes:
            buf = BytesIO()
            Image.new("RGBA", (4, 4), rgb).save(buf, format="PNG")
            return buf.getvalue()

        verts = [
            Vertex(0, 0, 0, 0, 0, 255, 255, 255, 255),
            Vertex(1, 0, 0, 1, 0, 255, 255, 255, 255),
            Vertex(0, 1, 0, 0, 1, 255, 255, 255, 255),
        ]
        opa = MeshPart(
            name="tunnel:rom_train_tunnel_tex",
            vertices=list(verts),
            triangles=[(0, 1, 2)],
            texture_name="rom_train_tunnel_tex",
            texture_png=_png((40, 30, 30, 255)),
            wrap_s=GX_CLAMP,
            wrap_t=GX_CLAMP,
            alpha_mode="OPAQUE",
        )
        cut = MeshPart(
            name="tree:rom_train_bgtree_tex",
            vertices=list(verts),
            triangles=[(0, 1, 2)],
            texture_name="rom_train_bgtree_tex",
            texture_png=_png((0, 0, 0, 0)),
            wrap_s=GX_CLAMP,
            wrap_t=GX_CLAMP,
            alpha_mode="MASK",
        )
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "split.glb"
            write_glb(path, [opa, cut])
            raw = path.read_bytes()
            n = struct.unpack_from("<I", raw, 12)[0]
            gltf = json.loads(raw[20 : 20 + n])
        self.assertEqual(len(gltf["meshes"]), 2)
        modes = {
            gltf["materials"][p["material"]].get("alphaMode", "OPAQUE")
            for mesh in gltf["meshes"]
            for p in mesh["primitives"]
        }
        self.assertEqual(modes, {"OPAQUE", "MASK"})
        for mesh in gltf["meshes"]:
            mesh_modes = {
                gltf["materials"][p["material"]].get("alphaMode", "OPAQUE")
                for p in mesh["primitives"]
            }
            self.assertEqual(len(mesh_modes), 1, mesh["name"])
        self.assertEqual(len(gltf["nodes"][0]["children"]), 2)

    def test_train_window_i4_alpha_via_coverage(self) -> None:
        """XLU + opaque I4 promotes intensity to alpha without texture-name gates."""
        from io import BytesIO

        from PIL import Image

        from asset_pipeline.texbank import (
            COVERAGE_XLU,
            i4_png_as_alpha,
            intensity_format_opaque_alpha,
            resolve_alpha_mode,
        )

        buf = BytesIO()
        Image.new("RGBA", (4, 4), (80, 80, 80, 255)).save(buf, format="PNG")
        png = buf.getvalue()
        self.assertTrue(intensity_format_opaque_alpha(png))
        out = i4_png_as_alpha(png)
        self.assertFalse(intensity_format_opaque_alpha(out))
        self.assertEqual(resolve_alpha_mode(COVERAGE_XLU, "BLEND"), "BLEND")
        ## Missing SetRenderMode (shineglass): texel BLEND still wins via fallback.
        self.assertEqual(resolve_alpha_mode(None, "BLEND"), "BLEND")
        self.assertEqual(resolve_alpha_mode(None, "OPAQUE"), "OPAQUE")

    def test_othermode_packets_classify_coverage(self) -> None:
        from asset_pipeline.gfx import apply_othermode, coverage_from_othermode_l, is_rendermode_update

        w0 = 0xE200001C  ## F3DEX2 SetRenderMode (sft=3, len=29)
        self.assertTrue(is_rendermode_update(w0))
        self.assertEqual(coverage_from_othermode_l(apply_othermode(0, w0, 0xC8112078)), "opa")
        self.assertEqual(coverage_from_othermode_l(apply_othermode(0, w0, 0xC8113078)), "tex_edge")
        self.assertEqual(coverage_from_othermode_l(apply_othermode(0, w0, 0xC8104A50)), "xlu")


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

    def test_close_bind_prefers_close_suffix(self) -> None:
        self.assertEqual(
            select_close_bind(
                [
                    "cKF_ba_r_obj_train1_1",
                    "cKF_ba_r_obj_train1_1_close",
                    "cKF_ba_r_obj_train1_1_open",
                ]
            ),
            "cKF_ba_r_obj_train1_1_close",
        )
        self.assertIsNone(select_close_bind(["cKF_ba_r_obj_train1_1_open"]))


class _V:
    def __init__(self, x: float, y: float, z: float) -> None:
        self.x = x
        self.y = y
        self.z = z


class SitsOnYTests(unittest.TestCase):
    def test_clean_y_up_aabb(self) -> None:
        verts = [_V(x, y, z) for x in (-1.0, 1.0) for y in (0.0, 2.0) for z in (-1.0, 1.0)]
        self.assertTrue(_sits_on_y(verts))

    def test_y_up_with_outlier_hands(self) -> None:
        ## Clock hands / vanes dip below the floor; percentile or majority must pass.
        body: list[_V] = []
        for i in range(5):
            for j in range(5):
                for k in range(5):
                    body.append(_V(-1.0 + i * 0.5, j * 0.5, -1.0 + k * 0.5))
        outliers = [_V(0.0, -0.4, 0.0), _V(0.1, -0.5, 0.0)]
        self.assertTrue(_sits_on_y(body + outliers))

    def test_y_up_with_heavy_vane_outliers(self) -> None:
        ## Player tent: >5% of verts below the floor (p05 fails; ≥90% still pass).
        dense: list[_V] = []
        for i in range(10):
            for j in range(10):
                dense.append(_V(-1.0 + i * 0.2, j * 0.5, 0.0))
        vanes = [_V(0.0, -1.5, 0.0) for _ in range(8)]
        self.assertGreater(len(vanes) / (len(dense) + len(vanes)), 0.05)
        self.assertTrue(_sits_on_y(dense + vanes))

    def test_rejects_x_chain(self) -> None:
        ## Character / train bind cloud: long along +X, modest Y/Z.
        verts = [_V(x, y, z) for x in (0.0, 4.0) for y in (-0.2, 0.4) for z in (-0.3, 0.3)]
        self.assertFalse(_sits_on_y(verts))

    def test_rejects_deep_mass_below_floor(self) -> None:
        verts = [_V(x, y, z) for x in (-1.0, 1.0) for y in (-1.0, 1.0) for z in (-1.0, 1.0)]
        self.assertFalse(_sits_on_y(verts))

    def test_y_up_structure_name_list_removed(self) -> None:
        import asset_pipeline.ckf as ckf

        self.assertFalse(hasattr(ckf, "_is_y_up_structure"))


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


class VertexShadeTests(unittest.TestCase):
    def test_geometry_mode_without_lighting_exports_colors(self) -> None:
        import tempfile
        from pathlib import Path

        from asset_pipeline.gfx import (
            G_ENDDL,
            G_GEOMETRYMODE,
            G_LIGHTING,
            G_TRI1,
            G_VTX,
            parse_gfx,
            parse_vtx_blob,
        )
        from asset_pipeline.glb import _material, write_glb

        ## Three verts: top black, bottom white — ceiling AO pattern.
        vtx = b""
        for y, rgb in ((0, (255, 255, 255)), (100, (128, 128, 128)), (200, (0, 0, 0))):
            vtx += struct.pack(">hhhHhhBBBB", 0, y, 0, 0, 0, 0, *rgb, 255)
        verts = parse_vtx_blob(vtx, scale=0.001)
        ## LoadGeometryMode without G_LIGHTING (museum / myhome walls).
        mode = 0x00210405  # ZBUFFER|SHADE|CULL_BACK|FOG|SHADING_SMOOTH
        self.assertFalse(mode & G_LIGHTING)
        dl = b""
        dl += struct.pack(">II", (G_GEOMETRYMODE << 24) | 0x000000, mode)
        ## G_VTX: n=3 at v0=0, w1 = vertex DRAM (treated as cursor when no base).
        dl += struct.pack(">II", (G_VTX << 24) | (3 << 12) | (3 << 1), 0)
        ## One triangle using cache indices 0,1,2 (bytes are ×2 in classic TRI1).
        dl += struct.pack(">II", (G_TRI1 << 24) | (0 << 16) | (2 << 8) | 4, 0)
        dl += struct.pack(">II", G_ENDDL << 24, 0)
        parts = parse_gfx("shade_test_model", dl, verts)
        self.assertEqual(len(parts), 1)
        self.assertFalse(parts[0].uses_lighting)
        tops = [v for v in parts[0].vertices if abs(v.y - 0.2) < 1e-6]
        bots = [v for v in parts[0].vertices if abs(v.y) < 1e-6]
        self.assertTrue(tops)
        self.assertTrue(bots)
        self.assertAlmostEqual(tops[0].r + tops[0].g + tops[0].b, 0.0)
        self.assertGreater(bots[0].r + bots[0].g + bots[0].b, 2.9)
        mat = _material("wall", None, vertex_shade=True)
        self.assertTrue(mat["extras"]["vertex_shade"])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "shade.glb"
            write_glb(path, parts)
            data = path.read_bytes()
            ## COLOR_0 accessor present in JSON chunk.
            self.assertIn(b"COLOR_0", data)

    def test_vertex_shade_exports_opaque_alpha(self) -> None:
        ## XLU mado verts often carry cn[].a ≈ 63; Godot would scissor/BLEND them away.
        import struct
        import tempfile
        from pathlib import Path

        from asset_pipeline.gfx import (
            G_ENDDL,
            G_GEOMETRYMODE,
            G_LIGHTING,
            G_TRI1,
            G_VTX,
            parse_gfx,
            parse_vtx_blob,
        )
        from asset_pipeline.glb import write_glb

        vtx = b""
        for y, rgb in ((0, (255, 255, 255)), (100, (128, 128, 128)), (200, (0, 0, 0))):
            vtx += struct.pack(">hhhHhhBBBB", 0, y, 0, 0, 0, 0, *rgb, 63)
        verts = parse_vtx_blob(vtx, scale=0.001)
        mode = 0x00210405
        self.assertFalse(mode & G_LIGHTING)
        dl = b""
        dl += struct.pack(">II", (G_GEOMETRYMODE << 24) | 0x000000, mode)
        dl += struct.pack(">II", (G_VTX << 24) | (3 << 12) | (3 << 1), 0)
        dl += struct.pack(">II", (G_TRI1 << 24) | (0 << 16) | (2 << 8) | 4, 0)
        dl += struct.pack(">II", G_ENDDL << 24, 0)
        parts = parse_gfx("mado_shade_model", dl, verts)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "mado.glb"
            write_glb(path, parts)
            raw = path.read_bytes()
            n = struct.unpack_from("<I", raw, 12)[0]
            import json

            j = json.loads(raw[20 : 20 + n])
            off = 12
            while off < len(raw):
                ln, ty = struct.unpack_from("<I4s", raw, off)
                off += 8
                if ty == b"BIN\x00":
                    blob = raw[off : off + ln]
                    break
                off += ln
            prim = j["meshes"][0]["primitives"][0]
            ai = prim["attributes"]["COLOR_0"]
            a = j["accessors"][ai]
            view = j["bufferViews"][a["bufferView"]]
            start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
            for i in range(a["count"]):
                _r, _g, _b, alpha = struct.unpack_from("<4f", blob, start + i * 16)
                self.assertAlmostEqual(alpha, 1.0)

    def test_default_lighting_keeps_normals_only(self) -> None:
        from asset_pipeline.gfx import G_ENDDL, G_TRI1, G_VTX, parse_gfx, parse_vtx_blob

        vtx = struct.pack(">hhhHhhBBBB", 0, 0, 0, 0, 0, 0, 0, 127, 0, 255)
        vtx += struct.pack(">hhhHhhBBBB", 10, 0, 0, 0, 0, 0, 0, 127, 0, 255)
        vtx += struct.pack(">hhhHhhBBBB", 0, 10, 0, 0, 0, 0, 0, 127, 0, 255)
        verts = parse_vtx_blob(vtx, scale=0.001)
        dl = b""
        dl += struct.pack(">II", (G_VTX << 24) | (3 << 12) | (3 << 1), 0)
        dl += struct.pack(">II", (G_TRI1 << 24) | (0 << 16) | (2 << 8) | 4, 0)
        dl += struct.pack(">II", G_ENDDL << 24, 0)
        parts = parse_gfx("lit_test_model", dl, verts)
        self.assertEqual(len(parts), 1)
        self.assertTrue(parts[0].uses_lighting)


if __name__ == "__main__":
    unittest.main()
