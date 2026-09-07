"""Extract `m_msg` dialogue window chrome from foresta.rel for local reference.

Textures from decomp `m_msg_data.c_inc` (`con_kaiwa2_*`, `con_namefuti_TXT`).
The game draws a flat PRIMITIVE fill plus three I4 border tiles (corners w1,
horizontal bands w3, vertical bands w2) — not one nine-patch atlas.

Also rasterises `con_kaiwa2_modelT` / `con_kaiwaname_modelT` into screen-space
PNGs (`msg_window_cloud`, `msg_nameplate_cloud`) so Godot can draw the exact
silhouette without reassembling the scallop tiles at runtime.

Output is gitignored under `assets/generated/ui/message/`.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops, ImageFilter

from .config import PipelineConfig
from .godot_import import write_import_sidecar
from .mapfile import MapSymbol, parse_map
from .rel import RelData
from .texbank import (
    G_IM_FMT_I,
    G_IM_SIZ_4b,
    decode_gbi_texture,
    image_png_bytes,
)
from .achd import load_achd_pack, maybe_hd_png
from .bti import I4
from io import BytesIO

## Decomp `mMsg_window` default tints (`m_msg_main.c_inc`).
MSG_BODY_PRIM = (235, 255, 235, 255)
MSG_NAME_PRIM = (160, 215, 30, 255)

## Composited GC frame body tint for the talk cloud (`MessageWindowChrome`).
## Matches native `MSG_BODY_PRIM` fill after XLU over field grass.
CLOUD_COMPOSITED_RGBA = (210, 228, 210, int(255 * 0.82))

## `FONT_nes_tex_font1` — 16×16 grid of 12×16 I4 glyphs (`mFont_TEX_CHAR_*`).
FONT_CHAR_W = 12
FONT_CHAR_H = 16
FONT_ATLAS_COLS = 16
FONT_ATLAS_ROWS = 16
## `mFont_Get_FontOffset` — advance = 12 − offset when CUT is set (talk body + name).
FONT_OFFSETS: tuple[int, ...] = (
	6, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 6, 6, 6,
	6, 4, 4, 3, 3, 3, 3, 3, 3, 5, 5, 5, 5, 5, 5, 5,
	7, 6, 5, 5, 5, 1, 4, 8, 6, 6, 1, 0, 8, 4, 8, 0,
	4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 8, 1, 4, 3, 4, 4,
	2, 3, 5, 4, 4, 5, 5, 4, 4, 6, 6, 5, 5, 2, 4, 4,
	5, 3, 5, 5, 5, 4, 4, 2, 5, 5, 6, 5, 0, 5, 5, 3,
	5, 5, 5, 5, 5, 6, 7, 5, 4, 7, 7, 6, 7, 3, 5, 5,
	5, 4, 6, 6, 7, 5, 6, 3, 6, 6, 7, 5, 5, 5, 5, 0,
	0, 6, 6, 6, 6, 8, 4, 5, 5, 5, 5, 5, 5, 3, 5, 5,
	0, 5, 5, 5, 5, 5, 5, 6, 6, 5, 5, 4, 5, 6, 6, 6,
	3, 4, 2, 3, 5, 2, 2, 0, 0, 0, 0, 0, 5, 5, 5, 0,
	1, 1, 1, 0, 3, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0,
	4, 4, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 4,
	8, 3, 8, 6, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2,
)

## Nine-patch atlas derived from the baked cloud (keep in sync with `MessageWindowChrome`).
CLOUD_NINE_MARGINS = (42, 22, 42, 22)
CLOUD_H_TILE = 32
CLOUD_V_TILE = 18
NAME_NINE_MARGINS = (16, 6, 16, 4)
NAME_H_TILE = 32

## `mMsg_init` screen placement used when baking mesh verts to pixels.
MSG_CENTER_X = 160.0
MSG_CENTER_Y = 185.4


@dataclass(frozen=True)
class TexSpec:
    name: str
    width: int
    height: int
    prim_as_color: tuple[int, int, int, int]
    out_name: str | None = None
    ## When True, RGB is forced white and intensity is alpha so Godot can PRIM-tint.
    modulate_base: bool = False


@dataclass(frozen=True)
class UiVertex:
    x: int
    y: int
    s: float
    t: float


CHROME: list[TexSpec] = [
    TexSpec("con_kaiwa2_w1_tex", 64, 64, MSG_BODY_PRIM, "msg_kaiwa_w1"),
    TexSpec("con_kaiwa2_w2_tex", 128, 64, MSG_BODY_PRIM, "msg_kaiwa_w2"),
    TexSpec("con_kaiwa2_w3_tex", 128, 64, MSG_BODY_PRIM, "msg_kaiwa_w3"),
    ## White+alpha — `MessageWindowChrome` multiplies by sex tint at runtime.
    TexSpec("con_namefuti_TXT", 64, 32, MSG_NAME_PRIM, "msg_nameplate", True),
]

## `con_kaiwa2_modelT` triangle batches from `m_msg_data.c_inc`.
KAIWA2_BATCHES: list[tuple[str, tuple[int, ...]]] = [
    ("msg_kaiwa_w3", (0, 1, 2, 2, 3, 0, 4, 5, 6, 6, 7, 4)),
    ("msg_kaiwa_w2", (8, 9, 10, 10, 11, 8, 12, 13, 14, 14, 15, 12)),
    ("msg_kaiwa_w1", (16, 17, 18, 18, 19, 16, 20, 21, 22, 22, 23, 20)),
]

NAMEPLATE_TRIS: tuple[int, ...] = (0, 1, 2, 2, 3, 0)


def extract_message_ui(cfg: PipelineConfig) -> dict[str, Any]:
    rel_path = cfg.extracted_disc / "files" / "foresta.rel"
    map_path = cfg.extracted_disc / "files" / "foresta.map"
    if not rel_path.is_file() or not map_path.is_file():
        return {"results": [], "converted": 0, "error": f"missing {rel_path.name} or {map_path.name}"}

    rel = RelData(rel_path)
    symbols = parse_map(map_path)
    by_name: dict[str, list[MapSymbol]] = {}
    for sym in symbols:
        by_name.setdefault(sym.name, []).append(sym)

    out_dir = cfg.godot_generated / "ui" / "message"
    stage_dir = cfg.converted / "ui" / "message"
    out_dir.mkdir(parents=True, exist_ok=True)
    stage_dir.mkdir(parents=True, exist_ok=True)

    ## Same ACHD pack for chrome tiles + font. Kaiwa sheets are grey I4 masks —
    ## PRIM tint is applied in `_extract_one` (mint body / white nameplate).
    achd = (
        load_achd_pack(cfg.achd_root, cfg.achd_cache)
        if cfg.achd_enabled and cfg.achd_root is not None
        else None
    )

    results: list[dict[str, Any]] = []
    tile_native: dict[str, tuple[int, int]] = {}
    for spec in CHROME:
        out_stem = spec.out_name or spec.name
        tile_native[out_stem] = (spec.width, spec.height)
        results.append(
            _extract_one(rel, by_name, spec, stage_dir, out_dir, cfg.project_root, achd=achd)
        )

    bake_results = _bake_message_shapes(
        rel, by_name, out_dir, stage_dir, cfg.project_root, tile_native=tile_native
    )
    results.extend(bake_results)
    results.append(
        _extract_nes_font(rel, by_name, stage_dir, out_dir, cfg.project_root, achd=achd)
    )

    converted = sum(1 for r in results if r["status"] == "converted")
    return {"results": results, "converted": converted, "output": str(out_dir)}


def _extract_nes_font(
    rel: RelData,
    by_name: dict[str, list[MapSymbol]],
    stage_dir: Path,
    out_dir: Path,
    project_root: Path,
    achd=None,
) -> dict[str, Any]:
    """Rasterise `FONT_nes_tex_font1` + AngelCode BMFont for Godot `FontFile` import."""
    record: dict[str, Any] = {
        "asset_id": "msg_font",
        "source": "FONT_nes_tex_font1",
        "output_path": "ui/message/msg_font.fnt",
        "status": "pending",
        "error": None,
    }
    try:
        from .dialogue import char_map

        sym = _pick_symbol(by_name, "FONT_nes_tex_font1")
        blob = rel.slice_at(sym.address, sym.size)
        atlas_w = FONT_CHAR_W * FONT_ATLAS_COLS
        atlas_h = FONT_CHAR_H * FONT_ATLAS_ROWS
        expected = atlas_w * atlas_h // 2
        if len(blob) < expected:
            raise ValueError(f"font blob too small: {len(blob)} < {expected}")
        used_achd = False
        scale = 1
        hd = maybe_hd_png(achd, blob[:expected], atlas_w, atlas_h, I4, None)
        if hd is not None:
            rgba = Image.open(BytesIO(hd)).convert("RGBA")
            if rgba.size[0] % atlas_w == 0 and rgba.size[1] % atlas_h == 0:
                sx = rgba.size[0] // atlas_w
                sy = rgba.size[1] // atlas_h
                if sx == sy and sx >= 1:
                    ## ACHD is often RGB-on-black; keep luminance as alpha for tintable glyphs.
                    if rgba.getextrema()[3] == (255, 255):
                        lum = rgba.convert("L")
                        rgba = Image.merge(
                            "RGBA",
                            (
                                Image.new("L", rgba.size, 255),
                                Image.new("L", rgba.size, 255),
                                Image.new("L", rgba.size, 255),
                                lum,
                            ),
                        )
                    scale = sx
                    used_achd = True
                else:
                    rgba = None
            else:
                rgba = None
        else:
            rgba = None
        if rgba is None:
            ## Dolphin 4-bit tile swizzle via `decode_gbi_texture` (same as other I4 UI).
            decoded = decode_gbi_texture(blob, atlas_w, atlas_h, G_IM_FMT_I, G_IM_SIZ_4b, b"").convert(
                "RGBA"
            )
            intensity = decoded.split()[0]
            rgba = Image.merge(
                "RGBA",
                (
                    Image.new("L", decoded.size, 255),
                    Image.new("L", decoded.size, 255),
                    Image.new("L", decoded.size, 255),
                    intensity,
                ),
            )
        png = image_png_bytes(rgba)
        cmap = char_map()
        fnt = _build_bmfont(cmap, scale=scale)
        for folder in (stage_dir, out_dir):
            (folder / "msg_font_atlas.png").write_bytes(png)
            (folder / "msg_font.fnt").write_text(fnt, encoding="utf-8")
        write_import_sidecar(out_dir / "msg_font_atlas.png", project_root)
        record["status"] = "converted"
        record["meta"] = {
            "width": rgba.size[0],
            "height": rgba.size[1],
            "native_width": atlas_w,
            "native_height": atlas_h,
            "scale": scale,
            "achd": used_achd,
            "address": f"0x{sym.address:08X}",
            "size": sym.size,
            "glyphs": sum(1 for ch in cmap if ch and ch != "\x7f"),
        }
    except Exception as exc:  # noqa: BLE001
        record["status"] = "error"
        record["error"] = f"{type(exc).__name__}: {exc}"
    return record


def _build_bmfont(cmap: list[str], scale: int = 1) -> str:
    scale = max(1, int(scale))
    cell_w = FONT_CHAR_W * scale
    cell_h = FONT_CHAR_H * scale
    atlas_w = cell_w * FONT_ATLAS_COLS
    atlas_h = cell_h * FONT_ATLAS_ROWS
    ## `size` / lineHeight match atlas glyph height so Godot's font_size=16 scales
    ## HD (e.g. size 128) down correctly: 16/128 → native on-screen size.
    base_size = FONT_CHAR_H * scale
    lines = [
        f'info face="FONT_nes_tex_font1" size={base_size} bold=0 italic=0 charset="" unicode=1 '
        "stretchH=100 smooth=0 aa=0 padding=0,0,0,0 spacing=0,0",
        f"common lineHeight={cell_h} base={cell_h} scaleW={atlas_w} "
        f"scaleH={atlas_h} pages=1 packed=0",
        'page id=0 file="msg_font_atlas.png"',
    ]
    chars: list[str] = []
    seen: set[int] = set()
    for code, ch in enumerate(cmap):
        if not ch or ch == "\x7f":
            continue
        cp = ord(ch)
        if cp in seen:
            continue
        seen.add(cp)
        col = code & 0xF
        row = code >> 4
        cut = max(1, FONT_CHAR_W - FONT_OFFSETS[code]) * scale
        chars.append(
            f"char id={cp} x={col * cell_w} y={row * cell_h} "
            f"width={cut} height={cell_h} xoffset=0 yoffset=0 "
            f"xadvance={cut} page=0 chnl=15"
        )
    ## Space must advance even if the atlas cell is empty.
    if ord(" ") not in seen:
        space_adv = (FONT_CHAR_W - FONT_OFFSETS[0x20]) * scale
        chars.append(
            f"char id={ord(' ')} x=0 y={2 * cell_h} width={scale} height={scale} "
            f"xoffset=0 yoffset=0 xadvance={space_adv} page=0 chnl=15"
        )
    ## Unicode punctuation that authored text may use — map onto disc glyphs.
    ## Ellipsis has no single cell; callers expand `…` → `...` before draw.
    period = 0x2E
    quote = 0x22
    apos = 0x27
    comma = 0x2C
    hyphen = 0x2D
    aliases = {
        ord("…"): period,  # fallback single period if not expanded
        ord("‥"): period,
        ord("“"): quote,
        ord("”"): quote,
        ord("„"): quote,
        ord("«"): quote,
        ord("»"): quote,
        ord("‘"): apos,
        ord("’"): apos,
        ord("‚"): comma,
        ord("‛"): apos,
        ord("—"): hyphen,  # em dash
        ord("–"): hyphen,  # en dash
        ord("―"): hyphen,
        ord("−"): hyphen,
        ord("‑"): hyphen,
        ord("﹣"): hyphen,
        ord("－"): hyphen,
        ord("．"): period,  # fullwidth
        ord("，"): comma,
        ord("！"): ord("!"),
        ord("？"): ord("?"),
        ord("："): ord(":"),
        ord("；"): ord(";"),
    }
    for uni, src in aliases.items():
        if uni in seen:
            continue
        col = src & 0xF
        row = src >> 4
        cut = max(1, FONT_CHAR_W - FONT_OFFSETS[src]) * scale
        chars.append(
            f"char id={uni} x={col * cell_w} y={row * cell_h} "
            f"width={cut} height={cell_h} xoffset=0 yoffset=0 "
            f"xadvance={cut} page=0 chnl=15"
        )
        seen.add(uni)
    lines.append(f"chars count={len(chars)}")
    lines.extend(chars)
    lines.append("")
    return "\n".join(lines)


def _pick_symbol(by_name: dict[str, list[MapSymbol]], name: str) -> MapSymbol:
    matches = by_name.get(name) or []
    if not matches:
        raise KeyError(name)
    return max(matches, key=lambda s: (s.size, -s.address))


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
    out_stem = spec.out_name or spec.name
    record: dict[str, Any] = {
        "asset_id": out_stem,
        "source": spec.name,
        "output_path": f"ui/message/{out_stem}.png",
        "status": "pending",
        "error": None,
    }
    try:
        sym = _pick_symbol(by_name, spec.name)
        data = rel.slice_at(sym.address, sym.size)
        hd = maybe_hd_png(achd, data, spec.width, spec.height, I4, None)
        if hd is not None:
            image = Image.open(BytesIO(hd)).convert("RGBA")
            used_achd = True
        else:
            image = decode_gbi_texture(data, spec.width, spec.height, G_IM_FMT_I, G_IM_SIZ_4b, b"")
            used_achd = False
        ## Native I4 and ACHD grey masks both need PRIM (or white+alpha for nameplate).
        image = _apply_chrome_prim(image, spec)
        png = image_png_bytes(image)
        for folder in (stage_dir, out_dir):
            path = folder / f"{out_stem}.png"
            path.write_bytes(png)
        write_import_sidecar(out_dir / f"{out_stem}.png", project_root)
        record["status"] = "converted"
        record["meta"] = {
            "width": image.width,
            "height": image.height,
            "native_width": spec.width,
            "native_height": spec.height,
            "achd": used_achd,
            "address": f"0x{sym.address:08X}",
            "size": sym.size,
        }
    except Exception as exc:  # noqa: BLE001
        record["status"] = "error"
        record["error"] = f"{type(exc).__name__}: {exc}"
    return record


def _bake_message_shapes(
    rel: RelData,
    by_name: dict[str, list[MapSymbol]],
    out_dir: Path,
    stage_dir: Path,
    project_root: Path,
    *,
    tile_native: dict[str, tuple[int, int]],
) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    tile_cache: dict[str, Image.Image] = {}

    def load_tile(stem: str) -> Image.Image:
        if stem not in tile_cache:
            path = out_dir / f"{stem}.png"
            if not path.is_file():
                raise FileNotFoundError(path)
            tile_cache[stem] = Image.open(path).convert("RGBA")
        return tile_cache[stem]

    bake_scale = 1
    for stem, native in tile_native.items():
        path = out_dir / f"{stem}.png"
        if not path.is_file():
            continue
        tw, th = Image.open(path).size
        nw, nh = native
        if nw > 0 and nh > 0:
            bake_scale = max(bake_scale, tw // nw, th // nh)
    bake_scale = max(1, min(bake_scale, 8))

    jobs: list[tuple[str, str, list[tuple[str, tuple[int, ...]]], bool]] = [
        ("msg_window_cloud", "con_kaiwa2_v", KAIWA2_BATCHES, False),
        ("msg_nameplate_cloud", "con_kaiwaname_v", [("msg_nameplate", NAMEPLATE_TRIS)], True),
    ]
    for out_stem, vtx_name, batches, mirror in jobs:
        record: dict[str, Any] = {
            "asset_id": out_stem,
            "source": vtx_name,
            "output_path": f"ui/message/{out_stem}.png",
            "status": "pending",
            "error": None,
        }
        try:
            sym = _pick_symbol(by_name, vtx_name)
            verts = _parse_ui_vtx(rel.slice_at(sym.address, sym.size))
            image, bounds = _rasterize_mesh(
                verts,
                batches,
                load_tile,
                tile_native=tile_native,
                mirror=mirror,
                scale=bake_scale,
            )
            if out_stem == "msg_window_cloud":
                ## Thin rim only — a deep rim kept the lobed mesh as an inner ghost
                ## inside ACHD's soft outer fringe. Flat mint fill covers the rest.
                image = _solidify_cloud_interior(image, rim_px=max(8, 2 * bake_scale))
                margins = tuple(m * bake_scale for m in CLOUD_NINE_MARGINS)
                nine, _nine_meta = _build_ninepatch_atlas(
                    image,
                    margins=margins,  # type: ignore[arg-type]
                    h_period=CLOUD_H_TILE * bake_scale,
                    v_period=CLOUD_V_TILE * bake_scale,
                )
                nine_png = image_png_bytes(nine)
                for folder in (stage_dir, out_dir):
                    nine_path = folder / "msg_window_ninepatch.png"
                    nine_path.write_bytes(nine_png)
                write_import_sidecar(out_dir / "msg_window_ninepatch.png", project_root)
                records.append(
                    {
                        "asset_id": "msg_window_ninepatch",
                        "source": "msg_window_cloud",
                        "output_path": "ui/message/msg_window_ninepatch.png",
                        "status": "converted",
                        "error": None,
                        "meta": _nine_meta,
                    }
                )
            png = image_png_bytes(image)
            for folder in (stage_dir, out_dir):
                path = folder / f"{out_stem}.png"
                path.write_bytes(png)
            write_import_sidecar(out_dir / f"{out_stem}.png", project_root)
            if out_stem == "msg_nameplate_cloud":
                margins = tuple(m * bake_scale for m in NAME_NINE_MARGINS)
                nine, _nine_meta = _build_ninepatch_atlas(
                    image,
                    margins=margins,  # type: ignore[arg-type]
                    h_period=NAME_H_TILE * bake_scale,
                    v_period=max(1, image.height - margins[1] - margins[3]),
                )
                nine_png = image_png_bytes(nine)
                for folder in (stage_dir, out_dir):
                    nine_path = folder / "msg_nameplate_ninepatch.png"
                    nine_path.write_bytes(nine_png)
                write_import_sidecar(out_dir / "msg_nameplate_ninepatch.png", project_root)
                records.append(
                    {
                        "asset_id": "msg_nameplate_ninepatch",
                        "source": "msg_nameplate_cloud",
                        "output_path": "ui/message/msg_nameplate_ninepatch.png",
                        "status": "converted",
                        "error": None,
                        "meta": _nine_meta,
                    }
                )
            record["status"] = "converted"
            record["meta"] = {
                "width": image.width,
                "height": image.height,
                "bounds": bounds,
                "bake_scale": bake_scale,
            }
        except Exception as exc:  # noqa: BLE001
            record["status"] = "error"
            record["error"] = f"{type(exc).__name__}: {exc}"
        records.append(record)
    return records


def _harden_cloud_alpha(image: Image.Image, *, threshold: int = 48) -> Image.Image:
    """Binary alpha: keep covered texels opaque, drop near-zero ACHD fringe dust."""
    rgba = image.convert("RGBA")
    r, g, b, a = rgba.split()
    hard = a.point(lambda v, t=threshold: 255 if v >= t else 0)
    return Image.merge("RGBA", (r, g, b, hard))


def _solidify_cloud_interior(image: Image.Image, *, rim_px: int = 8) -> Image.Image:
    """Flatten mesh seam lines: uniform interior, keep a thin textured border.

    `rim_px` is in bake-space pixels. Keep this small (≈2 GC px × scale) so the
    classic lobed gutter is not preserved as an inner silhouette under ACHD.
    Fill is always the composited mint — ACHD centers are too soft to sample.
    """
    rim_px = max(1, int(rim_px))
    ## Opaque coverage first so soft ACHD fill does not leave holes after erosion.
    image = _harden_cloud_alpha(image, threshold=48)
    alpha = image.split()[3]
    mask = alpha.point(lambda v: 255 if v > 48 else 0)
    eroded = mask
    for _ in range(rim_px):
        eroded = eroded.filter(ImageFilter.MinFilter(3))
    rim = ImageChops.subtract(mask, eroded)
    fill_rgba = CLOUD_COMPOSITED_RGBA
    fill = Image.new("RGBA", image.size, fill_rgba)
    body = Image.composite(fill, Image.new("RGBA", image.size, (0, 0, 0, 0)), mask)
    return Image.composite(image, body, rim)


def _build_ninepatch_atlas(
    source: Image.Image,
    *,
    margins: tuple[int, int, int, int],
    h_period: int,
    v_period: int,
) -> tuple[Image.Image, dict[str, Any]]:
    """Compact tileable nine-patch atlas with scallops kept in the fixed corners."""
    left, top, right, bottom = margins
    sw, sh = source.size
    if left + right + 2 >= sw or top + bottom + 2 >= sh:
        raise ValueError(f"margins {margins} too large for source {source.size}")
    h_period = max(1, min(h_period, sw - left - right))
    v_period = max(1, min(v_period, sh - top - bottom))
    atlas_w = left + h_period + right
    atlas_h = top + v_period + bottom
    out = Image.new("RGBA", (atlas_w, atlas_h), (0, 0, 0, 0))

    def blit(src_box: tuple[int, int, int, int], dst: tuple[int, int]) -> None:
        out.paste(source.crop(src_box), dst)

    blit((0, 0, left, top), (0, 0))
    blit((sw - right, 0, sw, top), (atlas_w - right, 0))
    blit((0, sh - bottom, left, sh), (0, atlas_h - bottom))
    blit((sw - right, sh - bottom, sw, sh), (atlas_w - right, atlas_h - bottom))
    blit((left, 0, left + h_period, top), (left, 0))
    blit((left, sh - bottom, left + h_period, sh), (left, atlas_h - bottom))
    blit((0, top, left, top + v_period), (0, top))
    blit((sw - right, top, sw, top + v_period), (atlas_w - right, top))

    fill_px = source.getpixel((sw // 2, sh // 2))
    out.paste(Image.new("RGBA", (h_period, v_period), fill_px), (left, top))

    meta = {
        "width": atlas_w,
        "height": atlas_h,
        "margins": margins,
        "h_period": h_period,
        "v_period": v_period,
    }
    return out, meta


def _parse_ui_vtx(blob: bytes) -> list[UiVertex]:
    if len(blob) % 16 != 0:
        raise ValueError("Vtx blob is not a multiple of 16 bytes")
    verts: list[UiVertex] = []
    for i in range(0, len(blob), 16):
        x, y, _z, _flag, u_raw, v_raw, _r, _g, _b, _a = struct.unpack_from(">hhhHhhBBBB", blob, i)
        verts.append(UiVertex(x=x, y=y, s=u_raw / 32.0, t=v_raw / 32.0))
    return verts


def _vtx_to_screen(v: UiVertex) -> tuple[float, float]:
    return (v.x / 16.0 + MSG_CENTER_X, -v.y / 16.0 + MSG_CENTER_Y)


def _rasterize_mesh(
    verts: list[UiVertex],
    batches: list[tuple[str, tuple[int, ...]]],
    load_tile,
    *,
    tile_native: dict[str, tuple[int, int]],
    mirror: bool,
    scale: int = 1,
) -> tuple[Image.Image, dict[str, float]]:
    screen = [_vtx_to_screen(v) for v in verts]
    xs = [p[0] for p in screen]
    ys = [p[1] for p in screen]
    min_x = int(min(xs))
    max_x = int(max(xs)) + 1
    min_y = int(min(ys))
    max_y = int(max(ys)) + 1
    width = max(1, (max_x - min_x) * scale)
    height = max(1, (max_y - min_y) * scale)
    out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    scale_f = float(scale)

    for tile_stem, indices in batches:
        tex = load_tile(tile_stem)
        native = tile_native.get(tile_stem, tex.size)
        st_scale = (tex.size[0] / max(1, native[0]), tex.size[1] / max(1, native[1]))
        for tri in range(0, len(indices), 3):
            i0, i1, i2 = indices[tri : tri + 3]
            p0 = ((screen[i0][0] - min_x) * scale_f, (screen[i0][1] - min_y) * scale_f)
            p1 = ((screen[i1][0] - min_x) * scale_f, (screen[i1][1] - min_y) * scale_f)
            p2 = ((screen[i2][0] - min_x) * scale_f, (screen[i2][1] - min_y) * scale_f)
            st0 = (verts[i0].s * st_scale[0], verts[i0].t * st_scale[1])
            st1 = (verts[i1].s * st_scale[0], verts[i1].t * st_scale[1])
            st2 = (verts[i2].s * st_scale[0], verts[i2].t * st_scale[1])
            _draw_textured_triangle(out, tex, p0, p1, p2, st0, st1, st2, mirror=mirror)

    bounds = {
        "min_x": float(min_x),
        "min_y": float(min_y),
        "max_x": float(max_x),
        "max_y": float(max_y),
        "center_x": (min_x + max_x) * 0.5,
        "center_y": (min_y + max_y) * 0.5,
        "width": float(max_x - min_x),
        "height": float(max_y - min_y),
        "bake_scale": float(scale),
    }
    return out, bounds


def _edge(a: tuple[float, float], b: tuple[float, float], p: tuple[float, float]) -> float:
    return (p[0] - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (p[1] - b[1])


def _tex_coord(c: float, size: int, *, mirror: bool) -> int:
    if size <= 0:
        return 0
    if mirror:
        period = size * 2
        pos = c % period
        if pos < 0.0:
            pos += period
        if pos >= size:
            pos = period - pos
    else:
        pos = c
    idx = int(pos)
    if idx >= size:
        idx = size - 1
    return max(0, idx)


def _sample_tex(
    tex_px: Any,
    tex_w: int,
    tex_h: int,
    s: float,
    t: float,
    *,
    mirror: bool,
) -> tuple[int, int, int, int]:
    xi = _tex_coord(s, tex_w, mirror=mirror)
    yi = _tex_coord(t, tex_h, mirror=mirror)
    return tex_px[xi, yi]


def _draw_textured_triangle(
    out: Image.Image,
    tex: Image.Image,
    p0: tuple[float, float],
    p1: tuple[float, float],
    p2: tuple[float, float],
    st0: tuple[float, float],
    st1: tuple[float, float],
    st2: tuple[float, float],
    *,
    mirror: bool,
) -> None:
    out_px = out.load()
    tex_px = tex.load()
    tex_w, tex_h = tex.size
    area = _edge(p0, p1, p2)
    if abs(area) < 1e-6:
        return

    xs = (p0[0], p1[0], p2[0])
    ys = (p0[1], p1[1], p2[1])
    min_x = max(int(min(xs)), 0)
    max_x = min(int(max(xs)) + 1, out.width)
    min_y = max(int(min(ys)), 0)
    max_y = min(int(max(ys)) + 1, out.height)

    for py in range(min_y, max_y):
        for px in range(min_x, max_x):
            w0 = _edge(p1, p2, (px, py)) / area
            w1 = _edge(p2, p0, (px, py)) / area
            w2 = _edge(p0, p1, (px, py)) / area
            if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
                continue
            s = st0[0] * w0 + st1[0] * w1 + st2[0] * w2
            t = st0[1] * w0 + st1[1] * w1 + st2[1] * w2
            sr, sg, sb, sa = _sample_tex(tex_px, tex_w, tex_h, s, t, mirror=mirror)
            if sa <= 0:
                continue
            dr, dg, db, da = out_px[px, py]
            alpha = sa / 255.0
            inv = 1.0 - alpha
            out_px[px, py] = (
                int(dr * inv + sr * alpha),
                int(dg * inv + sg * alpha),
                int(db * inv + sb * alpha),
                int(da * inv + sa),
            )


def _apply_chrome_prim(image: Image.Image, spec: TexSpec) -> Image.Image:
    """I4-style chrome: intensity × PRIM (body) or white+alpha (nameplate).

    ACHD kaiwa sheets are grey RGB + soft alpha; native decode is greyscale with
    opaque alpha. Fold luminance with source alpha so soft HD edges survive.
    """
    rgba = image.convert("RGBA")
    intensity = rgba.convert("L")
    src_a = rgba.split()[3]
    combined = ImageChops.multiply(intensity, src_a)
    if spec.modulate_base:
        out = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
        out.putalpha(combined)
        return out
    pr, pg, pb, pa = spec.prim_as_color
    alpha = combined.point(lambda v, p=pa: v * p // 255)
    solid = Image.new("RGB", rgba.size, (pr, pg, pb))
    out = solid.convert("RGBA")
    out.putalpha(alpha)
    return out


def _i_texel_as_alpha(image: Image.Image, prim: tuple[int, int, int, int]) -> Image.Image:
    ## Native I4 path: intensity in RGB, usually opaque alpha.
    return _apply_chrome_prim(
        image,
        TexSpec("tmp", image.size[0], image.size[1], prim),
    )
