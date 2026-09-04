"""Extract town-map (`m_map_ovl`) acre tiles + chrome from foresta.rel.

Acre tiles are CI4 32×32 `kan_tizu_*_TA_tex_txt` with the two embedded
`kan_tizu{1,2}_pal` TLUTs from `m_map_ovl.c`. Window chrome comes from
`kan_win.c` / `kan_hyouji*.c` / `kan_eki.c` (formats from GBI).

Output is gitignored under `assets/generated/ui/map/` — Nintendo IP.
"""

from __future__ import annotations

import json
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image

from .config import PipelineConfig
from .godot_import import write_import_sidecar
from .mapfile import MapSymbol, parse_map
from .rel import RelData
from .texbank import (
    G_IM_FMT_CI,
    G_IM_FMT_I,
    G_IM_FMT_IA,
    G_IM_SIZ_4b,
    G_IM_SIZ_8b,
    decode_gbi_texture,
    image_png_bytes,
)

# From `m_map_ovl.c` (RGB5A3 big-endian).
_KAN_TIZU1_PAL = (
    0x0000,
    0xC3B0,
    0x9E87,
    0xD294,
    0xCA52,
    0xBDEF,
    0xB5AD,
    0xB9CE,
    0xA2E8,
    0xB18C,
    0xA705,
    0xDAFF,
    0xAB4A,
    0xFFFF,
    0xB635,
    0xBE9F,
)
_KAN_TIZU2_PAL = (
    0x0000,
    0xC3B0,
    0x9E87,
    0xC94A,
    0xE70D,
    0xE1CE,
    0xB5AD,
    0xB195,
    0xF390,
    0xB18C,
    0xA705,
    0xFFFF,
    0xD54A,
    0xDAFF,
    0xB635,
    0xBE9F,
)

# Unique stems referenced by `l_map_texture[]` in `m_map_ovl.c`.
_ACRE_STEMS: list[str] = [
    "f",
    "tst1",
    "t",
    "tr1",
    "fmh",
    "c1",
    "c2",
    "c3",
    "c4",
    "c5",
    "c6",
    "c7",
    "c1r1",
    "c2r1",
    "c3r1",
    "c4r1",
    "c5r1",
    "c6r1",
    "c7r1",
    "c1r2",
    "c2r2",
    "c3r2",
    "c4r2",
    "c5r2",
    "c6r3",
    "c7r3",
    "r1",
    "r2",
    "r4",
    "r5",
    "r6",
    "r7",
    "r1b",
    "r2b",
    "r4b",
    "r5b",
    "r6b",
    "r7b",
    "c1s",
    "c2s",
    "c3s",
    "c4s",
    "c5s",
    "c6s",
    "c7s",
    "m",
    "mr1",
    "fsh",
    "fpk",
    "fpo",
    "fko",
    "pr1",
    "pr2",
    "pr4",
    "pr5",
    "pr6",
    "pr7",
    "mr1b",
    "fmu",
    "fta",
    "tr1b",
    "c1r2b",
    "c3r1b",
    "c4r1b",
    "c4r2b",
    "c5r2b",
    "c6r1b",
    "c7r1b",
    "mwf",
]

