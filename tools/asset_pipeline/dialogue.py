from __future__ import annotations

import json
import struct
from pathlib import Path
from typing import Any, Optional

from .config import PipelineConfig

_CODEC: Optional[dict[str, Any]] = None
CHUNK = 256
SUBS = {
    "STR_PLAYERNAME": "{player}",
    "STR_TALKNAME": "{speaker}",
    "STR_TAIL": "{catchphrase}",
    "STR_YEAR": "{year}",
    "STR_MONTH": "{month}",
    "STR_WEEK": "{weekday}",
    "STR_DAY": "{day}",
    "STR_HOUR": "{hour}",
    "STR_MIN": "{minute}",
    "STR_SEC": "{second}",
    "STR_COUNTRYNAME": "{town}",
    "STR_ISLANDNAME": "{island}",
    "STR_RNDNUM": "{rand}",
    "STR_AMPM": "{ampm}",
    "STR_ITEM0": "{item0}",
    "STR_ITEM1": "{item1}",
    "STR_ITEM2": "{item2}",
    "STR_ITEM3": "{item3}",
    "STR_ITEM4": "{item4}",
    "STR_DETERMINATION": "{ok}",
    "STR_MAIL": "{mail}",
}
for _i in range(20):
    SUBS[f"STR_FREE{_i}"] = "{free%d}" % _i

PAGE_BREAKS = {"BTN", "BTN2", "MSGCLEAR", "MSGCONTINUE"}
END_CMDS = {"MSGEND", "MSGTIMEEND"}


def _codec() -> dict[str, Any]:
    global _CODEC
    if _CODEC is None:
        path = Path(__file__).with_name("ac_msg_codec.json")
        _CODEC = json.loads(path.read_text(encoding="utf-8"))
    return _CODEC


def char_map() -> list[str]:
    return list(_codec()["char_map"])


def commands() -> list[str]:
    return list(_codec()["commands"])


def cont_sizes() -> list[int]:
    return list(_codec()["cont_sizes"])


def msg_id(msg_no: int) -> str:
    return f"msg_{msg_no}"


def decode_tokens(data: bytes) -> list[dict[str, Any]]:
    cmap = char_map()
    cmds = commands()
    sizes = cont_sizes()
    tokens: list[dict[str, Any]] = []
    i = 0
    n = len(data)
    while i < n:
        b = data[i]
        if b == 0x7F:
            if i + 1 >= n:
                break
            kind = data[i + 1]
            if kind >= len(sizes) or kind >= len(cmds):
                tokens.append({"type": "cmd", "name": f"UNK_{kind:02X}", "args": []})
                i += 2
                continue
            size = sizes[kind]
            args = list(data[i + 2 : i + size])
            tokens.append({"type": "cmd", "name": cmds[kind], "args": args})
            i += size
            continue
        if b < len(cmap):
            tokens.append({"type": "text", "text": cmap[b]})
        i += 1
    return tokens


def _u16(args: list[int], index: int = 0) -> int:
    if index + 1 >= len(args):
        return 0
    return (args[index] << 8) | args[index + 1]


def _u16_list(args: list[int], count: int) -> list[int]:
    out: list[int] = []
    for i in range(count):
        out.append(_u16(args, i * 2))
    return out


## Default `mFont` char scale unit is 32 (= 1.0). CHARSCALE applies to the next glyph only.
_DEFAULT_SCALE = 32


def _style_tag_color(rgb: tuple[int, int, int]) -> str:
    return "{c:%d,%d,%d}" % rgb


def _style_tag_scale(scale: int) -> str:
    return "{s:%d}" % scale


