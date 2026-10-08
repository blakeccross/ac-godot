"""Extract per-acre 16×16 collision from `data_bgd` (paired with each `grd_*` mesh).

Original: `mFM_bg_data_c` holds gfx + `collision[16][16]`. Godot stores a compact JSON
sidecar next to the GLB. Do not copy C structs into GDScript.
"""

from __future__ import annotations

import json
import struct
from pathlib import Path
from typing import Any

from .mapfile import MapSymbol
from .rel import RelData

BG_DATA_SIZE = 0x434
OFF_OPAQUE = 0x4
OFF_COLLISION = 0x1C
UNIT_COUNT = 256
## `mFM_bg_sound_source_data_c sound_source[6]` after the collision: `s16 kind, u8 ut_x, u8 ut_z`
## (kind 1 river / waterfall, 2 sea; 0 unused).
OFF_SOUNDS = OFF_COLLISION + UNIT_COUNT * 4
SOUND_COUNT = 6
# mCoBG heights are ×10 GX. Typical grass center is 4 (= 40 GX, one tile).
LAND_COUNTS = 4
HEIGHT_MAX = 31


def decode_unit(raw: int) -> dict[str, int]:
    """Bit layout from `mCoBG_CollisionData_c` comments (MSB first)."""
    return {
        "c": (raw >> 26) & 31,
        "nw": (raw >> 21) & 31,  # top_left
        "sw": (raw >> 16) & 31,  # bot_left
        "se": (raw >> 11) & 31,  # bot_right
        "ne": (raw >> 6) & 31,  # top_right
        "s": (raw >> 31) & 1,
        "a": raw & 63,
    }


def is_field_collision(units: list[dict[str, int]]) -> bool:
    """Reject TRACKS dummy rows that reuse an acre mesh with HEIGHT_MAX floors."""
    n_max = sum(1 for u in units if int(u["c"]) >= HEIGHT_MAX)
    return n_max <= len(units) // 2


def decode_sounds(blob: bytes) -> list[list[int]]:
    """`[kind, ut_x, ut_z]` for each used `sound_source` slot."""
    out: list[list[int]] = []
    for i in range(SOUND_COUNT):
        kind, ux, uz = struct.unpack_from(">hBB", blob, i * 4)
        if kind != 0:
            out.append([kind, ux, uz])
    return out


def extract_sounds(rel: RelData, symbols: list[MapSymbol], table: dict[str, list[dict[str, int]]]) -> dict[str, list[list[int]]]:
    """Field sound sources for the rows `extract_table` kept (same mesh prefix)."""
    by_addr = {s.address: s for s in symbols}
    bgd = next(s for s in symbols if s.name == "data_bgd")
    out: dict[str, list[list[int]]] = {}
    for i in range(bgd.size // BG_DATA_SIZE):
        base = bgd.address + i * BG_DATA_SIZE
        gfx = by_addr.get(rel.u32_at(base + OFF_OPAQUE))
        if gfx is None or not gfx.name.endswith("_model"):
            continue
        prefix = gfx.name[: -len("_model")]
        if prefix not in table:
            continue
        units = [
            decode_unit(struct.unpack_from(">I", rel.slice_at(base + OFF_COLLISION, UNIT_COUNT * 4), u * 4)[0])
            for u in range(UNIT_COUNT)
        ]
        if units != table[prefix]:
            continue
        out[prefix] = decode_sounds(rel.slice_at(base + OFF_SOUNDS, SOUND_COUNT * 4))
    return out


def extract_table(rel: RelData, symbols: list[MapSymbol]) -> dict[str, list[dict[str, int]]]:
    by_addr = {s.address: s for s in symbols}
    bgd = next(s for s in symbols if s.name == "data_bgd")
    out: dict[str, list[dict[str, int]]] = {}
    count = bgd.size // BG_DATA_SIZE
    for i in range(count):
        base = bgd.address + i * BG_DATA_SIZE
        opaque = rel.u32_at(base + OFF_OPAQUE)
        gfx = by_addr.get(opaque)
        if gfx is None or not gfx.name.endswith("_model"):
            continue
        prefix = gfx.name[: -len("_model")]
        blob = rel.slice_at(base + OFF_COLLISION, UNIT_COUNT * 4)
        units = [decode_unit(struct.unpack_from(">I", blob, u * 4)[0]) for u in range(UNIT_COUNT)]
        # Later `data_bgd` rows (`GRD_S_C1_3_1`, …) reuse the outdoor mesh with a
        # HEIGHT_MAX / FLOOR table. Keying by mesh name would overwrite the field.
        if prefix in out and (is_field_collision(out[prefix]) or not is_field_collision(units)):
            continue
        out[prefix] = units
    return out


def write_sidecars(
    table: dict[str, list[dict[str, int]]], dest_root: Path, sounds: dict[str, list[list[int]]] | None = None
) -> int:
    n = 0
    acres = dest_root / "environment" / "acres"
    acres.mkdir(parents=True, exist_ok=True)
    for prefix, units in table.items():
        path = acres / f"{prefix}.col.json"
        row: dict[str, Any] = {"id": prefix, "land_counts": LAND_COUNTS, "units": units}
        if sounds and sounds.get(prefix):
            row["sounds"] = sounds[prefix]
        path.write_text(json.dumps(row, separators=(",", ":")) + "\n")
        n += 1
    return n


def extract_and_write(rel: RelData, symbols: list[MapSymbol], dest_roots: Path | list[Path]) -> dict[str, Any]:
    table = extract_table(rel, symbols)
    sounds = extract_sounds(rel, symbols, table)
    roots = dest_roots if isinstance(dest_roots, list) else [dest_roots]
    written = 0
    for dest in roots:
        written = write_sidecars(table, dest, sounds)
    return {"acres": len(table), "written": written}
