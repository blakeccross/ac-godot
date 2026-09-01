"""Extract NPC eye/mouth texture frames from `face_*.bin` for face animation.

An AC character's face is not skinned geometry: the head has one eye quad and one mouth
quad, and `aNPC_tex_anm_ctrl` swaps their texture pointer per frame (`nture[8]` eyes,
`n_texture[6]` mouths). `texbank` already binds frame 0 of each so the head renders, but
animating needs every frame, so write them all out as separate PNGs.

`face_{species}.bin` layout (see `texbank.bind_model_segments`): eyes 0-7 at 0x000 then
mouths 0-5 at 0x800, each 32x16 CI4, shared RGB5A3 palette at 0xE00.
Output is gitignored under `assets/generated/characters/faces/`.
"""

from __future__ import annotations

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


def extract_faces(cfg: PipelineConfig) -> dict[str, Any]:
    data_dir = cfg.extracted_archives / "forest_1st" / "data"
    if not data_dir.is_dir():
        return {"results": [], "converted": 0, "error": f"missing {data_dir}"}

    sources = sorted(data_dir.glob("face_*.bin"))
    if not sources:
        return {"results": [], "converted": 0, "error": f"no face_*.bin under {data_dir}"}

    out_dir = cfg.godot_generated / "characters" / "faces"
    stage_dir = cfg.converted / "characters" / "faces"
    out_dir.mkdir(parents=True, exist_ok=True)
    stage_dir.mkdir(parents=True, exist_ok=True)

    results: list[dict[str, Any]] = []
    for src in sources:
        species = src.stem[len("face_") :]
        results.extend(_extract_species(src, species, stage_dir, out_dir, cfg.project_root))

    converted = sum(1 for r in results if r["status"] == "converted")
    return {"results": results, "converted": converted, "output": str(out_dir)}


def frame_offsets() -> list[tuple[str, int]]:
    """`(out suffix, byte offset)` for every frame in a `face_*.bin` face 0."""
    frames = [(f"eye{i}", EYE_BASE + i * FRAME_SIZE) for i in range(EYE_COUNT)]
    frames += [(f"mouth{i}", MOUTH_BASE + i * FRAME_SIZE) for i in range(MOUTH_COUNT)]
    return frames


def _extract_species(
    src: Path, species: str, stage_dir: Path, out_dir: Path, project_root: Path
) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    blob = src.read_bytes()
    palette = blob[PALETTE_OFFSET : PALETTE_OFFSET + PALETTE_SIZE]
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
            image = decode_gbi_texture(
                blob[offset : offset + FRAME_SIZE],
                FACE_W,
                FACE_H,
                G_IM_FMT_CI,
                G_IM_SIZ_4b,
                palette,
            )
            png = image_png_bytes(image)
            for folder in (stage_dir, out_dir):
                (folder / f"{stem}.png").write_bytes(png)
            write_import_sidecar(out_dir / f"{stem}.png", project_root)
            record["status"] = "converted"
        except Exception as exc:  # noqa: BLE001
            record["status"] = "error"
            record["error"] = f"{type(exc).__name__}: {exc}"
        records.append(record)
    return records