# Parallel to decomp `l_map_texture` / `l_map_pal` (`mFM_BLOCK_TYPE_*` order).
_BLOCK_STEMS: list[str] = [
    "f", "f", "f", "f", "f", "f", "f", "f", "f", "f", "f",  # 0-10 borders
    "tst1", "t", "tr1", "fmh",  # 11-14 station/dump/river/house
    "c1", "c2", "c3", "c4", "c5", "c6", "c7",  # 15-21 cliff
    "c1r1", "c2r1", "c3r1", "c4r1", "c5r1", "c6r1", "c7r1",  # 22-28
    "c1r2", "c2r2", "c3r2", "c4r2", "c5r2", "c1r2", "c4r2", "c5r2", "c6r3", "c7r3",  # 29-38
    "f",  # 39 flat
    "r1", "r2", "r2", "r4", "r5", "r6", "r7",  # 40-46 river
    "r1b", "r2b", "r2b", "r4b", "r5b", "r6b", "r7b",  # 47-53 bridge
    "c1s", "c2s", "c3s", "c4s", "c5s", "c6s", "c7s",  # 54-60 slope
    "f", "f",  # 61-62 transition
    "m", "mr1", "fsh", "fpk", "fpo", "fko",  # 63-68 beach/shop/shrine/post/police
    "pr1", "pr2", "pr2", "pr4", "pr5", "pr6", "pr7",  # 69-75 pool
    "f", "r1", "c1", "c1",  # 76-79 tracks6-9
    "c1", "c1",  # 80-81 ocean cliffs
    "mr1b", "mr1", "fmu", "fta", "tr1b",  # 82-86
    "c1r2b", "c3r1b", "c4r1b", "c4r2b", "c5r2b", "c6r1b", "c7r1b",  # 87-93
    "c7r1b", "c7r1b", "c7r1b", "c7r1b", "c7r1b", "c7r1b",  # 94-99 ocean/island
    "mwf", "mwf", "mwf", "mwf", "mwf",  # 100-104 port/sea/ocean6-8
    "c1r2b", "c4r2b", "c5r2b",  # 105-107 west cliff bridges
]

_BLOCK_PALS: list[int] = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1,
    0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0,
    0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0,
    0, 0,
    1, 1, 1, 1, 1, 1,
    0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0,
    0, 0,
    1, 1, 1, 1, 1,
    0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 1,
    0, 0, 0,
]


@dataclass(frozen=True)
class ChromeSpec:
    name: str
    width: int
    height: int
    fmt: int
    siz: int
    prim_as_color: tuple[int, int, int, int] | None = None
    out_name: str | None = None


_CHROME: list[ChromeSpec] = [
    ChromeSpec("kan_win_map_tex", 64, 16, G_IM_FMT_I, G_IM_SIZ_4b, (85, 55, 55, 255), "map_label"),
    ChromeSpec("kan_win_acre_tex", 32, 16, G_IM_FMT_I, G_IM_SIZ_4b, (85, 55, 55, 255), "acre_label"),
    ChromeSpec("kan_win_cursor_tex", 16, 16, G_IM_FMT_I, G_IM_SIZ_4b, (255, 255, 255, 255), "cursor"),
    ChromeSpec("kan_win_w1_tex", 128, 32, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="frame_w1"),
    ChromeSpec("kan_win_w2_tex", 32, 64, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="frame_w2"),
    ChromeSpec("kan_win_w3_tex", 32, 32, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="frame_w3"),
    ChromeSpec("kan_win_saki_tex", 32, 32, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="info_panel"),
    ChromeSpec("kan_win_suuji1_tex", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="col_1"),
    ChromeSpec("kan_win_suuji2_tex", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="col_2"),
    ChromeSpec("kan_win_suuji3_tex", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="col_3"),
    ChromeSpec("kan_win_suuji4_tex", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="col_4"),
    ChromeSpec("kan_win_suuji5_tex", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="col_5"),
    ChromeSpec("kan_win_a_tex_rgb_ia8", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="row_a"),
    ChromeSpec("kan_win_b_tex_rgb_ia8", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="row_b"),
    ChromeSpec("kan_win_c_tex_rgb_ia8", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="row_c"),
    ChromeSpec("kan_win_d_tex_rgb_ia8", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="row_d"),
    ChromeSpec("kan_win_e_tex_rgb_ia8", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="row_e"),
    ChromeSpec("kan_win_f_tex_rgb_ia8", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="row_f"),
    ChromeSpec("kan_win_omise_tex", 16, 16, G_IM_FMT_I, G_IM_SIZ_4b, (195, 80, 45, 255), "icon_shop"),
    ChromeSpec("kan_win_kouban_tex", 16, 16, G_IM_FMT_I, G_IM_SIZ_4b, (195, 80, 45, 255), "icon_police"),
    ChromeSpec("kan_win_yubin_tex", 16, 16, G_IM_FMT_I, G_IM_SIZ_4b, (190, 70, 60, 255), "icon_post"),
    ChromeSpec("kan_win_yashiro_tex", 16, 16, G_IM_FMT_I, G_IM_SIZ_4b, (190, 70, 60, 255), "icon_shrine"),
    ChromeSpec("kan_win_eki_tex", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="icon_station"),
    ChromeSpec("kan_win_gomi_tex", 16, 16, G_IM_FMT_I, G_IM_SIZ_4b, (190, 70, 60, 255), "icon_dump"),
    ChromeSpec("kan_win_mu_tex", 16, 16, G_IM_FMT_I, G_IM_SIZ_4b, (190, 70, 60, 255), "icon_museum"),
    ChromeSpec("kan_win_ta_tex", 16, 16, G_IM_FMT_I, G_IM_SIZ_4b, (190, 70, 60, 255), "icon_able"),
    ChromeSpec("kan_win_fune_tex", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="icon_port"),
    ChromeSpec("kan_win_play_tex", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="here_mark"),
    ChromeSpec("kan_win_yane_tex", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="icon_house"),
]


