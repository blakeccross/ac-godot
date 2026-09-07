"""Tests for Dolphin ACHD hash + DDS decode."""

from __future__ import annotations

import struct
import tempfile
import unittest
from pathlib import Path

from asset_pipeline.achd import (
    AchdPack,
    decode_dds,
    dolphin_texture_stem,
    gx_texture_byte_size,
)
from asset_pipeline.bti import CI4


class TestDolphinHash(unittest.TestCase):
    def test_ci4_stem_matches_known_gyroid(self) -> None:
        """int_hnw037_b_front_tex_txt → ACHD Mini metatoid front."""
        rel_path = Path("/Users/blakecross/Documents/ac-assets-work/extracted/disc/files/foresta.rel")
        map_path = Path("/Users/blakecross/Documents/ac-assets-work/extracted/disc/files/foresta.map")
        if not rel_path.is_file() or not map_path.is_file():
            self.skipTest("extracted disc not available")
        from asset_pipeline.mapfile import parse_map
        from asset_pipeline.rel import RelData

        rel = RelData(rel_path)
        by = {s.name: s for s in parse_map(map_path)}
        tex = by["int_hnw037_b_front_tex_txt"]
        pal = by["int_hnw037_pal"]
        data = rel.slice_at(tex.address, gx_texture_byte_size(32, 16, CI4))
        tlut = rel.slice_at(pal.address, 32)
        stem = dolphin_texture_stem(data, 32, 16, CI4, tlut)
        self.assertEqual(stem, "tex1_32x16_de749e9a60767e72_24654dd1912131f2_8")

    def test_pack_lookup_and_bc7_decode(self) -> None:
        achd = Path("/Users/blakecross/Downloads/ACHD V24 + Deluxe/ACHD")
        dds = achd / "Gyroids/Mini metatoid/tex1_32x16_de749e9a60767e72_24654dd1912131f2_8.dds"
        if not dds.is_file():
            self.skipTest("ACHD pack not available")
        with tempfile.TemporaryDirectory() as tmp:
            pack = AchdPack(achd, Path(tmp))
            png = pack.png_for_stem("tex1_32x16_de749e9a60767e72_24654dd1912131f2_8")
            self.assertIsNotNone(png)
            assert png is not None
            self.assertTrue(png.startswith(b"\x89PNG"))
            image = decode_dds(dds)
            self.assertEqual(image.size, (256, 128))
            self.assertGreater(pack.hits, 0)

    def test_field_terrain_classifier(self) -> None:
        from asset_pipeline.achd import is_field_terrain_texture

        self.assertTrue(is_field_terrain_texture("mFM_grd_s_grass_tex", "grd_s_c1_1"))
        self.assertTrue(is_field_terrain_texture("", "grd_s_r1_1"))
        self.assertTrue(is_field_terrain_texture("mFM_grd_s_earth_tex"))
        self.assertTrue(is_field_terrain_texture("obj_s_tree3_leaf_tex", "obj_s_tree5"))
        self.assertTrue(is_field_terrain_texture("obj_s_tree4_trunk_tex"))
        self.assertTrue(is_field_terrain_texture("obj_s_cedar_baby_tex", "obj_s_cedar1"))
        self.assertTrue(is_field_terrain_texture("", "obj_w_palm5"))
        self.assertTrue(is_field_terrain_texture("obj_s_stoneA_tex", "obj_s_stoneA"))
        self.assertTrue(is_field_terrain_texture("", "obj_w_stoneC"))
        self.assertFalse(is_field_terrain_texture("int_hnw037_b_front_tex_txt", "int_hnw037"))
        self.assertFalse(is_field_terrain_texture("tol_axe_1_edge1_tex_txt"))
        self.assertFalse(is_field_terrain_texture("obj_item_apple_tex", "int_minidisk"))

    def test_achd_png_usable_size_wrap_rule(self) -> None:
        from asset_pipeline.achd import achd_png_usable
        from asset_pipeline.texbank import GX_CLAMP, GX_REPEAT

        ## Exact size always OK (including REPEAT field tiles).
        self.assertTrue(achd_png_usable(32, 32, 32, 32, GX_REPEAT, GX_REPEAT))
        ## Upscaled REPEAT is not usable as-is (wrap-bake); maybe_hd_png caps it.
        self.assertFalse(achd_png_usable(32, 32, 256, 256, GX_REPEAT, GX_REPEAT))
        self.assertFalse(achd_png_usable(64, 64, 512, 512, GX_REPEAT, GX_CLAMP))
        ## Both-CLAMP + uniform integer scale is OK (portraits / trees).
        self.assertTrue(achd_png_usable(32, 32, 256, 256, GX_CLAMP, GX_CLAMP))
        ## MIRROR props (tank rocks) may upscale.
        from asset_pipeline.texbank import GX_MIRROR

        self.assertTrue(achd_png_usable(64, 64, 1024, 1024, GX_MIRROR, GX_MIRROR))
        self.assertFalse(achd_png_usable(32, 32, 256, 128, GX_CLAMP, GX_CLAMP))
        self.assertFalse(achd_png_usable(32, 32, 250, 250, GX_CLAMP, GX_CLAMP))

    def test_repeat_hd_tile_size_caps_grass(self) -> None:
        from asset_pipeline.achd import REPEAT_HD_MAX_EDGE, repeat_hd_tile_size

        self.assertEqual(REPEAT_HD_MAX_EDGE, 128)
        ## ACHD grass 32→256 caps to 128 (4×) for wrap-bake.
        self.assertEqual(repeat_hd_tile_size(32, 32, 256, 256), (128, 128))
        ## Earth 64→512 caps to 128 (2×).
        self.assertEqual(repeat_hd_tile_size(64, 64, 512, 512), (128, 128))
        ## Already within cap — keep full HD.
        self.assertEqual(repeat_hd_tile_size(32, 32, 128, 128), (128, 128))
        self.assertIsNone(repeat_hd_tile_size(32, 32, 32, 32))
        self.assertIsNone(repeat_hd_tile_size(32, 32, 48, 48))

    def test_maybe_hd_png_downscales_repeat(self) -> None:
        from asset_pipeline.achd import maybe_hd_png
        from asset_pipeline.bti import CI4
        from asset_pipeline.texbank import GX_CLAMP, GX_REPEAT
        from PIL import Image
        import io

        class _Stub:
            def lookup_png(self, *_a, **_k):
                img = Image.new("RGBA", (256, 256), (10, 200, 40, 255))
                buf = io.BytesIO()
                img.save(buf, format="PNG")
                return buf.getvalue()

        stub = _Stub()
        hd = maybe_hd_png(
            stub,  # type: ignore[arg-type]
            b"\0" * 512,
            32,
            32,
            CI4,
            b"\0" * 32,
            wrap_s=GX_REPEAT,
            wrap_t=GX_REPEAT,
        )
        self.assertIsNotNone(hd)
        assert hd is not None
        out = Image.open(io.BytesIO(hd))
        self.assertEqual(out.size, (128, 128))
        ## CLAMP keeps full 256.
        full = maybe_hd_png(
            stub,  # type: ignore[arg-type]
            b"\0" * 512,
            32,
            32,
            CI4,
            b"\0" * 32,
            wrap_s=GX_CLAMP,
            wrap_t=GX_CLAMP,
        )
        self.assertIsNotNone(full)
        assert full is not None
        self.assertEqual(Image.open(io.BytesIO(full)).size, (256, 256))

    def test_room_bank_skip(self) -> None:
        from asset_pipeline.achd import is_room_bank_texture

        self.assertTrue(is_room_bank_texture("player_room_floor.bin:33:0"))
        self.assertTrue(is_room_bank_texture("player_room_wall.bin:12:1"))
        self.assertTrue(is_room_bank_texture("player_room_wall_0_0"))
        self.assertTrue(is_room_bank_texture("player_room_floor_0_2"))
        self.assertFalse(is_room_bank_texture("int_sum_gre_counter01_front_tex"))
        self.assertFalse(is_room_bank_texture("mFM_grd_s_grass_tex"))
        self.assertFalse(is_room_bank_texture("rom_conveni_wall_C"))

    def test_player_model_skip(self) -> None:
        from asset_pipeline.achd import is_player_model_texture

        self.assertTrue(is_player_model_texture("boy_1_pants_tex_txt"))
        self.assertTrue(is_player_model_texture("boy_1_hole_tex_txt"))
        self.assertTrue(is_player_model_texture("seg_0A", "boy_1"))
        self.assertTrue(is_player_model_texture("", "boy_1"))
        self.assertTrue(is_player_model_texture("face_boy.bin:0:3"))
        self.assertTrue(is_player_model_texture("tex_boy.bin:12"))
        self.assertFalse(is_player_model_texture("seg_0A", "cat_1"))
        self.assertFalse(is_player_model_texture("int_sum_art01_monariza_tex"))
        self.assertFalse(is_player_model_texture("tol_axe_1_edge1_tex_txt"))


class TestDdsHeader(unittest.TestCase):
    def test_dx10_bc7_header_layout(self) -> None:
        achd = Path("/Users/blakecross/Downloads/ACHD V24 + Deluxe/ACHD")
        dds = achd / "Gyroids/Mini metatoid/tex1_32x16_de749e9a60767e72_24654dd1912131f2_8.dds"
        if not dds.is_file():
            self.skipTest("ACHD pack not available")
        blob = dds.read_bytes()
        self.assertEqual(blob[:4], b"DDS ")
        self.assertEqual(blob[84:88], b"DX10")
        dxgi = struct.unpack_from("<I", blob, 128)[0]
        self.assertIn(dxgi, {98, 99})


if __name__ == "__main__":
    unittest.main()
