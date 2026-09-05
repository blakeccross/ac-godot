"""Token helpers for unbound anime_N_txt segment resolution."""

from __future__ import annotations

import unittest

from asset_pipeline.texbank import (
    COVERAGE_OPA,
    COVERAGE_TEX_EDGE,
    COVERAGE_XLU,
    coverage_from_render_mode,
    dummy_name_score,
    dummy_palette_score,
    gfx_part_tokens,
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
    resolve_alpha_mode,
    revive_stained_glass_alpha,
    season_of_prefix,
    shop_shell_kind,
    skips_achd_texture,
    structure_palette_names,
    symbol_tokens,
    tmem_palette_slot,
    uv_samples_transparent,
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

    def test_resolve_alpha_mode_from_coverage(self) -> None:
        self.assertEqual(resolve_alpha_mode(COVERAGE_OPA, "MASK"), "OPAQUE")
        self.assertEqual(resolve_alpha_mode(COVERAGE_OPA, "BLEND"), "OPAQUE")
        self.assertEqual(
            resolve_alpha_mode(COVERAGE_TEX_EDGE, "MASK", samples_transparent=True),
            "MASK",
        )
        self.assertEqual(
            resolve_alpha_mode(COVERAGE_TEX_EDGE, "MASK", samples_transparent=False),
            "OPAQUE",
        )
        self.assertEqual(resolve_alpha_mode(COVERAGE_XLU, "OPAQUE"), "BLEND")
        self.assertEqual(resolve_alpha_mode(None, "MASK"), "MASK")
        self.assertEqual(resolve_alpha_mode(None, "BLEND"), "BLEND")

    def test_coverage_from_real_render_modes(self) -> None:
        ## Words from museum clock / train / mado SetRenderMode packets.
        self.assertEqual(coverage_from_render_mode(0xC8112078), COVERAGE_OPA)
        self.assertEqual(coverage_from_render_mode(0xC8113078), COVERAGE_TEX_EDGE)
        self.assertEqual(coverage_from_render_mode(0xC8104A50), COVERAGE_XLU)

    def test_uv_samples_transparent_footprint(self) -> None:
        from asset_pipeline.gfx import Vertex
        from asset_pipeline.texbank import GX_CLAMP
        from PIL import Image

        ## Left half opaque, right half clear (chromakey strip).
        img = Image.new("RGBA", (4, 4), (40, 30, 30, 255))
        for y in range(4):
            for x in range(2, 4):
                img.putpixel((x, y), (0, 0, 0, 0))
        verts = [
            Vertex(0, 0, 0, 0, 0, 1, 1, 1, 1, u=0.1, v=0.1),
            Vertex(1, 0, 0, 0, 0, 1, 1, 1, 1, u=0.4, v=0.1),
            Vertex(0, 1, 0, 0, 0, 1, 1, 1, 1, u=0.1, v=0.4),
        ]
        self.assertFalse(
            uv_samples_transparent(img, verts, [(0, 1, 2)], wrap_s=GX_CLAMP, wrap_t=GX_CLAMP)
        )
        verts[1] = Vertex(1, 0, 0, 0, 0, 1, 1, 1, 1, u=0.9, v=0.1)
        self.assertTrue(
            uv_samples_transparent(img, verts, [(0, 1, 2)], wrap_s=GX_CLAMP, wrap_t=GX_CLAMP)
        )

    def test_train_structure_palette_and_skip_achd(self) -> None:
        self.assertIn("obj_train1_a1_pal", structure_palette_names("obj_train1_1"))
        self.assertIn("obj_train1_a1_pal", structure_palette_names("obj_train1_2"))
        self.assertIn("obj_train1_a2_pal", structure_palette_names("obj_train1_3"))
        self.assertTrue(skips_achd_texture("obj_train1_t1_tex_txt"))
        self.assertTrue(skips_achd_texture("obj_train1_t4_tex_txt"))
        self.assertFalse(skips_achd_texture("obj_s_station1_a_tex_txt"))

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

    def test_shop_clock_tlut_is_n64_rgba5551_not_rgb5a3(self) -> None:
        from asset_pipeline.texbank import palette_from_rgb5a3, palette_from_rgba5551

        ## `obj_shop1_clock_pal` entry 1 = 0xC417 — wood brown as RGBA5551,
        ## purple/magenta if misread as GX RGB5A3 (high bit set).
        pal = bytes.fromhex("0000c417")
        a3 = palette_from_rgb5a3(pal)[1]
        n64 = palette_from_rgba5551(pal)[1]
        self.assertGreater(a3[2], a3[1])  # blue-led (wrong)
        self.assertGreater(n64[0], n64[2])  # red-led wood (right)
        self.assertNotEqual(a3[:3], n64[:3])

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

    def test_procedural_mka_face_has_dark_brows(self) -> None:
        from asset_pipeline.texbank import TextureBank

        face = TextureBank._procedural_mka_face()
        self.assertEqual(face.size, (32, 32))
        dark = sum(
            1
            for p in face.getdata()
            if p[0] < 40 and p[1] < 40 and p[2] < 40 and p[3] > 200
        )
        ## UV-island stamps only — must stay small to avoid blotches on the face shell.
        self.assertGreater(dark, 20)
        self.assertLess(dark, 120)
        ## Snout-tip nose (UV ~0.81, 0.625 → texel ~25, 20).
        nose = face.getpixel((25, 20))
        self.assertLess(nose[0], 40)
        self.assertLess(nose[1], 40)
        self.assertLess(nose[2], 40)

    def test_stamp_mka_face_puts_nose_on_snout_uv(self) -> None:
        from PIL import Image

        from asset_pipeline.texbank import TextureBank

        eye = Image.new("RGBA", (32, 16), (255, 255, 255, 255))
        mouth = Image.new("RGBA", (32, 16), (255, 255, 255, 255))
        ## Fill the crop windows used by `_stamp_mka_face_from_sheets`.
        for y in range(2, 11):
            for x in range(5, 11):
                eye.putpixel((x, y), (0, 0, 0, 255))
            for x in range(21, 27):
                eye.putpixel((x, y), (0, 0, 0, 255))
        for y in range(0, 10):
            for x in range(11, 21):
                mouth.putpixel((x, y), (10, 10, 10, 255))
        face = TextureBank._stamp_mka_face_from_sheets(eye, mouth)
        self.assertEqual(face.size, (32, 32))
        ## Nose stamp centered near UV (0.81, 0.625) → ~(26, 20).
        self.assertEqual(face.getpixel((26, 20))[:3], (10, 10, 10))
        self.assertEqual(face.getpixel((0, 0))[3], 255)


class ShopShellKindTests(unittest.TestCase):
    def test_nook_fw_suffixes(self) -> None:
        self.assertEqual(shop_shell_kind("rom_shop1f"), "floor")
        self.assertEqual(shop_shell_kind("rom_shop1w"), "wall")
        self.assertEqual(shop_shell_kind("rom_shop4_2f"), "floor")
        self.assertEqual(shop_shell_kind("rom_shop4_2w"), "wall")
        self.assertEqual(shop_shell_kind("rom_shop1_fuku"), "")
        self.assertEqual(shop_shell_kind("rom_shop4_1"), "")
        self.assertEqual(shop_shell_kind("rom_myhome1_floor"), "")


class LoadTlutFallbackTests(unittest.TestCase):
    def test_dolphin_miss_clears_stale_slot_not_img_addr(self) -> None:
        """Boy hat: failed LOADTLUT 0x0B must not treat skin SETTIMG bytes as a TLUT."""
        from asset_pipeline.gfx import _apply_loadtlut
        from asset_pipeline.texbank import TextureState

        class _Bank:
            def load_palette(self, addr: int, count: int):
                ## 0x0B anime miss; skin DRAM would look like a 32-byte "pal".
                if addr == 0x0B000000:
                    return None
                if addr == 0x00131F40:
                    return bytes(range(32))
                return None

        state = TextureState()
        state.img_addr = 0x00131F40
        state.palettes[15] = b"\xAA" * 32
        state.pal_slot = 15
        ## Real `head_boy_model` clothing LOADTLUT (dolphin, slot 15, seg 0x0B).
        _apply_loadtlut(0xF08F4010, 0x0B000000, _Bank(), state)
        self.assertNotIn(15, state.palettes)
        self.assertEqual(state.pal_slot, 15)

    def test_dolphin_hit_binds_slot(self) -> None:
        from asset_pipeline.gfx import _apply_loadtlut
        from asset_pipeline.texbank import TextureState

        shirt_pal = b"\x11" * 32

        class _Bank:
            def load_palette(self, addr: int, count: int):
                return shirt_pal if addr == 0x0B000000 else None

        state = TextureState()
        state.palettes[15] = b"\xAA" * 32
        _apply_loadtlut(0xF08F4010, 0x0B000000, _Bank(), state)
        self.assertEqual(state.palettes[15], shirt_pal)


if __name__ == "__main__":
    unittest.main()
