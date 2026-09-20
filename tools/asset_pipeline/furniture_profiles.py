"""Per-furniture behaviour flags from the decomp's `aFTR_PROFILE` tables.

`src/furniture/ac_*.c` define one profile per piece (`iam_sum_chair01` …). The last seven
fields before the vtable are `shape`, `move_bg_type`, `check_rotation`, `kankyo_map`,
`contact_action` and `interaction_type`; those decide how a piece is footprinted, sat on,
opened, switched or played. Written to the gitignored
`assets/generated/environment/fg/furniture_profiles.json`, keyed by visual id (`int_*`).
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from .config import PipelineConfig
from .fgdata import _guess_decomp

## `enum` order in `include/ac_furniture.h` (`aFTR_INTERACTION_*` are bit flags).
INTERACTION_BITS = {
    "STORAGE_DRAWERS": 0x1,
    "STORAGE_WARDROBE": 0x2,
    "STORAGE_CLOSET": 0x4,
    "MUSIC_DISK": 0x8,
    "NO_COLLISION": 0x10,
    "HANIWA": 0x20,
    "FISH": 0x40,
    "INSECT": 0x80,
    "MANNEKIN": 0x100,
    "UMBRELLA": 0x200,
    "FOSSIL": 0x400,
    "FAMICOM": 0x800,
    "START_DISABLED": 0x1000,
    "FAMICOM_ITEM": 0x2000,
    "RADIO_AEROBICS": 0x4000,
    "TOGGLE": 0x8000,
}
CONTACT_BITS = {
    "CHAIR_UNIDIRECTIONAL": 0x1,
    "CHAIR_MULTIDIRECTIONAL": 0x2,
    "CHAIR_SOFA": 0x4,
    "BED_SINGLE": 0x8,
    "BED_DOUBLE": 0x10,
}

_PROFILE_RE = re.compile(r"aFTR_PROFILE\s+iam_([A-Za-z0-9_]+)\s*=\s*\{(.*?)\n\};", re.S)


def convert_furniture_profiles(cfg: PipelineConfig, decomp_root: Path | None = None) -> dict[str, Any]:
    decomp = decomp_root or cfg.decomp_root or _guess_decomp(cfg)
    if decomp is None:
        return {"converted": 0, "error": "ac-decomp not found"}
    profiles = parse_profiles(decomp / "src" / "furniture")
    if not profiles:
        return {"converted": 0, "error": "no aFTR_PROFILE found under src/furniture"}
    out_dir = cfg.godot_generated / "environment" / "fg"
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / "furniture_profiles.json"
    path.write_text(json.dumps({"source": "src/furniture/ac_*.c", "profiles": profiles}, separators=(",", ":")) + "\n")
    return {"converted": 1, "profiles": len(profiles), "path": str(path)}


def parse_profiles(furniture_dir: Path) -> dict[str, dict[str, Any]]:
    out: dict[str, dict[str, Any]] = {}
    for path in sorted(furniture_dir.glob("ac_*.c")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for match in _PROFILE_RE.finditer(text):
            row = parse_profile_body(match.group(2))
            if row is not None:
                out[f"int_{match.group(1)}"] = row
    return out


def parse_profile_body(body: str) -> dict[str, Any] | None:
    body = re.sub(r"//[^\n]*", "", body)
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    fields = [f.strip() for f in body.replace("\n", " ").split(",")]
    fields = [f for f in fields if f]
    if len(fields) < 9:
        return None
    ## Counted from the end: … shape, move_bg, check_rotation, kankyo, contact, interaction, vtable.
    shape, _move_bg, check_rotation, _kankyo, contact, interaction, vtable = fields[-7:]
    shape_name = shape.replace("aFTR_SHAPE_", "")
    if shape_name not in ("TYPEA", "TYPEC") and not shape_name.startswith("TYPEB_"):
        return None
    return {
        "shape": shape_name,
        "check_rotation": 1 if _num(check_rotation) else 0,
        "contact": _flags(contact, "aFTR_CONTACT_ACTION_", CONTACT_BITS),
        "interaction": _flags(interaction, "aFTR_INTERACTION_", INTERACTION_BITS),
        ## A non-NULL vtable means the piece has its own move / draw proc — the ones that
        ## visibly react when their switch flips (lamps, TVs, stereos, clocks, …).
        "vtable": 1 if vtable not in ("NULL", "0") else 0,
    }


def _num(token: str) -> int:
    try:
        return int(token, 0)
    except ValueError:
        return 0


def _flags(expr: str, prefix: str, table: dict[str, int]) -> list[str]:
    out: list[str] = []
    for part in re.split(r"[|+]", expr):
        part = part.strip()
        if part.startswith(prefix):
            name = part[len(prefix) :]
            if name in table:
                out.append(name)
        elif _num(part):
            value = _num(part)
            out.extend(name for name, bit in table.items() if value & bit)
    return out
