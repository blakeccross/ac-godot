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

    def test_preserves_text_color_and_char_scale(self) -> None:
        cmap = char_map()
        cmds = commands()
        color = cmds.index("TEXTCOLOR")
        scale = cmds.index("CHARSCALE")
        raw = bytes(
            [
                0x7F,
                color,
                150,
                150,
                150,
                0x7F,
                scale,
                16,
                cmap.index("("),
                0x7F,
                scale,
                16,
                cmap.index("o"),
                0x7F,
                scale,
                16,
                cmap.index("k"),
                0x7F,
                scale,
                16,
                cmap.index(")"),
                0x7F,
                0x00,
            ]
        )
        text = tokens_to_conversation(2, decode_tokens(raw))["nodes"]["p0"]["text"]
        self.assertIn("{c:150,150,150}", text)
        self.assertIn("{s:16}", text)
        self.assertIn("(ok)", text)
        self.assertIn("{s:32}", text)

    def test_demonpc0_slot0_becomes_manpu_event(self) -> None:
        cmap = char_map()
        cmds = commands()
        demon = cmds.index("DEMONPC0")
        raw = bytes(
            [
                0x7F,
                demon,
                0,
                0,
                11,
                cmap.index("H"),
                cmap.index("i"),
                0x7F,
                0x00,
            ]
        )
        conv = tokens_to_conversation(9, decode_tokens(raw))
        self.assertEqual(
            conv["nodes"]["p0"]["events"],
            [{"op": "manpu", "code": 11, "name": "hate1"}],
        )
        self.assertEqual(conv["nodes"]["p0"]["text"], "Hi")

    def test_msgcontents_becomes_set_emote(self) -> None:
        cmap = char_map()
        cmds = commands()
        fun = cmds.index("MSGCONTENTS_FUN")
        raw = bytes([0x7F, fun, cmap.index("Y"), 0x7F, 0x00])
        conv = tokens_to_conversation(10, decode_tokens(raw))
        self.assertEqual(conv["nodes"]["p0"]["events"], [{"op": "set_emote", "name": "laugh"}])

    def test_demonpc0_non_manpu_slot_becomes_demo_order(self) -> None:
        cmap = char_map()
        cmds = commands()
        demon = cmds.index("DEMONPC0")
        raw = bytes(
            [
                0x7F,
                demon,
                2,  # timing slot
                0,
                5,
                cmap.index("A"),
                0x7F,
                0x00,
            ]
        )
        conv = tokens_to_conversation(11, decode_tokens(raw))
        self.assertEqual(
            conv["nodes"]["p0"]["events"],
            [{"op": "demo_order", "target": "npc0", "slot": 2, "value": 5}],
        )

    def test_demo_token_counts_match_imported_events(self) -> None:
        from asset_pipeline.dialogue import count_demo_tokens, count_events_in_conversation

        cmap = char_map()
        cmds = commands()
        demon = cmds.index("DEMONPC0")
        fun = cmds.index("MSGCONTENTS_FUN")
        plr = cmds.index("DEMOPLR")
        raw = bytes(
            [
                0x7F,
                demon,
                0,
                0,
                3,  # manpu smile
                0x7F,
                fun,  # set_emote
                0x7F,
                demon,
                1,
                0,
                2,  # demo_order timing
                0x7F,
                plr,
                0,
                0,
                254,  # demo_order player
                cmap.index("Z"),
                0x7F,
                0x00,
            ]
        )
        tokens = decode_tokens(raw)
        expected = count_demo_tokens(tokens)
        conv = tokens_to_conversation(12, tokens)
        imported = count_events_in_conversation(conv)
        self.assertEqual(expected, {"manpu": 1, "set_emote": 1, "demo_order": 2})
        self.assertEqual(imported, expected)

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
