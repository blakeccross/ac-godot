from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any

from .bg_collision import extract_and_write
from .bti import bti_to_png
from .ckf import clear_caches, convert_ckf_model, convert_static_gfx
from .config import PipelineConfig
from .dtk import ensure_dtk
from .glb import write_glb, write_skinned_glb
from .godot_import import write_import_sidecar
from .layout import (
    bti_output_path,
    output_folder_for_static,
    output_for_prefix,
    uses_shared_npc_anims,
)
from .mapfile import parse_map
from .rel import RelData
from .test_set import TEST_BTI, TEST_SKELETONS, TEST_STATIC
from .texbank import (
    G_IM_FMT_CI,
    G_IM_FMT_IA,
    G_IM_SIZ_4b,
    G_IM_SIZ_8b,
    TextureBank,
    decode_gbi_texture,
    image_png_bytes,
)

## Shared field-bank IA waves (DL: G_IM_FMT_IA / G_IM_SIZ_8b). Not CI4 — wrong size + opaque A.
_REL_IA_WAVE_DIMS: dict[str, tuple[int, int]] = {
    "mFM_grd_wave1_tex": (32, 32),
    "mFM_grd_wave2_tex": (32, 64),
    "mFM_grd_wave3_tex": (32, 32),
}

TRANSFORMS = {
    "scale": "vertex * config.scale (default 0.001). Not actor 0.01 or acre 0.0625 draw scale — Godot FieldCatalog applies those.",
    "z_axis": "cKF: wait bind already stands on +Y; else +90° about Z unless GX verts already sit on +Y (houses/shops/myhome/station bake door-clip joint-0 yaw: house −90°, shop/myhome −135°, station 0°). Static Gfx keep GX Z (no flip).",
    "rest_pose": "wait frame 1 when available; furniture/clocks bake own clip frame 1 (closed); Y-up structures use door-clip frame 1; else identity + ckf_basis",
    "animations": "cKF_ba_r_* sampled at 30 fps into skinned glTF clips",
    "textures": "GX CI4/CI8 + pal; I/IA * G_SETPRIMCOLOR; villager tmem on 0x0A/0x0B",
    "skin": "G_MTX 0x0D slots map to Gfx-bearing joints; seam verts stay on the parent",
}

PLAYER_CORE_ANIMS = [
    "cKF_ba_r_ply_1_wait1",
    "cKF_ba_r_ply_1_walk1",
    "cKF_ba_r_ply_1_run1",
    "cKF_ba_r_ply_1_dash1",
    "cKF_ba_r_ply_1_axe1",
    "cKF_ba_r_ply_1_axe_swing1",
    "cKF_ba_r_ply_1_pickup1",
    "cKF_ba_r_ply_1_dig1",
    "cKF_ba_r_ply_1_shake1",
    "cKF_ba_r_ply_1_net_swing1",
    "cKF_ba_r_ply_1_sao_swing1",
    "cKF_ba_r_ply_1_kamae_wait_m1",
    # Rod chain (`m_player_main_*_rod.c_inc`): hold, pull, land the fish, reel in empty,
    # cast onto land. Without these the fishing loop has no reel.
    "cKF_ba_r_ply_1_sao1",
    "cKF_ba_r_ply_1_turi_wait1",
    "cKF_ba_r_ply_1_turi_hiki1",
    "cKF_ba_r_ply_1_get_t1",
    # `notice_rod`: hold the catch up and turn to the camera. `get_t1` lifts it out of the
    # water, `get_t2` is the pose you read the fish's name over.
    "cKF_ba_r_ply_1_get_t2",
    "cKF_ba_r_ply_1_not_get_t1",
    "cKF_ba_r_ply_1_not_sao_swing1",
    # `putaway_rod`, which `notice_rod` requests once the catch report closes: the rod and the
    # fish go into the pocket. The rod itself has no putaway clip -- `tol_sao_1` carries only
    # six -- so it holds its wait pose through this one.
    "cKF_ba_r_ply_1_putaway_t1",
    # Door enter (`mPlayer_INDEX_DOOR` / type 0 → OPEN1). Walks into the doorway while the
    # structure door cKF plays.
    "cKF_ba_r_ply_1_open1",
    # Indoor exit / non-outdoor door (`mPlayer_INDEX_DOOR` type ≠ 0 → INTO_S1). Walks south
    # into the room exit before the outdoor emerge.
    "cKF_ba_r_ply_1_into_s1",
    # Outdoor emerge after indoor leave (`mPlayer_INDEX_OUTDOOR`). Demo exit uses GO_OUT_S1;
    # non-demo uses GO_OUT_O1 (often from mid-clip).
    "cKF_ba_r_ply_1_go_out_s1",
    "cKF_ba_r_ply_1_go_out_o1",
]