def tokens_to_styled_text(tokens: list[dict[str, Any]]) -> str:
    """Flatten tokens to text, keeping TEXTCOLOR / CHARSCALE / COLORCHARS / LINESCALE.

    Markup (expanded by `MessageWindowChrome` at draw time):
    - `{c:r,g,b}` sticky colour until the next colour tag
    - `{s:n}` sticky scale (`n/32`) until the next scale tag
    """
    parts: list[str] = []
    color: Optional[tuple[int, int, int]] = None
    ## Drawn scale for the open `{s:}` run.
    scale = _DEFAULT_SCALE
    ## LINESCALE is sticky for the sentence; CHARSCALE overrides one glyph then falls back.
    line_scale = _DEFAULT_SCALE
    pending_char_scale: Optional[int] = None
    colorchars_left = 0
    colorchars_rgb: Optional[tuple[int, int, int]] = None
    saved_color: Optional[tuple[int, int, int]] = None

    def set_color(rgb: Optional[tuple[int, int, int]]) -> None:
        nonlocal color
        if rgb == color:
            return
        color = rgb
        if rgb is not None:
            parts.append(_style_tag_color(rgb))

    def set_scale(val: int) -> None:
        nonlocal scale
        val = max(1, int(val))
        if val == scale:
            return
        scale = val
        parts.append(_style_tag_scale(val))

    def write_text(ch: str) -> None:
        nonlocal pending_char_scale, colorchars_left, colorchars_rgb, saved_color
        use_scale = pending_char_scale if pending_char_scale is not None else line_scale
        pending_char_scale = None
        set_scale(use_scale)
        if colorchars_left > 0 and colorchars_rgb is not None:
            set_color(colorchars_rgb)
            parts.append(ch)
            colorchars_left -= 1
            if colorchars_left == 0:
                set_color(saved_color if saved_color is not None else (50, 60, 50))
                colorchars_rgb = None
                saved_color = None
            return
        parts.append(ch)

    for tok in tokens:
        if tok["type"] == "text":
            write_text(str(tok.get("text", "")))
            continue
        name = str(tok["name"])
        args: list[int] = list(tok.get("args") or [])
        if name in SUBS:
            write_text(SUBS[name])
            continue
        if name == "SPACE" and args:
            write_text(" " * max(int(args[0]), 0))
            continue
        if name == "TEXTCOLOR" and len(args) >= 3:
            set_color((int(args[0]), int(args[1]), int(args[2])))
            continue
        if name == "CHARSCALE" and args:
            pending_char_scale = int(args[0])
            continue
        if name == "LINESCALE" and args:
            line_scale = max(1, int(args[0]))
            pending_char_scale = None
            set_scale(line_scale)
            continue
        if name == "COLORCHARS" and len(args) >= 4:
            saved_color = color
            colorchars_rgb = (int(args[0]), int(args[1]), int(args[2]))
            colorchars_left = max(0, int(args[3]))
            continue

    if scale != _DEFAULT_SCALE:
        parts.append(_style_tag_scale(_DEFAULT_SCALE))
    return "".join(parts)


## `MSGCONTENTS_*` → `set_emote` names consumed by talk hosts / intro directors.
_CONTENTS_EMOTE = {
    "MSGCONTENTS_NORMAL": "normal",
    "MSGCONTENTS_ANGRY": "angry",
    "MSGCONTENTS_SAD": "sad",
    "MSGCONTENTS_FUN": "laugh",
    "MSGCONTENTS_SLEEPY": "sleepy",
    "MSGCONTENTS_GLOOMY": "sad",
}

## `DEMON*` / `DEMOPLR` → `mDemo` order channel (`mMsg_Main_Cursol_SetDemoOrder_*`).
_DEMO_ORDER_TARGET = {
    "DEMOPLR": "player",
    "DEMONPC0": "npc0",
    "DEMONPC1": "npc1",
    "DEMONPC2": "npc2",
    "DEMONPCQST": "quest",
}

