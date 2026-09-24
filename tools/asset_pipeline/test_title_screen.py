"""Title screen extraction: pact parsing, the linear IA8 decode, and the press-start tint."""

from __future__ import annotations

import unittest

from asset_pipeline.audio import EXTRA_SE_NUMS, _sfx_catalog_entries, _with_extra_se
from asset_pipeline.title_screen import (
    PRESS_START_ENV,
    PRESS_START_PRIM,
    decode_ia8_linear,
    parse_pact,
    parse_title_demo_acres,
    parse_title_demo_fg,
    tint_ia4,
)

PACT_SOURCE = """
#include "types.h"

u16 pact3_head_table[] = {
  0x0B53, 0x00A0, 0x044D, /* position */
  0xE400, /* angle (320.625 deg) */
  0x0000, /* tool */
  0x0731  /* scale/size? */
};

/**
 * Key data format:
 * XXXXXXXB YYYYYYYA
 **/
u16 pact3_key_data[] = {
  0x0000, 0x0000, 0x02EC, 0x04EA,
  0x36FE,
};
"""


class ParsePactTests(unittest.TestCase):
    def test_header_words_ignore_comment_digits(self) -> None:
        pact = parse_pact(PACT_SOURCE, 3)
        self.assertEqual(pact["pos"], [0x0B53, 0x00A0, 0x044D])
        self.assertEqual(pact["angle"], 0xE400)
        self.assertEqual(pact["tool"], 0)
        self.assertEqual(pact["scale"], 0x0731)

    def test_key_data_words_in_order(self) -> None:
        pact = parse_pact(PACT_SOURCE, 3)
        self.assertEqual(pact["keys"], [0x0000, 0x0000, 0x02EC, 0x04EA, 0x36FE])

    def test_wrong_index_raises(self) -> None:
        with self.assertRaises(ValueError):
            parse_pact(PACT_SOURCE, 0)


class ParseFgTests(unittest.TestCase):
    def test_rows_are_seven_wide(self) -> None:
        source = """
        static mActor_name_t l_title_demo_fg[(BLOCK_Z_NUM - 2) * BLOCK_X_NUM] = {
            0x00CB, 0x00CB, 0x00CB, 0x00CB, 0x00CB, 0x00CB, 0x00CB,
            0x00CB, 0x00DD, 0x00AB, 0x00CC, 0x00E5, 0x002E, 0x00CB,
        };
        """
        fg = parse_title_demo_fg(source)
        self.assertEqual((fg["cols"], fg["rows"]), (7, 2))
        self.assertEqual(fg["ids"][8], 0x00DD)

    def test_ragged_table_raises(self) -> None:
        with self.assertRaises(ValueError):
            parse_title_demo_fg("l_title_demo_fg[3] = { 0x0001, 0x0002, 0x0003 };")


class DecodeTests(unittest.TestCase):
    def test_linear_rows_with_intensity_in_the_high_nibble(self) -> None:
        ## `f3`: I=15 (white) A=3. `0f`: I=0 A=15. The `f0` run is transparent white —
        ## the leading bytes of `log_win_logo3_tex`, which is what pinned the layout.
        img = decode_ia8_linear(bytes([0xF0, 0xF3, 0x0F, 0xFF]), 2, 2)
        self.assertEqual(img.getpixel((0, 0)), (255, 255, 255, 0))
        self.assertEqual(img.getpixel((1, 0)), (255, 255, 255, 51))
        self.assertEqual(img.getpixel((0, 1)), (0, 0, 0, 255))
        self.assertEqual(img.getpixel((1, 1)), (255, 255, 255, 255))

    def test_short_data_raises(self) -> None:
        with self.assertRaises(ValueError):
            decode_ia8_linear(b"\x00" * 3, 2, 2)


class TintTests(unittest.TestCase):
    def test_intensity_lerps_env_to_prim_and_alpha_is_kept(self) -> None:
        prim, env = PRESS_START_PRIM[2], PRESS_START_ENV[2]
        mask = decode_ia8_linear(bytes([0xF5, 0x05]), 2, 1)
        out = tint_ia4(mask, prim, env)
        ## Full intensity is PRIM; zero intensity is ENV.
        self.assertEqual(out.getpixel((0, 0))[:3], prim)
        self.assertEqual(out.getpixel((1, 0))[:3], env)
        self.assertEqual(out.getpixel((0, 0))[3], 5 * 17)

    def test_five_palettes_one_per_demo(self) -> None:
        self.assertEqual(len(PRESS_START_PRIM), 5)
        self.assertEqual(len(PRESS_START_ENV), 5)


