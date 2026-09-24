"""Extract the title screen: logo overlay textures + the 5 recorded attract-mode demos.

Ground truth (ac-decomp): `src/actor/ac_animal_logo.c` (the logo actor),
`src/game/m_titledemo.c` + `src/data/titledemo/pact0..4.c` (recorded input),
`src/game/m_trademark.c` (per-demo setup) and `src/game/m_field_make.c`
(`l_title_demo_fg`).

Two outputs, both gitignored under `assets/generated/`:

- `ui/title/` — the "PRESS START" halves and the copyright line, as baked RGBA
  PNGs. All of them are `G_IM_FMT_IA` + `G_IM_SIZ_8b` 64x16
  (1 byte/pixel), tinted at draw time by
  `gsDPSetCombineLERP(PRIMITIVE, ENVIRONMENT, TEXEL0, ENVIRONMENT, PRIMITIVE, 0, TEXEL0, 0)`
  i.e. RGB `= lerp(ENV, PRIM, intensity)` and A `= PRIM.a * texel.a`. The PRIM/ENV
  pair is baked in here (press start has one pair per demo, `aAL_press_start_draw`);
  the per-frame PRIM alpha (pulse / fade) is applied at draw time.
  **Not** the GX IA4 layout the other IA textures use: these are drawn through
  `gDPLoadTextureTile` + `gSPTextureRectangle` (the N64 path), so the bytes are
  *linear* rows (no 8x4 tiling) and the nibbles are `IIIIAAAA` (intensity high,
  alpha low). Decoding them as tiled `AAAAIIII` (what `bti.py` / the generic REL pass
  do, at a guessed 64x32) gives noise; linear + swapped nibbles reads "Press" /
  "START" / "(c)20" cleanly. The 1024-byte symbol size confirms 64x16 at 8 bpp.
- `titledemo/demos.json` — per demo: spawn position, angle, tool, and the raw
  30 Hz `u16` input samples; plus the fixed FG block table and the fixed acre (BG)
  layout for the demo town (`data_fdd[SCENE_TITLE_DEMO]` in `field_data.c`).

The input word is `XXXXXXXB YYYYYYYA` (`pact0.c` header comment); decoding lives in
GDScript (`TitleDemoInput`) so the raw words stay inspectable here.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from PIL import Image

from .config import PipelineConfig
from .fgdata import _guess_decomp
from .godot_import import write_import_sidecar
from .mapfile import MapSymbol, parse_map
from .rel import RelData
from .texbank import image_png_bytes

RGB = tuple[int, int, int]

TEX_W = 64
TEX_H = 16
DEMO_COUNT = 5

## `aAL_press_start_draw`: one PRIM/ENV pair per title demo (index = demo - 1).
PRESS_START_PRIM: list[RGB] = [(70, 40, 40), (60, 50, 30), (60, 40, 60), (40, 50, 70), (40, 50, 60)]
PRESS_START_ENV: list[RGB] = [(255, 90, 30), (255, 135, 0), (255, 100, 255), (120, 205, 245), (165, 245, 0)]
PRESS_START_SYMBOLS = ("log_win_logo3_tex", "log_win_logo4_tex")

## `aAL_copyright_draw` (VER_GAFE01_00): PRIM (40,40,45), ENV (210,210,215).
COPYRIGHT_PRIM: RGB = (40, 40, 45)
COPYRIGHT_ENV: RGB = (210, 210, 215)
COPYRIGHT_SYMBOLS = ("log_win_nintendo1_tex", "log_win_nintendo2_tex", "log_win_nintendo3_tex")

## Native art is tiny; pre-upscale like the other UI bakes (see `clock_ui.py`).
UPSCALE = 4


def decode_ia8_linear(data: bytes, width: int, height: int) -> Image.Image:
    """Linear N64 `G_IM_FMT_IA`/`G_IM_SIZ_8b`: one byte per texel, `IIIIAAAA`.

    Returns R=G=B=intensity, A=alpha, the shape `tint_ia4` expects.
    """
    if len(data) < width * height:
        raise ValueError(f"need {width * height} bytes, got {len(data)}")
    img = Image.new("RGBA", (width, height))
    px = img.load()
    for y in range(height):
        for x in range(width):
            b = data[y * width + x]
            i = (b >> 4) * 17
            a = (b & 0x0F) * 17
            px[x, y] = (i, i, i, a)
    return img


def tint_ia4(img: Image.Image, prim: RGB, env: RGB) -> Image.Image:
    """`lerp(ENV, PRIM, intensity)` with the mask's own alpha (bti.py IA4: R=G=B=I)."""
    lut = [
        tuple(round(env[c] + (prim[c] - env[c]) * (i / 255.0)) for c in range(3))
        for i in range(256)
    ]
    src = img.load()
    out = Image.new("RGBA", img.size)
    dst = out.load()
    for y in range(img.height):
        for x in range(img.width):
            intensity, _, _, alpha = src[x, y]
            r, g, b = lut[intensity]
            dst[x, y] = (r, g, b, alpha)
    return out


