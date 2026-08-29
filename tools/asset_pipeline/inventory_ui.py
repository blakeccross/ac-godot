"""Extract inventory window chrome from foresta.rel for local reference.

Formats/sizes come from decomp `inv_mwin.c` / `inv_mwin_g.c` GBI. Output is
gitignored under `assets/generated/ui/inventory/` — Nintendo IP, not for commit.
"""

from __future__ import annotations

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

# Prefer the inv_mwin.c dataobject cluster (US GAFE01 map); fall back to any match.
_CLUSTER_LO = 0x00438000
_CLUSTER_HI = 0x00447000


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


# Window chrome used by mIV_set_*_frame_dl / inv_mwin_model.
CHROME: list[TexSpec] = [
    TexSpec("inv_mwin_w1_tex_rgb_ci4", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_w1_tex_rgb_ci4_pal"),
    TexSpec("inv_mwin_w2_tex_rgb_ci4", 32, 64, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_w2_tex_rgb_ci4_pal"),
    TexSpec("inv_mwin_w3_tex_rgb_ci4", 64, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_w3_tex_rgb_ci4_pal"),
    TexSpec("inv_mwin_w4_tex_rgb_ci4", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_w4_tex_rgb_ci4_pal"),
    TexSpec("inv_mwin_w5_tex_rgb_ci4", 16, 16, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_w1_tex_rgb_ci4_pal"),
    TexSpec("inv_mwin_w6_tex_rgb_ci4", 32, 64, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_w6_tex_rgb_ci4_pal"),
    TexSpec("inv_mwin_nwaku_tex", 32, 32, G_IM_FMT_IA, G_IM_SIZ_8b, env_preview=(100, 100, 255, 255)),
    TexSpec("inv_mwin_items_tex", 64, 16, G_IM_FMT_I, G_IM_SIZ_4b, prim_as_color=(120, 120, 225, 255)),
    TexSpec("inv_mwin_letters_tex", 64, 16, G_IM_FMT_I, G_IM_SIZ_4b, prim_as_color=(195, 80, 80, 255)),
    TexSpec("inv_mwin_bells_tex", 64, 16, G_IM_FMT_I, G_IM_SIZ_4b, prim_as_color=(70, 160, 190, 255)),
    TexSpec("inv_mwin_suujiwaku1_tex", 16, 32, G_IM_FMT_IA, G_IM_SIZ_8b),
    TexSpec("inv_mwin_suujiwaku2_tex", 16, 32, G_IM_FMT_IA, G_IM_SIZ_8b),
    TexSpec("inv_mwin_3Dma_tex", 64, 64, G_IM_FMT_I, G_IM_SIZ_4b, prim_as_color=(100, 155, 255, 255)),
    TexSpec("inv_mwin_shirushi4_tex", 32, 32, G_IM_FMT_I, G_IM_SIZ_4b, prim_as_color=(100, 80, 100, 255)),
    TexSpec("inv_original_shirushi_tex", 32, 32, G_IM_FMT_I, G_IM_SIZ_4b, prim_as_color=(75, 50, 40, 255)),
    TexSpec("inv_original_shirushi3_tex", 32, 64, G_IM_FMT_IA, G_IM_SIZ_8b),
    TexSpec("inv_mwin_sen_tex", 16, 16, G_IM_FMT_I, G_IM_SIZ_4b, prim_as_color=(35, 160, 255, 110)),
    TexSpec("inv_mwin_sen2_tex", 16, 16, G_IM_FMT_I, G_IM_SIZ_4b, prim_as_color=(35, 160, 255, 110)),
    TexSpec("originl", 32, 32, G_IM_FMT_I, G_IM_SIZ_4b, out_name="inv_mwin_originl"),
    TexSpec("original2", 32, 64, G_IM_FMT_I, G_IM_SIZ_4b, out_name="inv_mwin_original2"),
    TexSpec("inv_mwin_aw3_tex", 64, 32, G_IM_FMT_I, G_IM_SIZ_4b),
    TexSpec("inv_mwin_aw4_tex", 32, 32, G_IM_FMT_I, G_IM_SIZ_4b),
    TexSpec("inv_mwin_aw5_tex", 16, 16, G_IM_FMT_I, G_IM_SIZ_4b),
    TexSpec("inv_mwin_aw6_tex", 32, 64, G_IM_FMT_I, G_IM_SIZ_4b),
    TexSpec("inv_mwin_gmushi_tex", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_gmushi_pal"),
    TexSpec("inv_mwin_gturi_tex", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_gturi_pal"),
    TexSpec("inv_mwin_gscoop_tex", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_gscoop_pal"),
    TexSpec("inv_mwin_gono_tex", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, "inv_mwin_gono_pal"),
    TexSpec("inv_win_mark_tex", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b),
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

    results: list[dict[str, Any]] = []
    project_root = cfg.project_root
    for spec in CHROME:
        record = _extract_one(rel, by_name, spec, stage_dir, out_dir, project_root)
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
                    out_name=f"{(spec.out_name or spec.name)}_item_blue",
                ),
                stage_dir,
                out_dir,
                project_root,
                force_env=True,
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
                    out_name=f"{(spec.out_name or spec.name)}_letter_red",
                ),
                stage_dir,
                out_dir,
                project_root,
                force_env=True,
            )
            results.append(red)

    paper = _copy_default_paper(cfg, stage_dir, out_dir)
    if paper is not None:
        results.append(paper)

    converted = sum(1 for r in results if r["status"] == "converted")
    return {"results": results, "converted": converted, "output": str(out_dir)}


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
        image = decode_gbi_texture(data, spec.width, spec.height, spec.fmt, spec.siz, pal)
        if spec.prim_as_color is not None and not force_env:
            image = _i_texel_as_alpha(image, spec.prim_as_color)
        if force_env and spec.env_preview is not None:
            image = _ia_env_preview(image, spec.env_preview)
        png = image_png_bytes(image)
        for folder in (stage_dir, out_dir):
            path = folder / f"{out_stem}.png"
            path.write_bytes(png)
        write_import_sidecar(out_dir / f"{out_stem}.png", project_root)
        record["status"] = "converted"
        record["meta"] = {
            "width": spec.width,
            "height": spec.height,
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
    """Approximate PRIMITIVE/ENVIRONMENT lerp with white prim + env tint for rings."""
    er, eg, eb, ea = env
    # Combiner: PRIM, ENV, TEXEL0, ENV → lerp(ENV, PRIM, texel). With PRIM white:
    # color = ENV + texel * (255 - ENV) / 255 ≈ ENV when texel low, white when high.
    r, g, b, a = image.convert("RGBA").split()
    out_r = r.point(lambda v, e=er: e + (255 - e) * v // 255)
    out_g = g.point(lambda v, e=eg: e + (255 - e) * v // 255)
    out_b = b.point(lambda v, e=eb: e + (255 - e) * v // 255)
    out_a = a.point(lambda v, e=ea: v * e // 255)
    return Image.merge("RGBA", (out_r, out_g, out_b, out_a))


def _copy_default_paper(cfg: PipelineConfig, stage_dir: Path, out_dir: Path) -> dict[str, Any] | None:
    """ITM_CLOTH226 is the default inventory paper (`backgound_texture`)."""
    src = cfg.godot_generated / "textures" / "player" / "shirts" / "shirt_226.png"
    if not src.is_file():
        return {
            "asset_id": "paper_cloth226",
            "source": "shirt_226.png",
            "output_path": "ui/inventory/paper_cloth226.png",
            "status": "skipped",
            "error": "shirt_226.png not generated yet",
        }
    dest_name = "paper_cloth226.png"
    data = src.read_bytes()
    for folder in (stage_dir, out_dir):
        (folder / dest_name).write_bytes(data)
    write_import_sidecar(out_dir / dest_name, cfg.project_root)
    return {
        "asset_id": "paper_cloth226",
        "source": str(src),
        "output_path": f"ui/inventory/{dest_name}",
        "status": "converted",
        "error": None,
    }
