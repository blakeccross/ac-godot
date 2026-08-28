from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any

from .bg_collision import extract_and_write
from .bti import bti_to_png
from .ckf import convert_ckf_model, convert_static_gfx
from .config import PipelineConfig
from .dtk import ensure_dtk
from .glb import write_glb, write_skinned_glb
from .godot_import import write_import_sidecar
from .mapfile import parse_map
from .rel import RelData
from .test_set import TEST_BTI, TEST_SKELETONS, TEST_STATIC
from .texbank import G_IM_FMT_CI, G_IM_SIZ_4b, TextureBank, decode_gbi_texture, image_png_bytes

TRANSFORMS = {
    "scale": "vertex * config.scale (default 0.001). Not actor 0.01 or acre 0.0625 draw scale — Godot FieldCatalog applies those.",
    "z_axis": "cKF: wait bind already stands on +Y; else +90° about Z unless GX verts already sit on +Y (houses/shops bake door-clip joint-0 yaw: house −90°, shop −135°). Static Gfx keep GX Z (no flip).",
    "rest_pose": "wait frame 1 when available; Y-up structures use door-clip frame 1; else identity + ckf_basis",
    "animations": "cKF_ba_r_* sampled at 30 fps into skinned glTF clips",
    "textures": "GX CI4/CI8 + pal; I/IA * G_SETPRIMCOLOR; villager tmem on 0x0A/0x0B",
    "skin": "G_MTX 0x0D slots map to Gfx-bearing joints; seam verts stay on the parent",
}

PLAYER_CORE_ANIMS = [
    "cKF_ba_r_ply_1_wait1",
    "cKF_ba_r_ply_1_walk1",
    "cKF_ba_r_ply_1_run1",
    "cKF_ba_r_ply_1_axe1",
    "cKF_ba_r_ply_1_pickup1",
]

# Prefer these first in the GLB; every cKF_ba_r_npc_1_* clip is still included.
NPC_CORE_ANIMS = [
    "cKF_ba_r_npc_1_wait1",
    "cKF_ba_r_npc_1_walk1",
    "cKF_ba_r_npc_1_run1",
]

# Species skeletons (cat_1, bev_1, …) share the 26-joint npc_1 bank. Not clocks/logos/effects.
_SPECIES_PREFIX = re.compile(r"^[a-z]{2,4}_?\d+$")

TEST_SKEL_BY_NAME = {item["skeleton"]: item for item in TEST_SKELETONS}
TEST_STATIC_BY_VTX = {item["vtx"]: item for item in TEST_STATIC}


def convert_assets(cfg: PipelineConfig) -> dict[str, Any]:
    if cfg.test_set_only:
        return convert_test_set(cfg)
    return convert_all(cfg)


def convert_acre_collision(cfg: PipelineConfig) -> dict[str, Any]:
    """Write `grd_*.col.json` sidecars from `data_bgd` without reconverting meshes."""
    rel = RelData(cfg.extracted_disc / "files" / "foresta.rel")
    symbols = parse_map(cfg.extracted_disc / "files" / "foresta.map")
    col = _write_acre_collision(cfg, rel, symbols)
    return {"results": [], "converted": col["written"], "acre_collision": col}


def convert_static_only(cfg: PipelineConfig) -> dict[str, Any]:
    """Reconvert static Gfx without wiping cKF / BTI output."""
    results: list[dict[str, Any]] = []
    rel = RelData(cfg.extracted_disc / "files" / "foresta.rel")
    symbols = parse_map(cfg.extracted_disc / "files" / "foresta.map")
    bank = TextureBank(rel, symbols, cfg.extracted_archives)
    static_jobs = _static_jobs(symbols)
    for i, item in enumerate(static_jobs, 1):
        record = _convert_static(cfg, rel, symbols, item, bank)
        results.append(record)
        if i % 50 == 0 or i == len(static_jobs):
            print(f"  static {i}/{len(static_jobs)}")
    col = _write_acre_collision(cfg, rel, symbols)
    converted = sum(1 for r in results if r["status"] == "converted")
    return {"results": results, "converted": converted, "acre_collision": col}


