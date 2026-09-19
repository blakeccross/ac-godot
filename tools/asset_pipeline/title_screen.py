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
  30 Hz `u16` input samples; plus the fixed FG block table for the demo town.

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

    out_dir = cfg.godot_generated / "titledemo"
    out_dir.mkdir(parents=True, exist_ok=True)
    catalog = {"source": "ac-decomp src/data/titledemo + m_field_make.c", "demos": demos, "fg": fg}
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
        "path": str(path),
    }
