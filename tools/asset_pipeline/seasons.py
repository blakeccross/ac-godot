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
from .convert import _static_jobs, _texture_bank
from .godot_import import write_import_sidecar
from .mapfile import parse_map
from .rel import RelData
from .texbank import (
	_FIELD_PAL_ROW_BY_SEASON,
	_TREE_PAL_ROW_BY_SEASON,
	G_IM_FMT_CI,
	G_IM_SIZ_4b,
	TextureBank,
	apply_prim,
	decode_gbi_texture,
	image_png_bytes,
)


# Role stem → substrings matched against decoded texture / material names.
GRASS_PATTERN_COUNT = 3

FIELD_ROLE_NEEDLES: dict[str, tuple[str, ...]] = {
	"grass": ("grass",),
	"earth": ("earth",),
	"cliff": ("cliff",),
	"bush_a": ("bush_a", "busha"),
	"bush_b": ("bush_b", "bushb"),
	"rail": ("rail",),
	"stone": ("stone",),
	"sand": ("sand",),
	"beach_wet": ("beach1", "beacha"),
	"river_edge": ("river_tex",),
}

TREE_ROLE_NEEDLES: dict[str, tuple[str, ...]] = {
	"tree_leaf": ("leaf",),
	"tree_trunk": ("trunk",),
}

## `m_bg_tex.c` dummy sizes (CI4). Pal tables are 16× RGB5A3 in segment 0x80.
_FIELD_TEX_SPECS: dict[str, tuple[int, int, str]] = {
	"grass_tex_dummy": (32, 32, "earth_pal"),
	"earth_tex_dummy": (64, 64, "earth_pal"),
	"cliff_tex_dummy": (64, 64, "earth_pal"),
	"bush_a_tex_dummy": (64, 64, "bush_pal"),
	"bush_b_tex_dummy": (64, 32, "bush_pal"),
	"rail_tex_dummy": (64, 64, "earth_pal"),
	"stone_tex_dummy": (64, 64, "earth_pal"),
	"sand_tex_dummy": (64, 32, "beach_pal"),
	"river_tex_dummy": (64, 32, "cliff_pal"),
	## Segment names are ``mFM_grd_*_rail_tex``, not ``rail_tex_dummy``.
	"rail_tex": (64, 64, "earth_pal"),
}

## `mFM_BG_TEX_*` order: triangle, square, circle. Each maps to a distinct CI4 tile in REL.
_GRASS_TEX_SYMBOLS: dict[str, tuple[tuple[str, ...], ...]] = {
	"s": (
		("mFM_grd_s_grass_tex", "grd_s_grass_tex"),
		("mFM_grd_s_grass_3_tex", "grd_s_grass_3_tex"),
		("mFM_grd_s_grass_2_tex", "grd_s_grass_2_tex"),
	),
	"w": (
		("mFM_grd_w_grass_tex", "grd_w_grass_tex"),
		("mFM_grd_w_grass_3_tex", "grd_w_grass_3_tex"),
		("mFM_grd_w_grass_2_tex", "grd_w_grass_2_tex"),
	),
}
_EARTH_PAL_SYMBOLS: tuple[str, ...] = (
	"mFM_earth_pal_dummy",
	"earth_pal_dummy",
	"mFM_earth_pal",
	"earth_pal",
)


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


def _pick_cliff_acre_job(jobs: dict[str, dict[str, Any]], season: str) -> dict[str, Any] | None:
	"""Cliff acres draw bush_a/b fringe; flat `grd_s_f_*` jobs often omit them."""
	candidates: list[str] = []
	if season == "w":
		candidates.extend(sorted(k for k in jobs if k.startswith("grd_w_c1_")))
	candidates.extend(sorted(k for k in jobs if k.startswith("grd_s_c1_")))
	for asset_id in candidates:
		return jobs[asset_id]
	return None


def _pick_river_acre_job(jobs: dict[str, dict[str, Any]], season: str) -> dict[str, Any] | None:
	"""River banks use earth_tex strips beside grass."""
	if season == "w":
		job = _pick_job(jobs, "grd_w_r1_1", "grd_w_r1_2")
		if job is not None:
			return job
	return _pick_job(jobs, "grd_s_r1_1", "grd_s_r1_2", "grd_s_r1_3")