def extract_map_ui(cfg: PipelineConfig) -> dict[str, Any]:
    rel_path = cfg.extracted_disc / "files" / "foresta.rel"
    map_path = cfg.extracted_disc / "files" / "foresta.map"
    if not rel_path.is_file() or not map_path.is_file():
        return {"results": [], "converted": 0, "error": f"missing {rel_path.name} or {map_path.name}"}

    rel = RelData(rel_path)
    by_name: dict[str, list[MapSymbol]] = {}
    for sym in parse_map(map_path):
        by_name.setdefault(sym.name, []).append(sym)

    out_dir = cfg.godot_generated / "ui" / "map"
    stage_dir = cfg.converted / "ui" / "map"
    tiles_out = out_dir / "tiles"
    chrome_out = out_dir / "chrome"
    tiles_stage = stage_dir / "tiles"
    chrome_stage = stage_dir / "chrome"
    for folder in (tiles_out, chrome_out, tiles_stage, chrome_stage):
        folder.mkdir(parents=True, exist_ok=True)

    results: list[dict[str, Any]] = []
    pals = [_pack_pal(_KAN_TIZU1_PAL), _pack_pal(_KAN_TIZU2_PAL)]

    for stem in _ACRE_STEMS:
        sym_name = f"kan_tizu_{stem}_TA_tex_txt"
        for pal_idx, pal in enumerate(pals):
            out_stem = f"{stem}_p{pal_idx}"
            results.append(
                _extract_ci4_tile(
                    rel,
                    by_name,
                    sym_name,
                    pal,
                    out_stem,
                    tiles_stage,
                    tiles_out,
                    cfg.project_root,
                )
            )

    for spec in _CHROME:
        results.extend(
            _extract_chrome(rel, by_name, spec, chrome_stage, chrome_out, cfg.project_root)
        )

    shell = _bake_window_shell(rel, by_name, chrome_stage, chrome_out, cfg.project_root)
    results.append(shell)

    catalog = {
        "tile_px": 32,
        "block_stems": _BLOCK_STEMS,
        "block_pals": _BLOCK_PALS,
        "tiles_dir": "ui/map/tiles",
        "chrome_dir": "ui/map/chrome",
        "window_shell": "ui/map/chrome/window_shell.png",
        "window_shell_native": [272, 204],
        "window_shell_inset": [34, 34, 34, 34],
    }
    for folder in (out_dir, stage_dir):
        (folder / "catalog.json").write_text(json.dumps(catalog, indent=2) + "\n")
    results.append({"asset_id": "catalog", "output_path": "ui/map/catalog.json", "status": "converted"})

    converted = sum(1 for r in results if r["status"] == "converted")
    return {"results": results, "converted": converted, "output": str(out_dir)}


