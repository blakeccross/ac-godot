"""Export seasonal RGBA texture packs for runtime material swaps.

Original acres keep one mesh and DMA season CI banks + palettes into segment
0x80. Our GLBs bake one season's colours into albedo. This module writes
per-season PNGs so Godot can swap ``albedo_texture`` when the clock season
changes — including when only summer meshes are present on disk.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .ckf import convert_static_gfx
from .config import PipelineConfig
from .convert import _static_jobs
from .godot_import import write_import_sidecar
from .mapfile import parse_map
from .rel import RelData
from .texbank import (
	_FIELD_PAL_ROW_BY_SEASON,
	_TREE_PAL_ROW_BY_SEASON,
	TextureBank,
)


# Role stem → substrings matched against decoded texture / material names.
FIELD_ROLE_NEEDLES: dict[str, tuple[str, ...]] = {
	"grass": ("grass",),
	"earth": ("earth",),
	"cliff": ("cliff",),
	"bush_a": ("bush_a", "busha"),
	"bush_b": ("bush_b", "bushb"),
	"rail": ("rail",),
	"stone": ("stone",),
	"sand": ("sand",),
}

TREE_ROLE_NEEDLES: dict[str, tuple[str, ...]] = {
	"tree_leaf": ("leaf",),
	"tree_trunk": ("trunk",),
}


def _clear_bank(bank: TextureBank) -> None:
	bank.segment_images.clear()
	bank.segment_palettes.clear()
	bank._segment_offset_names.clear()
	bank._png_cache.clear()


def _role_for_name(name: str, needles: dict[str, tuple[str, ...]]) -> str:
	compact = name.lower().replace(" ", "").replace("-", "").replace("_", "")
	# Longer needles first (busha before bush is handled by explicit bush_a keys).
	ordered = sorted(needles.items(), key=lambda kv: -max(len(n) for n in kv[1]))
	for role, parts in ordered:
		for part in parts:
			key = part.replace("_", "")
			if key and key in compact:
				return role
	return ""


def _pick_job(jobs: dict[str, dict[str, Any]], *candidates: str) -> dict[str, Any] | None:
	for name in candidates:
		if name in jobs:
			return jobs[name]
	return None


def _pick_acre_job(jobs: dict[str, dict[str, Any]], season: str) -> dict[str, Any] | None:
	"""Prefer a flat acre; winter bank needs a winter mesh when available."""
	if season == "w":
		job = _pick_job(jobs, "grd_w_f_1", "grd_w_f_2", "grd_w_f_3")
		if job is not None:
			return job
		for asset_id, item in sorted(jobs.items()):
			if asset_id.startswith("grd_w_f_"):
				return item
	job = _pick_job(jobs, "grd_s_f_1", "grd_s_f_2", "grd_s_f_3")
	if job is not None:
		return job
	for asset_id, item in sorted(jobs.items()):
		if asset_id.startswith("grd_s_f_"):
			return item
	return None


def _pick_tree_job(jobs: dict[str, dict[str, Any]], season: str) -> dict[str, Any] | None:
	if season == "w":
		job = _pick_job(jobs, "obj_w_tree5", "obj_w_tree4")
		if job is not None:
			return job
	job = _pick_job(jobs, "obj_s_tree5", "obj_f_tree5", "obj_s_tree4")
	if job is not None:
		return job
	for asset_id, item in sorted(jobs.items()):
		if "tree5" in asset_id and asset_id.startswith("obj_"):
			return item
	return None


def _write_png(path: Path, png: bytes, project_root: Path) -> None:
	path.parent.mkdir(parents=True, exist_ok=True)
	path.write_bytes(png)
	write_import_sidecar(path, project_root)


def _collect_roles(
	parts: list,
	needles: dict[str, tuple[str, ...]],
) -> dict[str, bytes]:
	out: dict[str, bytes] = {}
	for part in parts:
		png = getattr(part, "texture_png", None)
		name = getattr(part, "texture_name", "") or getattr(part, "name", "")
		if not png or not name:
			continue
		role = _role_for_name(str(name), needles)
		if role and role not in out:
			out[role] = png
	return out


def _export_field_season(
	cfg: PipelineConfig,
	rel: RelData,
	symbols: list,
	bank: TextureBank,
	jobs: dict[str, dict[str, Any]],
	season: str,
	out_dir: Path,
	*,
	force: bool,
) -> tuple[list[str], list[str]]:
	written: list[str] = []
	missing: list[str] = []
	job = _pick_acre_job(jobs, season)
	if job is None:
		return written, [f"field:{season}:no_acre_job"]
	_clear_bank(bank)
	bg_season = "w" if season == "w" else "s"
	bank.bind_field_bg(
		season=bg_season,
		variant=0,
		pal_row=_FIELD_PAL_ROW_BY_SEASON[season],
	)
	bank.current_prefix = job["asset_id"]
	try:
		parts = convert_static_gfx(
			rel, symbols, job["vtx"], job["gfx"], cfg.scale, bank=bank
		)
	except Exception as exc:  # noqa: BLE001
		return written, [f"field:{season}:{type(exc).__name__}:{exc}"]
	by_role = _collect_roles(parts, FIELD_ROLE_NEEDLES)
	for role in FIELD_ROLE_NEEDLES:
		dest = out_dir / f"{role}.png"
		png = by_role.get(role)
		if png is None:
			missing.append(f"{season}/{role}")
			continue
		if dest.is_file() and not force:
			continue
		_write_png(dest, png, cfg.project_root)
		written.append(str(dest))
	return written, missing


def _export_tree_season(
	cfg: PipelineConfig,
	rel: RelData,
	symbols: list,
	bank: TextureBank,
	jobs: dict[str, dict[str, Any]],
	season: str,
	out_dir: Path,
	*,
	force: bool,
) -> tuple[list[str], list[str]]:
	written: list[str] = []
	missing: list[str] = []
	job = _pick_tree_job(jobs, season)
	if job is None:
		return written, [f"tree:{season}:no_tree_job"]
	_clear_bank(bank)
	# Autumn keeps summer tree CI; force the autumn FG palette row via prefix.
	if season == "f":
		bank.current_prefix = "obj_f_tree5"
		bank._apply_seasonal_fg_pals("obj_f_tree5")
	else:
		bank.bind_static_segments(job["asset_id"])
	try:
		parts = convert_static_gfx(
			rel, symbols, job["vtx"], job["gfx"], cfg.scale, bank=bank
		)
	except Exception as exc:  # noqa: BLE001
		return written, [f"tree:{season}:{type(exc).__name__}:{exc}"]
	by_role = _collect_roles(parts, TREE_ROLE_NEEDLES)
	for role in TREE_ROLE_NEEDLES:
		dest = out_dir / f"{role}.png"
		png = by_role.get(role)
		if png is None:
			missing.append(f"{season}/{role}")
			continue
		if dest.is_file() and not force:
			continue
		_write_png(dest, png, cfg.project_root)
		written.append(str(dest))
	return written, missing


def export_seasonal_textures(cfg: PipelineConfig, *, force: bool = False) -> dict[str, Any]:
	"""Write ``environment/seasons/{s,f,w}/*.png`` under the Godot generated root."""
	if not cfg.rel_path.is_file() or not cfg.map_path.is_file():
		return {
			"ok": False,
			"error": "foresta.rel / foresta.map missing; run extract first",
			"written": 0,
			"out": "",
			"missing": [],
		}
	rel = RelData(cfg.rel_path)
	symbols = parse_map(cfg.map_path)
	bank = TextureBank(rel, symbols, cfg.extracted_archives)
	jobs = {item["asset_id"]: item for item in _static_jobs(symbols)}
	root = cfg.godot_generated / "environment" / "seasons"
	written: list[str] = []
	missing: list[str] = []
	for season in ("s", "f", "w"):
		out_dir = root / season
		w, m = _export_field_season(
			cfg, rel, symbols, bank, jobs, season, out_dir, force=force
		)
		written.extend(w)
		missing.extend(m)
		w, m = _export_tree_season(
			cfg, rel, symbols, bank, jobs, season, out_dir, force=force
		)
		written.extend(w)
		missing.extend(m)
	ok = len(written) > 0
	return {
		"ok": ok,
		"written": len(written),
		"out": str(root),
		"paths": written[:40],
		"missing": missing,
		"error": "" if ok else "no seasonal textures written",
	}
