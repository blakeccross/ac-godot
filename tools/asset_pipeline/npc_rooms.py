"""Convert disc `fgnpcdata.bin` + `npc_house_list` into per-villager furniture layouts.

Gitignored under `assets/generated/environment/fg/npc_rooms.json` like outdoor FG.
"""

from __future__ import annotations

import json
import re
import struct
from pathlib import Path
from typing import Any

from .config import PipelineConfig
from .fgdata import FG_STRIDE, ITEMS_PER_ACRE, UT_NUM, _guess_decomp
from .villagers import NPC_NUM, parse_roster

FTR0_START = 0x1000
FTR0_END = 0x2000
FTR1_START = 0x3000
FTR1_END = 0x4000
EMPTY = 0x0000
RSV_WALL = 0xFFFE
EMPTY_NO = 0xFFFF
## `FTR_HNW_COMMON000` in `m_ftr_def.h`. Draw picks `cKF_bs_r_int_hnw001`…
## `int_hnw127` with `ftr_actor->name - 0x16C` (`ac_hnw_common.c`).
FTR_HNW_COMMON000 = 0x16C
HNW_COUNT = 127


def convert_npc_rooms(cfg: PipelineConfig, decomp_root: Path | None = None) -> dict[str, Any]:
    decomp = decomp_root or cfg.decomp_root or _guess_decomp(cfg)
    if decomp is None:
        return {"converted": 0, "error": "ac-decomp not found"}
    src = _find_fgnpcdata(cfg)
    if src is None:
        return {"converted": 0, "error": "fgnpcdata.bin not found under work_root"}
    templates = _parse_templates(src)
    iam = _parse_iam_names(decomp / "src" / "actor" / "ac_furniture_profile_data.c_inc")
    shapes = _parse_iam_shapes(decomp / "src" / "furniture")
    houses = _parse_house_layers(decomp / "src" / "data" / "npc" / "house_list.c")
    roster = parse_roster(decomp)
    by_villager: dict[str, Any] = {}
    placed = 0
    for i, entry in enumerate(roster):
        house = houses[i] if i < len(houses) else {}
        main = int(house.get("main", 0))
        secondary = int(house.get("secondary", 0))
        items = templates.get(main, [])
        placements = _decode_placements(items, iam, shapes)
        placed += len(placements)
        by_villager[entry["id"]] = {
            "npc_idx": i,
            "main_layer": main,
            "secondary_layer": secondary,
            "wall_index": int(entry.get("wall_index", 0)),
            "floor_index": int(entry.get("floor_index", 0)),
            "placements": placements,
        }
    out_dir = cfg.godot_generated / "environment" / "fg"
    out_dir.mkdir(parents=True, exist_ok=True)
    catalog = {
        "source": "forest_2nd/data/fgnpcdata.bin",
        "stride": FG_STRIDE,
        "villagers": by_villager,
    }
    path = out_dir / "npc_rooms.json"
    path.write_text(json.dumps(catalog, separators=(",", ":")) + "\n")
    stage = cfg.converted / "environment" / "fg"
    stage.mkdir(parents=True, exist_ok=True)
    (stage / "npc_rooms.json").write_text(path.read_text())
    return {
        "converted": 1,
        "villagers": len(by_villager),
        "placements": placed,
        "templates": len(templates),
        "path": str(path),
    }


def _find_fgnpcdata(cfg: PipelineConfig) -> Path | None:
    candidates = [
        cfg.extracted_archives / "forest_2nd" / "data" / "fgnpcdata.bin",
        cfg.work_root / "extracted" / "archives" / "forest_2nd" / "data" / "fgnpcdata.bin",
    ]
    for path in candidates:
        if path.is_file():
            return path
    return None


