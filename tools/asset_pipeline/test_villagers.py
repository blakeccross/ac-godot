from __future__ import annotations

import unittest
from pathlib import Path

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


if __name__ == "__main__":
    unittest.main()
