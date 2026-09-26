from __future__ import annotations

import unittest
from pathlib import Path

from asset_pipeline.ckf import _joint_gfx_index
from asset_pipeline.mapfile import MapSymbol
from asset_pipeline.villagers import NPC_NUM, parse_roster

DECOMP = Path("/Users/blakecross/Documents/ac-decomp")


@unittest.skipUnless((DECOMP / "include" / "m_name_table.h").is_file(), "ac-decomp not present")
class VillagerRosterTests(unittest.TestCase):
    def test_roster_has_every_animal(self) -> None:
        roster = parse_roster(DECOMP)
        self.assertEqual(len(roster), NPC_NUM)
        ids = [e["id"] for e in roster]
        self.assertEqual(len(ids), len(set(ids)))
        filbert = next(e for e in roster if e["id"] == "filbert")
        self.assertEqual(filbert["display_name"], "Filbert")
        self.assertEqual(filbert["species"], "squirrel")
        self.assertEqual(filbert["personality"], "lazy")
        self.assertTrue(filbert["starter"])
        self.assertIsInstance(filbert["wall_index"], int)
        self.assertIsInstance(filbert["floor_index"], int)
        self.assertGreaterEqual(filbert["wall_index"], 0)
        dora = next(e for e in roster if e["id"] == "dora")
        self.assertEqual(dora["species"], "mouse")
        amelia = next(e for e in roster if e["id"] == "amelia")
        self.assertEqual(amelia["species"], "eagle")
        ankha = next(e for e in roster if e["id"] == "ankha")
        self.assertTrue(ankha["islander"])
        self.assertFalse(ankha["starter"])
        self.assertGreaterEqual(sum(1 for e in roster if e["starter"]), 12)
        looks = {e["looks"] for e in roster if e["starter"]}
        self.assertEqual(looks, {0, 1, 2, 3, 4, 5})
        houses = {(e["wall_index"], e["floor_index"]) for e in roster}
        self.assertGreater(len(houses), 40)

    def test_each_villager_has_its_own_texture_set(self) -> None:
        ## Species share a skeleton, not textures: Stu is `bul_1` bones + `bul_2` sheets.
        roster = parse_roster(DECOMP)
        stu = next(e for e in roster if e["id"] == "stu")
        self.assertEqual((stu["prefix"], stu["texture_set"]), ("bul", "bul_2"))
        sets = [e["texture_set"] for e in roster]
        self.assertEqual(len(set(sets)), NPC_NUM)
        self.assertTrue(all(s.startswith(e["prefix"] + "_") for s, e in zip(sets, roster)))


class JointGfxIndexTests(unittest.TestCase):
    def test_code_symbol_at_the_same_address_does_not_rename_a_joint_dl(self) -> None:
        ## `Lfoot1_bul_model` and `m_player.o`'s demo function share 0x18d858; the bull's
        ## left thigh vanished when the function name won.
        table = MapSymbol(0x18D970, 312, 4, "cKF_je_r_bul_1_tbl", "dataobject.obj")
        syms = [
            MapSymbol(0x18D858, 820, 4, ".text", "dataobject.obj"),
            MapSymbol(0x18D858, 128, 8, "Lfoot1_bul_model", "dataobject.obj"),
            MapSymbol(0x18D858, 144, 4, "Player_actor_request_main_demo_geton_train", "m_player.o"),
            table,
        ]
        self.assertEqual(_joint_gfx_index(syms, table)[0x18D858].name, "Lfoot1_bul_model")


if __name__ == "__main__":
    unittest.main()