def _pick_beach_acre_job(jobs: dict[str, dict[str, Any]], _season: str) -> dict[str, Any] | None:
	"""Beach sand, earth transitions, and wet-shore I4 (`beach1`)."""
	for asset_id in sorted(jobs):
		if not asset_id.startswith("grd_s_m_"):
			continue
		if "_mh_" in asset_id or "_ta_" in asset_id or "_wf_" in asset_id:
			continue
		return jobs[asset_id]
	return _pick_job(jobs, "grd_s_m_1", "grd_s_m_2")


def _pick_shrine_acre_job(jobs: dict[str, dict[str, Any]], _season: str) -> dict[str, Any] | None:
	"""Wishing-well lot (`grd_s_f_ko_*`): bush_b fringe, stone path, earth."""
	return _pick_job(jobs, "grd_s_f_ko_1", "grd_s_f_ko_2", "grd_s_f_ko_3")


def _spec_for_tex_name(name: str) -> tuple[int, int, str] | None:
	lower = name.lower()
	for key, spec in _FIELD_TEX_SPECS.items():
		if key in lower:
			return spec
	return None


def _pal_offset(names: dict[int, str], needle: str) -> int | None:
	for off, label in names.items():
		if needle in label.lower():
			return off
	return None


def _collect_roles_from_field_bank(bank: TextureBank) -> dict[str, bytes]:
	"""Decode grass/earth/cliff/bush CI tiles bound into segment 0x80."""
	out: dict[str, bytes] = {}
	seg = bank.segment_images.get(0x80)
	names = bank._segment_offset_names.get(0x80, {})
	if seg is None or not names:
		return out
	data = bytes(seg.data)
	pals: dict[str, bytes | None] = {
		"earth_pal": None,
		"bush_pal": None,
		"beach_pal": None,
		"cliff_pal": None,
	}
	earth_off = _pal_offset(names, "earth_pal")
	if earth_off is not None and earth_off + 32 <= len(data):
		pals["earth_pal"] = data[earth_off : earth_off + 32]
	bush_off = _pal_offset(names, "bush_pal")
	if bush_off is not None and bush_off + 32 <= len(data):
		pals["bush_pal"] = data[bush_off : bush_off + 32]
	beach_off = _pal_offset(names, "beach_pal")
	if beach_off is not None and beach_off + 32 <= len(data):
		pals["beach_pal"] = data[beach_off : beach_off + 32]
	cliff_off = _pal_offset(names, "cliff_pal")
	if cliff_off is not None and cliff_off + 32 <= len(data):
		pals["cliff_pal"] = data[cliff_off : cliff_off + 32]
	for off, name in sorted(names.items()):
		if "pal" in name.lower():
			continue
		role = _role_for_name(name, FIELD_ROLE_NEEDLES)
		if not role or role in out:
			continue
		spec = _spec_for_tex_name(name)
		if spec is None:
			continue
		width, height, pal_key = spec
		pal = pals.get(pal_key)
		if not pal:
			continue
		needed = width * height // 2
		if off + needed > len(data):
			continue
		try:
			image = decode_gbi_texture(
				data[off : off + needed], width, height, G_IM_FMT_CI, G_IM_SIZ_4b, pal
			)
			image = apply_prim(image, (255, 255, 255, 255))
			out[role] = image_png_bytes(image)
		except (KeyError, ValueError, IndexError):
			continue
	return out


def _find_symbol(bank: TextureBank, names: tuple[str, ...]):
	for name in names:
		sym = bank._find_symbol(name)
		if sym is not None and sym.size > 0:
			return sym
	return None


def _discover_grass_symbol(bank: TextureBank, bg_season: str, pattern: int):
	"""Scan REL names when canonical ``mFM_grd_*_grass*_tex`` symbols differ by build."""
	needle: str
	if pattern == 0:
		needle = f"grd_{bg_season}_grass_tex"
		for name, sym in sorted(bank.by_name.items()):
			lower = name.lower()
			if needle in lower and "grass_2" not in lower and "grass_3" not in lower:
				return sym
	elif pattern == 1:
		needle = f"grd_{bg_season}_grass_3_tex"
		for name, sym in sorted(bank.by_name.items()):
			if needle in name.lower():
				return sym
	else:
		needle = f"grd_{bg_season}_grass_2_tex"
		for name, sym in sorted(bank.by_name.items()):
			if needle in name.lower():
				return sym
	return None


def _field_earth_pal_row(bank: TextureBank, rel: RelData, season: str) -> bytes | None:
	"""Monthly earth palette row used by ``grass_tex_dummy`` (``mFM_LoadBGCommonMonthlyPal``)."""
	row = _FIELD_PAL_ROW_BY_SEASON[season]
	for name in _EARTH_PAL_SYMBOLS:
		sym = bank._find_symbol(name)
		if sym is None or sym.size < 32:
			continue
		try:
			blob = rel.slice_at(sym.address, min(sym.size, (row + 1) * 32))
		except ValueError:
			continue
		off = row * 32
		if off + 32 <= len(blob):
			return blob[off : off + 32]
	return None


