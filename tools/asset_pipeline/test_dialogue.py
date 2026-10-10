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

    def test_btn_mid_page_keeps_writing_the_same_page(self) -> None:
        def text(t: str) -> list:
            return [{"type": "text", "text": ch} for ch in t]

        def cmd(name: str) -> dict:
            return {"type": "cmd", "name": name, "args": []}

        tokens = text("Hm.") + [cmd("BTN")] + text("\nOK!") + [cmd("BTN"), cmd("MSGCLEAR")] + text("Bye") + [cmd("MSGEND")]
        conv = tokens_to_conversation(9, tokens)
        nodes = conv["nodes"]
        self.assertEqual(nodes["p0"]["text"], "Hm.{btn}\nOK!")
        self.assertEqual(nodes["p1"]["text"], "Bye")

    def test_a_choice_inside_a_message_carries_on_after_the_pick(self) -> None:
        def text(t: str) -> list:
            return [{"type": "text", "text": ch} for ch in t]

        def cmd(name: str, args: list | None = None) -> dict:
            return {"type": "cmd", "name": name, "args": args or []}

        select = ["Yes", "No", "Stereo", "Mono"]
        tokens = (
            text("Which?") + [cmd("SETSELSTR2", [0, 2, 0, 3]), cmd("BTN"), cmd("OPENCHOICE")]
            + text("\n") + [cmd("MSGCLEAR")] + text("{ok} it is. Sure?")
            + [cmd("SETSELSTR2", [0, 0, 0, 1]), cmd("BTN"), cmd("OPENCHOICE"), cmd("SETNEXTMSG0", [0, 5]),
               cmd("SETNEXTMSG1", [0, 6])]
            + text("\n") + [cmd("MSGCONTINUE")]
        )
        nodes = tokens_to_conversation(4, tokens, select)["nodes"]
        self.assertEqual(nodes["p0"]["next"], "c0")
        self.assertEqual([o["text"] for o in nodes["c0"]["options"]], ["Stereo", "Mono"])
        self.assertEqual({o["goto"] for o in nodes["c0"]["options"]}, {"p1"})
        self.assertEqual(nodes["p1"]["next"], "choice")
        self.assertEqual([o["goto"] for o in nodes["choice"]["options"]], [msg_id(5), msg_id(6)])
        self.assertNotIn("open_choice", nodes["p1"])

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

    def test_line_style_resets_at_a_newline(self) -> None:
        ## Each line is a new `mFontSentence`: colour and line scale do not carry over.
        def text(t: str) -> list:
            return [{"type": "text", "text": ch} for ch in t]

        def cmd(name: str, args: list | None = None) -> dict:
            return {"type": "cmd", "name": name, "args": args or []}

        colored = tokens_to_conversation(3, [cmd("TEXTCOLOR", [150, 150, 150])] + text("A\nB") + [cmd("MSGEND")])
        body = colored["nodes"]["p0"]["text"]
        self.assertIn("{c:150,150,150}A", body)
        self.assertIn("{c:50,60,50}\nB", body)
        scaled = tokens_to_conversation(4, [cmd("LINESCALE", [64])] + text("A\nB") + [cmd("MSGEND")])
        self.assertIn("{s:64}A{s:32}\nB", scaled["nodes"]["p0"]["text"])
        ## CHARSCALE multiplies the line scale (16/32 * 64/32 = 1).
        both = tokens_to_conversation(
            5, [cmd("LINESCALE", [64]), cmd("CHARSCALE", [16])] + text("A") + [cmd("MSGEND")]
        )
        self.assertIn("{s:32}A", both["nodes"]["p0"]["text"])

    def test_cursor_codes_become_marks_and_branches(self) -> None:
        def text(t: str) -> list:
            return [{"type": "text", "text": ch} for ch in t]

        def cmd(name: str, args: list | None = None) -> dict:
            return {"type": "cmd", "name": name, "args": args or []}

        voiced = tokens_to_conversation(6, [cmd("MSGCONTENTS_FUN")] + text("Y") + [cmd("MSGEND")])
        self.assertIn("{vs:3}", voiced["nodes"]["p0"]["text"])
        self.assertEqual(voiced["nodes"]["p0"]["events"], [{"op": "set_emote", "name": "laugh"}])
        cut = tokens_to_conversation(
            7, [cmd("SNDCUT", [0])] + text(".") + [cmd("SNDCUT", [1]), cmd("MSGEND")]
        )
        self.assertEqual(cut["nodes"]["p0"]["text"], "{cut:1}.{cut:0}")
        cancel = tokens_to_conversation(8, text("Oh") + [cmd("ABLECANCEL"), cmd("MSGEND")])
        self.assertIn("{can}", cancel["nodes"]["p0"]["text"])
        forced = tokens_to_conversation(9, text("Hi") + [cmd("FORCENEXT"), cmd("MSGCONTINUE")])
        self.assertTrue(forced["nodes"]["p0"]["force_next"])
        sex = tokens_to_conversation(
            10, text("I") + [cmd("MALEFEMALECHK", [0, 10, 0, 11]), cmd("MSGCONTINUE")]
        )
        self.assertEqual(sex["nodes"]["p0"]["next_male"], msg_id(10))
        self.assertEqual(sex["nodes"]["p0"]["next_female"], msg_id(11))
        select = ["Yes", "No"]
        choice = tokens_to_conversation(
            11,
            text("Go?") + [cmd("SETSELSTR2", [0, 0, 0, 1]), cmd("SELNOB"), cmd("OPENCHOICE"),
                           cmd("SETNEXTMSG0", [0, 1]), cmd("SETNEXTMSG1", [0, 2]),
                           cmd("FORCENEXT"), cmd("MSGCONTINUE")],
            select,
        )
        self.assertTrue(choice["nodes"]["choice"]["b_last"])

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


class DialogueBgmEventTests(unittest.TestCase):
    def test_bgm_make_and_delete_become_events(self) -> None:
        from asset_pipeline.dialogue import _page_event_from_token

        self.assertEqual(
            _page_event_from_token("BGMMAKE", [2, 0]), {"op": "bgm_make", "bgm": 2, "stop": 0}
        )
        self.assertEqual(
            _page_event_from_token("BGMDELETE", [1, 1]), {"op": "bgm_delete", "bgm": 1, "stop": 1}
        )


class MailTextTests(unittest.TestCase):
    def _raw(self, text: str) -> bytes:
        cmap = char_map()
        return bytes(cmap.index(c) for c in text)

    def test_header_line_break_is_the_name_slot(self) -> None:
        from asset_pipeline.dialogue import mail_text

        self.assertEqual(mail_text(self._raw("Dear \n,"), header=True), "Dear {name},")
        self.assertEqual(mail_text(self._raw("\n, FYI:"), header=True), "{name}, FYI:")

    def test_header_without_one_break_puts_the_name_last(self) -> None:
        from asset_pipeline.dialogue import mail_text

        self.assertEqual(mail_text(self._raw("Hi "), header=True), "Hi {name}")

    def test_body_keeps_leading_breaks(self) -> None:
        from asset_pipeline.dialogue import mail_text

        self.assertEqual(mail_text(self._raw("\nHello  ")), "\nHello")
