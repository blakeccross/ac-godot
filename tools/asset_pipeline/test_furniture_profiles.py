"""`aFTR_PROFILE` → behaviour flags."""

from __future__ import annotations

import unittest

from asset_pipeline.furniture_profiles import parse_profile_body


class ProfileTests(unittest.TestCase):
    def test_storage_closet(self) -> None:
        body = """
	NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
	40.0f, 0.01f, aFTR_SHAPE_TYPEA, mCoBG_FTR_TYPEA, 0, 0, 0,
	aFTR_INTERACTION_STORAGE_CLOSET, &aSumHalChest02_func,"""
        row = parse_profile_body(body)
        assert row is not None
        self.assertEqual(row["shape"], "TYPEA")
        self.assertEqual(row["interaction"], ["STORAGE_CLOSET"])
        self.assertEqual(row["vtable"], 1)

    def test_chair_contact_and_comments(self) -> None:
        body = """
	int_a, int_b, NULL, NULL, NULL, NULL, NULL, NULL, // models
	18.0f, 0.01f, aFTR_SHAPE_TYPEA, mCoBG_FTR_TYPEA, 0, 0,
	aFTR_CONTACT_ACTION_CHAIR_UNIDIRECTIONAL, 0, NULL,"""
        row = parse_profile_body(body)
        assert row is not None
        self.assertEqual(row["contact"], ["CHAIR_UNIDIRECTIONAL"])
        self.assertEqual(row["interaction"], [])
        self.assertEqual(row["vtable"], 0)

    def test_numeric_and_combined_flags(self) -> None:
        body = """
	NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 1.0f, 0.01f,
	aFTR_SHAPE_TYPEB_0, mCoBG_FTR_TYPEB_0, 1, 0, 0x10 | 8, aFTR_INTERACTION_MUSIC_DISK | aFTR_INTERACTION_TOGGLE, NULL,"""
        row = parse_profile_body(body)
        assert row is not None
        self.assertEqual(row["shape"], "TYPEB_0")
        self.assertEqual(row["check_rotation"], 1)
        self.assertEqual(sorted(row["contact"]), ["BED_DOUBLE", "BED_SINGLE"])
        self.assertEqual(row["interaction"], ["MUSIC_DISK", "TOGGLE"])

    def test_rejects_non_profile(self) -> None:
        self.assertIsNone(parse_profile_body("1, 2, 3"))


if __name__ == "__main__":
    unittest.main()
