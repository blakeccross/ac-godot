"""Furniture by number (`FTR_NUM` = 1266) for gift and prize lists.

Each furniture index `i` is, in the game:
- the profile `furniture_quality[i]` (`ac_furniture_profile_data.c_inc`) → `iam_X`, whose
  model the pipeline converts as `int_X`;
- a name in `ftrName_table` (i < 1024) or `ftrName2_table` (the rest), 16 bytes each;
- a price in `ftr_price_table` (u16 per index, 0xFFFF-terminated) in foresta.rel;
- a "birth type" in `mRmTp_birth_type[]` (`m_room_type.c`): which list hands it out —
  Nook's A/B/C groups, events, Halloween, Jingle, Gulliver (JONASON), the lottery, …

Written to the gitignored `assets/generated/items/ftr_catalog.json`:
`{"items": [{"index", "visual", "name", "price", "birth"}, …]}`.
"""

from __future__ import annotations

import json
import re
import struct
from pathlib import Path
from typing import Any

from .config import PipelineConfig
from .fgdata import _guess_decomp

NAME_LEN = 16
FTR0_NAMES = 1024


def _profiles(decomp: Path) -> list[str]:
    text = (decomp / "src" / "actor" / "ac_furniture_profile_data.c_inc").read_text(errors="replace")
    body = text[text.find("furniture_quality[]") :]
    body = body[: body.find("};")]
    return re.findall(r"&iam_([A-Za-z0-9_]+)", body)


def _profile_files(decomp: Path) -> dict[str, str]:
    """`iam_X` → the text of the file that defines it."""
    out: dict[str, str] = {}
    for path in sorted((decomp / "src" / "furniture").glob("ac_*.c")):
        text = path.read_text(errors="replace")
        for m in re.finditer(r"aFTR_PROFILE\s+iam_([A-Za-z0-9_]+)\s*=", text):
            out[m.group(1)] = text
    return out


def _visual_for(prof: str, text: str, glbs: set[str]) -> str:
    """The converted model: `int_<profile>` when it exists, else the first `int_*` model or
    skeleton the profile's file draws (`cKF_bs_r_int_sum_clchest01`, `int_x_model`)."""
    direct = f"int_{prof}"
    if not glbs or direct in glbs:
        return direct
    for token in re.findall(r"(int_[A-Za-z0-9_]+)", text):
        for cut in ("_model", "_mdl", "_v", "_tex", "_txt", "_pal", "_tbl"):
            base = token.split(cut)[0] if cut in token else token
            if base in glbs:
                return base
    return direct


def _birth_types(decomp: Path) -> list[str]:
    text = (decomp / "src" / "game" / "m_room_type.c").read_text(errors="replace")
    start = text.find("mRmTp_birth_type[FTR_NUM]")
    body = text[start : text.find("};", start)]
    return [m.lower() for m in re.findall(r"mRmTp_BIRTH_TYPE_([A-Z0-9_]+)", body)]


def convert_ftr_catalog(cfg: PipelineConfig) -> dict[str, Any]:
    from .dialogue import char_map
    from .mapfile import index_by_name, parse_map
    from .rel import RelData

    decomp = cfg.decomp_root or _guess_decomp(cfg)
    if decomp is None:
        return {"converted": 0, "error": "ac-decomp not found"}
    rel_path = getattr(cfg, "rel_path", None)
    map_path = getattr(cfg, "map_path", None)
    if rel_path is None or map_path is None or not Path(rel_path).is_file():
        return {"converted": 0, "error": "foresta.rel / .map not found"}
    rel = RelData(Path(rel_path))
    by_name = index_by_name(parse_map(Path(map_path)))
    cmap = char_map()

    def names(symbol: str) -> list[str]:
        sym = by_name.get(symbol)
        if sym is None:
            return []
        blob = rel.slice_at(sym.address, sym.size)
        return [
            "".join(cmap[b] for b in blob[i : i + NAME_LEN]).rstrip()
            for i in range(0, len(blob) - NAME_LEN + 1, NAME_LEN)
        ]

    names0 = names("ftrName_table")
    names1 = names("ftrName2_table")
    price_sym = by_name.get("ftr_price_table")
    prices: list[int] = []
    if price_sym is not None:
        blob = rel.slice_at(price_sym.address, price_sym.size)
        prices = list(struct.unpack(">%dH" % (len(blob) // 2), blob[: len(blob) // 2 * 2]))
        if 0xFFFF in prices:
            prices = prices[: prices.index(0xFFFF)]
    profiles = _profiles(decomp)
    births = _birth_types(decomp)
    files = _profile_files(decomp)
    glb_dir = cfg.godot_generated / "furniture"
    glbs = {p.stem for p in glb_dir.glob("*.glb")} if glb_dir.is_dir() else set()
    items = []
    for i, prof in enumerate(profiles):
        name = names0[i] if i < FTR0_NAMES and i < len(names0) else (
            names1[i - FTR0_NAMES] if 0 <= i - FTR0_NAMES < len(names1) else ""
        )
        items.append({
            "index": i,
            "visual": _visual_for(prof, files.get(prof, ""), glbs),
            "name": name,
            "price": prices[i] if i < len(prices) else 0,
            "birth": births[i] if i < len(births) else "",
        })
    out_dir = cfg.godot_generated / "items"
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / "ftr_catalog.json"
    path.write_text(json.dumps({"items": items}, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    return {"converted": len(items), "path": str(path)}
