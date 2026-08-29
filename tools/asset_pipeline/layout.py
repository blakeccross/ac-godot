"""Godot output paths for converted disc assets. Shared by convert and scan."""

from __future__ import annotations

import re

_SPECIES_PREFIX = re.compile(r"^[a-z]{2,4}_?\d+$")


def uses_shared_npc_anims(prefix: str) -> bool:
    if prefix.startswith(("boy_", "girl_", "int_", "tol_", "obj_", "act_", "ef_", "grd_", "logo_", "clk_")):
        return False
    return bool(_SPECIES_PREFIX.fullmatch(prefix))


def env_subdir(prefix: str) -> str:
    lower = prefix.lower()
    if (
        prefix.startswith("rom_")
        or prefix.startswith("mCL_rom_")
        or prefix in {"police_indoor", "room01"}
    ):
        return "environment/interiors"
    if prefix.startswith("grd_"):
        return "environment/acres"
    if "tree" in lower:
        return "environment/trees"
    if "flower" in lower:
        return "environment/flowers"
    if "stone" in lower or "rock" in lower:
        return "environment/rocks"
    return "environment"


def output_for_prefix(prefix: str) -> str:
    if prefix.startswith(("boy_", "girl_")):
        return f"characters/player/{prefix}.glb"
    if prefix.startswith("int_") or prefix.startswith("clk_"):
        return f"furniture/{prefix}.glb"
    if prefix.startswith("tol_"):
        return f"items/{prefix}.glb"
    if prefix.startswith("ef_"):
        return f"effects/{prefix}.glb"
    if prefix.startswith("logo_"):
        return f"ui/{prefix}.glb"
    if prefix.startswith(("obj_", "act_", "grd_", "rom_")):
        return f"{env_subdir(prefix)}/{prefix}.glb"
    if uses_shared_npc_anims(prefix):
        return f"characters/villagers/{prefix}.glb"
    return f"characters/other/{prefix}.glb"


def output_folder_for_static(prefix: str) -> str:
    if prefix.startswith("int_"):
        return "furniture"
    if prefix.startswith("tol_"):
        return "items"
    if prefix.startswith("ef_"):
        return "effects"
    if prefix.startswith(("obj_", "act_", "grd_", "rom_", "mCL_rom_")) or prefix in {
        "police_indoor",
        "room01",
    }:
        return env_subdir(prefix)
    return "environment"


def bti_output_path(archive_relative: str) -> str:
    """Keep archive subdirs so forest_1st/foo.bti and forest_2nd/foo.bti do not collide."""
    rel = archive_relative.replace("\\", "/")
    if rel.lower().endswith(".bti.szs"):
        rel = rel[: -len(".bti.szs")] + ".png"
    elif rel.lower().endswith(".bti"):
        rel = rel[: -len(".bti")] + ".png"
    else:
        rel = rel + ".png"
    return f"ui/{rel}"