## `aNPC_check_manpu_demoCode` / `eff_idx[]` — DEMONPC0 slot 0 only.
## Keep in sync with `NpcManpu.CODE_CLIPS` (GDScript).
_MANPU_CODE_NAMES = {
    1: "muka1",
    2: "gaaan1",
    3: "smile1",
    4: "ha1",
    5: "punpun1",
    6: "a1",
    7: "aseru1",
    8: "buruburu1",
    9: "goukyu1",
    10: "happy1",
    11: "hate1",
    12: "hirameki1",
    13: "hyuuu1",
    14: "lovelove1",
    15: "muuuuu1",
    16: "otikomu1",
    17: "shituren1",
    18: "warudakumi1",
    19: "neboke1",
    20: "love1",
    21: "niko1",
    22: "musu1",
    23: "komari1",
    24: "smile_d1",
    25: "gaaan_d1",
    26: "hirameki_d1",
    27: "ha_d1",
    28: "musu_d1",
    29: "niko_d1",
    30: "komari_d1",
    31: "hate_d1",
    32: "keirei1",
    33: "punpun_r1",
    34: "musu_r1",
    35: "hyuuu_r1",
    36: "a_r1",
    37: "akireru_r1",
    38: "matarou_r1",
    39: "gekido_r1",
    40: "ha_e1",
    41: "kieeeei1",
    42: "a2_r1",
    0xFE: "reset_sit",
    0xFF: "reset",
}


def manpu_name_for_code(code: int) -> str:
    return str(_MANPU_CODE_NAMES.get(int(code), ""))


def count_demo_tokens(tokens: list[dict[str, Any]]) -> dict[str, int]:
    """Raw control-code tallies used to verify import does not drop manpu."""
    out = {"manpu": 0, "set_emote": 0, "demo_order": 0}
    for tok in tokens:
        if tok.get("type") != "cmd":
            continue
        name = str(tok.get("name", ""))
        args: list[int] = list(tok.get("args") or [])
        if name in _CONTENTS_EMOTE:
            out["set_emote"] += 1
            continue
        target = _DEMO_ORDER_TARGET.get(name)
        if target is None or len(args) < 3:
            continue
        slot = int(args[0])
        if name == "DEMONPC0" and slot == 0:
            out["manpu"] += 1
        else:
            out["demo_order"] += 1
    return out


def count_events_in_conversation(conv: dict[str, Any]) -> dict[str, int]:
    out = {"manpu": 0, "set_emote": 0, "demo_order": 0}
    nodes = conv.get("nodes") or {}
    if not isinstance(nodes, dict):
        return out
    for node in nodes.values():
        if not isinstance(node, dict):
            continue
        for ev in node.get("events") or []:
            if not isinstance(ev, dict):
                continue
            op = str(ev.get("op", ""))
            if op in out:
                out[op] += 1
    return out


def _page_event_from_token(name: str, args: list[int]) -> Optional[dict[str, Any]]:
    ## Face mood window colour family (`MSGCONTENTS_*`).
    emote = _CONTENTS_EMOTE.get(name)
    if emote is not None:
        return {"op": "set_emote", "name": emote}

    target = _DEMO_ORDER_TARGET.get(name)
    if target is None or len(args) < 3:
        return None
    order_idx = int(args[0])
    order_val = (int(args[1]) << 8) | (int(args[2]) & 0xFF)
    ## Slot 0 on NPC0 is manpu (`aNPC_check_manpu_demoCode`).
    if name == "DEMONPC0" and order_idx == 0:
        event: dict[str, Any] = {"op": "manpu", "code": order_val}
        clip = manpu_name_for_code(order_val)
        if clip:
            event["name"] = clip
        return event
    ## Timing / give / quest / player demo slots — keep so nothing is dropped.
    return {
        "op": "demo_order",
        "target": target,
        "slot": order_idx,
        "value": order_val,
    }


