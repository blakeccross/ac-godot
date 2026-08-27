from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from .config import PipelineConfig
from .mapfile import dataobject_symbols, parse_map

MAGIC = {
    b"RARC": "RARC",
    b"Yaz0": "YAZ0",
    b"Yay0": "YAY0",
}

CATEGORY_HINTS = (
    ("player", "character"),
    ("boy_", "character"),
    ("girl", "character"),
    ("ply_", "character"),
    ("npc", "character"),
    ("cKF_bs_r_bea", "character"),
    ("cKF_bs_r_cat", "character"),
    ("cKF_bs_r_dog", "character"),
    ("cKF_bs_r_duk", "character"),
    ("cKF_bs_r_pbr", "character"),
    ("cKF_bs_r_brd", "character"),
    ("cKF_bs_r_ant", "character"),
    ("cKF_bs_r_wls", "character"),
    ("tree", "environment"),
    ("mura_", "environment"),
    ("floor", "furniture"),
    ("wall", "furniture"),
    ("int_", "furniture"),
    ("tol_", "items"),
    ("title", "ui"),
    ("mail", "ui"),
    ("message", "ui"),
    ("string", "ui"),
    ("bti", "texture"),
)


def _category(name: str) -> str:
    lower = name.lower()
    for needle, cat in CATEGORY_HINTS:
        if needle.lower() in lower:
            return cat
    return "unknown"


def _format_of(path: Path) -> str:
    suffix = path.suffix.lower().lstrip(".")
    if suffix:
        return suffix.upper() or "BIN"
    magic = path.read_bytes()[:4]
    return MAGIC.get(magic, "BIN")


def _sha1(path: Path) -> str:
    h = hashlib.sha1()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def scan(cfg: PipelineConfig) -> dict[str, Any]:
    assets: list[dict[str, Any]] = []

    for folder, source_kind in (
        (cfg.extracted_disc / "files", "disc"),
        (cfg.extracted_archives, "archive"),
    ):
        if not folder.exists():
            continue
        for path in sorted(folder.rglob("*")):
            if not path.is_file():
                continue
            rel = path.relative_to(folder).as_posix()
            fmt = _format_of(path)
            converter = _converter_for(fmt, rel)
            output_path = None
            if fmt == "BTI":
                output_path = f"ui/{path.stem}.png"
            assets.append(
                {
                    "asset_id": rel.replace("/", "_").replace(".", "_").lower(),
                    "source_path": rel,
                    "source_kind": source_kind,
                    "source_format": fmt,
                    "original_filename": path.name,
                    "category": _category(rel),
                    "size": path.stat().st_size,
                    "sha1": _sha1(path),
                    "related_textures": [],
                    "related_animations": [],
                    "converter": converter,
                    "output_path": output_path,
                    "conversion_status": "discovered",
                    "conversion_error": None,
                }
            )

    map_path = cfg.extracted_disc / "files" / "foresta.map"
    if map_path.exists():
        for symbol in dataobject_symbols(parse_map(map_path)):
            if symbol.size <= 0 or symbol.name.startswith("."):
                continue
            cat = _category(symbol.name)
            converter = "none"
            output_path = None
            if symbol.name.startswith("cKF_bs_r_"):
                converter = "ckf_glb"
                stem = symbol.name.replace("cKF_bs_r_", "")
                output_path = f"unknown/{stem}.glb"
                if cat == "character":
                    output_path = f"characters/{stem}.glb"
                elif cat == "furniture":
                    output_path = f"furniture/{stem}.glb"
                elif cat == "items":
                    output_path = f"items/{stem}.glb"
                elif cat == "environment":
                    output_path = f"environment/{stem}.glb"
            elif symbol.name.endswith("_tex_txt"):
                converter = "n64_texture_pending"
            elif symbol.name.endswith("_v") and not symbol.name.startswith("cKF_"):
                converter = "static_gfx_glb"
                output_path = f"unknown/{symbol.name}.glb"
            assets.append(
                {
                    "asset_id": symbol.name.lower(),
                    "source_path": f"foresta.rel:.data+0x{symbol.address:08X}",
                    "source_kind": "rel_symbol",
                    "source_format": "CKF" if symbol.name.startswith("cKF_") else "BLOB",
                    "original_filename": symbol.name,
                    "category": cat,
                    "size": symbol.size,
                    "sha1": None,
                    "related_textures": [],
                    "related_animations": [],
                    "converter": converter,
                    "output_path": output_path,
                    "conversion_status": "discovered",
                    "conversion_error": None,
                }
            )

    assets.sort(key=lambda a: (a["source_kind"], a["source_path"], a["asset_id"]))
    manifest = {
        "game": "GAFE01_00",
        "asset_count": len(assets),
        "assets": assets,
    }
    cfg.manifests.mkdir(parents=True, exist_ok=True)
    out = cfg.manifests / "assets.json"
    out.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest


def _converter_for(fmt: str, rel: str) -> str:
    if fmt == "BTI":
        return "bti_png"
    if fmt == "RARC":
        return "rarc_extract"
    if fmt == "YAZ0":
        return "yaz0"
    if "foresta.rel" in rel:
        return "rel_symbols"
    if rel.endswith("audiorom.img"):
        return "audio_pending"
    return "none"
