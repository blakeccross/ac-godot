"""Extract the `banti` field HUD clock badges (`clk_win_*`) from foresta.rel.

Ground truth: ac-decomp `src/game/m_banti.c` (the `banti_*` functions) and
`src/data/model/clk_win.c`. `banti` is a **persistent field-gameplay** HUD —
not a submenu overlay — drawn by `banti_draw()` every frame the player is
outdoors (`mFI_FIELDTYPE_FG`) and not in the first-intro cutscene. Its alpha
(`banti_calc_disp_alpha_rate`) fades toward 1 only when
`mPlib_Get_address_able_display() == mPlayer_ADDRESSABLE_TRUE` (player idle:
not moving, not talking, no menu open) and fades to 0 otherwise — exactly the
"fades out walking, fades in when stopped" behavior. It also shifts to the
opposite screen corner (`banti.disp_left`, `Matrix_translate(-184, 0, 0)`)
when the player's own on-screen position would overlap it
(`banti_chk_disp_left`: player screen x>=180 and y>=150).

Each digit/word texture is a **complete pre-baked round badge** — circle
outline, hairline divider, and glyph all in one `IA4` (`G_IM_FMT_IA` +
`G_IM_SIZ_8b`, 1 byte/pixel: alpha in the high nibble, intensity in the low
nibble — *not* 2-byte IA8 despite the `_ia8`/`TA` symbol suffixes, see
`texbank.gbi_to_gx`'s Dolphin note) mask, tinted at draw time via
`gsDPSetCombineLERP(PRIMITIVE, ENVIRONMENT, TEXEL0, ...)`: final color is
`lerp(ENV, PRIM, intensity)`, alpha from the mask's own alpha channel. The
PRIM/ENV pairs (`banti_draw_hiduke`/`banti_draw_jikan`/`banti_draw`) are
baked into the PNGs here so Godot can draw them as plain textures:

- date digits (month/day, `clk_win_suuji1..31_TA_tex_txt`, 32x32): PRIM
  (235,255,120) / ENV (80,40,40) — pale yellow-green on brown-red.
- time digits (hour/minute, `clk_win_jikan0..9_TA_tex_txt` +
  `clk_win_jikan_TA_tex_txt` [blank — the hidden leading hour zero], 16x16):
  PRIM (255,255,255) / ENV (60,25,10) — white on dark brown.
- weekday (`clk_win_sun..sat_tex_rgb_ia8`, 32x32): PRIM (255,255,225) / ENV
  (80,40,0), except Sunday which uses ENV (165,30,30) (red).
- am/pm (`clk_win_am/pm_tex_rgb_ia8`, 32x32): PRIM (255,255,120) / ENV
  (70,10,10).
- the blinking `:` separator (`maru`, 16x16, drawn only on odd RTC seconds —
  `clk_win_maru2T_model`, two instances): PRIM (215,120,0) / ENV (70,50,50).

Output is gitignored under `assets/generated/ui/clock/`.
"""

from __future__ import annotations

from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import Any

from PIL import Image

from .achd import load_achd_pack, maybe_hd_png
from .config import PipelineConfig
from .godot_import import write_import_sidecar
from .mapfile import MapSymbol, parse_map
from .rel import RelData
from .texbank import (
    G_IM_FMT_IA,
    G_IM_SIZ_8b,
    GX_MIRROR,
    decode_gbi_texture,
    gbi_to_gx,
    image_png_bytes,
)

RGB = tuple[int, int, int]

## `banti_draw_hiduke` (m_banti.c).
DATE_PRIM: RGB = (235, 255, 120)
DATE_ENV: RGB = (80, 40, 40)

## `banti_draw_jikan`.
TIME_PRIM: RGB = (255, 255, 255)
TIME_ENV: RGB = (60, 25, 10)

## `banti_draw` — weekday (non-Sunday / Sunday).
WEEKDAY_PRIM: RGB = (255, 255, 225)
WEEKDAY_ENV: RGB = (80, 40, 0)
SUNDAY_ENV: RGB = (165, 30, 30)

## `banti_draw` — am/pm.
AMPM_PRIM: RGB = (255, 255, 120)
AMPM_ENV: RGB = (70, 10, 10)

## `banti_draw` — blinking `:` dot (`maru`, tinted for `clk_win_maru2T_model`).
DOT_PRIM: RGB = (215, 120, 0)
DOT_ENV: RGB = (70, 50, 50)

WEEKDAY_SYMBOLS = [
    "clk_win_sun_tex_rgb_ia8", "clk_win_mon_tex_rgb_ia8", "clk_win_tue_tex_rgb_ia8",
    "clk_win_wed_tex_rgb_ia8", "clk_win_thu_tex_rgb_ia8", "clk_win_fri_tex_rgb_ia8",
    "clk_win_sat_tex_rgb_ia8",
]


@dataclass(frozen=True)
class TexSpec:
    name: str
    size: int
    out_name: str
    prim: RGB
    env: RGB


