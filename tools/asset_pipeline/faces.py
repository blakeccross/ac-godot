"""Extract NPC eye/mouth texture frames from `face_*.bin` for face animation.

An AC character's face is not skinned geometry: the head has one eye quad and one mouth
quad, and `aNPC_tex_anm_ctrl` swaps their texture pointer per frame (`nture[8]` eyes,
`n_texture[6]` mouths). `texbank` already binds frame 0 of each so the head renders, but
animating needs every frame, so write them all out as separate PNGs.

`face_{species}.bin` layout (see `texbank.bind_model_segments`): eyes 0-7 at 0x000 then
mouths 0-5 at 0x800, each 32x16 CI4, shared RGB5A3 palette at 0xE00.

Villager variants store per-frame REL symbols `{prefix}_eye{N}_TA_tex_txt` /
`{prefix}_mouth{N}_TA_tex_txt` (1-indexed). Output is keyed by species code (`cat_1` →
`cat`) so `NpcFace` can load `cat_eye0.png` for any `cat_*` GLB.

Output is gitignored under `assets/generated/characters/faces/`.
"""

from __future__ import annotations

import re
import shutil
from pathlib import Path
from typing import Any

from .config import PipelineConfig
from .godot_import import write_import_sidecar
from .texbank import (
    G_IM_FMT_CI,
    G_IM_SIZ_4b,
    decode_gbi_texture,
    image_png_bytes,
)

FACE_W = 32
FACE_H = 16
## One 32x16 CI4 texel block.
FRAME_SIZE = 0x100
EYE_BASE = 0x000
EYE_COUNT = 8
MOUTH_BASE = 0x800
MOUTH_COUNT = 6
PALETTE_OFFSET = 0xE00
PALETTE_SIZE = 0x20
EYE_REL_COUNT = 8
MOUTH_REL_COUNT = 6
_VARIANT_SUFFIX = re.compile(r"^(?P<species>[a-z]+)_(?P<variant>\d+)$", re.IGNORECASE)


def extract_faces(cfg: PipelineConfig) -> dict[str, Any]:
    out_dir = cfg.godot_generated / "characters" / "faces"
    stage_dir = cfg.converted / "characters" / "faces"
    out_dir.mkdir(parents=True, exist_ok=True)
    stage_dir.mkdir(parents=True, exist_ok=True)

    results: list[dict[str, Any]] = []
    data_dir = cfg.extracted_archives / "forest_1st" / "data"
    if data_dir.is_dir():
        for src in sorted(data_dir.glob("face_*.bin")):
            species = src.stem[len("face_") :]
            results.extend(_extract_species(src, species, stage_dir, out_dir, cfg))

    results.extend(_extract_villager_faces_from_rel(cfg, stage_dir, out_dir))

    if not results:
        return {
            "results": [],
            "converted": 0,
            "error": f"no face_*.bin under {data_dir} and no REL villager face textures",
        }

    converted = sum(1 for r in results if r["status"] == "converted")
    return {"results": results, "converted": converted, "output": str(out_dir)}


def frame_offsets() -> list[tuple[str, int]]:
    """`(out suffix, byte offset)` for every frame in a `face_*.bin` face 0."""
    frames = [(f"eye{i}", EYE_BASE + i * FRAME_SIZE) for i in range(EYE_COUNT)]
    frames += [(f"mouth{i}", MOUTH_BASE + i * FRAME_SIZE) for i in range(MOUTH_COUNT)]
    return frames


def discover_villager_prefixes(rel_dir: Path) -> dict[str, str]:
    """Map species code (`cat`) to one REL prefix (`cat_1`)."""
    by_species: dict[str, list[str]] = {}
    for src in rel_dir.glob("*_eye1_TA_tex_txt.png"):
        prefix = src.name[: -len("_eye1_TA_tex_txt.png")]
        species = species_code_from_prefix(prefix)
        by_species.setdefault(species, []).append(prefix)

    chosen: dict[str, str] = {}
    for species, prefixes in by_species.items():
        chosen[species] = sorted(prefixes, key=_variant_sort_key)[0]
    return dict(sorted(chosen.items()))


def species_code_from_prefix(prefix: str) -> str:
    match = _VARIANT_SUFFIX.match(prefix)
    if match:
        return match.group("species")
    return prefix