def _pick_symbol(by_name: dict[str, list[MapSymbol]], name: str) -> MapSymbol:
    matches = by_name.get(name)
    if not matches:
        raise KeyError(name)
    return max(matches, key=lambda s: s.size)


def _write_png(image: Image.Image, stem: str, out_dir: Path, stage_dir: Path, project_root: Path) -> None:
    png = image_png_bytes(image)
    for folder in (stage_dir, out_dir):
        (folder / f"{stem}.png").write_bytes(png)
    write_import_sidecar(out_dir / f"{stem}.png", project_root)


def extract_title_ui(cfg: PipelineConfig) -> dict[str, Any]:
    rel_path = cfg.extracted_disc / "files" / "foresta.rel"
    map_path = cfg.extracted_disc / "files" / "foresta.map"
    if not rel_path.is_file() or not map_path.is_file():
        return {"results": [], "converted": 0, "error": f"missing {rel_path.name} or {map_path.name}"}

    rel = RelData(rel_path)
    by_name: dict[str, list[MapSymbol]] = {}
    for sym in parse_map(map_path):
        by_name.setdefault(sym.name, []).append(sym)

    out_dir = cfg.godot_generated / "ui" / "title"
    stage_dir = cfg.converted / "ui" / "title"
    out_dir.mkdir(parents=True, exist_ok=True)
    stage_dir.mkdir(parents=True, exist_ok=True)

    def decode(symbol: str) -> Image.Image:
        sym = _pick_symbol(by_name, symbol)
        if sym.size != TEX_W * TEX_H:
            raise ValueError(f"{symbol}: expected {TEX_W * TEX_H} bytes (64x16 IA8), got {sym.size}")
        data = rel.slice_at(sym.address, sym.size)
        return decode_ia8_linear(data, TEX_W, TEX_H)

    def bake(mask: Image.Image, prim: RGB, env: RGB) -> Image.Image:
        return tint_ia4(mask, prim, env).resize((TEX_W * UPSCALE, TEX_H * UPSCALE), Image.LANCZOS)

    results: list[dict[str, Any]] = []
    jobs: list[tuple[str, str, RGB, RGB]] = []
    for half, symbol in enumerate(PRESS_START_SYMBOLS):
        for demo in range(DEMO_COUNT):
            jobs.append((f"press_start_{demo}_{half}", symbol, PRESS_START_PRIM[demo], PRESS_START_ENV[demo]))
    for i, symbol in enumerate(COPYRIGHT_SYMBOLS):
        jobs.append((f"copyright_{i}", symbol, COPYRIGHT_PRIM, COPYRIGHT_ENV))

    masks: dict[str, Image.Image] = {}
    for stem, symbol, prim, env in jobs:
        record: dict[str, Any] = {"asset_id": stem, "source": symbol, "output_path": f"ui/title/{stem}.png"}
        try:
            if symbol not in masks:
                masks[symbol] = decode(symbol)
            _write_png(bake(masks[symbol], prim, env), stem, out_dir, stage_dir, cfg.project_root)
            record["status"] = "converted"
        except Exception as exc:  # noqa: BLE001
            record["status"] = "error"
            record["error"] = f"{type(exc).__name__}: {exc}"
        results.append(record)

    converted = sum(1 for r in results if r["status"] == "converted")
    return {"results": results, "converted": converted, "output": str(out_dir)}


def _u16_words(text: str) -> list[int]:
    return [int(m, 16) for m in re.findall(r"0x[0-9A-Fa-f]{1,4}", text)]


