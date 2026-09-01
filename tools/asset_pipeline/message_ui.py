"""Extract `m_msg` dialogue window chrome from foresta.rel for local reference.

Textures from decomp `m_msg_data.c_inc` (`con_kaiwa2_*`, `con_namefuti_TXT`).
Output is gitignored under `assets/generated/ui/message/` — Nintendo IP, not for commit.
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
    G_IM_FMT_I,
    G_IM_SIZ_4b,
    decode_gbi_texture,
    image_png_bytes,
)

## Decomp `mMsg_window` default tints (`m_msg_main.c_inc`).
MSG_BODY_PRIM = (235, 255, 235, 255)
MSG_NAME_PRIM = (160, 215, 30, 255)


@dataclass(frozen=True)
class TexSpec:
    name: str
    width: int
    height: int
    prim_as_color: tuple[int, int, int, int]
    out_name: str | None = None


CHROME: list[TexSpec] = [
    TexSpec("con_kaiwa2_w1_tex", 64, 64, MSG_BODY_PRIM, "msg_kaiwa_w1"),
    TexSpec("con_kaiwa2_w2_tex", 128, 64, MSG_BODY_PRIM, "msg_kaiwa_w2"),
    TexSpec("con_kaiwa2_w3_tex", 128, 64, MSG_BODY_PRIM, "msg_kaiwa_w3"),
    TexSpec("con_namefuti_TXT", 64, 32, MSG_NAME_PRIM, "msg_nameplate"),
]


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

    results: list[dict[str, Any]] = []
    tiles: dict[str, Image.Image] = {}
    for spec in CHROME:
        record = _extract_one(rel, by_name, spec, stage_dir, out_dir, cfg.project_root)
        results.append(record)
        if record["status"] == "converted":
            path = out_dir / f"{spec.out_name or spec.name}.png"
            tiles[spec.out_name or spec.name] = Image.open(path).convert("RGBA")

    composite = _compose_window_body(tiles)
    if composite is not None:
        for folder in (stage_dir, out_dir):
            path = folder / "msg_window_body.png"
            path.write_bytes(image_png_bytes(composite))
        write_import_sidecar(out_dir / "msg_window_body.png", cfg.project_root)
        results.append(
            {
                "asset_id": "msg_window_body",
                "source": "con_kaiwa2_*",
                "output_path": "ui/message/msg_window_body.png",
                "status": "converted",
                "error": None,
            }
        )

    converted = sum(1 for r in results if r["status"] == "converted")
    return {"results": results, "converted": converted, "output": str(out_dir)}


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
        image = decode_gbi_texture(data, spec.width, spec.height, G_IM_FMT_I, G_IM_SIZ_4b, b"")
        image = _i_texel_as_alpha(image, spec.prim_as_color)
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
    pr, pg, pb, pa = prim
    intensity = image.convert("RGBA").split()[0]
    alpha = intensity.point(lambda v, p=pa: v * p // 255)
    solid = Image.new("RGB", image.size, (pr, pg, pb))
    out = solid.convert("RGBA")
    out.putalpha(alpha)
    return out


def _compose_window_body(tiles: dict[str, Image.Image]) -> Image.Image | None:
    """Stitch `con_kaiwa2` tiles into one 9-slice-friendly sheet (decomp `con_kaiwa2_modelT`)."""
    w1 = tiles.get("msg_kaiwa_w1")
    w2 = tiles.get("msg_kaiwa_w2")
    w3 = tiles.get("msg_kaiwa_w3")
    if w1 is None or w2 is None or w3 is None:
        return None
    corner = 32
    mid_w = 128
    body_h = 64
    width = corner * 2 + mid_w
    height = body_h * 3
    out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    # Top band (w3): corners from w1, edge from w3 center crop.
    out.paste(w1.crop((0, 0, corner, body_h)), (0, 0))
    out.paste(w3.crop((0, 0, mid_w, body_h)), (corner, 0))
    out.paste(w1.crop((corner, 0, corner * 2, body_h)), (corner + mid_w, 0))
    # Middle band (w2).
    out.paste(w1.crop((0, 0, corner, body_h)), (0, body_h))
    out.paste(w2.crop((0, 0, mid_w, body_h)), (corner, body_h))
    out.paste(w1.crop((corner, 0, corner * 2, body_h)), (corner + mid_w, body_h))
    # Bottom band mirrors top (GC window uses symmetric curl).
    out.paste(w1.crop((0, 0, corner, body_h)), (0, body_h * 2))
    out.paste(w3.crop((0, 0, mid_w, body_h)), (corner, body_h * 2))
    out.paste(w1.crop((corner, 0, corner * 2, body_h)), (corner + mid_w, body_h * 2))
    return out
