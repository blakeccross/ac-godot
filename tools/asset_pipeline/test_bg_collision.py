"""`mFM_bg_sound_source_data_c` decoding (`bg_collision.decode_sounds`)."""

from __future__ import annotations

import struct
import unittest

from .bg_collision import SOUND_COUNT, decode_sounds


class BgSoundsTest(unittest.TestCase):
    def test_used_slots_only(self) -> None:
        blob = b"".join(struct.pack(">hBB", k, x, z) for k, x, z in [(1, 5, 1), (0, 0, 0), (2, 7, 14)])
        blob += b"\0" * (SOUND_COUNT * 4 - len(blob))
        self.assertEqual(decode_sounds(blob), [[1, 5, 1], [2, 7, 14]])


if __name__ == "__main__":
    unittest.main()
