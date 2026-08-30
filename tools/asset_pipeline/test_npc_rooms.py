"""NPC house FG layer → furniture visual ids."""

from __future__ import annotations

import unittest

from asset_pipeline.npc_rooms import (
    EMPTY,
    FTR_HNW_COMMON000,
    RSV_WALL,
    _decode_placements,
    _item_to_visual,
)


class NpcRoomDecodeTests(unittest.TestCase):
    def test_item_to_visual_uses_iam_index(self) -> None:
        iam = ["sum_chair01", "ari_isu01"]
        self.assertEqual(_item_to_visual(0x1000, iam), "int_sum_chair01")
        self.assertEqual(_item_to_visual(0x1007, iam), "int_ari_isu01")
        self.assertIsNone(_item_to_visual(0x0804, iam))
        self.assertIsNone(_item_to_visual(RSV_WALL, iam))

    def test_decode_skips_walls_and_keeps_cell_facing(self) -> None:
        iam = ["ari_table01"]
        items = [EMPTY] * 256
        items[1 * 16 + 3] = 0x1002  # idx 0, facing 2
        items[0] = RSV_WALL
        placements = _decode_placements(items, iam, {"ari_table01": 1})
        self.assertEqual(len(placements), 1)
        self.assertEqual(placements[0]["cell"], [3, 1])
        self.assertEqual(placements[0]["facing"], 2)
        self.assertEqual(placements[0]["visual_id"], "int_ari_table01")
        self.assertEqual(placements[0]["size"], 1)

    def test_fmanekin_stores_cloth_index(self) -> None:
        iam = ["pad"] * 3 + ["fmanekin"] * 5
        items = [EMPTY] * 256
        items[1 * 16 + 2] = 0x1000 + 5 * 4  # idx 5 = second fmanekin
        placements = _decode_placements(items, iam)
        self.assertEqual(placements[0]["visual_id"], "int_fmanekin")
        self.assertEqual(placements[0]["cloth"], 2)

    def test_hnw_common_maps_to_numbered_skeleton(self) -> None:
        iam = ["pad"] * FTR_HNW_COMMON000 + ["hnw_common"] * 3
        self.assertEqual(_item_to_visual(0x1000 + FTR_HNW_COMMON000 * 4, iam), "int_hnw001")
        self.assertEqual(_item_to_visual(0x1000 + (FTR_HNW_COMMON000 + 1) * 4 + 2, iam), "int_hnw002")
        items = [EMPTY] * 256
        items[2 * 16 + 4] = 0x1000 + FTR_HNW_COMMON000 * 4
        placements = _decode_placements(items, iam, {"hnw_common": 0})
        self.assertEqual(placements[0]["visual_id"], "int_hnw001")
        self.assertEqual(placements[0]["size"], 0)


if __name__ == "__main__":
    unittest.main()