def convert_ckf_prefixes(cfg: PipelineConfig, prefixes: list[str]) -> dict[str, Any]:
    """Reconvert named cKF skeletons without wiping other generated output."""
    results: list[dict[str, Any]] = []
    rel = RelData(cfg.extracted_disc / "files" / "foresta.rel")
    symbols = parse_map(cfg.extracted_disc / "files" / "foresta.map")
    bank = TextureBank(rel, symbols, cfg.extracted_archives)
    names = {s.name for s in symbols}
    anims_by_prefix = _index_anims(symbols)
    wanted = {f"cKF_bs_r_{p}" if not p.startswith("cKF_bs_r_") else p for p in prefixes}
    skels = [s for s in symbols if s.name in wanted]
    for i, skel in enumerate(skels, 1):
        item = _skeleton_job(skel.name, names, anims_by_prefix)
        record = _convert_ckf(cfg, rel, symbols, item, bank)
        results.append(record)
        print(f"  ckf {i}/{len(skels)} {skel.name} {record['status']}")
    return {"results": results, "converted": sum(1 for r in results if r["status"] == "converted")}


def convert_static_prefixes(cfg: PipelineConfig, needles: list[str]) -> dict[str, Any]:
    """Reconvert static Gfx whose asset_id contains any needle (e.g. palm, cedar)."""
    results: list[dict[str, Any]] = []
    rel = RelData(cfg.extracted_disc / "files" / "foresta.rel")
    symbols = parse_map(cfg.extracted_disc / "files" / "foresta.map")
    bank = TextureBank(rel, symbols, cfg.extracted_archives)
    lowered = [n.lower() for n in needles]
    jobs = [
        item
        for item in _static_jobs(symbols)
        if any(n in item["asset_id"].lower() for n in lowered)
    ]
    for i, item in enumerate(jobs, 1):
        record = _convert_static(cfg, rel, symbols, item, bank)
        results.append(record)
        print(f"  static {i}/{len(jobs)} {item['asset_id']} {record['status']}")
    converted = sum(1 for r in results if r["status"] == "converted")
    return {"results": results, "converted": converted}


def convert_test_set(cfg: PipelineConfig) -> dict[str, Any]:
    results: list[dict[str, Any]] = []
    id_map: dict[str, Any] = {}
    _reset_output_dirs(cfg)
    rel = RelData(cfg.extracted_disc / "files" / "foresta.rel")
    symbols = parse_map(cfg.extracted_disc / "files" / "foresta.map")
    bank = TextureBank(rel, symbols, cfg.extracted_archives)

    for item in TEST_SKELETONS:
        record = _convert_ckf(cfg, rel, symbols, item, bank)
        results.append(record)
        id_map[item["skeleton"]] = {
            "godot_asset_id": item["asset_id"],
            "output": item["output"],
            "confident_name": item["confident_name"],
        }

    for item in TEST_STATIC:
        record = _convert_static(cfg, rel, symbols, item, bank)
        results.append(record)
        id_map[item["vtx"]] = {
            "godot_asset_id": item["asset_id"],
            "output": item["output"],
            "confident_name": item["confident_name"],
        }

    for src_rel, dest_rel in TEST_BTI:
        results.append(_convert_bti(cfg, src_rel, dest_rel))
        id_map[src_rel] = {
            "godot_asset_id": Path(dest_rel).stem,
            "output": dest_rel,
            "confident_name": True,
        }

    _write_acre_collision(cfg, rel, symbols)
    return _write_report(cfg, results, id_map)