# Prefer these first in the GLB; every cKF_ba_r_npc_1_* clip is still included.
NPC_CORE_ANIMS = [
    "cKF_ba_r_npc_1_wait1",
    "cKF_ba_r_npc_1_walk1",
    "cKF_ba_r_npc_1_run1",
]

## `ac_npc_guide` train intro clips baked into `xct_1.glb` for the test set.
INTRO_ROVER_NPC_ANIMS = [
    "cKF_ba_r_npc_1_open_d1",
    "cKF_ba_r_npc_1_walk1",
    "cKF_ba_r_npc_1_wait1",
    "cKF_ba_r_npc_1_sitdown_d1",
    "cKF_ba_r_npc_1_sitdown_wait_d1",
    "cKF_ba_r_npc_1_standup_d1",
    "cKF_ba_r_npc_1_to_deck_d1",
    "cKF_ba_r_npc_1_keitai_on1",
    "cKF_ba_r_npc_1_keitai_talk1",
    "cKF_ba_r_npc_1_keitai_talk2",
    "cKF_ba_r_npc_1_keitai_off1",
    "cKF_ba_r_npc_1_open_d2",
]

## `ac_npc_sleep_obaba` sleep wait + nod/twitch clips baked into `kab_1.glb`.
INTRO_SLEEP_NPC_ANIMS = [
    "cKF_ba_r_npc_1_wait_nemu1",
    "cKF_ba_r_npc_1_kokkuri_d1",
    "cKF_ba_r_npc_1_kokkuri_d2",
]

# Species skeletons (cat_1, bev_1, …) share the 26-joint npc_1 bank. Not clocks/logos/effects.

TEST_SKEL_BY_NAME = {item["skeleton"]: item for item in TEST_SKELETONS}
TEST_STATIC_BY_VTX = {item["vtx"]: item for item in TEST_STATIC}

# The held-up catch models. Naming each `_a` job exactly keeps the `_b` / `_c` swim poses
# out, since `"act_f01_funa_a"` is not a substring of `"act_f01_funa_b"`.
FISH_STATIC_NEEDLES = [
    item["asset_id"] for item in TEST_STATIC if item["asset_id"].startswith("act_f")
]

BUG_STATIC_NEEDLES = [
    item["asset_id"] for item in TEST_STATIC if item["asset_id"].startswith("act_m_")
]

# River / marine / cliff-river acres. Avoid `grd_s_r` (hits `grd_s_rail`) and `grd_s_m` (hits museum `grd_s_mh`).
## Field sign (`ac_sign`): vtx is `obj_{s,w}_kanban_v`; DLs are `write_model` (paper on
## seg 0x09) then `obj_sign_{s,w}_model` (wood frame). Blank paper uses `hakushi_tex`.
KANBAN_SIGN_GFX: dict[str, list[str]] = {
    "obj_s_kanban": ["write_model", "obj_sign_s_model"],
    "obj_w_kanban": ["write_model", "obj_sign_w_model"],
}

WATER_STATIC_NEEDLES = [
    "grd_s_r1",
    "grd_s_r2",
    "grd_s_r3",
    "grd_s_r4",
    "grd_s_r5",
    "grd_s_r6",
    "grd_s_r7",
    "grd_w_r1",
    "grd_w_r2",
    "grd_w_r3",
    "grd_w_r4",
    "grd_w_r5",
    "grd_w_r6",
    "grd_w_r7",
    "grd_s_m_",
    "grd_w_m_",
    ## Open-ocean border acres: OPA dark-blue beachB under XLU waves.
    "grd_s_o_",
    "grd_w_o_",
    ## Cliff-edge ocean / marine (`grd_s_e2_o_*` does not match `grd_s_o_`).
    "grd_s_e2_o",
    "grd_s_e3_o",
    "grd_s_e2_m",
    "grd_s_e3_m",
    "grd_w_e2_o",
    "grd_w_e3_o",
    "grd_w_e2_m",
    "grd_w_e3_m",
    "grd_s_t_r",
    "grd_w_t_r",
    "grd_s_c1_r",
    "grd_s_c2_r",
    "grd_s_c3_r",
    "grd_s_c4_r",
    "grd_s_c5_r",
    "grd_s_c6_r",
    "grd_s_c7_r",
    "grd_w_c1_r",
    "grd_w_c2_r",
    "grd_w_c3_r",
    "grd_w_c4_r",
    "grd_w_c5_r",
    "grd_w_c6_r",
    "grd_w_c7_r",
]


