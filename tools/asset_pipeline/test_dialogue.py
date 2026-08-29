from __future__ import annotations

import struct
import unittest
from asset_pipeline.dialogue import (
    char_map,
    commands,
    decode_table,
    decode_tokens,
    msg_id,
    tokens_to_conversation,
)


class DialogueCodecTests(unittest.TestCase):
    def test_ascii_letters_line_up(self) -> None:
        cmap = char_map()
        self.assertEqual(cmap[65], "A")
        self.assertEqual(cmap[72], "H")
        self.assertEqual(cmap[105], "i")
        self.assertEqual(commands()[0], "MSGEND")

    def test_decodes_line_and_end(self) -> None:
        cmap = char_map()
        raw = bytes([cmap.index("H"), cmap.index("i"), 0x7F, 0x00])
        tokens = decode_tokens(raw)
        self.assertEqual(tokens[0]["text"], "H")
        self.assertEqual(tokens[1]["text"], "i")
        self.assertEqual(tokens[2]["name"], "MSGEND")
        conv = tokens_to_conversation(7, tokens)
        self.assertEqual(conv["id"], "msg_7")
        self.assertEqual(conv["nodes"]["p0"]["text"], "Hi")

    def test_player_name_and_choice_next(self) -> None:
        cmap = char_map()
        cmds = commands()
        player = cmds.index("STR_PLAYERNAME")
        nxt = cmds.index("SETNEXTMSG0")
        raw = bytes(
            [
                cmap.index("H"),
                cmap.index("i"),
                0x7F,
                player,
                0x7F,
                nxt,
                0x12,
                0x34,
                0x7F,
                0x00,
            ]
        )
        conv = tokens_to_conversation(1, decode_tokens(raw))
        self.assertIn("{player}", conv["nodes"]["p0"]["text"])
        self.assertEqual(conv["nodes"]["p0"]["next"], msg_id(0x1234))

    def test_table_splits_entries(self) -> None:
        cmap = char_map()
        a = bytes([cmap.index("A"), 0x7F, 0x00])
        b = bytes([cmap.index("B"), 0x7F, 0x00])
        data = a + b
        table = struct.pack(">I", len(a)) + struct.pack(">I", len(a) + len(b))
        entries = decode_table(data, table)
        self.assertEqual(len(entries), 2)
        self.assertEqual(decode_tokens(entries[0])[0]["text"], "A")
        self.assertEqual(decode_tokens(entries[1])[0]["text"], "B")


if __name__ == "__main__":
    unittest.main()
