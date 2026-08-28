"""Convert disc `fgdata.bin` + decomp combi table into a Godot FG catalog.

Original towns copy authored 16×16 FG item grids (`mFM_InitFgCombiSaveData` /
`RESOURCE_FGDATA`), then fruit/cedar passes and border clears. The catalog is
gitignored under `assets/generated/` like other disc-derived data.
"""

from __future__ import annotations

import json
import re
import struct
from pathlib import Path
from typing import Any

from .config import PipelineConfig

FG_STRIDE = 518  # fg_id u16 + items[256] u16 + haniwa_step[4]
UT_NUM = 16
ITEMS_PER_ACRE = UT_NUM * UT_NUM
TREE = 0x0804
EMPTY = 0x0000
EMPTY_SENTINEL = 0xFFFF


def convert_fgdata(cfg: PipelineConfig, decomp_root: Path | None = None) -> dict[str, Any]:
    src = _find_fgdata(cfg)
    if src is None:
        return {"converted": 0, "error": "fgdata.bin not found under work_root"}
    decomp = decomp_root or _guess_decomp(cfg)
    templates = _parse_templates(src)
    combis = _parse_combis(decomp) if decomp is not None else []
    out_dir = cfg.godot_generated / "environment" / "fg"
    out_dir.mkdir(parents=True, exist_ok=True)
    catalog = {
        "source": "forest_1st/data/fgdata.bin",
        "stride": FG_STRIDE,
        "templates": {str(fid): list(items) for fid, items in sorted(templates.items())},
        "combis": combis,
    }
    path = out_dir / "catalog.json"
    path.write_text(json.dumps(catalog, separators=(",", ":")) + "\n")
    # Staging copy under work_root for parity with other convert steps.
    stage = cfg.converted / "environment" / "fg"
    stage.mkdir(parents=True, exist_ok=True)
    (stage / "catalog.json").write_text(path.read_text())
    tree_combis = sum(1 for c in combis if _template_tree_count(templates, c["fg"]) > 0)
    return {
        "converted": 1,
        "templates": len(templates),
        "combis": len(combis),
        "combis_with_trees": tree_combis,
        "path": str(path),
    }


def _find_fgdata(cfg: PipelineConfig) -> Path | None:
    candidates = [
        cfg.extracted_archives / "forest_1st" / "data" / "fgdata.bin",
        cfg.work_root / "extracted" / "archives" / "forest_1st" / "data" / "fgdata.bin",
    ]
    for path in candidates:
        if path.is_file():
            return path
    return None


def _guess_decomp(cfg: PipelineConfig) -> Path | None:
    for path in (
        cfg.project_root.parent.parent / "ac-decomp",
        Path.home() / "Documents" / "ac-decomp",
        cfg.project_root / ".." / "ac-decomp",
    ):
        resolved = path.resolve()
        if (resolved / "include" / "m_fg_type.h").is_file():
            return resolved
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


def _parse_combis(decomp: Path) -> list[dict[str, Any]]:
    bg_vals = _enum_values(decomp / "include" / "m_bg_type.h", "BG_TYPE_")
    fg_vals = _explicit_values(decomp / "include" / "m_fg_type.h", "FG_TYPE_")
    type_vals = _enum_values(decomp / "include" / "m_field_make.h", "mFM_BLOCK_TYPE_")
    text = (decomp / "src" / "data" / "combi" / "data_combi.c").read_text()
    rows: list[dict[str, Any]] = []
    for m in re.finditer(
        r"\{\s*(BG_TYPE_\w+)\s*,\s*(FG_TYPE_\w+)\s*,\s*(mFM_BLOCK_TYPE_\w+)\s*\}",
        text,
    ):
        bg_sym, fg_sym, type_sym = m.group(1), m.group(2), m.group(3)
        if bg_sym not in bg_vals or fg_sym not in fg_vals or type_sym not in type_vals:
            continue
        bg_name = bg_sym.removeprefix("BG_TYPE_").lower()
        if not bg_name.startswith("grd_"):
            continue
        rows.append(
            {
                "bg": bg_name,
                "fg": fg_vals[fg_sym],
                "type": type_vals[type_sym],
            }
        )
    return rows


def _enum_values(path: Path, prefix: str) -> dict[str, int]:
    text = path.read_text()
    values: dict[str, int] = {}
    next_val = 0
    for m in re.finditer(rf"({re.escape(prefix)}\w+)\s*(?:=\s*(0x[0-9A-Fa-f]+|\d+))?\s*,", text):
        name = m.group(1)
        if m.group(2):
            next_val = int(m.group(2), 0)
        values[name] = next_val
        next_val += 1
    return values


def _explicit_values(path: Path, prefix: str) -> dict[str, int]:
    text = path.read_text()
    values: dict[str, int] = {}
    for m in re.finditer(rf"({re.escape(prefix)}\w+)\s*=\s*(0x[0-9A-Fa-f]+|\d+)", text):
        values[m.group(1)] = int(m.group(2), 0)
    return values


def _template_tree_count(templates: dict[int, list[int]], fg_id: int) -> int:
    items = templates.get(fg_id)
    if not items:
        return 0
    return sum(1 for x in items if x == TREE)