def convert_assets(cfg: PipelineConfig) -> dict[str, Any]:
    if cfg.test_set_only:
        return convert_test_set(cfg)
    return convert_all(cfg)


def _rel_and_map(cfg: PipelineConfig) -> tuple[RelData, list]:
    clear_caches()
    return RelData(cfg.rel_path), parse_map(cfg.map_path)


def convert_acre_collision(cfg: PipelineConfig) -> dict[str, Any]:
    """Write `grd_*.col.json` sidecars from `data_bgd` without reconverting meshes."""
    rel, symbols = _rel_and_map(cfg)
    col = _write_acre_collision(cfg, rel, symbols)
    return {"results": [], "converted": col["written"], "acre_collision": col}


def convert_static_only(cfg: PipelineConfig) -> dict[str, Any]:
    """Reconvert static Gfx without wiping cKF / BTI output."""
    results: list[dict[str, Any]] = []
    rel, symbols = _rel_and_map(cfg)
    bank = TextureBank(rel, symbols, cfg.extracted_archives)
    static_jobs = _static_jobs(symbols)
    for i, item in enumerate(static_jobs, 1):
        record = _convert_static(cfg, rel, symbols, item, bank)
        results.append(record)
        if i % 50 == 0 or i == len(static_jobs):
            print(f"  static {i}/{len(static_jobs)}")
    col = _write_acre_collision(cfg, rel, symbols)
    converted = sum(1 for r in results if r["status"] == "converted")
    return {
        "results": results,
        "converted": converted,
        "acre_collision": col,
    }


def convert_ckf_prefixes(cfg: PipelineConfig, prefixes: list[str]) -> dict[str, Any]:
    """Reconvert named cKF skeletons without wiping other generated output."""
    results: list[dict[str, Any]] = []
    rel, symbols = _rel_and_map(cfg)
    bank = TextureBank(rel, symbols, cfg.extracted_archives)
    names = {s.name for s in symbols}
    wanted = {f"cKF_bs_r_{p}" if not p.startswith("cKF_bs_r_") else p for p in prefixes}
    skels = [s for s in symbols if s.name in wanted]
    for i, skel in enumerate(skels, 1):
        item = _skeleton_job(skel.name, names)
        record = _convert_ckf(cfg, rel, symbols, item, bank)
        results.append(record)
        print(f"  ckf {i}/{len(skels)} {skel.name} {record['status']}")
    return {"results": results, "converted": sum(1 for r in results if r["status"] == "converted")}


def convert_ckf_starting_with(cfg: PipelineConfig, *prefixes: str) -> dict[str, Any]:
    """Reconvert every cKF skeleton whose prefix starts with one of `prefixes`."""
    rel, symbols = _rel_and_map(cfg)
    wanted: list[str] = []
    for symbol in symbols:
        if not symbol.name.startswith("cKF_bs_r_"):
            continue
        stem = symbol.name.replace("cKF_bs_r_", "")
        if any(stem.startswith(p) for p in prefixes):
            wanted.append(stem)
    return convert_ckf_prefixes(cfg, wanted)


def convert_static_prefixes(cfg: PipelineConfig, needles: list[str]) -> dict[str, Any]:
    """Reconvert static Gfx whose asset_id contains any needle (e.g. palm, cedar)."""
    results: list[dict[str, Any]] = []
    rel, symbols = _rel_and_map(cfg)
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