def convert_all(cfg: PipelineConfig) -> dict[str, Any]:
    results: list[dict[str, Any]] = []
    id_map: dict[str, Any] = {}
    _reset_output_dirs(cfg)
    rel = RelData(cfg.extracted_disc / "files" / "foresta.rel")
    symbols = parse_map(cfg.extracted_disc / "files" / "foresta.map")
    bank = TextureBank(rel, symbols, cfg.extracted_archives)
    names = {s.name for s in symbols}

    anims_by_prefix = _index_anims(symbols)
    skels = [s for s in symbols if s.name.startswith("cKF_bs_r_")]
    for i, skel in enumerate(skels, 1):
        item = _skeleton_job(skel.name, names, anims_by_prefix)
        record = _convert_ckf(cfg, rel, symbols, item, bank)
        results.append(record)
        id_map[item["skeleton"]] = {
            "godot_asset_id": item["asset_id"],
            "output": item["output"],
            "confident_name": item["confident_name"],
        }
        if i % 50 == 0 or i == len(skels):
            print(f"  skeletons {i}/{len(skels)}")

    static_jobs = _static_jobs(symbols)
    for i, item in enumerate(static_jobs, 1):
        record = _convert_static(cfg, rel, symbols, item, bank)
        results.append(record)
        id_map[item["vtx"]] = {
            "godot_asset_id": item["asset_id"],
            "output": item["output"],
            "confident_name": item["confident_name"],
        }
        if i % 50 == 0 or i == len(static_jobs):
            print(f"  static {i}/{len(static_jobs)}")

    results.extend(_convert_all_bti(cfg))
    results.extend(_convert_player_bins(cfg))
    results.extend(_convert_room_bins(cfg))
    print("  dumping REL textures...")
    results.extend(_convert_rel_textures(cfg, rel, symbols, bank))
    _write_acre_collision(cfg, rel, symbols)

    for rec in results:
        src = rec.get("skeleton") or rec.get("source") or rec.get("vtx") or rec.get("asset_id")
        if src and src not in id_map:
            id_map[str(src)] = {
                "godot_asset_id": rec.get("asset_id"),
                "output": rec.get("output_path"),
                "confident_name": rec.get("confident_name", False),
            }

    return _write_report(cfg, results, id_map)


def _index_anims(symbols: list) -> dict[str, list[str]]:
    grouped: dict[str, list[str]] = {}
    for symbol in symbols:
        if not symbol.name.startswith("cKF_ba_r_"):
            continue
        rest = symbol.name[len("cKF_ba_r_") :]
        grouped.setdefault(rest, []).append(symbol.name)
        head = rest.split("_")[0]
        grouped.setdefault(head, []).append(symbol.name)
        # prefix up to last _chunk for names like int_kon_redclock
        grouped.setdefault(rest, [])
    return grouped


def _all_npc_anims(names: set[str]) -> list[str]:
    """Every shared villager clip. The game uses one npc_1 bank for all species."""
    anims = [n for n in names if n.startswith("cKF_ba_r_npc_1_")]
    anims.sort(key=lambda n: (0 if n in NPC_CORE_ANIMS else 1, NPC_CORE_ANIMS.index(n) if n in NPC_CORE_ANIMS else n))
    return anims


def _uses_shared_npc_anims(prefix: str) -> bool:
    if prefix.startswith(("boy_", "girl_", "int_", "tol_", "obj_", "act_", "ef_", "grd_", "logo_", "clk_")):
        return False
    return bool(_SPECIES_PREFIX.fullmatch(prefix))


def _anims_for_prefix(prefix: str, names: set[str], anims_by_prefix: dict[str, list[str]]) -> list[str]:
    known = TEST_SKEL_BY_NAME.get(f"cKF_bs_r_{prefix}")
    hits = [
        n
        for n in names
        if n == f"cKF_ba_r_{prefix}" or n.startswith(f"cKF_ba_r_{prefix}_")
    ]
    hits.sort()
    if prefix.startswith("boy_"):
        extra = [n for n in names if n.startswith("cKF_ba_r_ply_1_")]
        extra.sort()
        core = [n for n in PLAYER_CORE_ANIMS if n in names]
        rest = [n for n in extra if n not in core]
        return core + rest
    if _uses_shared_npc_anims(prefix):
        # Prefix-specific clips are rare; the disc bank is always npc_1_*.
        return _all_npc_anims(names)
    if known and not hits:
        return list(known.get("animations") or [])
    return hits


