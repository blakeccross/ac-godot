"""Extract inventory window chrome from foresta.rel.

Formats/sizes come from decomp `inv_mwin.c` / `inv_mwin_g.c` GBI. Prefer ACHD
(hi-res) sheets when configured. Output is gitignored under
`assets/generated/ui/inventory/` — Nintendo IP, not for commit.
"""

from __future__ import annotations

from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import Any

import json

from PIL import Image

from .achd import load_achd_pack, maybe_hd_png
from .config import PipelineConfig
from .godot_import import write_import_sidecar
from .mapfile import MapSymbol, parse_map
from .rel import RelData
from .map_ui import _edge, _mirror_tile, _parse_ui_vtx
from .texbank import (
    G_IM_FMT_CI,
    G_IM_FMT_I,
    G_IM_FMT_IA,
    G_IM_SIZ_4b,
    G_IM_SIZ_8b,
    GX_CLAMP,
    decode_gbi_texture,
    gbi_to_gx,
    image_png_bytes,
)

# Prefer the inv_mwin.c dataobject cluster (US GAFE01 map); fall back to any match.
_CLUSTER_LO = 0x00438000
_CLUSTER_HI = 0x00447000

_NATIVE_W = 240
_NATIVE_H = 180
_SHELL_ORIGIN = (-120, 90)
_BAKE_SCALE = 4
## Internal supersample for shell silhouette AA (final PNG stays bake_scale).
_SHELL_SSAA = 2
_INV_VTX_COUNT = 296
_ITEM_SLOT_BASE = 176
_ITEM_SLOT_COUNT = 15
_MAIL_SLOT_BASE = 236
_MAIL_SLOT_COUNT = 10

# (vtx_base, frame stem, triangle index triples) from inv_mwin.c border DLs.
_BORDER_PIECES: list[tuple[int, str, tuple[tuple[int, int, int], ...]]] = [
    (72, "frame_w1", ((0, 1, 2), (1, 3, 2))),  # w1T
    (76, "frame_w3", ((0, 1, 2), (1, 3, 2))),  # w2T
    (80, "frame_w4", ((0, 1, 2), (1, 3, 2))),  # w3T
    (84, "frame_w3", ((0, 1, 2), (3, 0, 2))),  # w4T
    (88, "frame_w1", ((0, 1, 2), (3, 0, 2))),  # w5T
    (92, "frame_w6", ((0, 1, 2), (0, 2, 3))),  # w6T
    (96, "frame_w1", ((0, 1, 2), (1, 3, 2))),  # w7T
    (100, "frame_w3", ((0, 1, 2), (1, 3, 2))),  # w8T
    (104, "frame_w4", ((0, 1, 2), (3, 0, 2))),  # w9T
    (108, "frame_w3", ((0, 1, 2), (3, 0, 2))),  # w10T
    (112, "frame_w1", ((0, 1, 2), (3, 0, 2))),  # w11T
    (116, "frame_w2", ((0, 1, 2), (0, 3, 1))),  # w12T
    # w13 center uses w5 CI; native sheet is index-0 only — paper fill covers this rect.
]

# inv_mwin_1cT_model — white I4 scalloped rim (triangle indices from inv_mwin.c).
_RIM_BATCHES: list[tuple[str, int, int, tuple[tuple[int, int, int], ...]]] = [
    (
        "inv_mwin_aw5_tex.png",
        124,
        30,
        (
            (0, 1, 2),
            (1, 3, 2),
            (2, 4, 5),
            (4, 6, 5),
            (7, 0, 8),
            (7, 9, 0),
            (1, 9, 10),
            (9, 11, 10),
            (10, 12, 3),
            (12, 4, 3),
            (13, 11, 14),
            (13, 15, 11),
            (16, 17, 7),
            (16, 18, 17),
            (19, 20, 5),
            (19, 21, 20),
        ),
    ),
    (
        "inv_mwin_aw4_tex.png",
        124,
        30,
        ((22, 23, 24), (24, 25, 22), (26, 27, 28), (27, 29, 28)),
    ),
    (
        "inv_mwin_aw3_tex.png",
        154,
        22,
        (
            (0, 1, 2),
            (1, 3, 2),
            (4, 5, 6),
            (5, 7, 6),
            (8, 9, 10),
            (9, 11, 10),
            (12, 13, 14),
            (14, 15, 12),
        ),
    ),
    (
        "inv_mwin_aw6_tex.png",
        154,
        22,
        ((16, 17, 18), (16, 19, 17), (16, 20, 19), (20, 21, 19)),
    ),
]




