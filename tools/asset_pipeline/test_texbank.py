"""Token helpers for unbound anime_N_txt segment resolution."""

from __future__ import annotations

import unittest

from asset_pipeline.texbank import (
    dummy_name_score,
    dummy_palette_score,
    gfx_part_tokens,
    is_image_symbol,
    season_of_prefix,
    symbol_tokens,
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
        self.assertTrue(is_image_symbol("obj_s_tree3_leaf_tex"))
        self.assertFalse(is_image_symbol("obj_s_shrine_pal"))
        self.assertFalse(is_image_symbol("obj_s_shrine_leaf_model"))


if __name__ == "__main__":
    unittest.main()