def _pack_pal(entries: tuple[int, ...]) -> bytes:
    return struct.pack(f">{len(entries)}H", *entries)


def _pick_symbol(by_name: dict[str, list[MapSymbol]], name: str) -> MapSymbol:
    matches = by_name.get(name) or []
    if not matches:
        raise KeyError(name)
    return max(matches, key=lambda s: (s.size, -s.address))


def _extract_ci4_tile(
    rel: RelData,
    by_name: dict[str, list[MapSymbol]],
    sym_name: str,
    pal: bytes,
    out_stem: str,
    stage_dir: Path,
    out_dir: Path,
    project_root: Path,
) -> dict[str, Any]:
    dest_rel = f"ui/map/tiles/{out_stem}.png"
    record: dict[str, Any] = {
        "asset_id": out_stem,
        "source": sym_name,
        "output_path": dest_rel,
        "status": "pending",
        "error": None,
    }
    try:
        sym = _pick_symbol(by_name, sym_name)
        data = rel.slice_at(sym.address, min(sym.size, 512))
        image = decode_gbi_texture(data, 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, pal)
        ## Map acres abut; transparent CI edge texels left cream gaps in Godot. Fill
        ## them with the nearest opaque colour so neighbouring tiles connect.
        image = _fill_transparent(image)
        png = image_png_bytes(image)
        for folder in (stage_dir, out_dir):
            path = folder / f"{out_stem}.png"
            path.write_bytes(png)
        write_import_sidecar(out_dir / f"{out_stem}.png", project_root)
        record["status"] = "converted"
    except Exception as exc:  # noqa: BLE001
        record["status"] = "error"
        record["error"] = f"{type(exc).__name__}: {exc}"
    return record


def _extract_chrome(
    rel: RelData,
    by_name: dict[str, list[MapSymbol]],
    spec: ChromeSpec,
    stage_dir: Path,
    out_dir: Path,
    project_root: Path,
) -> list[dict[str, Any]]:
    out_stem = spec.out_name or spec.name
    dest_rel = f"ui/map/chrome/{out_stem}.png"
    record: dict[str, Any] = {
        "asset_id": out_stem,
        "source": spec.name,
        "output_path": dest_rel,
        "status": "pending",
        "error": None,
    }
    extras: list[dict[str, Any]] = []
    try:
        sym = _pick_symbol(by_name, spec.name)
        need = spec.width * spec.height
        if spec.fmt == G_IM_FMT_CI or (spec.fmt == G_IM_FMT_I and spec.siz == G_IM_SIZ_4b):
            need //= 2
        data = rel.slice_at(sym.address, min(sym.size, max(need, 16)))
        image = decode_gbi_texture(data, spec.width, spec.height, spec.fmt, spec.siz, b"")
        if spec.prim_as_color is not None:
            image = _i_texel_as_alpha(image, spec.prim_as_color)
        png = image_png_bytes(image)
        for folder in (stage_dir, out_dir):
            path = folder / f"{out_stem}.png"
            path.write_bytes(png)
        write_import_sidecar(out_dir / f"{out_stem}.png", project_root)
        record["status"] = "converted"
        if out_stem == "cursor":
            frame = _compose_cursor_frame(image)
            frame_stem = "cursor_frame"
            png_frame = image_png_bytes(frame)
            for folder in (stage_dir, out_dir):
                (folder / f"{frame_stem}.png").write_bytes(png_frame)
            write_import_sidecar(out_dir / f"{frame_stem}.png", project_root)
            extras.append(
                {
                    "asset_id": frame_stem,
                    "source": spec.name,
                    "output_path": f"ui/map/chrome/{frame_stem}.png",
                    "status": "converted",
                }
            )
    except Exception as exc:  # noqa: BLE001
        record["status"] = "error"
        record["error"] = f"{type(exc).__name__}: {exc}"
    return [record, *extras]


