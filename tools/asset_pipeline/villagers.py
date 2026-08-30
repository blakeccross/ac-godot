"""Build `data/villagers/*.tres` from decomp NPC tables (names, looks, grow).

Display names are allowed. Do not copy C structs or Nintendo dialogue banks.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Optional

from .config import PipelineConfig
from .fgdata import _guess_decomp

NPC_NUM = 236
LOOKS = ["normal", "peppy", "lazy", "jock", "cranky", "snooty"]
LOOKS_ENUM = {
    "mNpc_LOOKS_GIRL": 0,
    "mNpc_LOOKS_KO_GIRL": 1,
    "mNpc_LOOKS_BOY": 2,
    "mNpc_LOOKS_SPORT_MAN": 3,
    "mNpc_LOOKS_GRIM_MAN": 4,
    "mNpc_LOOKS_NANIWA_LADY": 5,
}
GROW = {
    "mNpc_GROW_STARTER": "starter",
    "mNpc_GROW_MOVE_IN": "move_in",
    "mNpc_GROW_ISLANDER": "islander",
}
PREFIX_SPECIES = {
    "ant": "anteater",
    "bea": "bear",
    "brd": "bird",
    "bul": "bull",
    "cat": "cat",
    "cbr": "cub",
    "chn": "chicken",
    "cow": "cow",
    "crd": "alligator",
    "dog": "dog",
    "duk": "duck",
    "elp": "elephant",
    "flg": "frog",
    "goa": "goat",
    "gor": "gorilla",
    "hip": "hippo",
    "hrs": "horse",
    "kal": "koala",
    "kgr": "kangaroo",
    "lon": "lion",
    "mus": "mouse",
    "oct": "octopus",
    "ost": "ostrich",
    "pbr": "eagle",
    "pgn": "penguin",
    "pig": "pig",
    "rbt": "rabbit",
    "rhn": "rhino",
    "shp": "sheep",
    "squ": "squirrel",
    "tig": "tiger",
    "wol": "wolf",
    "wls": "wolf",
}
DISPLAY_SPECIAL = {
    "wart_jr": "Wart Jr.",
    "sue_e": "Sue E.",
    "t_bone": "T-Bone",
    "ohare": "O'Hare",
}
# Hand-authored catchphrases already in the repo. Generator keeps them.
CATCHPHRASES = {
    "filbert": "bucko",
    "rosie": "silly",
    "bunnie": "teehee",
    "biskit": "dawg",
    "midge": "tweedle",
    "ribbot": "zzrrbbitt",
    "dora": "squeaky",
    "gruff": "blehhee",
    "lobo": "ah-rooooo",
    "sprocket": "zort",
    "friga": "brr",
    "olivia": "purrr",
}


def generate_villagers(cfg: PipelineConfig, decomp_root: Path | None = None) -> dict[str, Any]:
    decomp = decomp_root or cfg.decomp_root or _guess_decomp(cfg)
    if decomp is None or not (decomp / "include" / "m_name_table.h").is_file():
        return {"written": 0, "error": "ac-decomp not found"}
    roster = parse_roster(decomp)
    dest = cfg.project_root / "data" / "villagers"
    dest.mkdir(parents=True, exist_ok=True)
    written = 0
    for entry in roster:
        _write_tres(dest / f"{entry['id']}.tres", entry)
        written += 1
    return {"written": written, "count": len(roster), "starters": sum(1 for e in roster if e["starter"])}


def parse_roster(decomp: Path) -> list[dict[str, Any]]:
    names = _parse_npc_names(decomp / "include" / "m_name_table.h")
    looks = _parse_looks(decomp / "src" / "game" / "m_name_table.c")
    grow = _parse_grow(decomp / "src" / "data" / "npc" / "grow_list.c")
    prefixes = _parse_draw_prefixes(decomp / "src" / "data" / "npc" / "npc_draw_data.c")
    houses = _parse_house_list(decomp / "src" / "data" / "npc" / "house_list.c")
    if len(names) != NPC_NUM:
        raise ValueError(f"expected {NPC_NUM} NPCs, got {len(names)}")
    roster: list[dict[str, Any]] = []
    for i, raw in enumerate(names):
        vid = _villager_id(raw)
        look = looks[i] if i < len(looks) else 2
        grow_kind = grow[i] if i < len(grow) else "starter"
        prefix = prefixes[i] if i < len(prefixes) else ""
        species = PREFIX_SPECIES.get(prefix, prefix if prefix else "unknown")
        house = houses[i] if i < len(houses) else {}
        roster.append(
            {
                "npc_idx": i,
                "id": vid,
                "display_name": DISPLAY_SPECIAL.get(vid, _title_name(vid)),
                "species": species,
                "prefix": prefix,
                "looks": look,
                "personality": LOOKS[look] if 0 <= look < len(LOOKS) else "lazy",
                "starter": grow_kind == "starter",
                "islander": grow_kind == "islander",
                "catchphrase": CATCHPHRASES.get(vid, ""),
                "wall_index": int(house.get("wall", 0)),
                "floor_index": int(house.get("floor", 0)),
                "house_type": int(house.get("type", 0)),
                "house_palette": int(house.get("palette", 0)),
            }
        )
    return roster


def _parse_npc_names(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    names: list[str] = []
    for match in re.finditer(r"^#define NPC_([A-Z0-9_]+)\s+\(NPC_START \+ (\d+)\)", text, re.M):
        name, idx = match.group(1), int(match.group(2))
        if name in ("START", "END", "TEST0", "TEST1", "ALL_END"):
            continue
        if idx >= NPC_NUM:
            continue
        while len(names) <= idx:
            names.append("")
        names[idx] = name
    if any(n == "" for n in names) or len(names) < NPC_NUM:
        missing = [i for i, n in enumerate(names) if n == ""]
        raise ValueError(f"incomplete NPC name table, missing {missing[:8]}")
    return names[:NPC_NUM]


def _parse_looks(path: Path) -> list[int]:
    text = path.read_text(encoding="utf-8", errors="replace")
    start = text.find("u8 npc_looks_table")
    if start < 0:
        raise ValueError("npc_looks_table not found")
    block = text[start : text.find("};", start)]
    out: list[int] = []
    for match in re.finditer(r"mNpc_LOOKS_[A-Z_]+", block):
        key = match.group(0)
        if key not in LOOKS_ENUM:
            continue
        out.append(LOOKS_ENUM[key])
        if len(out) >= NPC_NUM:
            break
    if len(out) < NPC_NUM:
        raise ValueError(f"looks table too short: {len(out)}")
    return out[:NPC_NUM]


def _parse_grow(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    out: list[str] = []
    for match in re.finditer(r"mNpc_GROW_[A-Z_]+", text):
        key = match.group(0)
        if key not in GROW:
            continue
        out.append(GROW[key])
        if len(out) >= NPC_NUM:
            break
    if len(out) < NPC_NUM:
        raise ValueError(f"grow list too short: {len(out)}")
    return out[:NPC_NUM]


def _parse_house_list(path: Path) -> list[dict[str, int]]:
    """`npc_house_list`: type, palette, ITM_WALL*, ITM_CARPET* (u8 index = item low byte)."""
    text = path.read_text(encoding="utf-8", errors="replace")
    start = text.find("npc_house_list[]")
    if start < 0:
        raise ValueError("npc_house_list not found")
    block = text[start : text.find("};", start)]
    out: list[dict[str, int]] = []
    row = re.compile(
        r"\{\s*(\d+)\s*,\s*(\d+)\s*,\s*ITM_WALL(\d+)\s*,\s*ITM_CARPET(\d+)\s*,"
    )
    for match in row.finditer(block):
        out.append(
            {
                "type": int(match.group(1)),
                "palette": int(match.group(2)),
                "wall": int(match.group(3)),
                "floor": int(match.group(4)),
            }
        )
        if len(out) >= NPC_NUM:
            break
    if len(out) < NPC_NUM:
        raise ValueError(f"house list too short: {len(out)}")
    return out[:NPC_NUM]


def _parse_draw_prefixes(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    start = text.find("npc_draw_data_tbl[]")
    if start < 0:
        raise ValueError("npc_draw_data_tbl not found")
    # Table continues through special NPCs; villagers are the first NPC_NUM entries.
    block = text[start:]
    prefixes: list[str] = []
    for match in re.finditer(r"&cKF_bs_r_([a-z0-9]+)_(\d+)", block):
        prefixes.append(match.group(1))
        if len(prefixes) >= NPC_NUM:
            break
    if len(prefixes) < NPC_NUM:
        raise ValueError(f"draw table too short: {len(prefixes)}")
    return prefixes[:NPC_NUM]


def _villager_id(enum_name: str) -> str:
    return enum_name.lower()


def _title_name(vid: str) -> str:
    return " ".join(part.capitalize() for part in vid.split("_"))


def _write_tres(path: Path, entry: dict[str, Any]) -> None:
    personality = entry["personality"]
    lines = [
        '[gd_resource type="Resource" script_class="VillagerData" format=3]',
        "",
        '[ext_resource type="Script" path="res://scripts/data/villager_data.gd" id="1"]',
        f'[ext_resource type="Resource" path="res://data/personalities/{personality}.tres" id="2"]',
        "",
        "[resource]",
        'script = ExtResource("1")',
        f'id = &"{entry["id"]}"',
        f'display_name = "{_escape(entry["display_name"])}"',
        f'species = &"{entry["species"]}"',
    ]
    if entry["catchphrase"]:
        lines.append(f'catchphrase = "{_escape(entry["catchphrase"])}"')
    lines.append('personality = ExtResource("2")')
    if entry["islander"]:
        lines.append("islander = true")
    lines.append(f"starter = {'true' if entry['starter'] else 'false'}")
    lines.append(f"wall_index = {int(entry.get('wall_index', 0))}")
    lines.append(f"floor_index = {int(entry.get('floor_index', 0))}")
    lines.append(f"house_type = {int(entry.get('house_type', 0))}")
    lines.append(f"house_palette = {int(entry.get('house_palette', 0))}")
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def _escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"')