def _skeleton_job(skeleton: str, names: set[str], anims_by_prefix: dict[str, list[str]]) -> dict[str, Any]:
    if skeleton in TEST_SKEL_BY_NAME:
        item = dict(TEST_SKEL_BY_NAME[skeleton])
        prefix = skeleton.replace("cKF_bs_r_", "")
        item["animations"] = _anims_for_prefix(prefix, names, anims_by_prefix)
        return item
    prefix = skeleton.replace("cKF_bs_r_", "")
    return {
        "asset_id": prefix,
        "skeleton": skeleton,
        "output": _output_for_prefix(prefix),
        "animations": _anims_for_prefix(prefix, names, anims_by_prefix),
        "confident_name": False,
    }


def _env_subdir(prefix: str) -> str:
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


def _output_for_prefix(prefix: str) -> str:
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
        return f"{_env_subdir(prefix)}/{prefix}.glb"
    if _uses_shared_npc_anims(prefix):
        return f"characters/villagers/{prefix}.glb"
    # Odd cKF leftovers (hnw, …) — keep out of the species folder.
    return f"characters/other/{prefix}.glb"


def _output_folder_for_static(prefix: str) -> str:
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
        return _env_subdir(prefix)
    # Other static props (UI widgets, letters, …) stay under environment/.
    return "environment"


def _name_under_prefix(name: str, prefix: str) -> bool:
    """True if name belongs to prefix (grd_s_f_1 must not match grd_s_f_10_*)."""
    if name == prefix:
        return True
    if not name.startswith(prefix + "_"):
        return False
    rest = name[len(prefix) + 1 :]
    if prefix[-1:].isdigit() and rest[:1].isdigit():
        return False
    return True


def _static_model_names(prefix: str, symbols: list) -> list[str]:
    """Display lists for a static vtx blob: prefer *_gfx_model, else *_model."""
    gfx = [
        s.name
        for s in symbols
        if s.name.endswith("_gfx_model") and _name_under_prefix(s.name, prefix)
    ]
    if gfx:
        return sorted(gfx)
    models = [
        s.name
        for s in symbols
        if s.name.endswith("_model")
        and not s.name.endswith("_modelT")
        and not s.name.endswith("_mat_model")
        and not s.name.endswith("_gfx_model")
        and _name_under_prefix(s.name, prefix)
    ]
    return sorted(models)


def _static_jobs(symbols: list) -> list[dict[str, Any]]:
    skel_prefixes = {s.name.replace("cKF_bs_r_", "") for s in symbols if s.name.startswith("cKF_bs_r_")}
    jobs: list[dict[str, Any]] = []
    seen_vtx: set[str] = set()
    for symbol in symbols:
        if not symbol.name.endswith("_v") or symbol.name.startswith("cKF_"):
            continue
        prefix = symbol.name[:-2]
        if prefix in skel_prefixes:
            continue
        model_names = _static_model_names(prefix, symbols)
        if not model_names:
            continue
        if symbol.name in seen_vtx:
            continue
        seen_vtx.add(symbol.name)
        if symbol.name in TEST_STATIC_BY_VTX:
            jobs.append(dict(TEST_STATIC_BY_VTX[symbol.name]))
            continue
        folder = _output_folder_for_static(prefix)
        jobs.append(
            {
                "asset_id": prefix,
                "vtx": symbol.name,
                "gfx": model_names,
                "output": f"{folder}/{prefix}.glb",
                "confident_name": False,
            }
        )
    return jobs


def _convert_ckf(cfg: PipelineConfig, rel: RelData, symbols: list, item: dict[str, Any], bank: TextureBank) -> dict[str, Any]:
    record: dict[str, Any] = {
        "asset_id": item["asset_id"],
        "skeleton": item["skeleton"],
        "output_path": item["output"],
        "status": "pending",
        "error": None,
        "parts": 0,
        "triangles": 0,
        "vertices": 0,
        "animations_documented": item["animations"],
        "confident_name": item["confident_name"],
        "textured_parts": 0,
    }
    try:
        model = convert_ckf_model(
            rel,
            symbols,
            item["skeleton"],
            cfg.scale,
            animation_names=item.get("animations") or [],
            bank=bank,
        )
        dest = cfg.converted / item["output"]
        write_skinned_glb(
            dest,
            model,
            extras={
                "asset_id": item["asset_id"],
                "source_skeleton": item["skeleton"],
                "scale": cfg.scale,
                "transforms": TRANSFORMS,
            },
        )
        record["status"] = "converted"
        record["parts"] = len(model.parts)
        record["triangles"] = sum(len(p.triangles) for p in model.parts)
        record["vertices"] = sum(len(p.vertices) for p in model.parts)
        record["joints"] = len(model.joints)
        record["animations_baked"] = list(model.animations)
        record["textured_parts"] = sum(1 for p in model.parts if p.texture_png)
        _copy_generated(cfg, dest, item["output"])
    except Exception as exc:  # noqa: BLE001 — report per-asset, keep going
        record["status"] = "error"
        record["error"] = f"{type(exc).__name__}: {exc}"
    return record