def convert_test_static_needles(cfg: PipelineConfig, needles: list[str]) -> dict[str, Any]:
    """Convert explicit `TEST_STATIC` rows matching needles.

    Insect poses share one vtx across `a`/`b` GLBs, so they cannot go through
    `_static_jobs`'s one-row-per-vtx dedupe.
    """
    results: list[dict[str, Any]] = []
    rel, symbols = _rel_and_map(cfg)
    bank = TextureBank(rel, symbols, cfg.extracted_archives)
    lowered = [n.lower() for n in needles]
    jobs = [
        item
        for item in TEST_STATIC
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
    rel, symbols = _rel_and_map(cfg)
    bank = TextureBank(rel, symbols, cfg.extracted_archives)
    names = {s.name for s in symbols}

    for raw in TEST_SKELETONS:
        item = _skeleton_job(raw["skeleton"], names, core_only=True)
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
    _reset_staging(cfg)
    rel, symbols = _rel_and_map(cfg)
    bank = TextureBank(rel, symbols, cfg.extracted_archives)
    names = {s.name for s in symbols}

    skels = [s for s in symbols if s.name.startswith("cKF_bs_r_")]
    for i, skel in enumerate(skels, 1):
        item = _skeleton_job(skel.name, names)
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


def _all_npc_anims(names: set[str]) -> list[str]:
    """Every shared villager clip. The game uses one npc_1 bank for all species."""
    anims = [n for n in names if n.startswith("cKF_ba_r_npc_1_")]
    anims.sort(key=lambda n: (0 if n in NPC_CORE_ANIMS else 1, NPC_CORE_ANIMS.index(n) if n in NPC_CORE_ANIMS else n))
    return anims


def _core_anims(wanted: list[str], names: set[str]) -> list[str]:
    return [n for n in wanted if n in names]


def _intro_rover_anims(names: set[str]) -> list[str]:
    return [n for n in INTRO_ROVER_NPC_ANIMS if n in names]


def _intro_sleep_npc_anims(names: set[str]) -> list[str]:
    return [n for n in INTRO_SLEEP_NPC_ANIMS if n in names]


def _anims_for_prefix(prefix: str, names: set[str], *, core_only: bool = False) -> list[str]:
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
        core = _core_anims(PLAYER_CORE_ANIMS, names)
        if core_only:
            return core
        rest = [n for n in extra if n not in core]
        return core + rest
    if uses_shared_npc_anims(prefix):
        # Pose evaluation is cached across species; rest translations still differ
        # so each GLB embeds its own tracks. core_only is the test-set path.
        if core_only:
            if prefix == "xct_1":
                intro = _intro_rover_anims(names)
                if intro:
                    return intro
            if prefix == "kab_1":
                sleep = _intro_sleep_npc_anims(names)
                if sleep:
                    return sleep
            return _core_anims(NPC_CORE_ANIMS, names)
        return _all_npc_anims(names)
    if known and not hits:
        return list(known.get("animations") or [])
    return hits


def _skeleton_job(skeleton: str, names: set[str], *, core_only: bool = False) -> dict[str, Any]:
    if skeleton in TEST_SKEL_BY_NAME:
        item = dict(TEST_SKEL_BY_NAME[skeleton])
        prefix = skeleton.replace("cKF_bs_r_", "")
        item["animations"] = _anims_for_prefix(prefix, names, core_only=core_only)
        return item
    prefix = skeleton.replace("cKF_bs_r_", "")
    return {
        "asset_id": prefix,
        "skeleton": skeleton,
        "output": output_for_prefix(prefix),
        "animations": _anims_for_prefix(prefix, names, core_only=core_only),
        "confident_name": False,
    }


def _name_under_prefix(name: str, prefix: str, all_prefixes: set[str] | None = None) -> bool:
    """True if name belongs to prefix (grd_s_f_1 must not match grd_s_f_10_*).

    `{prefix}T_gfx_model` is the overlay spelling (`obj_s_palm5_cocoT_*` has no
    extra underscore before T). A longer vtx prefix owns the symbol: `obj_s_palm5`
    must not swallow `obj_s_palm5_cocoT_gfx_model`.
    """
    owned = False
    if name == prefix:
        owned = True
    elif name.startswith(prefix + "T_") or name == prefix + "T":
        owned = True
    elif name.startswith(prefix + "_"):
        # `grd_s_f_10_*` does not start with `grd_s_f_1_`, so the digit-boundary
        # case does not reach here. Furniture parts (`int_ari_isu01_00T_model`,
        # `int_ari_reizou01_01_model`) must still belong to the vtx prefix.
        owned = True
    elif (
        prefix[-1:].isalpha()
        and len(name) > len(prefix)
        and name.startswith(prefix)
        and name[len(prefix)].isdigit()
    ):
        # `int_ike_art_fel_v` owns `int_ike_art_fel01_on_model`.
        owned = True
    if not owned:
        return False
    if all_prefixes:
        for other in all_prefixes:
            if other == prefix or len(other) <= len(prefix) or not other.startswith(prefix):
                continue
            if name == other or name.startswith(other + "_") or name.startswith(other + "T"):
                return False
    return True


def _owning_vtx_prefix(name: str, prefixes: set[str]) -> str | None:
    """Longest vtx prefix that owns this Gfx symbol (digit-safe, T-overlay aware)."""
    parts = name.split("_")
    for i in range(len(parts), 0, -1):
        cand = "_".join(parts[:i])
        variants = [cand]
        if cand.endswith("T"):
            variants.append(cand[:-1])
        for variant in variants:
            for owner in (variant, variant.rstrip("0123456789")):
                if owner and owner in prefixes and _name_under_prefix(name, owner):
                    return owner
    # Hardwood stumps: vtx `obj_s_stump5`, Gfx `obj_stump5T_gfx_model` (season infix dropped).
    dropped = re.match(r"^obj_(stump\d+)T_", name)
    if dropped:
        for season in ("s", "w", "f"):
            variant = f"obj_{season}_{dropped.group(1)}"
            if variant in prefixes:
                return variant
    return None


def _static_jobs(symbols: list) -> list[dict[str, Any]]:
    skel_prefixes = {s.name.replace("cKF_bs_r_", "") for s in symbols if s.name.startswith("cKF_bs_r_")}
    all_prefixes = {
        s.name[:-2]
        for s in symbols
        if s.name.endswith("_v") and not s.name.startswith("cKF_") and s.name[:-2] not in skel_prefixes
    }
    gfx_by_prefix: dict[str, list[str]] = {p: [] for p in all_prefixes}
    model_by_prefix: dict[str, list[str]] = {p: [] for p in all_prefixes}
    for symbol in symbols:
        name = symbol.name
        if name.endswith("_gfx_model"):
            owner = _owning_vtx_prefix(name, all_prefixes)
            if owner:
                gfx_by_prefix[owner].append(name)
        elif (
            name.endswith("_model")
            and not name.endswith("_modelT")
            and not name.endswith("_mat_model")
            and not name.endswith("_gfx_model")
        ):
            owner = _owning_vtx_prefix(name, all_prefixes)
            if owner:
                model_by_prefix[owner].append(name)

    jobs: list[dict[str, Any]] = []
    seen_vtx: set[str] = set()
    names = {s.name for s in symbols}
    for symbol in symbols:
        if not symbol.name.endswith("_v") or symbol.name.startswith("cKF_"):
            continue
        prefix = symbol.name[:-2]
        # An explicit entry names its own Gfx symbols, so it must not be gated on the
        # prefix inference below. `tol_uki_1_v` is drawn by `tol_uki1_model`, which no
        # amount of prefix matching will pair with it.
        if symbol.name in TEST_STATIC_BY_VTX:
            if symbol.name in seen_vtx:
                continue
            seen_vtx.add(symbol.name)
            jobs.append(dict(TEST_STATIC_BY_VTX[symbol.name]))
            continue
        if prefix in skel_prefixes:
            continue
        gfx_names = KANBAN_SIGN_GFX.get(prefix)
        if gfx_names is not None:
            if symbol.name in seen_vtx:
                continue
            if symbol.obj != "dataobject.obj":
                continue
            seen_vtx.add(symbol.name)
            folder = output_folder_for_static(prefix)
            jobs.append(
                {
                    "asset_id": prefix,
                    "vtx": symbol.name,
                    "gfx": list(gfx_names),
                    "output": f"{folder}/{prefix}.glb",
                    "confident_name": True,
                }
            )
            continue
        if prefix.endswith("_shadow"):
            # Blob shadows (`*_shadow_v`). Godot uses the sun; DLs are often empty.
            continue
        model_names = sorted(gfx_by_prefix.get(prefix) or model_by_prefix.get(prefix) or [])
        ## Tree-leaf XLU (`ef_s_cedar_modelT`) shares a prefix with numbered shake/cut DLs
        ## (`ef_s_cedar3_*`). Export the leaf card only for the base symbol.
        if prefix.startswith("ef_s_"):
            preferred = [n for n in (f"{prefix}_modelT", f"{prefix}_model") if n in names]
            if preferred:
                model_names = preferred
        # Acre OPA is `*_model`; XLU water/waves live on `*_modelT` (not plant `obj_*T_gfx`).
        if prefix.startswith("grd_"):
            model_t = f"{prefix}_modelT"
            if model_t in names and model_t not in model_names:
                model_names.append(model_t)
        if not model_names:
            continue
        if symbol.name in seen_vtx:
            continue
        if symbol.obj != "dataobject.obj":
            ## Overlay/DOL-local meshes (`tol_sponge_1`, `lat_atena`, `mbg`) are not in
            ## `foresta.rel` `.data` — only `dataobject.obj` symbols slice reliably.
            continue
        seen_vtx.add(symbol.name)
        folder = output_folder_for_static(prefix)
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
    except ValueError as exc:
        msg = str(exc)
        if msg.startswith("Meshless cKF") or msg.startswith("Empty cKF"):
            record["status"] = "skipped"
            record["error"] = msg
        else:
            record["status"] = "error"
            record["error"] = f"{type(exc).__name__}: {exc}"
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
        dest_rel = bti_output_path(rel)
        results.append(_convert_bti(cfg, rel, dest_rel))
    dtk = ensure_dtk(cfg.dtk_path)
    for path in sorted(archives.rglob("*.bti.szs")):
        src_rel = path.relative_to(archives).as_posix()
        dest_rel = bti_output_path(src_rel)
        record = {
            "asset_id": Path(dest_rel).stem,
            "source": src_rel,
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
    """Decode named REL textures: CI4 with nearby palettes, plus known IA field waves."""
    results: list[dict[str, Any]] = []
    pals = [s for s in symbols if s.name.endswith("_pal") and s.size >= 32]
    pals.sort(key=lambda s: s.address)
    pal_i = 0
    for symbol in symbols:
        if not (symbol.name.endswith("_tex_txt") or (symbol.name.endswith("_tex") and not symbol.name.endswith("_tex_txt"))):
            continue
        if symbol.size <= 0:
            continue
        dest_rel = f"textures/rel/{symbol.name}.png"
        ia_dims = _REL_IA_WAVE_DIMS.get(symbol.name)
        if ia_dims is not None:
            try:
                data = rel.slice_at(symbol.address, symbol.size)
                results.append(
                    _png_record(
                        cfg,
                        dest_rel,
                        symbol.name,
                        data,
                        ia_dims[0],
                        ia_dims[1],
                        b"",
                        fmt=G_IM_FMT_IA,
                        siz=G_IM_SIZ_8b,
                    )
                )
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
        if not pal_blob:
            continue
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
    fmt: int = G_IM_FMT_CI,
    siz: int = G_IM_SIZ_4b,
) -> dict[str, Any]:
    record: dict[str, Any] = {
        "asset_id": Path(dest_rel).stem,
        "source": source,
        "output_path": dest_rel,
        "status": "pending",
        "error": None,
    }
    try:
        image = decode_gbi_texture(data, width, height, fmt, siz, pal if fmt == G_IM_FMT_CI else None)
        dest = cfg.converted / dest_rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(image_png_bytes(image))
        record["status"] = "converted"
        record["meta"] = {"width": width, "height": height, "fmt": fmt, "siz": siz}
        _copy_generated(cfg, dest, dest_rel)
    except Exception as exc:  # noqa: BLE001
        record["status"] = "error"
        record["error"] = f"{type(exc).__name__}: {exc}"
    return record


def _write_acre_collision(cfg: PipelineConfig, rel: RelData, symbols: list) -> dict[str, Any]:
    col = extract_and_write(rel, symbols, [cfg.converted, cfg.godot_generated])
    print(f"  acre collision {col['written']} sidecars")
    return col


def _write_report(cfg: PipelineConfig, results: list[dict[str, Any]], id_map: dict[str, Any]) -> dict[str, Any]:
    report = {"transforms": TRANSFORMS, "results": results}
    cfg.manifests.mkdir(parents=True, exist_ok=True)
    (cfg.manifests / "conversion_report.json").write_text(json.dumps(report, indent=2) + "\n")
    (cfg.manifests / "id_map.json").write_text(json.dumps(id_map, indent=2, sort_keys=True) + "\n")
    return report


def _reset_staging(cfg: PipelineConfig) -> None:
    """Clear work-root staging only. Never wipe assets/generated (FG, inventory UI, prior --full)."""
    folder = cfg.converted
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
    write_import_sidecar(dest, cfg.project_root)
    ## Godot "Extract" leaves `name_0.png` siblings that ignore GLB samplers (wave2 CLAMP T)
    ## and can stick around after a bad reimport. Drop them whenever we refresh a GLB.
    if dest.suffix.lower() == ".glb":
        stem = dest.stem
        for sibling in dest.parent.glob(f"{stem}_*.png"):
            if sibling.stem[len(stem) + 1 :].isdigit():
                sibling.unlink(missing_ok=True)
                Path(str(sibling) + ".import").unlink(missing_ok=True)