def _variant_sort_key(prefix: str) -> tuple[int, str]:
    match = _VARIANT_SUFFIX.match(prefix)
    if match:
        return (int(match.group("variant")), prefix)
    return (0, prefix)


def _extract_species(
    src: Path, species: str, stage_dir: Path, out_dir: Path, cfg: PipelineConfig
) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    blob = src.read_bytes()
    palette = blob[PALETTE_OFFSET : PALETTE_OFFSET + PALETTE_SIZE]
    from .achd import load_achd_pack, maybe_hd_png
    from .bti import CI4

    pack = load_achd_pack(cfg.achd_root, cfg.achd_cache) if cfg.achd_enabled else None
    for suffix, offset in frame_offsets():
        stem = f"{species}_{suffix}"
        record: dict[str, Any] = {
            "asset_id": stem,
            "source": src.name,
            "output_path": f"characters/faces/{stem}.png",
            "status": "pending",
            "error": None,
        }
        try:
            if len(blob) < offset + FRAME_SIZE or len(palette) < PALETTE_SIZE:
                raise ValueError(f"{src.name} too short for {suffix} at 0x{offset:04X}")
            texels = blob[offset : offset + FRAME_SIZE]
            hd = maybe_hd_png(pack, texels, FACE_W, FACE_H, CI4, palette)
            if hd is not None:
                png = hd
            else:
                image = decode_gbi_texture(
                    texels,
                    FACE_W,
                    FACE_H,
                    G_IM_FMT_CI,
                    G_IM_SIZ_4b,
                    palette,
                )
                png = image_png_bytes(image)
            for folder in (stage_dir, out_dir):
                (folder / f"{stem}.png").write_bytes(png)
            write_import_sidecar(out_dir / f"{stem}.png", cfg.project_root)
            record["status"] = "converted"
        except Exception as exc:  # noqa: BLE001
            record["status"] = "error"
            record["error"] = f"{type(exc).__name__}: {exc}"
        records.append(record)
    return records


def _extract_villager_faces_from_rel(
    cfg: PipelineConfig, stage_dir: Path, out_dir: Path
) -> list[dict[str, Any]]:
    rel_dir = cfg.converted / "textures" / "rel"
    if not rel_dir.is_dir():
        return []

    records: list[dict[str, Any]] = []
    for _species, prefix in discover_villager_prefixes(rel_dir).items():
        for eye_i in range(1, EYE_REL_COUNT + 1):
            records.append(
                _copy_rel_face_frame(
                    rel_dir,
                    prefix,
                    _species,
                    f"eye{eye_i - 1}",
                    f"{prefix}_eye{eye_i}_TA_tex_txt.png",
                    stage_dir,
                    out_dir,
                    cfg.project_root,
                )
            )
        for mouth_i in range(1, MOUTH_REL_COUNT + 1):
            records.append(
                _copy_rel_face_frame(
                    rel_dir,
                    prefix,
                    _species,
                    f"mouth{mouth_i - 1}",
                    f"{prefix}_mouth{mouth_i}_TA_tex_txt.png",
                    stage_dir,
                    out_dir,
                    cfg.project_root,
                )
            )
    return records


def _copy_rel_face_frame(
    rel_dir: Path,
    prefix: str,
    species: str,
    suffix: str,
    rel_name: str,
    stage_dir: Path,
    out_dir: Path,
    project_root: Path,
) -> dict[str, Any]:
    src = rel_dir / rel_name
    stem = f"{species}_{suffix}"
    record: dict[str, Any] = {
        "asset_id": stem,
        "source": rel_name,
        "output_path": f"characters/faces/{stem}.png",
        "status": "pending",
        "error": None,
    }
    if not src.is_file():
        record["status"] = "skipped"
        record["error"] = f"missing {rel_name}"
        return record
    try:
        for folder in (stage_dir, out_dir):
            shutil.copy2(src, folder / f"{stem}.png")
        write_import_sidecar(out_dir / f"{stem}.png", project_root)
        record["status"] = "converted"
    except Exception as exc:  # noqa: BLE001
        record["status"] = "error"
        record["error"] = f"{type(exc).__name__}: {exc}"
    return record