def _convert_static(
    cfg: PipelineConfig, rel: RelData, symbols: list, item: dict[str, Any], bank: TextureBank
) -> dict[str, Any]:
    record: dict[str, Any] = {
        "asset_id": item["asset_id"],
        "vtx": item["vtx"],
        "gfx": item["gfx"],
        "output_path": item["output"],
        "status": "pending",
        "error": None,
        "parts": 0,
        "triangles": 0,
        "vertices": 0,
        "confident_name": item["confident_name"],
        "textured_parts": 0,
    }
    try:
        bank.segment_images.clear()
        bank.segment_palettes.clear()
        bank._segment_offset_names.clear()
        bank.bind_static_segments(item["asset_id"])
        parts = convert_static_gfx(rel, symbols, item["vtx"], item["gfx"], cfg.scale, bank=bank)
        dest = cfg.converted / item["output"]
        write_glb(
            dest,
            parts,
            extras={
                "asset_id": item["asset_id"],
                "source_vtx": item["vtx"],
                "source_gfx": item["gfx"],
                "scale": cfg.scale,
                "transforms": TRANSFORMS,
            },
        )
        record["status"] = "converted"
        record["parts"] = len(parts)
        record["triangles"] = sum(len(p.triangles) for p in parts)
        record["vertices"] = sum(len(p.vertices) for p in parts)
        record["textured_parts"] = sum(1 for p in parts if p.texture_png)
        _copy_generated(cfg, dest, item["output"])
    except Exception as exc:  # noqa: BLE001
        record["status"] = "error"
        record["error"] = f"{type(exc).__name__}: {exc}"
    return record


def _convert_bti(cfg: PipelineConfig, src_rel: str, dest_rel: str) -> dict[str, Any]:
    record = {
        "asset_id": Path(dest_rel).stem,
        "source": src_rel,
        "output_path": dest_rel,
        "status": "pending",
        "error": None,
        "confident_name": True,
    }
    try:
        src = cfg.extracted_archives / src_rel
        dest = cfg.converted / dest_rel
        meta = bti_to_png(src, dest)
        record["status"] = "converted"
        record["meta"] = meta
        _copy_generated(cfg, dest, dest_rel)
    except Exception as exc:  # noqa: BLE001
        record["status"] = "error"
        record["error"] = f"{type(exc).__name__}: {exc}"
    return record


def _convert_all_bti(cfg: PipelineConfig) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    archives = cfg.extracted_archives
    if not archives.is_dir():
        return results
    for path in sorted(archives.rglob("*.bti")):
        rel = path.relative_to(archives).as_posix()
        dest_rel = f"ui/{path.stem}.png"
        results.append(_convert_bti(cfg, rel, dest_rel))
    dtk = ensure_dtk(cfg.dtk_path)
    for path in sorted(archives.rglob("*.bti.szs")):
        dest_rel = f"ui/{path.name.replace('.bti.szs', '')}.png"
        record = {
            "asset_id": Path(dest_rel).stem,
            "source": path.relative_to(archives).as_posix(),
            "output_path": dest_rel,
            "status": "pending",
            "error": None,
        }
        try:
            dest = cfg.converted / dest_rel
            raw = path.read_bytes()
            tmp = cfg.converted / "_tmp" / path.name.replace(".szs", "")
            tmp.parent.mkdir(parents=True, exist_ok=True)
            if raw[:4] == b"Yaz0":
                subprocess.check_call([str(dtk), "yaz0", "decompress", str(path), "-o", str(tmp)])
            else:
                tmp.write_bytes(raw)
            meta = bti_to_png(tmp, dest)
            tmp.unlink(missing_ok=True)
            record["status"] = "converted"
            record["meta"] = meta
            _copy_generated(cfg, dest, dest_rel)
        except Exception as exc:  # noqa: BLE001
            record["status"] = "error"
            record["error"] = f"{type(exc).__name__}: {exc}"
        results.append(record)
    return results


