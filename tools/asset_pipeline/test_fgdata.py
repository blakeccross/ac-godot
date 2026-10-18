"""FG catalog: the index-ordered combi table a save's `combi_table` resolves through."""

from __future__ import annotations

import unittest

from asset_pipeline.fgdata import _block_type_values, parse_combi_table

FIELD_MAKE_H = """
enum {
    mFM_BLOCK_TYPE_CLIFF,
    mFM_BLOCK_TYPE_RAIL = 11,
    mFM_BLOCK_TYPE_GRASS,
    mFM_BLOCK_TYPE_NONE = 255
};
"""

DATA_COMBI_C = """
mFM_combo_info_c data_combi_table[] = {
    { BG_TYPE_292, FG_TYPE_EMPTY, mFM_BLOCK_TYPE_NONE }, // not a field acre
    /* { BG_TYPE_GRD_S_X_1, FG_TYPE_0001, mFM_BLOCK_TYPE_GRASS }, */
    { BG_TYPE_GRD_S_T_ST1_1, FG_TYPE_0005, mFM_BLOCK_TYPE_RAIL },
    { BG_TYPE_GRD_S_F_1, FG_TYPE_UNKNOWN, mFM_BLOCK_TYPE_GRASS },
};
"""


class CombiTableTests(unittest.TestCase):
    def test_rows_keep_index_order_including_non_field_rows(self) -> None:
        rows = parse_combi_table(
            DATA_COMBI_C, _block_type_values(FIELD_MAKE_H), {"FG_TYPE_EMPTY": 203, "FG_TYPE_0005": 5}
        )
        self.assertEqual(
            rows,
            [
                {"bg": "292", "fg": 203, "type": 255},
                {"bg": "grd_s_t_st1_1", "fg": 5, "type": 11},
                {"bg": "grd_s_f_1", "fg": -1, "type": 12},
            ],
        )


if __name__ == "__main__":
    unittest.main()