def tokens_to_conversation(
    msg_no: int, tokens: list[dict[str, Any]], select: Optional[list[str]] = None
) -> dict[str, Any]:
    pages: list[tuple[str, list[dict[str, Any]]]] = []
    page_tokens: list[dict[str, Any]] = []
    page_events: list[dict[str, Any]] = []
    next_force = ""
    next_by_choice: list[str] = ["", "", "", "", "", ""]
    next_random: list[str] = []
    choice_ids: list[int] = []
    open_choice = False

    def flush() -> None:
        nonlocal page_tokens, page_events
        text = tokens_to_styled_text(page_tokens).strip("\n")
        events = list(page_events)
        page_tokens = []
        page_events = []
        if text != "" or events:
            pages.append((text, events))

    for tok in tokens:
        if tok["type"] == "text":
            page_tokens.append(tok)
            continue
        name = str(tok["name"])
        args: list[int] = list(tok.get("args") or [])
        if name in SUBS:
            page_tokens.append(tok)
            continue
        if name in PAGE_BREAKS:
            flush()
            continue
        if name in END_CMDS:
            flush()
            break
        event = _page_event_from_token(name, args)
        if event is not None:
            page_events.append(event)
            continue
        if name == "OPENCHOICE":
            open_choice = True
            continue
        if name == "SETFORCEMSG":
            n = _u16(args)
            if n != 0xFFFF:
                next_force = msg_id(n)
            continue
        if name.startswith("SETNEXTMSG") and name[-1].isdigit() and "RND" not in name:
            slot = int(name[-1])
            n = _u16(args)
            next_by_choice[slot] = "" if n == 0xFFFF else msg_id(n)
            continue
        if name.startswith("SETNEXTMSGRND") and name[-1].isdigit():
            count = int(name[-1])
            next_random = [msg_id(n) for n in _u16_list(args, count) if n != 0xFFFF]
            continue
        if name.startswith("SETSELSTR") and name[-1].isdigit():
            count = int(name[-1])
            choice_ids = _u16_list(args, count)
            continue
        if name == "SPACE" and args:
            page_tokens.append(tok)
            continue
        if name in ("TEXTCOLOR", "CHARSCALE", "LINESCALE", "COLORCHARS"):
            page_tokens.append(tok)
            continue

    flush()
    if not pages:
        pages = [("", [])]

    nodes: dict[str, Any] = {}
    start = "p0"
    for i, (page, events) in enumerate(pages):
        nid = f"p{i}"
        if page == "" and events:
            ## Demo codes between pages (e.g. smile right before OPENCHOICE).
            node: dict[str, Any] = {"type": "event", "events": events}
        else:
            node = {"type": "line", "text": page.replace("\r", "")}
            if events:
                node["events"] = events
        if i + 1 < len(pages):
            node["next"] = f"p{i + 1}"
        nodes[nid] = node
    last_id = f"p{len(pages) - 1}"
    last = nodes[last_id]
    labels = _choice_labels(choice_ids, select)
    if open_choice and labels:
        options = []
        for i, label in enumerate(labels):
            dest = next_by_choice[i] if i < len(next_by_choice) else ""
            opt: dict[str, Any] = {"text": label, "goto": dest or next_force}
            options.append(opt)
        nodes["choice"] = {"type": "choice", "options": options}
        last["next"] = "choice"
    elif next_random:
        nodes["rng"] = {
            "type": "random",
            "options": [{"goto": dest, "weight": 1} for dest in next_random],
        }
        last["next"] = "rng"
    elif next_force:
        last["next"] = next_force
    elif any(next_by_choice):
        last["next"] = next(dest for dest in next_by_choice if dest)

    return {
        "id": msg_id(msg_no),
        "msg_no": msg_no,
        "start": start,
        "nodes": nodes,
    }


def _choice_labels(ids: list[int], select: Optional[list[str]]) -> list[str]:
    labels: list[str] = []
    for i, sid in enumerate(ids):
        if select is not None and 0 <= sid < len(select) and select[sid]:
            labels.append(select[sid])
        else:
            labels.append(f"{{choice:{sid}}}")
    return labels


def decode_table(data: bytes, table: bytes) -> list[bytes]:
    entries: list[bytes] = []
    last = 0
    for i in range(0, len(table), 4):
        chunk = table[i : i + 4]
        if len(chunk) < 4:
            break
        end = struct.unpack(">I", chunk)[0]
        if end == 0:
            entries.append(b"")
            continue
        entries.append(data[last:end])
        last = end
    return entries


