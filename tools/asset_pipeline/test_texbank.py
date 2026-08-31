"""Token helpers for unbound anime_N_txt segment resolution."""

from __future__ import annotations

import unittest

from asset_pipeline.texbank import (
    dummy_name_score,
    dummy_palette_score,
    gfx_part_tokens,
    is_dolphin_loadtlut,
    is_image_symbol,
    parse_loadtlut,
    parse_settile,
    parse_settilesize,
    parse_settimg,
    season_of_prefix,
    symbol_tokens,
    tmem_palette_slot,
)


class SymbolTokenTests(unittest.TestCase):
    def test_drops_season_and_role_suffixes(self) -> None:
        self.assertEqual(symbol_tokens("obj_s_shrine_leaf_model"), {"shrine", "leaf"})
        self.assertEqual(symbol_tokens("obj_s_tree3_leaf_tex"), {"tree", "leaf"})
        self.assertEqual(symbol_tokens("obj_myhome_mark_tex_txt"), {"myhome", "mark"})
        self.assertEqual(symbol_tokens("obj_s_frag_fragA_model"), {"frag"})

    def test_gfx_part_is_suffix_after_prefix(self) -> None:
        self.assertEqual(gfx_part_tokens("obj_s_shrine", "obj_s_shrine_leaf_model"), {"leaf"})
        self.assertEqual(gfx_part_tokens("obj_s_myhome1", "obj_s_myhome1_mark_model"), {"mark"})
        self.assertEqual(gfx_part_tokens("obj_s_frag", "obj_s_frag_fragA_model"), {"frag"})

    def test_leaf_prefers_tree_leaf_over_object_tile(self) -> None:
        part = {"leaf"}
        prefix = {"shrine"}
        leaf = dummy_name_score("obj_s_tree3_leaf_tex", part, prefix)
        tile = dummy_name_score("obj_s_shrine_t1_tex_txt", part, prefix)
        self.assertGreater(leaf, tile)
        self.assertEqual(tile, 0)

    def test_mark_matches_shared_myhome_tex(self) -> None:
        part = {"mark"}
        prefix = {"myhome"}
        self.assertGreaterEqual(dummy_name_score("obj_myhome_mark_tex_txt", part, prefix), 10)
        self.assertEqual(dummy_name_score("obj_s_myhome1_t1_tex_txt", part, prefix), 0)

    def test_palette_requires_same_object_family(self) -> None:
        # Shop "front" must not steal a goldfish furniture pal.
        self.assertEqual(
            dummy_palette_score("int_sum_demekin_front_pic_ci4_pal", {"front"}, {"shop"}),
            0,
        )
        self.assertGreaterEqual(
            dummy_palette_score("obj_myhome_mark_pal", {"mark"}, {"myhome"}),
            10,
        )
        # Inventory leaf pal is not the shrine's.
        self.assertEqual(
            dummy_palette_score("inv_mwin_leaf_pal", {"leaf"}, {"shrine"}),
            0,
        )

    def test_season_and_image_filter(self) -> None:
        self.assertEqual(season_of_prefix("obj_w_shrine"), "w")
        self.assertEqual(season_of_prefix("grd_w_f_1"), "w")
        self.assertEqual(season_of_prefix("grd_s_r1_1"), "s")
        self.assertEqual(season_of_prefix("obj_f_tree5"), "f")
        self.assertTrue(is_image_symbol("obj_s_tree3_leaf_tex"))
        self.assertFalse(is_image_symbol("obj_s_shrine_pal"))
        self.assertFalse(is_image_symbol("obj_s_shrine_leaf_model"))


class ClassicGbiTests(unittest.TestCase):
    def test_classic_settimg_has_no_pixel_height(self) -> None:
        ## gsDPSetTextureImage(CI, 4b, width=1, timg) — dimensions come from SETTILESIZE.
        w0 = (0xFD << 24) | (2 << 21) | (0 << 19) | 0  # width-1 = 0
        _fmt, _siz, width, height, _addr = parse_settimg(w0, 0x80400000)
        self.assertEqual(height, 0)
        self.assertEqual(width, 1)

    def test_settilesize_64x64(self) -> None:
        ## uls=ult=0, lrs=lrt=(64-1)<<2 = 252 → width/height 64.
        w0 = (0 << 12) | 0
        w1 = (252 << 12) | 252
        self.assertEqual(parse_settilesize(w0, w1), (64, 64))

    def test_classic_loadtlut_uses_sentinel_slot(self) -> None:
        ## gsDPLoadTLUTCmd(G_TX_LOADTILE, 15) → w0=0xF0000000, w1=0x0703C000.
        self.assertFalse(is_dolphin_loadtlut(0xF0000000))
        slot, count, addr = parse_loadtlut(0xF0000000, 0x0703C000)
        self.assertEqual(slot, -1)
        self.assertEqual(count, 16)
        self.assertEqual(addr, 0)

    def test_dolphin_loadtlut_keeps_packed_slot(self) -> None:
        ## G_TLUT_DOLPHIN in bits 22–23, slot 15, count 16, dram in w1.
        w0 = 0xF0000000 | (2 << 22) | (15 << 16) | 16
        self.assertTrue(is_dolphin_loadtlut(w0))
        slot, count, addr = parse_loadtlut(w0, 0x80123456)
        self.assertEqual(slot, 15)
        self.assertEqual(count, 16)
        self.assertEqual(addr, 0x80123456)

    def test_settile_tmem_palette_slot(self) -> None:
        ## gsDPSetTile(..., tmem=256+15*16=496, ...)
        tmem = 256 + 15 * 16
        w0 = (0xF5 << 24) | tmem
        w1 = 15 << 20
        _fmt, _siz, pal_slot, _ws, _wt, parsed_tmem = parse_settile(w0, w1)
        self.assertEqual(parsed_tmem, tmem)
        self.assertEqual(pal_slot, 15)
        self.assertEqual(tmem_palette_slot(tmem), 15)


if __name__ == "__main__":
    unittest.main()