def _convert_player_bins(cfg: PipelineConfig) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    data = cfg.extracted_archives / "forest_1st" / "data"
    face_path = data / "face_boy.bin"
    if face_path.is_file():
        face = face_path.read_bytes()
        for face_i in range(64):
            base = 0xE20 * face_i
            if base + 0xE20 > len(face):
                break
            pal = face[base + 0xE00 : base + 0xE20]
            for expr in range(14):
                dest_rel = f"textures/player/faces/face_{face_i:02d}_{expr:02d}.png"
                results.append(
                    _png_record(
                        cfg,
                        dest_rel,
                        f"face_boy.bin:{face_i}:{expr}",
                        face[base + 0x100 * expr : base + 0x100 * (expr + 1)],
                        32,
                        16,
                        pal,
                    )
                )
    tex_path = data / "tex_boy.bin"
    pal_path = data / "pallet_boy.bin"
    if tex_path.is_file() and pal_path.is_file():
        tex = tex_path.read_bytes()
        pal = pal_path.read_bytes()
        count = min(len(tex) // 0x200, len(pal) // 0x20)
        for i in range(count):
            dest_rel = f"textures/player/shirts/shirt_{i:03d}.png"
            results.append(
                _png_record(
                    cfg,
                    dest_rel,
                    f"tex_boy.bin:{i}",
                    tex[i * 0x200 : (i + 1) * 0x200],
                    32,
                    32,
                    pal[i * 0x20 : (i + 1) * 0x20],
                )
            )
    return results


def _convert_room_bins(cfg: PipelineConfig) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    data = cfg.extracted_archives / "forest_2nd" / "data"
    floor = data / "player_room_floor.bin"
    if floor.is_file():
        blob = floor.read_bytes()
        n = len(blob) // 0x2020
        for i in range(n):
            base = 0x2020 * i
            pal = blob[base : base + 0x20]
            for p in range(4):
                dest_rel = f"textures/rooms/floor/floor_{i:02d}_{p}.png"
                tex = blob[base + 0x20 + 0x800 * p : base + 0x20 + 0x800 * (p + 1)]
                results.append(_png_record(cfg, dest_rel, f"player_room_floor.bin:{i}:{p}", tex, 64, 64, pal))
    wall = data / "player_room_wall.bin"
    if wall.is_file():
        blob = wall.read_bytes()
        n = len(blob) // 0x1020
        for i in range(n):
            base = 0x1020 * i
            pal = blob[base : base + 0x20]
            for p in range(2):
                dest_rel = f"textures/rooms/wall/wall_{i:02d}_{p}.png"
                tex = blob[base + 0x20 + 0x800 * p : base + 0x20 + 0x800 * (p + 1)]
                results.append(_png_record(cfg, dest_rel, f"player_room_wall.bin:{i}:{p}", tex, 64, 64, pal))
    return results


def _infer_ci4_size(nbytes: int) -> tuple[int, int] | None:
    pixels = nbytes * 2
    candidates = (
        (8, 8),
        (16, 8),
        (8, 16),
        (16, 16),
        (32, 8),
        (8, 32),
        (32, 16),
        (16, 32),
        (32, 32),
        (64, 16),
        (16, 64),
        (64, 32),
        (32, 64),
        (64, 64),
        (128, 32),
        (32, 128),
        (128, 64),
        (64, 128),
        (128, 128),
        (256, 64),
        (64, 256),
        (256, 128),
        (128, 256),
        (256, 256),
    )
    for width, height in candidates:
        if width * height == pixels:
            return width, height
    side = int(pixels**0.5)
    if side * side == pixels and side > 0:
        return side, side
    return None


def _convert_rel_textures(cfg: PipelineConfig, rel: RelData, symbols: list, bank: TextureBank) -> list[dict[str, Any]]:
    """Decode every named REL CI texture using map sizes + a nearby palette when present."""
    results: list[dict[str, Any]] = []
    pals = [s for s in symbols if s.name.endswith("_pal") and s.size >= 32]
    pals.sort(key=lambda s: s.address)
    pal_i = 0
    for symbol in symbols:
        if not (symbol.name.endswith("_tex_txt") or (symbol.name.endswith("_tex") and not symbol.name.endswith("_tex_txt"))):
            continue
        if symbol.size <= 0:
            continue
        dims = _infer_ci4_size(symbol.size)
        if dims is None:
            continue
        while pal_i + 1 < len(pals) and pals[pal_i + 1].address <= symbol.address:
            pal_i += 1
        pal_blob = None
        if pals and pals[pal_i].address <= symbol.address and symbol.address - pals[pal_i].address < 0x2000:
            pal_sym = pals[pal_i]
            pal_blob = rel.slice_at(pal_sym.address, min(pal_sym.size, 512))
        elif bank._tree_pal and "tree" in symbol.name:
            pal_blob = bank._tree_pal
        dest_rel = f"textures/rel/{symbol.name}.png"
        try:
            data = rel.slice_at(symbol.address, symbol.size)
            results.append(_png_record(cfg, dest_rel, symbol.name, data, dims[0], dims[1], pal_blob or b""))
        except Exception as exc:  # noqa: BLE001
            results.append(
                {
                    "asset_id": symbol.name,
                    "source": symbol.name,
                    "output_path": dest_rel,
                    "status": "error",
                    "error": f"{type(exc).__name__}: {exc}",
                }
            )
    return results


def _png_record(
    cfg: PipelineConfig,
    dest_rel: str,
    source: str,
    data: bytes,
    width: int,
    height: int,
    pal: bytes,
) -> dict[str, Any]:
    record: dict[str, Any] = {
        "asset_id": Path(dest_rel).stem,
        "source": source,
        "output_path": dest_rel,
        "status": "pending",
        "error": None,
    }
    try:
        image = decode_gbi_texture(data, width, height, G_IM_FMT_CI, G_IM_SIZ_4b, pal)
        dest = cfg.converted / dest_rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(image_png_bytes(image))
        record["status"] = "converted"
        record["meta"] = {"width": width, "height": height}
        _copy_generated(cfg, dest, dest_rel)
    except Exception as exc:  # noqa: BLE001
        record["status"] = "error"
        record["error"] = f"{type(exc).__name__}: {exc}"
    return record


def _write_acre_collision(cfg: PipelineConfig, rel: RelData, symbols: list) -> dict[str, Any]:
    col = extract_and_write(rel, symbols, cfg.godot_generated)
    print(f"  acre collision {col['written']} sidecars")
    return col


def _write_report(cfg: PipelineConfig, results: list[dict[str, Any]], id_map: dict[str, Any]) -> dict[str, Any]:
    report = {"transforms": TRANSFORMS, "results": results}
    cfg.manifests.mkdir(parents=True, exist_ok=True)
    (cfg.manifests / "conversion_report.json").write_text(json.dumps(report, indent=2) + "\n")
    (cfg.manifests / "id_map.json").write_text(json.dumps(id_map, indent=2, sort_keys=True) + "\n")
    return report


def _reset_output_dirs(cfg: PipelineConfig) -> None:
    for folder in (cfg.converted, cfg.godot_generated):
        folder.mkdir(parents=True, exist_ok=True)
        for child in folder.iterdir():
            if child.name in {".gitkeep", "README.md"}:
                continue
            if child.is_dir():
                shutil.rmtree(child)
            else:
                child.unlink()


def _copy_generated(cfg: PipelineConfig, src: Path, rel: str) -> None:
    dest = cfg.godot_generated / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)
    write_import_sidecar(dest)