class StartChimeTests(unittest.TestCase):
    def test_extra_se_is_added_when_the_enum_lacks_it(self) -> None:
        merged = _with_extra_se({"cursol": 1})
        self.assertEqual(merged["44d"], 0x44D)
        self.assertEqual(merged["cursol"], 1)

    def test_extra_se_does_not_duplicate_a_named_entry(self) -> None:
        ## If the enum ever names 0x44D, keep that name rather than adding a second id.
        merged = _with_extra_se({"start_chime": 0x44D})
        self.assertNotIn("44d", merged)

    def test_catalog_entry_points_at_the_hex_id_the_game_plays(self) -> None:
        entries = {e["id"]: e for e in _sfx_catalog_entries({})}
        self.assertEqual(entries["44d"]["se_num"], 0x44D)
        self.assertEqual(entries["44d"]["path"], "sfx/44d.ogg")
        self.assertEqual(set(EXTRA_SE_NUMS), {"44d", "3f", "73", "2b"})


ACRE_SCENES_H = """
enum scene_table {
    SCENE_TEST1,
    SCENE_FIELD_TOOL, /* field tool */
    SCENE_TITLE_DEMO, /* title screen demo */
    SCENE_NUM
};
"""

ACRE_COMBI_H = """
enum __block_combi__ {
    BLOCK_COMBI_GRD_1,
    BLOCK_COMBI_GRD_S_E1_1,
    BLOCK_COMBI_GRD_S_M_1_232,
    BLOCK_COMBI_NUM
};
"""

ACRE_DATA_COMBI_C = """
mFM_combo_info_c data_combi_table[] = {
    { BG_TYPE_292, FG_TYPE_EMPTY, mFM_BLOCK_TYPE_NONE },
    { BG_TYPE_GRD_S_E1_1, FG_TYPE_EMPTY, mFM_BLOCK_TYPE_BORDER_CLIFF_TOP },
    { BG_TYPE_GRD_S_M_1, FG_TYPE_0061, mFM_BLOCK_TYPE_BEACH },
};
"""

ACRE_FIELD_MAKE_H = """
enum {
    mFM_BLOCK_TYPE_BORDER_CLIFF_TOP,
    mFM_BLOCK_TYPE_BORDER_CLIFF_RIVER, // comment
    mFM_BLOCK_TYPE_BEACH = 63,
    mFM_BLOCK_TYPE_NONE = 255
};
"""

ACRE_FIELD_DATA_C = """
mFM_field_data_c data_fdd[SCENE_NUM] = {
    { mFI_FIELD_FG, 1, 1, { { BLOCK_COMBI_GRD_1, 0 }, }, fd0_actable, 0x0, },
    { mFI_FIELD_FG, 2, 1, { { BLOCK_COMBI_GRD_1, 0 }, { BLOCK_COMBI_GRD_1, 0 }, }, x_actable, },
    {
        mFI_FIELD_FG,
        2,
        2,
        {
            { BLOCK_COMBI_GRD_S_E1_1, 1 }, { BLOCK_COMBI_GRD_S_E1_1, 1 },
            { BLOCK_COMBI_GRD_S_M_1_232, 0 }, { BLOCK_COMBI_GRD_1, 0 },
        },
        title_demo_actable,
        0x00000000,
    },
};
"""


class ParseAcresTests(unittest.TestCase):
    def test_title_demo_entry_resolves_bg_type_and_height(self) -> None:
        acres = parse_title_demo_acres(
            ACRE_FIELD_DATA_C, ACRE_DATA_COMBI_C, ACRE_COMBI_H, ACRE_FIELD_MAKE_H, ACRE_SCENES_H
        )
        self.assertEqual((acres["cols"], acres["rows"]), (2, 2))
        self.assertEqual(acres["bg"], ["grd_s_e1_1", "grd_s_e1_1", "grd_s_m_1", "292"])
        self.assertEqual(acres["types"], [0, 0, 63, 255])
        self.assertEqual(acres["heights"], [1, 1, 0, 0])

    def test_combi_table_length_mismatch_raises(self) -> None:
        short = ACRE_DATA_COMBI_C.replace("{ BG_TYPE_292, FG_TYPE_EMPTY, mFM_BLOCK_TYPE_NONE },", "")
        with self.assertRaises(ValueError):
            parse_title_demo_acres(
                ACRE_FIELD_DATA_C, short, ACRE_COMBI_H, ACRE_FIELD_MAKE_H, ACRE_SCENES_H
            )


if __name__ == "__main__":
    unittest.main()
