"""Furniture by number (`FTR_NUM` = 1266) for gift and prize lists.

Each furniture index `i` is, in the game:
- the profile `furniture_quality[i]` (`ac_furniture_profile_data.c_inc`) → `iam_X`, whose
  model the pipeline converts as `int_X`;
- a name in `ftrName_table` (i < 1024) or `ftrName2_table` (the rest), 16 bytes each;
- a price in `ftr_price_table` (u16 per index, 0xFFFF-terminated) in foresta.rel;
- a "birth type" in `mRmTp_birth_type[]` (`m_room_type.c`): which list hands it out —
  Nook's A/B/C groups, events, Halloween, Jingle, Gulliver (JONASON), the lottery, …

Also the other listable goods (`itemName_carpet` / `_wall` / `_cloth` with their
`*_price_table`s) and the shop's named lists (`ftr_listA`, `carpet_listEvent`,
`ftr_listJonason`, …) that `mSP_SelectRandomItem_New` draws from, as indices.

Written to the gitignored `assets/generated/items/ftr_catalog.json`:
`{"items": [{"index", "visual", "name", "price", "birth", "huusui", "face"}, …],
  "carpet"|"wall"|"cloth": [{"index", "name", "price"}, …],
  "lists": {"ftr"|"carpet"|"wall"|"cloth": {"A": [index, …], "Event": […], …}}}`.
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


## `m_catalog_ovl_data.c_inc`: each catalog page's entries in page order. Furniture,
## clothing, umbrellas, gyroids and fossils are furniture indices (they share
## `furniture_collected_bitfield`); wallpaper / carpet / stationery / music index their own
## item ranges.
CATALOG_PAGES = ("ftr", "wall", "carpet", "cloth", "umbrella", "paper", "haniwa", "fossil", "music")


def _catalog_pages(decomp: Path) -> dict[str, list[int]]:
    path = decomp / "src" / "game" / "m_catalog_ovl_data.c_inc"
    if not path.is_file():
        return {}
    text = path.read_text(errors="replace")
    out: dict[str, list[int]] = {}
    start = text.find("mCL_furniture_list[]")
    if start >= 0:
        body = text[start : text.find("};", start)]
        out["ftr"] = [int(m, 16) for m in re.findall(r"\{\s*0x([0-9A-Fa-f]+)\s*,", body)]
    for page in CATALOG_PAGES[1:]:
        start = text.find(f"mCL_{page}_idx_list[]")
        if start < 0:
            continue
        body = text[text.find("{", start) : text.find("};", start)]
        out[page] = [int(m, 16) for m in re.findall(r"0x([0-9A-Fa-f]+)", body)]
    return out


## `mHsRm_ftr_info` → `mMkRm_ftr_info` in `m_huusui_room_ovl.o` (a second table of that name
## belongs to `m_mark_room_ovl.o`): per furniture, the feng shui colour
## (`mHsRm_HUUSUI_NONE`, YELLOW, RED, ORANGE, GREEN, LUCKY) and whether it has a face.
def _huusui_info(rel: Any, symbols: list) -> list[tuple[int, bool]]:
    for sym in symbols:
        if sym.name == "mMkRm_ftr_info" and sym.obj == "m_huusui_room_ovl.o":
            blob = rel.slice_at(sym.address, sym.size)
            return [(blob[i], blob[i + 1] != 0) for i in range(0, len(blob) - 1, 2)]
    return []


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
    huusui = _huusui_info(rel, parse_map(Path(map_path)))
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
            "huusui": huusui[i][0] if i < len(huusui) else 0,
            "face": huusui[i][1] if i < len(huusui) else False,
        })
    def u16s(symbol: str) -> list[int]:
        sym = by_name.get(symbol)
        if sym is None:
            return []
        blob = rel.slice_at(sym.address, sym.size)
        return list(struct.unpack(">%dH" % (len(blob) // 2), blob[: len(blob) // 2 * 2]))

    def goods(kind: str, count_names: str, price_table: str) -> list[dict[str, Any]]:
        names_k = names(count_names)
        prices_k = u16s(price_table)
        if 0xFFFF in prices_k:
            prices_k = prices_k[: prices_k.index(0xFFFF)]
        return [
            {"index": i, "name": n, "price": prices_k[i] if i < len(prices_k) else 0}
            for i, n in enumerate(names_k)
        ]

    ranges = {"carpet": 0x2600, "wall": 0x2700, "cloth": 0x2400}

    def to_index(kind: str, item: int) -> int:
        if kind == "ftr":
            if 0x1000 <= item < 0x2000:
                return (item - 0x1000) >> 2
            if 0x3000 <= item < 0x4000:
                return FTR0_NAMES + ((item - 0x3000) >> 2)
            return -1
        return item - ranges[kind]

    lists: dict[str, dict[str, list[int]]] = {}
    for kind in ("ftr", "carpet", "wall", "cloth"):
        found: dict[str, list[int]] = {}
        for name in by_name:
            if not name.startswith(f"{kind}_list"):
                continue
            label = name[len(kind) + 5 :]
            if not label or not label[0].isupper():
                continue
            values = [v for v in u16s(name) if v not in (0, 0xFFFF)]
            found[label] = [i for i in (to_index(kind, v) for v in values) if i >= 0]
        lists[kind] = found

    out_dir = cfg.godot_generated / "items"
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / "ftr_catalog.json"
    path.write_text(json.dumps({
        "items": items,
        "carpet": goods("carpet", "itemName_carpet", "carpet_price_table"),
        "wall": goods("wall", "itemName_wall", "wall_price_table"),
        "cloth": goods("cloth", "itemName_cloth", "cloth_price_table"),
        "lists": lists,
        "catalog": _catalog_pages(decomp),
    }, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    from .hra import export_hra
    hra = export_hra(decomp, out_dir)
    return {"converted": len(items), "path": str(path), "hra": hra}