def parse_pact(source: str, index: int) -> dict[str, Any]:
    """One `pactN.c`: header (`x y z angle tool scale`) + the key-data words."""
    head_match = re.search(rf"pact{index}_head_table\[\]\s*=\s*\{{(.*?)\}};", source, re.S)
    keys_match = re.search(rf"pact{index}_key_data\[\]\s*=\s*\{{(.*?)\}};", source, re.S)
    if head_match is None or keys_match is None:
        raise ValueError(f"pact{index}: head/key tables not found")
    ## Strip `/* ... */` comments first: the header notes contain digits ("258.03 deg").
    head = _u16_words(re.sub(r"/\*.*?\*/", "", head_match.group(1), flags=re.S))
    if len(head) != 6:
        raise ValueError(f"pact{index}: head table has {len(head)} words, expected 6")
    keys = _u16_words(re.sub(r"/\*.*?\*/", "", keys_match.group(1), flags=re.S))
    return {
        "pos": head[0:3],
        "angle": head[3],
        "tool": head[4],
        "scale": head[5],
        "keys": keys,
    }


def parse_title_demo_fg(source: str) -> dict[str, Any]:
    """`l_title_demo_fg[(BLOCK_Z_NUM - 2) * BLOCK_X_NUM]`, 7 columns wide."""
    match = re.search(r"l_title_demo_fg\[[^\]]*\]\s*=\s*\{(.*?)\};", source, re.S)
    if match is None:
        raise ValueError("l_title_demo_fg not found")
    ids = _u16_words(match.group(1))
    cols = 7
    if len(ids) % cols != 0:
        raise ValueError(f"l_title_demo_fg: {len(ids)} entries is not a multiple of {cols}")
    return {"cols": cols, "rows": len(ids) // cols, "ids": ids}


def _strip_c_comments(text: str) -> str:
    return re.sub(r"//[^\n]*", "", re.sub(r"/\*.*?\*/", "", text, flags=re.S))


def _enum_names(source: str, enum_tag: str) -> list[str]:
    """Member names of `enum <enum_tag> { ... }` in declaration order (no explicit values)."""
    match = re.search(rf"enum\s+{re.escape(enum_tag)}\s*\{{(.*?)\}}", source, re.S)
    if match is None:
        raise ValueError(f"enum {enum_tag} not found")
    names = []
    for part in _strip_c_comments(match.group(1)).split(","):
        name = part.strip()
        if name:
            if "=" in name:
                raise ValueError(f"enum {enum_tag}: explicit value in {name!r} not supported")
            names.append(name)
    return names


def _block_type_values(field_make_h: str) -> dict[str, int]:
    """`mFM_BLOCK_TYPE_*` → value (the enum mixes implicit and explicit values)."""
    out: dict[str, int] = {}
    value = -1
    for match in re.finditer(r"\benum\s*\{(.*?)\}", field_make_h, re.S):
        body = _strip_c_comments(match.group(1))
        if "mFM_BLOCK_TYPE_" not in body:
            continue
        for part in body.split(","):
            item = part.strip()
            if not item.startswith("mFM_BLOCK_TYPE_"):
                continue
            if "=" in item:
                name, raw = (s.strip() for s in item.split("=", 1))
                value = int(raw, 0)
            else:
                name = item
                value += 1
            out[name] = value
        return out
    raise ValueError("mFM_BLOCK_TYPE enum not found")


def _top_level_entries(body: str) -> list[str]:
    """Split a C initializer list body into its depth-1 `{ ... }` entries."""
    entries: list[str] = []
    depth = 0
    start = -1
    for i, ch in enumerate(body):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start >= 0:
                entries.append(body[start : i + 1])
    return entries


def parse_title_demo_acres(
    field_data_c: str, data_combi_c: str, combi_type_h: str, field_make_h: str, scene_table_h: str
) -> dict[str, Any]:
    """The title demo's fixed acre layout: `data_fdd[SCENE_TITLE_DEMO].combi`.

    `mFM_MakeField` takes `combi = field_data->combi` for every scene that is not
    `SCENE_FG` / a player room, so the attract town's BG is this hard-coded 7x8 table,
    not a save's random field. Each `{ BLOCK_COMBI_*, height }` resolves through
    `data_combi_table` (indexed by the `__block_combi__` enum) to its BG name and
    `mFM_BLOCK_TYPE_*`.
    """
    scenes = _enum_names(scene_table_h, "scene_table")
    scene_index = scenes.index("SCENE_TITLE_DEMO")
    table = re.search(r"data_fdd\[[^\]]*\]\s*=\s*\{(.*)\};", _strip_c_comments(field_data_c), re.S)
    if table is None:
        raise ValueError("data_fdd not found")
    entries = _top_level_entries(table.group(1))
    if scene_index >= len(entries):
        raise ValueError(f"data_fdd has {len(entries)} entries, SCENE_TITLE_DEMO is {scene_index}")
    entry = entries[scene_index]
    head = re.match(r"\{\s*(\w+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,", entry)
    if head is None:
        raise ValueError("data_fdd[SCENE_TITLE_DEMO]: header not parsed")
    cols, rows = int(head.group(2)), int(head.group(3))
    cells = re.findall(r"\{\s*(BLOCK_COMBI_\w+)\s*,\s*(\d+)\s*\}", entry)
    if len(cells) != cols * rows:
        raise ValueError(f"data_fdd[SCENE_TITLE_DEMO]: {len(cells)} cells for {cols}x{rows}")

    combis = [n for n in _enum_names(combi_type_h, "__block_combi__") if n != "BLOCK_COMBI_NUM"]
    combi_rows = re.findall(
        r"\{\s*(BG_TYPE_\w+)\s*,\s*(FG_TYPE_\w+)\s*,\s*(mFM_BLOCK_TYPE_\w+)\s*\}",
        _strip_c_comments(data_combi_c),
    )
    if len(combi_rows) != len(combis):
        raise ValueError(f"data_combi_table has {len(combi_rows)} rows for {len(combis)} combis")
    block_types = _block_type_values(field_make_h)

    bg: list[str] = []
    types: list[int] = []
    heights: list[int] = []
    for combi, height in cells:
        bg_type, _fg_type, block_type = combi_rows[combis.index(combi)]
        bg.append(bg_type.removeprefix("BG_TYPE_").lower())
        types.append(block_types[block_type])
        heights.append(int(height))
    return {"cols": cols, "rows": rows, "bg": bg, "types": types, "heights": heights}


def extract_title_demo(cfg: PipelineConfig, decomp_root: Path | None = None) -> dict[str, Any]:
    decomp = decomp_root or cfg.decomp_root or _guess_decomp(cfg)
    if decomp is None:
        return {"converted": 0, "error": "ac-decomp checkout not found (set decomp_root)"}
    data_dir = decomp / "src" / "data" / "titledemo"
    field_make = decomp / "src" / "game" / "m_field_make.c"
    if not data_dir.is_dir() or not field_make.is_file():
        return {"converted": 0, "error": f"title demo sources missing under {decomp}"}

    demos = [parse_pact((data_dir / f"pact{i}.c").read_text(), i) for i in range(DEMO_COUNT)]
    fg = parse_title_demo_fg(field_make.read_text())
    acres = parse_title_demo_acres(
        (decomp / "src" / "data" / "field" / "field_data.c").read_text(),
        (decomp / "src" / "data" / "combi" / "data_combi.c").read_text(),
        (decomp / "include" / "m_combi_type.h").read_text(),
        (decomp / "include" / "m_field_make.h").read_text(),
        (decomp / "include" / "m_scene_table.h").read_text(),
    )

    out_dir = cfg.godot_generated / "titledemo"
    out_dir.mkdir(parents=True, exist_ok=True)
    catalog = {
        "source": "ac-decomp src/data/titledemo + m_field_make.c + field_data.c",
        "demos": demos,
        "fg": fg,
        "acres": acres,
    }
    path = out_dir / "demos.json"
    path.write_text(json.dumps(catalog, separators=(",", ":")) + "\n")
    stage = cfg.converted / "titledemo"
    stage.mkdir(parents=True, exist_ok=True)
    (stage / "demos.json").write_text(path.read_text())
    return {
        "converted": 1,
        "demos": len(demos),
        "samples": [len(d["keys"]) for d in demos],
        "fg_blocks": len(fg["ids"]),
        "acre_blocks": len(acres["bg"]),
        "path": str(path),
    }
