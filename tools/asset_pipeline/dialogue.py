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


def tokens_to_conversation(
    msg_no: int, tokens: list[dict[str, Any]], select: Optional[list[str]] = None
) -> dict[str, Any]:
    pages: list[str] = []
    buf: list[str] = []
    next_force = ""
    next_by_choice: list[str] = ["", "", "", "", "", ""]
    next_random: list[str] = []
    choice_ids: list[int] = []
    open_choice = False

    def flush() -> None:
        text = "".join(buf).strip("\n")
        buf.clear()
        if text != "":
            pages.append(text)

    for tok in tokens:
        if tok["type"] == "text":
            buf.append(tok["text"])
            continue
        name = str(tok["name"])
        args: list[int] = list(tok.get("args") or [])
        if name in SUBS:
            buf.append(SUBS[name])
            continue
        if name in PAGE_BREAKS:
            flush()
            continue
        if name in END_CMDS:
            flush()
            break
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
            buf.append(" " * max(int(args[0]), 0))

    flush()
    if not pages:
        pages = [""]

    nodes: dict[str, Any] = {}
    start = "p0"
    for i, page in enumerate(pages):
        nid = f"p{i}"
        node: dict[str, Any] = {"type": "line", "text": page.replace("\r", "")}
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
    for i, raw in enumerate(raw_entries):
        if not raw:
            continue
        conversations.append(tokens_to_conversation(i, decode_tokens(raw), select))

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
    }