def _compose_cursor_frame(corner: Image.Image) -> Image.Image:
    """Mirror the I4 corner into a full selection frame (GX_MIRROR on the model)."""
    c = corner.convert("RGBA")
    w, h = c.size
    frame = Image.new("RGBA", (w * 2, h * 2), (0, 0, 0, 0))
    tl = c
    tr = c.transpose(Image.FLIP_LEFT_RIGHT)
    bl = c.transpose(Image.FLIP_TOP_BOTTOM)
    br = tr.transpose(Image.FLIP_TOP_BOTTOM)
    frame.paste(tl, (0, 0), tl)
    frame.paste(tr, (w, 0), tr)
    frame.paste(bl, (0, h), bl)
    frame.paste(br, (w, h), br)
    return frame


def _fill_transparent(image: Image.Image) -> Image.Image:
    """Replace fully transparent texels with nearest opaque RGB (alpha 255)."""
    img = image.convert("RGBA")
    w, h = img.size
    px = img.load()
    opaque: list[tuple[int, int]] = []
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > 0:
                opaque.append((x, y))
    if not opaque:
        return img
    # Seed: flood from opaque outward (a few passes covers CI edge rings).
    for _ in range(max(w, h)):
        changed = False
        for y in range(h):
            for x in range(w):
                if px[x, y][3] > 0:
                    continue
                best = None
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and px[nx, ny][3] > 0:
                        best = px[nx, ny]
                        break
                if best is not None:
                    px[x, y] = (best[0], best[1], best[2], 255)
                    changed = True
        if not changed:
            break
    return img


## `kan_win_color0_mode` first pair — yellow window shell (PRIM / ENV).
_WINDOW_PRIM = (255, 255, 85, 255)
_WINDOW_ENV = (185, 0, 0, 255)

## `kan_win_kiwakuT_model` batches after `gsSPVertex(&kan_win_v[12], 27, 0)`.
## Indices are relative to that load; wrap/mirror match the GBI tile modes.
_KIWAKU_BATCHES: list[tuple[str, str, tuple[int, ...]]] = [
    (
        "w3",
        "wrap",
        (0, 1, 2, 3, 1, 0, 4, 5, 6, 5, 7, 6, 1, 8, 9, 9, 8, 10),
    ),
    (
        "w2",
        "mirror",
        (11, 12, 13, 11, 13, 14, 15, 16, 17, 15, 18, 16),
    ),
    (
        "w1",
        "mirror",
        (19, 20, 21, 20, 22, 21, 23, 24, 25, 26, 23, 25),
    ),
]
_KIWAKU_VTX_BASE = 12
_KIWAKU_VTX_COUNT = 27
_SHELL_BAKE_SCALE = 2


@dataclass(frozen=True)
class _UiVtx:
    x: int
    y: int
    s: float
    t: float


