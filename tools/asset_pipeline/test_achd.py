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

    def test_field_terrain_skip(self) -> None:
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