def _decode_grass_pattern_png(
	rel: RelData, bank: TextureBank, bg_season: str, pattern: int, season: str
) -> bytes | None:
	"""Decode one town grass motif (32×32 CI4 + earth pal row)."""
	candidates = _GRASS_TEX_SYMBOLS.get(bg_season, _GRASS_TEX_SYMBOLS["s"])
	if pattern < 0 or pattern >= len(candidates):
		return None
	sym = _find_symbol(bank, candidates[pattern])
	if sym is None:
		sym = _discover_grass_symbol(bank, bg_season, pattern)
	if sym is None:
		return None
	pal = _field_earth_pal_row(bank, rel, season)
	if not pal:
		return None
	width, height = 32, 32
	needed = width * height // 2
	try:
		data = rel.slice_at(sym.address, min(sym.size, needed))
	except ValueError:
		return None
	if len(data) < needed:
		return None
	try:
		image = decode_gbi_texture(data, width, height, G_IM_FMT_CI, G_IM_SIZ_4b, pal)
		image = apply_prim(image, (255, 255, 255, 255))
		return image_png_bytes(image)
	except (KeyError, ValueError, IndexError):
		return None


def _export_grass_patterns(
	cfg: PipelineConfig,
	bank: TextureBank,
	rel: RelData,
	season: str,
	out_dir: Path,
	*,
	force: bool,
) -> tuple[list[str], list[str]]:
	"""Write ``grass_0..2.png`` from ``mFM_grd_*_grass*_tex`` CI tiles."""
	written: list[str] = []
	missing: list[str] = []
	bg_season = "w" if season == "w" else "s"
	for variant in range(GRASS_PATTERN_COUNT):
		png = _decode_grass_pattern_png(rel, bank, bg_season, variant, season)
		if png is None:
			## Fallback: older path via segment-0x80 bank variant (often identical to 0).
			_clear_bank(bank)
			bank.bind_field_bg(
				season=bg_season,
				variant=variant,
				pal_row=_FIELD_PAL_ROW_BY_SEASON[season],
			)
			png = _collect_roles_from_field_bank(bank).get("grass")
		dest = out_dir / f"grass_{variant}.png"
		if png is None:
			missing.append(f"{season}/grass_{variant}")
			continue
		if dest.is_file() and not force:
			continue
		_write_png(dest, png, cfg.project_root)
		written.append(str(dest))
		if variant == 0:
			legacy = out_dir / "grass.png"
			if force or not legacy.is_file():
				_write_png(legacy, png, cfg.project_root)
				written.append(str(legacy))
	return written, missing


def _merge_gfx_roles(
	bank: TextureBank,
	rel: RelData,
	symbols: list,
	job: dict[str, Any] | None,
	scale: float,
	needles: dict[str, tuple[str, ...]],
	into: dict[str, bytes],
) -> None:
	if job is None:
		return
	bank.current_prefix = job["asset_id"]
	try:
		parts = convert_static_gfx(rel, symbols, job["vtx"], job["gfx"], scale, bank=bank)
	except Exception:  # noqa: BLE001
		return
	for role, png in _collect_roles(parts, needles).items():
		into.setdefault(role, png)


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
		name_s = str(name)
		if getattr(part, "water_kind", "") == "beach_wet":
			compact = name_s.lower().replace("_", "")
			if "beachb" not in compact and "beach2" not in compact:
				out.setdefault("beach_wet", png)
		role = _role_for_name(name_s, needles)
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
	for role, png in _collect_roles_from_field_bank(bank).items():
		by_role.setdefault(role, png)
	for extra_job in [
		_pick_cliff_acre_job(jobs, season),
		_pick_river_acre_job(jobs, season),
		_pick_beach_acre_job(jobs, season),
		_pick_shrine_acre_job(jobs, season),
	]:
		_merge_gfx_roles(
			bank, rel, symbols, extra_job, cfg.scale, FIELD_ROLE_NEEDLES, by_role
		)
	w, m = _export_grass_patterns(cfg, bank, rel, season, out_dir, force=force)
	written.extend(w)
	missing.extend(m)
	for role in FIELD_ROLE_NEEDLES:
		if role == "grass":
			continue
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
	bank = _texture_bank(cfg, rel, symbols)
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