def _parse_templates(path: Path) -> dict[int, list[int]]:
    data = path.read_bytes()
    out: dict[int, list[int]] = {}
    for i in range(len(data) // FG_STRIDE):
        off = i * FG_STRIDE
        fg_id = struct.unpack_from(">H", data, off)[0]
        items = list(struct.unpack_from(">" + "H" * ITEMS_PER_ACRE, data, off + 2))
        out[fg_id] = items
    return out


def _parse_house_layers(path: Path) -> list[dict[str, int]]:
    text = path.read_text(encoding="utf-8", errors="replace")
    start = text.find("npc_house_list[]")
    if start < 0:
        raise ValueError("npc_house_list not found")
    block = text[start : text.find("};", start)]
    out: list[dict[str, int]] = []
    row = re.compile(
        r"\{\s*(\d+)\s*,\s*(\d+)\s*,\s*ITM_WALL(\d+)\s*,\s*ITM_CARPET(\d+)\s*,\s*(0x[0-9a-fA-F]+)\s*,\s*(0x[0-9a-fA-F]+)"
    )
    for match in row.finditer(block):
        out.append(
            {
                "type": int(match.group(1)),
                "palette": int(match.group(2)),
                "wall": int(match.group(3)),
                "floor": int(match.group(4)),
                "main": int(match.group(5), 16),
                "secondary": int(match.group(6), 16),
            }
        )
        if len(out) >= NPC_NUM:
            break
    if len(out) < NPC_NUM:
        raise ValueError(f"house list too short: {len(out)}")
    return out[:NPC_NUM]


def _parse_iam_names(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    names = re.findall(r"&iam_([a-z0-9_]+)", text)
    if len(names) < 100:
        raise ValueError(f"furniture profile too short: {len(names)}")
    return names


def _parse_iam_shapes(furniture_dir: Path) -> dict[str, int]:
    """aFTR_SHAPE_TYPEA=1×1, TYPEB=1×2, TYPEC=2×2 (`mRmTp_FTRSIZE_*`)."""
    out: dict[str, int] = {}
    shape_re = re.compile(
        r"aFTR_PROFILE\s+iam_([a-z0-9_]+)\s*=\s*\{[^}]*aFTR_SHAPE_(TYPEA|TYPEC|TYPEB_\d+)",
        re.S,
    )
    for path in furniture_dir.glob("ac_*.c"):
        text = path.read_text(encoding="utf-8", errors="replace")
        for match in shape_re.finditer(text):
            kind = match.group(2)
            if kind == "TYPEA":
                size = 0
            elif kind == "TYPEC":
                size = 2
            else:
                size = 1
            out[match.group(1)] = size
    return out


def _decode_placements(items: list[int], iam: list[str], shapes: dict[str, int] | None = None) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    if len(items) != ITEMS_PER_ACRE:
        return out
    shapes = shapes or {}
    cloth0 = next((i for i, name in enumerate(iam) if name == "fmanekin"), -1)
    for z in range(UT_NUM):
        for x in range(UT_NUM):
            item = items[z * UT_NUM + x]
            if item in (EMPTY, EMPTY_NO, RSV_WALL):
                continue
            idx = _ftr_index(item)
            if idx is None or idx >= len(iam):
                continue
            iam_name = iam[idx]
            visual = _visual_for_iam(iam_name, idx)
            facing = item & 3
            size = int(shapes.get(iam_name, 0))
            row: dict[str, Any] = {
                "cell": [x, z],
                "facing": facing,
                "visual_id": visual,
                "item": item,
                "size": size,
            }
            ## `iam_fmanekin`: shared `obj_shop_manekin` + shirt `(name - FTR_CLOTH_START) >> 2`.
            if iam_name == "fmanekin" and cloth0 >= 0:
                row["cloth"] = idx - cloth0
            out.append(row)
    return out


def _ftr_index(item: int) -> int | None:
    if FTR0_START <= item < FTR0_END:
        return (item - FTR0_START) >> 2
    if FTR1_START <= item < FTR1_END:
        return (item - FTR1_START) >> 2
    return None


def _visual_for_iam(name: str, idx: int) -> str:
    if name == "hnw_common":
        variant = idx - FTR_HNW_COMMON000
        if 0 <= variant < HNW_COUNT:
            return f"int_hnw{variant + 1:03d}"
    return f"int_{name}"


def _item_to_visual(item: int, iam: list[str]) -> str | None:
    idx = _ftr_index(item)
    if idx is None or idx < 0 or idx >= len(iam):
        return None
    return _visual_for_iam(iam[idx], idx)