def decode_strings(data: bytes, table: bytes) -> list[str]:
    out: list[str] = []
    for raw in decode_table(data, table):
        if not raw:
            out.append("")
            continue
        parts: list[str] = []
        for tok in decode_tokens(raw):
            if tok["type"] == "text":
                parts.append(tok["text"])
            elif tok["name"] in SUBS:
                parts.append(SUBS[tok["name"]])
        out.append("".join(parts).strip())
    return out


def find_pair(cfg: PipelineConfig, stem: str) -> Optional[tuple[Path, Path]]:
    names = (f"{stem}.bin", f"{stem}_table.bin")
    roots = [
        cfg.extracted_disc / "files",
        cfg.extracted_archives / "forest_2nd" / "data",
        cfg.game_files / "files" if cfg.game_files.is_dir() else None,
        cfg.game_files if cfg.game_files.is_dir() else None,
    ]
    for root in roots:
        if root is None:
            continue
        data = root / names[0]
        table = root / names[1]
        if data.is_file() and table.is_file():
            return data, table
    return None


def convert_dialogue(cfg: PipelineConfig) -> dict[str, Any]:
    pair = find_pair(cfg, "message_data")
    if pair is None:
        return {
            "error": "message_data.bin / message_data_table.bin not found. Extract the disc (files/) first.",
            "converted": 0,
        }
    data_path, table_path = pair
    select_pair = find_pair(cfg, "select_data")
    string_pair = find_pair(cfg, "string_data")
    select = decode_strings(select_pair[0].read_bytes(), select_pair[1].read_bytes()) if select_pair else []
    strings = decode_strings(string_pair[0].read_bytes(), string_pair[1].read_bytes()) if string_pair else []
    raw_entries = decode_table(data_path.read_bytes(), table_path.read_bytes())
    conversations: list[dict[str, Any]] = []
    expected = {"manpu": 0, "set_emote": 0, "demo_order": 0}
    imported = {"manpu": 0, "set_emote": 0, "demo_order": 0}
    for i, raw in enumerate(raw_entries):
        if not raw:
            continue
        tokens = decode_tokens(raw)
        for key, n in count_demo_tokens(tokens).items():
            expected[key] += n
        conv = tokens_to_conversation(i, tokens, select)
        for key, n in count_events_in_conversation(conv).items():
            imported[key] += n
        conversations.append(conv)

    dropped = {
        key: expected[key] - imported[key]
        for key in expected
        if expected[key] != imported[key]
    }
    if dropped:
        parts = ", ".join(
            f"{k} expected {expected[k]} got {imported[k]}" for k in sorted(dropped)
        )
        return {
            "error": f"dialogue demo/manpu import mismatch: {parts}",
            "converted": 0,
            "manpu_events": imported["manpu"],
            "set_emote_events": imported["set_emote"],
            "demo_order_events": imported["demo_order"],
        }

    out_dir = cfg.godot_generated / "dialogue"
    out_dir.mkdir(parents=True, exist_ok=True)
    files: list[str] = []
    for chunk_i in range(0, len(conversations), CHUNK):
        chunk = conversations[chunk_i : chunk_i + CHUNK]
        name = f"{chunk_i:04d}.json"
        (out_dir / name).write_text(
            json.dumps({"conversations": chunk}, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        files.append(name)
    if select:
        (out_dir / "select.json").write_text(
            json.dumps(select, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    if strings:
        (out_dir / "strings.json").write_text(
            json.dumps(strings, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    index = {
        "count": len(conversations),
        "chunk_size": CHUNK,
        "files": files,
        "select_count": len(select),
        "string_count": len(strings),
        "manpu_events": imported["manpu"],
        "set_emote_events": imported["set_emote"],
        "demo_order_events": imported["demo_order"],
        "source": str(data_path),
    }
    (out_dir / "index.json").write_text(
        json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return {
        "converted": len(conversations),
        "output": str(out_dir),
        "files": len(files),
        "select_count": len(select),
        "string_count": len(strings),
        "manpu_events": imported["manpu"],
        "set_emote_events": imported["set_emote"],
        "demo_order_events": imported["demo_order"],
    }