def _ia_prim_env(image: Image.Image, prim: tuple[int, int, int, int], env: tuple[int, int, int, int]) -> Image.Image:
    """Combiner PRIM, ENV, TEXEL0, ENV — lerp(ENV, PRIM, intensity)."""
    pr, pg, pb, _pa = prim
    er, eg, eb, ea = env
    rgba = image.convert("RGBA")
    r, g, b, a = rgba.split()
    # Intensity from RGB average of IA decode (R=G=B=I).
    out_r = r.point(lambda v, p=pr, e=er: e + (p - e) * v // 255)
    out_g = g.point(lambda v, p=pg, e=eg: e + (p - e) * v // 255)
    out_b = b.point(lambda v, p=pb, e=eb: e + (p - e) * v // 255)
    out_a = a.point(lambda v, e=ea: v * e // 255 if e < 255 else v)
    return Image.merge("RGBA", (out_r, out_g, out_b, out_a))


def _parse_ui_vtx(blob: bytes) -> list[_UiVtx]:
    if len(blob) % 16 != 0:
        raise ValueError("Vtx blob is not a multiple of 16 bytes")
    verts: list[_UiVtx] = []
    for i in range(0, len(blob), 16):
        x, y, _z, _flag, u_raw, v_raw, _r, _g, _b, _a = struct.unpack_from(">hhhHhhBBBB", blob, i)
        verts.append(_UiVtx(x=x, y=y, s=u_raw / 32.0, t=v_raw / 32.0))
    return verts


def _edge(a: tuple[float, float], b: tuple[float, float], p: tuple[float, float]) -> float:
    return (p[0] - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (p[1] - b[1])


def _tex_coord(c: float, size: int, *, mode: str) -> int:
    if size <= 0:
        return 0
    if mode == "mirror":
        period = size * 2
        pos = c % period
        if pos < 0.0:
            pos += period
        if pos >= size:
            pos = period - pos
        idx = int(pos)
    elif mode == "wrap":
        idx = int(c % size)
        if idx < 0:
            idx += size
    else:
        idx = int(c)
    if idx >= size:
        idx = size - 1
    return max(0, idx)


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
    mode: str,
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
            w0 = _edge(p1, p2, (px + 0.5, py + 0.5)) / area
            w1 = _edge(p2, p0, (px + 0.5, py + 0.5)) / area
            w2 = _edge(p0, p1, (px + 0.5, py + 0.5)) / area
            if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
                continue
            s = st0[0] * w0 + st1[0] * w1 + st2[0] * w2
            t = st0[1] * w0 + st1[1] * w1 + st2[1] * w2
            xi = _tex_coord(s, tex_w, mode=mode)
            yi = _tex_coord(t, tex_h, mode=mode)
            sr, sg, sb, sa = tex_px[xi, yi]
            if sa <= 0:
                continue
            dr, dg, db, da = out_px[px, py]
            alpha = sa / 255.0
            inv = 1.0 - alpha
            out_px[px, py] = (
                int(dr * inv + sr * alpha),
                int(dg * inv + sg * alpha),
                int(db * inv + sb * alpha),
                max(da, sa),
            )


def _fill_enclosed_holes(image: Image.Image, *, sample_xy: tuple[int, int]) -> None:
    """Paint interior transparent pockets with the body colour (keep exterior alpha)."""
    w, h = image.size
    px = image.load()
    exterior = [[False] * w for _ in range(h)]
    stack: list[tuple[int, int]] = []
    for x in range(w):
        stack.append((x, 0))
        stack.append((x, h - 1))
    for y in range(h):
        stack.append((0, y))
        stack.append((w - 1, y))
    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= w or y >= h or exterior[y][x]:
            continue
        if px[x, y][3] > 8:
            continue
        exterior[y][x] = True
        stack.extend(((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)))
    sx, sy = sample_xy
    fill = px[max(0, min(w - 1, sx)), max(0, min(h - 1, sy))]
    if fill[3] < 8:
        fill = (*_WINDOW_PRIM[:3], 255)
    for y in range(h):
        for x in range(w):
            if px[x, y][3] <= 8 and not exterior[y][x]:
                px[x, y] = fill


def _bake_window_shell(
    rel: RelData,
    by_name: dict[str, list[MapSymbol]],
    stage_dir: Path,
    out_dir: Path,
    project_root: Path,
) -> dict[str, Any]:
    """Rasterize `kan_win_kiwakuT_model` — scalloped yellow map window silhouette."""
    record: dict[str, Any] = {
        "asset_id": "window_shell",
        "source": "kan_win_kiwakuT_model + color0",
        "output_path": "ui/map/chrome/window_shell.png",
        "status": "pending",
        "error": None,
    }
    try:
        w1 = _ia_prim_env(Image.open(out_dir / "frame_w1.png"), _WINDOW_PRIM, _WINDOW_ENV)
        w2 = _ia_prim_env(Image.open(out_dir / "frame_w2.png"), _WINDOW_PRIM, _WINDOW_ENV)
        w3 = _ia_prim_env(Image.open(out_dir / "frame_w3.png"), _WINDOW_PRIM, _WINDOW_ENV)
        tiles = {"w1": w1, "w2": w2, "w3": w3}

        vtx_sym = _pick_symbol(by_name, "kan_win_v")
        verts = _parse_ui_vtx(rel.slice_at(vtx_sym.address, vtx_sym.size))
        loaded = verts[_KIWAKU_VTX_BASE : _KIWAKU_VTX_BASE + _KIWAKU_VTX_COUNT]
        if len(loaded) < _KIWAKU_VTX_COUNT:
            raise ValueError(f"kan_win_v too short for kiwaku ({len(loaded)})")

        # Submenu units are 1:1 with vtx coords (Matrix_scale(16) cancelled by projection).
        # Flip Y (N64 up) and shift so the outer AABB lands at the origin.
        xs = [float(v.x) for v in loaded]
        ys = [float(-v.y) for v in loaded]
        min_x, max_x = min(xs), max(xs)
        min_y, max_y = min(ys), max(ys)
        scale = float(_SHELL_BAKE_SCALE)
        width = max(1, int(round((max_x - min_x) * scale)))
        height = max(1, int(round((max_y - min_y) * scale)))
        shell = Image.new("RGBA", (width, height), (0, 0, 0, 0))

        def to_px(v: _UiVtx) -> tuple[float, float]:
            return ((v.x - min_x) * scale, (-v.y - min_y) * scale)

        for tile_key, mode, indices in _KIWAKU_BATCHES:
            tex = tiles[tile_key]
            for tri in range(0, len(indices), 3):
                i0, i1, i2 = indices[tri : tri + 3]
                v0, v1, v2 = loaded[i0], loaded[i1], loaded[i2]
                _draw_textured_triangle(
                    shell,
                    tex,
                    to_px(v0),
                    to_px(v1),
                    to_px(v2),
                    (v0.s, v0.t),
                    (v1.s, v1.t),
                    (v2.s, v2.t),
                    mode=mode,
                )

        # Kiwaku's w3 batch only covers the left body; the game draws label chrome
        # (`kan_win_model2`) into the right cutout. Fill enclosed holes so the shell
        # is a continuous yellow window for Godot.
        _fill_enclosed_holes(shell, sample_xy=(width // 3, height // 2))

        for name, img in (("window_w1", w1), ("window_w2", w2), ("window_w3", w3)):
            png = image_png_bytes(img)
            for folder in (stage_dir, out_dir):
                (folder / f"{name}.png").write_bytes(png)
            write_import_sidecar(out_dir / f"{name}.png", project_root)

        png = image_png_bytes(shell)
        for folder in (stage_dir, out_dir):
            (folder / "window_shell.png").write_bytes(png)
        write_import_sidecar(out_dir / "window_shell.png", project_root)
        record["status"] = "converted"
        record["width"] = width
        record["height"] = height
    except Exception as exc:  # noqa: BLE001
        record["status"] = "error"
        record["error"] = f"{type(exc).__name__}: {exc}"
    return record


def _i_texel_as_alpha(image: Image.Image, prim: tuple[int, int, int, int]) -> Image.Image:
    """GBI: RGB = PRIMITIVE, A = TEXEL (intensity)."""
    pr, pg, pb, pa = prim
    intensity = image.convert("RGBA").split()[0]
    alpha = intensity.point(lambda v, p=pa: v * p // 255)
    solid = Image.new("RGB", image.size, (pr, pg, pb))
    out = solid.convert("RGBA")
    out.putalpha(alpha)
    return out