def _build_specs() -> list[TexSpec]:
    specs: list[TexSpec] = []
    for day in range(1, 32):
        specs.append(TexSpec(f"clk_win_suuji{day}_TA_tex_txt", 32, f"date_{day}", DATE_PRIM, DATE_ENV))
    for digit in range(10):
        specs.append(TexSpec(f"clk_win_jikan{digit}_TA_tex_txt", 16, f"time_{digit}", TIME_PRIM, TIME_ENV))
    specs.append(TexSpec("clk_win_jikan_TA_tex_txt", 16, "time_blank", TIME_PRIM, TIME_ENV))
    for i, sym in enumerate(WEEKDAY_SYMBOLS):
        env = SUNDAY_ENV if i == 0 else WEEKDAY_ENV
        specs.append(TexSpec(sym, 32, f"weekday_{i}", WEEKDAY_PRIM, env))
    specs.append(TexSpec("clk_win_am_tex_rgb_ia8", 32, "am", AMPM_PRIM, AMPM_ENV))
    specs.append(TexSpec("clk_win_pm_tex_rgb_ia8", 32, "pm", AMPM_PRIM, AMPM_ENV))
    specs.append(TexSpec("maru", 16, "dot", DOT_PRIM, DOT_ENV))
    return specs


def _tint_ia4(img: Image.Image, prim: RGB, env: RGB) -> Image.Image:
    ## `img` is an IA4 decode: R=G=B=intensity, A=alpha (bti.py's IA4 branch).
    ## Replicates `gsDPSetCombineLERP(PRIMITIVE, ENVIRONMENT, TEXEL0, ...)`:
    ## color = lerp(ENV, PRIM, intensity), alpha unchanged.
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


def _extract_one(
    rel: RelData,
    by_name: dict[str, list[MapSymbol]],
    spec: TexSpec,
    stage_dir: Path,
    out_dir: Path,
    project_root: Path,
    *,
    achd=None,
) -> dict[str, Any]:
    dest_rel = f"ui/clock/{spec.out_name}.png"
    record: dict[str, Any] = {
        "asset_id": spec.out_name,
        "source": spec.name,
        "output_path": dest_rel,
        "status": "pending",
        "error": None,
    }
    try:
        sym = _pick_symbol(by_name, spec.name)
        data = rel.slice_at(sym.address, sym.size)

        gx = gbi_to_gx(G_IM_FMT_IA, G_IM_SIZ_8b)
        hd = maybe_hd_png(
            achd, data, spec.size, spec.size, gx, None,
            wrap_s=GX_MIRROR, wrap_t=GX_MIRROR, label=spec.out_name,
        )
        used_achd = False
        if hd is not None:
            ## ACHD keeps this asset class as a re-tintable intensity+alpha
            ## mask too (R=G=B=intensity, just higher-res) — confirmed by
            ## sampling: plain (255,255,255,255)/(0,0,0,0) pixels, no color.
            ## Tint it exactly like the native decode, don't use it as-is.
            mask = Image.open(BytesIO(hd)).convert("RGBA")
            image = _tint_ia4(mask, spec.prim, spec.env)
            used_achd = True
        else:
            native = decode_gbi_texture(data, spec.size, spec.size, G_IM_FMT_IA, G_IM_SIZ_8b, None)
            image = _tint_ia4(native, spec.prim, spec.env)
            ## Native res is far below typical HUD display size — pre-upscale
            ## before Godot scales it further (see `asset-pipeline-achd-fidelity`
            ## convention in `message_ui.py`'s font atlas bake).
            image = image.resize((spec.size * 4, spec.size * 4), Image.LANCZOS)

        png = image_png_bytes(image)
        for folder in (stage_dir, out_dir):
            path = folder / f"{spec.out_name}.png"
            path.write_bytes(png)
        write_import_sidecar(out_dir / f"{spec.out_name}.png", project_root)

        record["status"] = "converted"
        record["meta"] = {
            "width": image.width,
            "height": image.height,
            "native_size": [spec.size, spec.size],
            "achd": used_achd,
            "address": f"0x{sym.address:08X}",
            "size": sym.size,
        }
    except Exception as exc:  # noqa: BLE001
        record["status"] = "error"
        record["error"] = f"{type(exc).__name__}: {exc}"
    return record


def extract_clock_ui(cfg: PipelineConfig) -> dict[str, Any]:
    rel_path = cfg.extracted_disc / "files" / "foresta.rel"
    map_path = cfg.extracted_disc / "files" / "foresta.map"
    if not rel_path.is_file() or not map_path.is_file():
        return {"results": [], "converted": 0, "error": f"missing {rel_path.name} or {map_path.name}"}

    rel = RelData(rel_path)
    symbols = parse_map(map_path)
    by_name: dict[str, list[MapSymbol]] = {}
    for sym in symbols:
        by_name.setdefault(sym.name, []).append(sym)

    out_dir = cfg.godot_generated / "ui" / "clock"
    stage_dir = cfg.converted / "ui" / "clock"
    out_dir.mkdir(parents=True, exist_ok=True)
    stage_dir.mkdir(parents=True, exist_ok=True)

    achd = (
        load_achd_pack(cfg.achd_root, cfg.achd_cache)
        if cfg.achd_enabled and cfg.achd_root is not None
        else None
    )

    results: list[dict[str, Any]] = []
    for spec in _build_specs():
        results.append(_extract_one(rel, by_name, spec, stage_dir, out_dir, cfg.project_root, achd=achd))

    converted = sum(1 for r in results if r["status"] == "converted")
    achd_hits = sum(1 for r in results if (r.get("meta") or {}).get("achd"))
    return {
        "results": results,
        "converted": converted,
        "achd_hits": achd_hits,
        "output": str(out_dir),
    }
