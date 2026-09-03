"""Token helpers for unbound anime_N_txt segment resolution."""

from __future__ import annotations

import unittest

from asset_pipeline.texbank import (
    dummy_name_score,
    dummy_palette_score,
    gfx_part_tokens,
    house_clock_alpha_mode,
    is_dolphin_loadtlut,
    is_house_clock_texture,
    is_image_symbol,
    is_indoor_mado_texture,
    is_museum_clock_texture,
    is_museum_plate_texture,
    museum_art_house_twin,
    museum_dummy_wood_twin,
    museum_gaku_house_palette,
    parse_loadtlut,
    parse_settile,
    parse_settilesize,
    parse_settimg,
    revive_stained_glass_alpha,
    season_of_prefix,
    skips_achd_texture,
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

    def test_museum_art_house_twin_maps_mona_lisa(self) -> None:
        twin = museum_art_house_twin("obj_art01_art_tex")
        self.assertEqual(twin, ("int_sum_art01_monariza_tex", "int_sum_art01_pal"))
        self.assertIsNone(museum_art_house_twin("obj_art01_gaku_tex"))

    def test_museum_gaku_uses_house_wood_palette(self) -> None:
        self.assertEqual(museum_gaku_house_palette("obj_art01_gaku_tex"), "int_sum_art01_pal")
        self.assertEqual(museum_gaku_house_palette("obj_art01_name_tex"), "int_sum_art01_pal")
        self.assertIsNone(museum_gaku_house_palette("obj_art01_art_tex"))

    def test_museum_ike_plates_use_etc_palette(self) -> None:
        ## ang/sya/fel: name+gaku share `*_etc_pal`, not the canvas art pal.
        self.assertEqual(museum_gaku_house_palette("obj_art_sya_name_tex"), "obj_art_sya_etc_pal")
        self.assertEqual(museum_gaku_house_palette("obj_art_sya_gaku_tex"), "obj_art_sya_etc_pal")
        self.assertEqual(museum_gaku_house_palette("obj_art_ang_name_tex"), "obj_art_ang_etc_pal")

    def test_museum_plate_textures_skip_achd(self) -> None:
        self.assertTrue(is_museum_plate_texture("obj_art01_name_tex"))
        self.assertTrue(is_museum_plate_texture("obj_art_sya_gaku_tex"))
        self.assertFalse(is_museum_plate_texture("obj_art_sya_art_tex"))
        self.assertFalse(is_museum_plate_texture("obj_art01_art_tex"))
        ## Empty frames are not "plates" — they need wood ACHD / dummy03 twin.
        self.assertFalse(is_museum_plate_texture("obj_art_dummy01_name_tex"))
        self.assertFalse(is_museum_plate_texture("obj_art_dummy01_tex"))

    def test_mado_and_clock_skip_achd(self) -> None:
        self.assertTrue(is_indoor_mado_texture("rom_museum1_mado1_tex"))
        self.assertTrue(is_indoor_mado_texture("rom_museum1_mado2_tex"))
        self.assertTrue(is_house_clock_texture("obj_clock_museum1_front_tex_txt"))
        self.assertTrue(is_museum_clock_texture("obj_clock_museum1_front_tex_txt"))
        self.assertFalse(is_museum_clock_texture("obj_clock_tailor_1_tex_txt"))
        self.assertTrue(skips_achd_texture("rom_museum1_mado1_tex"))
        self.assertTrue(skips_achd_texture("obj_clock_museum1_dai_tex_txt"))
        self.assertTrue(skips_achd_texture("obj_art01_name_tex"))
        self.assertFalse(skips_achd_texture("obj_art01_art_tex"))
        self.assertEqual(house_clock_alpha_mode("obj_clock_museum1_dai_tex_txt", "BLEND"), "OPAQUE")
        self.assertEqual(house_clock_alpha_mode("obj_clock_museum1_hari_tex_txt", "BLEND"), "MASK")
        self.assertEqual(house_clock_alpha_mode("rom_museum1_wallA_tex", "BLEND"), "BLEND")

    def test_museum_clock_linear_rgba5551_is_wood_not_neon(self) -> None:
        from asset_pipeline.bti import decode_linear_rgba5551, decode_gx_image, RGB5A3

        ## Synthetic: opaque wood brown as N64 RGBA5551 word 0xAAAA-ish pattern.
        ## Real museum front top color is (172,82,32); GX RGB5A3 misread is neon green.
        w, h = 4, 4
        ## Pack RGBA5551 for (172,82,32,255) ≈ r=21 g=10 b=4 a=1
        word = (21 << 11) | (10 << 6) | (4 << 1) | 1
        blob = word.to_bytes(2, "big") * (w * h)
        lin = decode_linear_rgba5551(blob, w, h)
        self.assertEqual(lin.getpixel((0, 0))[0], 21 * 255 // 31)
        gx = decode_gx_image(blob, w, h, RGB5A3, None)
        ## Same bytes as RGB5A3 are a different color — proves the museum path matters.
        self.assertNotEqual(lin.getpixel((0, 0)), gx.getpixel((0, 0)))

    def test_revive_stained_glass_alpha(self) -> None:
        from PIL import Image

        img = Image.new("RGBA", (2, 1))
        img.putpixel((0, 0), (255, 200, 0, 0))  # yellow glass A=0
        img.putpixel((1, 0), (40, 0, 0, 255))  # lead
        out = revive_stained_glass_alpha(img)
        self.assertEqual(out.getpixel((0, 0))[:3], (255, 200, 0))
        self.assertGreater(out.getpixel((0, 0))[3], 200)
        self.assertEqual(out.getpixel((1, 0)), (40, 0, 0, 255))

    def test_museum_dummy_wood_twin(self) -> None:
        self.assertEqual(
            museum_dummy_wood_twin("obj_art_dummy01_tex"),
            ("obj_art_dummy03_tex", "obj_art_dummy03_pal"),
        )
        self.assertEqual(
            museum_dummy_wood_twin("obj_art_dummy08_name_tex"),
            ("obj_art_dummy03_name_tex", "obj_art_dummy03_pal"),
        )
        self.assertIsNone(museum_dummy_wood_twin("obj_art_dummy03_tex"))
        self.assertIsNone(museum_dummy_wood_twin("obj_art01_art_tex"))


if __name__ == "__main__":
    unittest.main()