@dataclass(frozen=True)
class TexSpec:
    name: str
    width: int
    height: int
    fmt: int
    siz: int
    pal: str | None = None
    ## When set, RGB = prim and texel intensity becomes alpha (label-style I4).
    prim_as_color: tuple[int, int, int, int] | None = None
    ## Optional second write with env-colored IA ring preview.
    env_preview: tuple[int, int, int, int] | None = None
    out_name: str | None = None
    native_only: bool = False


# Window chrome used by mIV_set_*_frame_dl / inv_mwin_model.
# `out_name` is the Godot-facing stem under ui/inventory/.
CHROME: list[TexSpec] = [
    TexSpec("inv_mwin_w1_tex_rgb_ci4", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_w1_tex_rgb_ci4_pal", out_name="frame_w1"),
    TexSpec("inv_mwin_w2_tex_rgb_ci4", 32, 64, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_w2_tex_rgb_ci4_pal", out_name="frame_w2"),
    TexSpec("inv_mwin_w3_tex_rgb_ci4", 64, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_w3_tex_rgb_ci4_pal", out_name="frame_w3"),
    TexSpec("inv_mwin_w4_tex_rgb_ci4", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_w4_tex_rgb_ci4_pal", out_name="frame_w4"),
    TexSpec("inv_mwin_w5_tex_rgb_ci4", 16, 16, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_w1_tex_rgb_ci4_pal", out_name="frame_w5"),
    TexSpec("inv_mwin_w6_tex_rgb_ci4", 32, 64, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_w6_tex_rgb_ci4_pal", out_name="frame_w6"),
    TexSpec(
        "inv_mwin_nwaku_tex",
        32,
        32,
        G_IM_FMT_IA,
        G_IM_SIZ_8b,
        env_preview=(100, 100, 255, 255),
        out_name="slot_ring",
    ),
    TexSpec(
        "inv_mwin_items_tex",
        64,
        16,
        G_IM_FMT_I,
        G_IM_SIZ_4b,
        prim_as_color=(120, 120, 225, 255),
        out_name="items_label",
    ),
    TexSpec(
        "inv_mwin_letters_tex",
        64,
        16,
        G_IM_FMT_I,
        G_IM_SIZ_4b,
        prim_as_color=(195, 80, 80, 255),
        out_name="letters_label",
    ),
    TexSpec(
        "inv_mwin_bells_tex",
        64,
        16,
        G_IM_FMT_I,
        G_IM_SIZ_4b,
        prim_as_color=(70, 160, 190, 255),
        out_name="bells_label",
    ),
    TexSpec("inv_mwin_suujiwaku1_tex", 16, 32, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="bells_frame"),
    TexSpec("inv_mwin_suujiwaku2_tex", 16, 32, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="bells_frame2"),
    TexSpec(
        "inv_mwin_3Dma_tex",
        64,
        64,
        G_IM_FMT_I,
        G_IM_SIZ_4b,
        prim_as_color=(100, 155, 255, 255),
        out_name="portrait_frame",
    ),
    TexSpec("inv_mwin_shirushi4_tex", 32, 32, G_IM_FMT_I, G_IM_SIZ_4b, prim_as_color=(100, 80, 100, 255)),
    TexSpec("inv_original_shirushi_tex", 32, 32, G_IM_FMT_I, G_IM_SIZ_4b, prim_as_color=(75, 50, 40, 255)),
    TexSpec("inv_original_shirushi3_tex", 32, 64, G_IM_FMT_IA, G_IM_SIZ_8b),
    TexSpec(
        "inv_mwin_sen_tex",
        16,
        16,
        G_IM_FMT_I,
        G_IM_SIZ_4b,
        prim_as_color=(70, 170, 255, 200),
        out_name="name_bar",
    ),
    TexSpec(
        "inv_mwin_sen2_tex",
        16,
        16,
        G_IM_FMT_I,
        G_IM_SIZ_4b,
        prim_as_color=(70, 170, 255, 200),
        out_name="name_bar2",
    ),
    TexSpec("originl", 32, 32, G_IM_FMT_I, G_IM_SIZ_4b, out_name="inv_mwin_originl"),
    TexSpec("original2", 32, 64, G_IM_FMT_I, G_IM_SIZ_4b, out_name="inv_mwin_original2"),
    TexSpec("inv_mwin_aw3_tex", 64, 32, G_IM_FMT_I, G_IM_SIZ_4b),
    TexSpec("inv_mwin_aw4_tex", 32, 32, G_IM_FMT_I, G_IM_SIZ_4b),
    TexSpec("inv_mwin_aw5_tex", 16, 16, G_IM_FMT_I, G_IM_SIZ_4b),
    TexSpec("inv_mwin_aw6_tex", 32, 64, G_IM_FMT_I, G_IM_SIZ_4b),
    TexSpec("inv_mwin_gmushi_tex", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_gmushi_pal", out_name="tab_bug"),
    TexSpec("inv_mwin_gturi_tex", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_gturi_pal", out_name="tab_fish"),
    TexSpec("inv_mwin_gscoop_tex", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_gscoop_pal", out_name="tab_scoop"),
    TexSpec("inv_mwin_gono_tex", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_gono_pal", out_name="tab_axe"),
    TexSpec("inv_mwin_mtegami_tex", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_mtegami_pal", out_name="letter"),
    TexSpec("inv_mwin_pmtegami_tex", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_mtegami_pal", out_name="letter_present"),
    TexSpec("inv_mwin_otegami_tex", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_otegami_pal", out_name="letter_open"),
    TexSpec("inv_mwin_potegami_tex", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_otegami_pal", out_name="letter_open_present"),
    TexSpec("inv_mwin_mtegami2_tex", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_mtegami2_pal", out_name="letter_alt"),
    TexSpec("inv_win_mark_tex", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b, out_name="cursor_mark"),
]


def extract_inventory_ui(cfg: PipelineConfig) -> dict[str, Any]:
    rel_path = cfg.extracted_disc / "files" / "foresta.rel"
    map_path = cfg.extracted_disc / "files" / "foresta.map"
    if not rel_path.is_file() or not map_path.is_file():
        return {"results": [], "converted": 0, "error": f"missing {rel_path.name} or {map_path.name}"}

    rel = RelData(rel_path)
    symbols = parse_map(map_path)
    by_name: dict[str, list[MapSymbol]] = {}
    for sym in symbols:
        by_name.setdefault(sym.name, []).append(sym)

    out_dir = cfg.godot_generated / "ui" / "inventory"
    stage_dir = cfg.converted / "ui" / "inventory"
    out_dir.mkdir(parents=True, exist_ok=True)
    stage_dir.mkdir(parents=True, exist_ok=True)

    achd = (
        load_achd_pack(cfg.achd_root, cfg.achd_cache)
        if cfg.achd_enabled and cfg.achd_root is not None
        else None
    )

    results: list[dict[str, Any]] = []
    project_root = cfg.project_root
    for spec in CHROME:
        record = _extract_one(rel, by_name, spec, stage_dir, out_dir, project_root, achd=achd)
        results.append(record)
        if record["status"] == "converted" and spec.env_preview is not None:
            preview = _extract_one(
                rel,
                by_name,
                TexSpec(
                    spec.name,
                    spec.width,
                    spec.height,
                    spec.fmt,
                    spec.siz,
                    env_preview=spec.env_preview,
                    out_name="slot_item",
                ),
                stage_dir,
                out_dir,
                project_root,
                force_env=True,
                achd=achd,
            )
            results.append(preview)
            red = _extract_one(
                rel,
                by_name,
                TexSpec(
                    spec.name,
                    spec.width,
                    spec.height,
                    spec.fmt,
                    spec.siz,
                    env_preview=(255, 60, 60, 255),
                    out_name="slot_letter",
                ),
                stage_dir,
                out_dir,
                project_root,
                force_env=True,
                achd=achd,
            )
            results.append(red)

    paper = _copy_default_paper(cfg, stage_dir, out_dir)
    if paper is not None:
        results.append(paper)

    shell = _bake_inventory_window_shell(rel, by_name, stage_dir, out_dir, project_root, achd=achd)
    results.append(shell["record"])
    catalog_path = shell.get("catalog_path")

    converted = sum(1 for r in results if r["status"] == "converted")
    achd_hits = sum(1 for r in results if (r.get("meta") or {}).get("achd"))
    out: dict[str, Any] = {
        "results": results,
        "converted": converted,
        "achd_hits": achd_hits,
        "output": str(out_dir),
    }
    if catalog_path:
        out["catalog"] = catalog_path
    if shell.get("width") and shell.get("height"):
        out["window_shell"] = {
            "path": "ui/inventory/window_shell.png",
            "width": shell["width"],
            "height": shell["height"],
            "alpha_bbox": shell.get("alpha_bbox"),
        }
    return out


def _pick_symbol(by_name: dict[str, list[MapSymbol]], name: str) -> MapSymbol:
    matches = by_name.get(name) or []
    if not matches:
        raise KeyError(name)
    in_cluster = [s for s in matches if _CLUSTER_LO <= s.address < _CLUSTER_HI]
    pool = in_cluster or matches
    # Prefer the largest map size when duplicates differ (shared nwaku copies).
    return max(pool, key=lambda s: (s.size, -s.address))


def _extract_one(
    rel: RelData,
    by_name: dict[str, list[MapSymbol]],
    spec: TexSpec,
    stage_dir: Path,
    out_dir: Path,
    project_root: Path,
    *,
    force_env: bool = False,
    achd=None,
) -> dict[str, Any]:
    out_stem = spec.out_name or spec.name
    dest_rel = f"ui/inventory/{out_stem}.png"
    record: dict[str, Any] = {
        "asset_id": out_stem,
        "source": spec.name,
        "output_path": dest_rel,
        "status": "pending",
        "error": None,
    }
    try:
        sym = _pick_symbol(by_name, spec.name)
        data = rel.slice_at(sym.address, sym.size)
        pal = b""
        if spec.pal:
            pal_sym = _pick_symbol(by_name, spec.pal)
            pal = rel.slice_at(pal_sym.address, min(pal_sym.size, 512))
        gx = gbi_to_gx(spec.fmt, spec.siz)
        ## Prefer ACHD for chrome; `native_only` remains for rare false-hits.
        hd = None
        if not spec.native_only:
            hd = maybe_hd_png(
                achd,
                data,
                spec.width,
                spec.height,
                gx,
                pal if spec.fmt == G_IM_FMT_CI else None,
                wrap_s=GX_CLAMP,
                wrap_t=GX_CLAMP,
            )
        used_achd = False
        if hd is not None:
            image = Image.open(BytesIO(hd)).convert("RGBA")
            used_achd = True
        else:
            image = decode_gbi_texture(data, spec.width, spec.height, spec.fmt, spec.siz, pal)
        if spec.prim_as_color is not None and not force_env:
            ## ACHD I4 labels are often white-on-black; same combiner as native.
            image = _i_texel_as_alpha(image, spec.prim_as_color)
        ## Env tint the IA quadrant first (native ST / rim calibrated for one sheet),
        ## then GX_MIRROR to a full ring — faster and sharper at ACHD sizes.
        if force_env and spec.env_preview is not None:
            image = _ia_env_preview(image, spec.env_preview)
        if force_env or spec.out_name in ("slot_ring", "portrait_frame"):
            image = _mirror_tile(image)
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


def _i_texel_as_alpha(image: Image.Image, prim: tuple[int, int, int, int]) -> Image.Image:
    """GBI: RGB = PRIMITIVE, A = TEXEL (intensity)."""
    pr, pg, pb, pa = prim
    intensity = image.convert("RGBA").split()[0]
    alpha = intensity.point(lambda v, p=pa: v * p // 255)
    solid = Image.new("RGB", image.size, (pr, pg, pb))
    out = solid.convert("RGBA")
    out.putalpha(alpha)
    return out


def _ia_env_preview(image: Image.Image, env: tuple[int, int, int, int]) -> Image.Image:
    """Pocket slot: transparent outside (I≈187), thick ENV rim, dark fill (I≈0)."""
    er, eg, eb, _ea = env
    rgba = image.convert("RGBA")
    w, h = rgba.size
    src = rgba.load()
    ## Rim thickness scales with sheet size (native quadrant 32 → radius 3).
    rim_r = max(3, int(round(3.0 * max(w, h) / 32.0)))
    rim_r2 = rim_r * rim_r
    # First pass: classify pixels.
    kind = [[0] * w for _ in range(h)]  # 0 outside, 1 fill, 2 edge
    for y in range(h):
        for x in range(w):
            intensity, _g, _b, alpha = src[x, y]
            if alpha <= 0 or intensity >= 170:
                continue
            kind[y][x] = 1 if intensity <= 24 else 2
    # Dilate fill→edge contact into a thicker rim (WW rings are ~3–4px @ native).
    rim_mask = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if kind[y][x] != 1:
                continue
            for dy in range(-rim_r, rim_r + 1):
                for dx in range(-rim_r, rim_r + 1):
                    if dx * dx + dy * dy > rim_r2:
                        continue
                    nx, ny = x + dx, y + dy
                    if nx < 0 or ny < 0 or nx >= w or ny >= h:
                        continue
                    if kind[ny][nx] == 0 or kind[ny][nx] == 2:
                        rim_mask[ny][nx] = True
    fill = (72, 62, 88) if er < 200 else (110, 48, 48)
    rim = (min(255, er + 55), min(255, eg + 55), min(255, eb + 30))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dst = out.load()
    for y in range(h):
        for x in range(w):
            if rim_mask[y][x]:
                dst[x, y] = (*rim, 255)
            elif kind[y][x] == 1:
                dst[x, y] = (*fill, 240)
            elif kind[y][x] == 2:
                dst[x, y] = (*rim, 255)
    return out


def _copy_default_paper(cfg: PipelineConfig, stage_dir: Path, out_dir: Path) -> dict[str, Any] | None:
    """ITM_CLOTH226 is the default inventory paper (`backgound_texture`)."""
    src = cfg.godot_generated / "textures" / "player" / "shirts" / "shirt_226.png"
    if not src.is_file():
        return {
            "asset_id": "paper",
            "source": "shirt_226.png",
            "output_path": "ui/inventory/paper.png",
            "status": "skipped",
            "error": "shirt_226.png not generated yet",
        }
    dest_name = "paper.png"
    # Soften toward cream so the pocket sheet matches the classic screenshot
    # (cloth226 encodes as saturated yellow in our decode).
    paper = Image.open(src).convert("RGBA")
    paper = _cream_paper(paper)
    data = image_png_bytes(paper)
    for folder in (stage_dir, out_dir):
        (folder / dest_name).write_bytes(data)
    write_import_sidecar(out_dir / dest_name, project_root=cfg.project_root)
    ## Keep legacy stem for older references.
    for folder in (stage_dir, out_dir):
        (folder / "paper_cloth226.png").write_bytes(data)
    write_import_sidecar(out_dir / "paper_cloth226.png", cfg.project_root)
    return {
        "asset_id": "paper",
        "source": str(src),
        "output_path": f"ui/inventory/{dest_name}",
        "status": "converted",
        "error": None,
        "meta": {"achd": src.stat().st_size > 2048, "cream": True},
    }


def _cream_paper(image: Image.Image) -> Image.Image:
    """Lift saturated yellow big-dot shirt toward cream polka paper."""
    px = image.load()
    w, h = image.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a <= 0:
                continue
            # Near-white dots stay white; yellow field → cream.
            if r > 240 and g > 240 and b > 240:
                px[x, y] = (255, 255, 255, a)
                continue
            cream_r, cream_g, cream_b = (255, 248, 208)
            nr = int(r * 0.18 + cream_r * 0.82)
            ng = int(g * 0.18 + cream_g * 0.82)
            nb = int(b * 0.10 + cream_b * 0.90)
            px[x, y] = (nr, ng, nb, a)
    return image

def _vtx_to_px(x: float, y: float) -> tuple[float, float]:
    ox, oy = _SHELL_ORIGIN
    return ((x - ox) * _BAKE_SCALE, (oy - y) * _BAKE_SCALE)


def _quad_bounds(verts: list, base: int) -> dict[str, int]:
    xs = [float(verts[base + j].x) for j in range(4)]
    ys = [float(verts[base + j].y) for j in range(4)]
    min_x, max_x = int(min(xs)), int(max(xs))
    min_y, max_y = int(min(ys)), int(max(ys))
    cx = int(round(sum(xs) / 4.0))
    cy = int(round(sum(ys) / 4.0))
    return {
        "x": cx,
        "y": cy,
        "min_x": min_x,
        "min_y": min_y,
        "max_x": max_x,
        "max_y": max_y,
        "w": max_x - min_x,
        "h": max_y - min_y,
    }


def _px_rect_centered(cx: float, cy: float, size: float) -> dict[str, float]:
    """Center (cx,cy) + side length in vtx → bake-pixel rect (top-left origin)."""
    half = size * 0.5
    x0, y0 = _vtx_to_px(cx - half, cy + half)
    x1, y1 = _vtx_to_px(cx + half, cy - half)
    return {
        "x": min(x0, x1),
        "y": min(y0, y1),
        "w": abs(x1 - x0),
        "h": abs(y1 - y0),
    }


def _px_rect_aabb(min_x: float, min_y: float, max_x: float, max_y: float) -> dict[str, float]:
    x0, y0 = _vtx_to_px(min_x, max_y)
    x1, y1 = _vtx_to_px(max_x, min_y)
    return {
        "x": min(x0, x1),
        "y": min(y0, y1),
        "w": abs(x1 - x0),
        "h": abs(y1 - y0),
    }


def _build_layout_catalog(verts: list) -> dict[str, Any]:
    items: list[dict[str, Any]] = []
    for i in range(_ITEM_SLOT_COUNT):
        base = _ITEM_SLOT_BASE + i * 4
        b = _quad_bounds(verts, base)
        size = max(b["w"], b["h"])
        items.append(
            {
                "i": i,
                "x": b["x"],
                "y": b["y"],
                "size": size,
                "px": _px_rect_centered(b["x"], b["y"], size),
            }
        )
    mail: list[dict[str, Any]] = []
    for i in range(_MAIL_SLOT_COUNT):
        base = _MAIL_SLOT_BASE + i * 4
        b = _quad_bounds(verts, base)
        size = max(b["w"], b["h"])
        mail.append(
            {
                "i": i,
                "x": b["x"],
                "y": b["y"],
                "size": size,
                "px": _px_rect_centered(b["x"], b["y"], size),
            }
        )
    portrait_b = _quad_bounds(verts, 276)
    bells_xs: list[int] = []
    bells_ys: list[int] = []
    for j in range(12):
        bells_xs.append(int(verts[284 + j].x))
        bells_ys.append(int(verts[284 + j].y))
    bells_min_x, bells_max_x = min(bells_xs), max(bells_xs)
    bells_min_y, bells_max_y = min(bells_ys), max(bells_ys)

    def label_rect(base: int) -> dict[str, Any]:
        b = _quad_bounds(verts, base)
        return {
            "x": b["min_x"],
            "y": b["min_y"],
            "w": b["w"],
            "h": b["h"],
            "px": _px_rect_aabb(b["min_x"], b["min_y"], b["max_x"], b["max_y"]),
        }

    portrait_size = max(portrait_b["w"], portrait_b["h"])
    return {
        "native_size": [_NATIVE_W, _NATIVE_H],
        "bake_size": [_NATIVE_W * _BAKE_SCALE, _NATIVE_H * _BAKE_SCALE],
        "bake_scale": _BAKE_SCALE,
        "origin": list(_SHELL_ORIGIN),
        "items": items,
        "mail": mail,
        "portrait": {
            "x": portrait_b["x"],
            "y": portrait_b["y"],
            "size": portrait_size,
            "px": _px_rect_centered(portrait_b["x"], portrait_b["y"], portrait_size),
        },
        "bells_frame": {
            "x": int(round((bells_min_x + bells_max_x) / 2)),
            "y": int(round((bells_min_y + bells_max_y) / 2)),
            "w": bells_max_x - bells_min_x,
            "h": bells_max_y - bells_min_y,
            "px": _px_rect_aabb(bells_min_x, bells_min_y, bells_max_x, bells_max_y),
        },
        "items_label": label_rect(56),
        "letters_label": label_rect(60),
        "bells_label": label_rect(64),
    }


def _alpha_bbox(image: Image.Image) -> dict[str, int] | None:
    w, h = image.size
    px = image.load()
    min_x, min_y = w, h
    max_x, max_y = -1, -1
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > 8:
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    if max_x < 0:
        return None
    return {"x": min_x, "y": min_y, "w": max_x - min_x + 1, "h": max_y - min_y + 1}


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


def _border_mask_alpha(r: int, g: int, b: int, a: int) -> int:
    if a <= 0:
        return 0
    # Native CI4 border tiles encode holes as transparent black, edge as opaque orange.
    if r < 16 and g < 16 and b < 16:
        return 0
    return a


def _draw_paper_border_triangle(
    out: Image.Image,
    paper: Image.Image,
    border: Image.Image,
    p0: tuple[float, float],
    p1: tuple[float, float],
    p2: tuple[float, float],
    st0: tuple[float, float],
    st1: tuple[float, float],
    st2: tuple[float, float],
) -> None:
    """inv_mwin_mode: RGB=TEXEL0 (paper, repeat), A=TEXEL1 (border CI, mirror)."""
    out_px = out.load()
    paper_px = paper.load()
    border_px = border.load()
    pw, ph = paper.size
    bw, bh = border.size
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
            s_p = st0[0] * w0 + st1[0] * w1 + st2[0] * w2
            t_p = st0[1] * w0 + st1[1] * w1 + st2[1] * w2
            s_b = s_p
            t_b = t_p
            pxi = _tex_coord(s_p, pw, mode="wrap")
            pyi = _tex_coord(t_p, ph, mode="wrap")
            pr, pg, pb, _pa = paper_px[pxi, pyi]
            bxi = _tex_coord(s_b, bw, mode="mirror")
            byi = _tex_coord(t_b, bh, mode="mirror")
            br, bg, bb, ba = border_px[bxi, byi]
            ba = _border_mask_alpha(br, bg, bb, ba)
            if ba <= 0:
                continue
            dr, dg, db, da = out_px[px, py]
            as_ = ba / 255.0
            ad_ = da / 255.0
            ao = as_ + ad_ * (1.0 - as_)
            if ao <= 1e-6:
                continue
            out_px[px, py] = (
                int((pr * as_ + dr * ad_ * (1.0 - as_)) / ao + 0.5),
                int((pg * as_ + dg * ad_ * (1.0 - as_)) / ao + 0.5),
                int((pb * as_ + db * ad_ * (1.0 - as_)) / ao + 0.5),
                int(ao * 255.0 + 0.5),
            )


def _fill_enclosed_paper(shell: Image.Image, paper: Image.Image) -> None:
    """Tile paper into transparent regions enclosed by the shell silhouette."""
    w, h = shell.size
    px = shell.load()
    paper_px = paper.load()
    pw, ph = paper.size
    if pw <= 0 or ph <= 0:
        return
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
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > 8 or exterior[y][x]:
                continue
            pr, pg, pb, pa = paper_px[x % pw, y % ph]
            shell_px_a = 255 if pa > 0 else 0
            px[x, y] = (pr, pg, pb, shell_px_a)


def _recolor_shell_paper(shell: Image.Image, paper: Image.Image) -> None:
    """Replace opaque RGB with screen-space paper so border UV seams disappear."""
    pw, ph = paper.size
    if pw <= 0 or ph <= 0:
        return
    px = shell.load()
    paper_px = paper.load()
    w, h = shell.size
    for y in range(h):
        for x in range(w):
            _r, _g, _b, a = px[x, y]
            if a <= 8:
                continue
            pr, pg, pb, pa = paper_px[x % pw, y % ph]
            if pa <= 0:
                continue
            px[x, y] = (pr, pg, pb, a)


def _soft_white_rim(shell: Image.Image, inner: int = 3, outer: int = 5) -> None:
    """Thin bright fringe along the silhouette (WW-style; stand-in for inv_mwin_1cT).

    Earlier radius=14 flooded the whole border band (~40px solid white). Keep a
    short inward stroke + soft outward glow only.
    """
    if inner <= 0 and outer <= 0:
        return
    w, h = shell.size
    px = shell.load()
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

    # Chebyshev distance from each opaque pixel to exterior (capped).
    max_d = max(inner, outer) + 1
    dist_in = [[max_d] * w for _ in range(h)]
    frontier: list[tuple[int, int]] = []
    for y in range(h):
        for x in range(w):
            if exterior[y][x] or px[x, y][3] <= 8:
                continue
            touch = False
            for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= w or ny >= h or exterior[ny][nx]:
                    touch = True
                    break
            if touch:
                dist_in[y][x] = 0
                frontier.append((x, y))
    head = 0
    while head < len(frontier):
        x, y = frontier[head]
        head += 1
        d = dist_in[y][x]
        if d >= inner:
            continue
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nx, ny = x + dx, y + dy
            if nx < 0 or ny < 0 or nx >= w or ny >= h:
                continue
            if exterior[ny][nx] or px[nx, ny][3] <= 8:
                continue
            nd = d + 1
            if nd < dist_in[ny][nx]:
                dist_in[ny][nx] = nd
                frontier.append((nx, ny))

    for y in range(h):
        for x in range(w):
            if exterior[y][x] or px[x, y][3] <= 8:
                continue
            if dist_in[y][x] <= inner:
                px[x, y] = (255, 255, 255, 255)

    if outer <= 0:
        return
    # Soft white halo just outside the silhouette.
    for y in range(h):
        for x in range(w):
            if not exterior[y][x]:
                continue
            best = outer + 1
            for dy in range(-outer, outer + 1):
                for dx in range(-outer, outer + 1):
                    nx, ny = x + dx, y + dy
                    if nx < 0 or ny < 0 or nx >= w or ny >= h:
                        continue
                    if exterior[ny][nx] or px[nx, ny][3] <= 8:
                        continue
                    dist = max(abs(dx), abs(dy))
                    if dist < best:
                        best = dist
            if best > outer:
                continue
            a = int(220.0 * (1.0 - float(best) / float(outer + 1)))
            if a <= 0:
                continue
            px[x, y] = (255, 255, 255, max(px[x, y][3], a))


def _decode_border_tiles(
    rel: RelData, by_name: dict[str, list[MapSymbol]], *, achd=None
) -> dict[str, tuple[Image.Image, tuple[int, int]]]:
    """Return stem → (sheet, native_size). ST from `inv_mwin_v` is in native space."""
    tiles: dict[str, tuple[Image.Image, tuple[int, int]]] = {}
    frame_specs = [s for s in CHROME if s.out_name and s.out_name.startswith("frame_w")]
    for spec in frame_specs:
        stem = spec.out_name or spec.name
        sym = _pick_symbol(by_name, spec.name)
        data = rel.slice_at(sym.address, sym.size)
        pal = b""
        if spec.pal:
            pal_sym = _pick_symbol(by_name, spec.pal)
            pal = rel.slice_at(pal_sym.address, min(pal_sym.size, 512))
        gx = gbi_to_gx(spec.fmt, spec.siz)
        hd = None
        if not spec.native_only:
            hd = maybe_hd_png(
                achd,
                data,
                spec.width,
                spec.height,
                gx,
                pal if spec.fmt == G_IM_FMT_CI else None,
                wrap_s=GX_CLAMP,
                wrap_t=GX_CLAMP,
            )
        if hd is not None:
            image = Image.open(BytesIO(hd)).convert("RGBA")
        else:
            image = decode_gbi_texture(
                data, spec.width, spec.height, spec.fmt, spec.siz, pal
            ).convert("RGBA")
        tiles[stem] = (image, (spec.width, spec.height))
    return tiles


def _bake_inventory_window_shell(
    rel: RelData,
    by_name: dict[str, list[MapSymbol]],
    stage_dir: Path,
    out_dir: Path,
    project_root: Path,
    *,
    achd=None,
) -> dict[str, Any]:
    record: dict[str, Any] = {
        "asset_id": "window_shell",
        "source": "inv_mwin_model (paper×border; 1cT rim deferred)",
        "output_path": "ui/inventory/window_shell.png",
        "status": "pending",
        "error": None,
    }
    catalog_path: str | None = None
    out_w = _NATIVE_W * _BAKE_SCALE
    out_h = _NATIVE_H * _BAKE_SCALE
    ssaa = max(1, _SHELL_SSAA)
    width = out_w * ssaa
    height = out_h * ssaa
    alpha_bbox: dict[str, int] | None = None
    try:
        sym = _pick_symbol(by_name, "inv_mwin_v")
        blob = rel.slice_at(sym.address, sym.size)
        if len(blob) != _INV_VTX_COUNT * 16:
            raise ValueError(f"inv_mwin_v size {len(blob)} != {_INV_VTX_COUNT * 16}")
        verts = _parse_ui_vtx(blob)

        paper_path = out_dir / "paper.png"
        if not paper_path.is_file():
            raise FileNotFoundError("paper.png missing (run paper copy first)")
        paper = Image.open(paper_path).convert("RGBA")

        borders = _decode_border_tiles(rel, by_name, achd=achd)
        used_achd = any(img.size != native for img, native in borders.values())

        shell = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        ox, oy = _SHELL_ORIGIN
        scale = float(_BAKE_SCALE * ssaa)

        def to_px(v) -> tuple[float, float]:
            return ((float(v.x) - ox) * scale, (oy - float(v.y)) * scale)

        def scale_st(v, native: tuple[int, int], tex: Image.Image) -> tuple[float, float]:
            nw, nh = native
            sx = tex.size[0] / float(nw) if nw else 1.0
            sy = tex.size[1] / float(nh) if nh else 1.0
            return (v.s * sx, v.t * sy)

        for vtx_base, stem, tris in _BORDER_PIECES:
            border, native = borders[stem]
            batch = verts[vtx_base : vtx_base + 4]
            if len(batch) < 4:
                raise ValueError(f"vtx batch @ {vtx_base} too short")
            for i0, i1, i2 in tris:
                v0, v1, v2 = batch[i0], batch[i1], batch[i2]
                _draw_paper_border_triangle(
                    shell,
                    paper,
                    border,
                    to_px(v0),
                    to_px(v1),
                    to_px(v2),
                    scale_st(v0, native, border),
                    scale_st(v1, native, border),
                    scale_st(v2, native, border),
                )

        # 1cT I4 rim deferred: offline raster of those batches floods interior
        # quads. Border silhouette + enclosed paper fill is enough for layout.
        _fill_enclosed_paper(shell, paper)
        _recolor_shell_paper(shell, paper)
        _soft_white_rim(shell, inner=2 * ssaa, outer=4 * ssaa)

        if ssaa > 1:
            ## Downsample for smooth scalloped AA (native tris are binary-covered).
            shell = shell.resize((out_w, out_h), Image.Resampling.LANCZOS)

        catalog = _build_layout_catalog(verts)
        catalog_bytes = json.dumps(catalog, indent=2).encode("utf-8")
        for folder in (stage_dir, out_dir):
            (folder / "catalog.json").write_bytes(catalog_bytes)
        catalog_path = str(out_dir / "catalog.json")

        png = image_png_bytes(shell)
        for folder in (stage_dir, out_dir):
            (folder / "window_shell.png").write_bytes(png)
            (folder / "window_shell_preview.png").write_bytes(png)
        write_import_sidecar(out_dir / "window_shell.png", project_root)

        alpha_bbox = _alpha_bbox(shell)
        record["status"] = "converted"
        record["meta"] = {
            "width": out_w,
            "height": out_h,
            "native_size": [_NATIVE_W, _NATIVE_H],
            "bake_scale": _BAKE_SCALE,
            "ssaa": ssaa,
            "alpha_bbox": alpha_bbox,
            "achd": used_achd,
        }
    except Exception as exc:  # noqa: BLE001
        record["status"] = "error"
        record["error"] = f"{type(exc).__name__}: {exc}"


    return {
        "record": record,
        "catalog_path": catalog_path,
        "width": out_w if record["status"] == "converted" else None,
        "height": out_h if record["status"] == "converted" else None,
        "alpha_bbox": alpha_bbox,
    }

