"""Extract design editor / design list window chrome (`m_design_ovl.c`, `des_win_*`).

Same "GBI UI geometry -> baked PNG" pattern as `inventory_ui.py`/`map_ui.py`, reusing
their generic helpers (`_pick_symbol`, `_parse_ui_vtx`, `_ia_prim_env`,
`_draw_textured_triangle`, `_fill_enclosed_holes` from `map_ui.py`) rather than
reimplementing them. The one bespoke piece is `_BORDER_BATCHES`: the exact
vertex-range + triangle-index wiring for the 8-piece rounded window border
(`des_win_shitaT_model`), hand-transcribed from `src/data/model/des_win.c` (available
in the decomp source, unlike the compiled `.inc` vertex data) — there is no automatic
GBI display-list walker for 2D UI models in this pipeline, so this mirrors exactly how
`inventory_ui.py`'s `_BORDER_PIECES` and `map_ui.py`'s `_KIWAKU_BATCHES` were built.

All 8 `des_win_awN_tex` pieces share one combiner
(`gsDPSetCombineLERP(PRIMITIVE, ENVIRONMENT, TEXEL0, ENVIRONMENT, ...)`,
`des_win.c:190`) with one shared PRIM/ENV pair (`des_win.c:191-192`) — identical shape
to `map_ui.py`'s `_ia_prim_env`, so no new combiner code is needed either.

Output is gitignored (Nintendo IP, not for commit).
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image

from .config import PipelineConfig
from .godot_import import write_import_sidecar
from .map_ui import _draw_textured_triangle, _ia_prim_env, _mirror_tile, _parse_ui_vtx, _pick_symbol
from .mapfile import MapSymbol, parse_map
from .rel import RelData
from .gfx import RenderState, parse_gfx, parse_vtx_blob
from .texbank import G_IM_FMT_CI, G_IM_FMT_I, G_IM_FMT_IA, TextureBank, TextureState, G_IM_SIZ_4b, G_IM_SIZ_8b, decode_gbi_texture, gbi_to_gx, image_png_bytes

OUT_DIR_NAME = "design"

## `des_win_shitaT_model` PRIM/ENV (`des_win.c:191-192`) — shared by all 8 border tiles.
_BORDER_PRIM = (85, 55, 55, 255)
_BORDER_ENV = (155, 90, 50, 255)
## A plausible neutral fill for the window's flat-color interior panels
## (`des_win_area1-4_model`, whose own PRIMITIVE color isn't set in `des_win.c` itself —
## inherited from the caller, `m_design_ovl.c`, not transcribed here). Close to the
## existing hand-authored `design_editor_overlay.tscn` frame color it replaces.
_INTERIOR_FILL = (240, 233, 217, 255)
_BAKE_SCALE = 3


@dataclass(frozen=True)
class TexSpec:
	name: str
	width: int
	height: int
	fmt: int
	siz: int
	out_name: str | None = None
	## `LERP(PRIMITIVE, ENVIRONMENT, TEXEL0, ENVIRONMENT)` baked with fixed colours.
	prim: tuple[int, int, int, int] | None = None
	env: tuple[int, int, int, int] | None = None
	## I-format coverage masks (`PRIMITIVE` colour, `TEXEL0` alpha): white RGB, alpha = I,
	## tinted at runtime with the caller's `gDPSetPrimColor`.
	mask: bool = False


## Plain chrome pieces — decoded as-is, no geometry baking. Sizes/formats transcribed
## from `des_win.c`'s `gsDPSetTextureImage_Dolphin` calls and `des_marking.c`.
_TOOL_PRIM = (70, 80, 50, 255)  # `des_tool.c` icon PRIM/ENV
_TOOL_ENV = (235, 205, 145, 255)
_CURSOR_PRIM = (60, 70, 60, 255)  # `des_cursor.c`
_CURSOR_ENV = (235, 235, 225, 255)


def _i4(name: str, w: int = 16, h: int = 16) -> TexSpec:
	return TexSpec(name, w, h, G_IM_FMT_I, G_IM_SIZ_4b, mask=True)


def _ia8(name: str, prim, env, w: int = 32, h: int = 32) -> TexSpec:
	return TexSpec(name, w, h, G_IM_FMT_IA, G_IM_SIZ_8b, prim=prim, env=env)


CHROME: list[TexSpec] = [
	_i4("des_win_sen_tex"),
	_i4("des_win_cwaku_tex"),
	_i4("des_win_color_tex"),
	_i4("des_win_marking_tex"),
	# `des_win_marking2T_model`: PRIM/ENV change per mode, so raw IA (lerp at runtime).
	TexSpec("des_win_marking3_tex", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b),
	_ia8("des_win_kirikae_tex", (80, 80, 60, 255), (195, 185, 165, 255)),
	_ia8("des_win_start_tex", (225, 225, 205, 255), (30, 30, 20, 255), 16, 16),
	_ia8("kei_win_quit_tex", (225, 205, 225, 255), (115, 40, 95, 255), 32, 16),
	*[_i4(f"des_win_suuji{i}_tex_rgb_i4") for i in range(10)],
	*[_ia8(f"des_tool_pen{i}_tex_rgb_ia8", _TOOL_PRIM, _TOOL_ENV) for i in range(1, 4)],
	*[_ia8(f"des_tool_nuri{i}_tex_rgb_ia8", _TOOL_PRIM, _TOOL_ENV) for i in range(1, 7)],
	*[_ia8(f"des_tool_waku{i}_tex_rgb_ia8", _TOOL_PRIM, _TOOL_ENV) for i in range(1, 6)],
	*[_ia8(f"des_tool_mark{i}_tex_rgb_ia8", _TOOL_PRIM, _TOOL_ENV) for i in range(1, 5)],
	_ia8("des_tool_undo_tex", _TOOL_PRIM, _TOOL_ENV),
	_ia8("des_cursor_pen_tex", (61, 70, 60, 255), _CURSOR_ENV),
	_ia8("des_cursor_nuri_tex", _CURSOR_PRIM, _CURSOR_ENV),
	_ia8("des_cursor_waku_tex", _CURSOR_PRIM, _CURSOR_ENV),
	_ia8("des_cursor_sen_tex", _CURSOR_PRIM, (225, 235, 225, 255)),
	_i4("des_cursor_mark1_tex", 16, 32),
	_i4("des_cursor_mark2_tex", 16, 32),
	_i4("des_cursor_mark3_tex"),
	_i4("des_cursor_mark4_tex"),
	_i4("des_cursor_undo_tex", 32, 32),
]

## The 8 border tiles + their native size (`des_win.c:194-227`). All GX_MIRROR.
_BORDER_TEX: dict[str, tuple[int, int]] = {
	"aw8": (16, 16),
	"aw7": (16, 32),
	"aw6": (16, 32),
	"aw5": (32, 16),
	"aw4": (32, 64),
	"aw3": (16, 32),
	"aw2": (64, 32),
	"aw1": (64, 32),
}

## `des_win_shitaT_model` (`des_win.c:188-232`): one `(vtx_base, count)` load per
## group, then one `(tile, local_triangle_indices)` entry per texture bind within that
## group's currently-loaded vertices. A bind can trail into the *next* group (the bound
## texture persists across `gsSPVertex` reloads) — `aw4` binds at the end of group A but
## draws with group B's vertices, `aw2` binds at the end of B/draws with C, `aw1` binds
## at the end of C/draws with D.
_BORDER_GROUPS: list[tuple[int, int]] = [
	(120, 28),  # A
	(148, 24),  # B
	(172, 16),  # C
	(188, 16),  # D
]
_BORDER_BATCHES: list[tuple[int, str, tuple[int, ...]]] = [
	# group A (base 120)
	(0, "aw8", (0, 1, 2, 1, 3, 2)),
	(0, "aw7", (4, 5, 6, 5, 7, 6, 8, 9, 10, 9, 11, 10)),
	(0, "aw6", (12, 13, 14, 15, 12, 14, 16, 17, 18, 19, 16, 18)),
	(0, "aw5", (20, 21, 22, 21, 23, 22, 24, 25, 26, 27, 24, 26)),
	# group B (base 148) — aw4 bound at the end of group A
	(1, "aw4", (0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 7, 5, 8, 9, 10, 8, 10, 11, 12, 13, 14, 12, 15, 13)),
	(1, "aw3", (16, 17, 18, 17, 19, 18, 20, 21, 22, 21, 23, 22)),
	# group C (base 172) — aw2 bound at the end of group B
	(2, "aw2", (0, 1, 2, 1, 3, 2, 4, 5, 6, 5, 7, 6, 8, 9, 10, 11, 8, 10, 12, 13, 14, 15, 12, 14)),
	# group D (base 188) — aw1 bound at the end of group C
	(3, "aw1", (0, 1, 2, 3, 4, 5, 6, 7, 8, 7, 9, 8, 10, 3, 5, 11, 12, 13, 12, 14, 13, 1, 15, 2)),
]


def extract_design_ui(cfg: PipelineConfig) -> dict[str, Any]:
	stage_dir = cfg.converted / "ui" / OUT_DIR_NAME
	out_dir = cfg.godot_generated / "ui" / OUT_DIR_NAME
	stage_dir.mkdir(parents=True, exist_ok=True)
	out_dir.mkdir(parents=True, exist_ok=True)

	results: list[dict[str, Any]] = []
	try:
		rel = RelData(cfg.rel_path)
		symbols = parse_map(cfg.map_path)
	except Exception as exc:  # noqa: BLE001
		return {"error": f"{type(exc).__name__}: {exc}"}

	by_name: dict[str, list[MapSymbol]] = {}
	for sym in symbols:
		by_name.setdefault(sym.name, []).append(sym)

	for spec in CHROME:
		results.append(_extract_plain(rel, by_name, spec, stage_dir, out_dir, cfg.project_root))

	border_tiles: dict[str, Image.Image] = {}
	for tile, (w, h) in _BORDER_TEX.items():
		spec = TexSpec(f"des_win_{tile}_tex", w, h, G_IM_FMT_IA, G_IM_SIZ_8b)
		rec = _extract_plain(rel, by_name, spec, stage_dir, out_dir, cfg.project_root, save=False)
		results.append(rec)
		if rec["status"] == "converted":
			border_tiles[tile] = rec.pop("_image")

	shell = _bake_border_shell(rel, by_name, border_tiles, stage_dir, out_dir, cfg.project_root)
	results.append(shell)
	results.extend(_bake_design_book(cfg, rel, symbols, by_name, stage_dir, out_dir))

	converted = sum(1 for r in results if r.get("status") == "converted")
	catalog = {"results": [{k: v for k, v in r.items() if k != "_image"} for r in results]}
	catalog_bytes = json.dumps(catalog, indent=2).encode("utf-8")
	for folder in (stage_dir, out_dir):
		(folder / "catalog.json").write_bytes(catalog_bytes)

	return {"results": results, "converted": converted, "output": str(out_dir), "window_shell": shell}


def _extract_plain(
	rel: RelData,
	by_name: dict[str, list[MapSymbol]],
	spec: TexSpec,
	stage_dir: Path,
	out_dir: Path,
	project_root: Path,
	*,
	save: bool = True,
) -> dict[str, Any]:
	out_stem = spec.out_name or spec.name
	record: dict[str, Any] = {
		"asset_id": out_stem,
		"source": spec.name,
		"output_path": f"ui/{OUT_DIR_NAME}/{out_stem}.png",
		"status": "pending",
		"error": None,
	}
	try:
		sym = _pick_symbol(by_name, spec.name)
		data = rel.slice_at(sym.address, sym.size)
		gx = gbi_to_gx(spec.fmt, spec.siz)
		image = decode_gbi_texture(data, spec.width, spec.height, spec.fmt, spec.siz, b"")
		if spec.prim is not None and spec.env is not None:
			image = _ia_prim_env(image, spec.prim, spec.env)
		elif spec.mask:
			intensity = image.convert("RGBA").split()[0]
			white = Image.new("L", image.size, 255)
			image = Image.merge("RGBA", (white, white, white, intensity))
		if save:
			png = image_png_bytes(image)
			for folder in (stage_dir, out_dir):
				(folder / f"{out_stem}.png").write_bytes(png)
			write_import_sidecar(out_dir / f"{out_stem}.png", project_root)
		else:
			record["_image"] = image
		record["status"] = "converted"
		record["meta"] = {"width": image.width, "height": image.height, "address": f"0x{sym.address:08X}"}
	except Exception as exc:  # noqa: BLE001
		record["status"] = "error"
		record["error"] = f"{type(exc).__name__}: {exc}"
	return record


def _fill_interior(image: Image.Image, fill: tuple[int, int, int, int]) -> None:
	"""Flood-fill from the canvas edges to find exterior transparent pixels, then paint
	every remaining (enclosed) transparent pixel with `fill` — a flat paper tone for the
	window's interior, since `des_win_area1-4_model`'s own PRIMITIVE color isn't set in
	`des_win.c` (inherited from the caller) and isn't worth chasing for a flat panel."""
	w, h = image.size
	px = image.load()
	exterior = bytearray(w * h)
	stack: list[tuple[int, int]] = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)]
	stack += [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
	while stack:
		x, y = stack.pop()
		if x < 0 or y < 0 or x >= w or y >= h or exterior[y * w + x]:
			continue
		if px[x, y][3] > 8:
			continue
		exterior[y * w + x] = 1
		stack.extend(((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)))
	for y in range(h):
		for x in range(w):
			if px[x, y][3] <= 8 and not exterior[y * w + x]:
				px[x, y] = fill


def _bake_border_shell(
	rel: RelData,
	by_name: dict[str, list[MapSymbol]],
	border_tiles: dict[str, Image.Image],
	stage_dir: Path,
	out_dir: Path,
	project_root: Path,
) -> dict[str, Any]:
	record: dict[str, Any] = {
		"asset_id": "window_shell",
		"source": "des_win_shitaT_model",
		"output_path": f"ui/{OUT_DIR_NAME}/window_shell.png",
		"status": "pending",
		"error": None,
	}
	try:
		colored = {k: _ia_prim_env(v, _BORDER_PRIM, _BORDER_ENV) for k, v in border_tiles.items()}
		vtx_sym = _pick_symbol(by_name, "des_win_v")
		verts = _parse_ui_vtx(rel.slice_at(vtx_sym.address, vtx_sym.size))

		groups = [verts[base : base + count] for base, count in _BORDER_GROUPS]
		all_used = [v for g in groups for v in g]
		xs = [float(v.x) for v in all_used]
		ys = [float(-v.y) for v in all_used]
		min_x, max_x = min(xs), max(xs)
		min_y, max_y = min(ys), max(ys)
		width = max(1, int(round((max_x - min_x) * _BAKE_SCALE)))
		height = max(1, int(round((max_y - min_y) * _BAKE_SCALE)))
		shell = Image.new("RGBA", (width, height), (0, 0, 0, 0))

		def to_px(v) -> tuple[float, float]:
			return ((v.x - min_x) * _BAKE_SCALE, (-v.y - min_y) * _BAKE_SCALE)

		for group_idx, tile, indices in _BORDER_BATCHES:
			verts_g = groups[group_idx]
			tex = colored[tile]
			for tri in range(0, len(indices), 3):
				i0, i1, i2 = indices[tri : tri + 3]
				v0, v1, v2 = verts_g[i0], verts_g[i1], verts_g[i2]
				_draw_textured_triangle(
					shell,
					tex,
					to_px(v0),
					to_px(v1),
					to_px(v2),
					(v0.s, v0.t),
					(v1.s, v1.t),
					(v2.s, v2.t),
					mode="mirror",
				)

		_fill_interior(shell, _INTERIOR_FILL)
		record["status"] = "converted"
		record["width"] = width
		record["height"] = height

		png = image_png_bytes(shell)
		for folder in (stage_dir, out_dir):
			(folder / "window_shell.png").write_bytes(png)
		write_import_sidecar(out_dir / "window_shell.png", project_root)
	except Exception as exc:  # noqa: BLE001
		record["status"] = "error"
		record["error"] = f"{type(exc).__name__}: {exc}"
	return record


## ---- Design book and album windows ------------------------------------------------
##
## `m_needlework_ovl.c` (`mNW_set_frame_dl`, `inv_original.c`) and `m_cporiginal_ovl.c`
## (`mCO_set_frame_main_dl` etc., `sav_win1.c`). Each window's display lists are walked
## with the GBI parser and rasterised in layers, so runtime content can go between:
##   *_mask   cloth coverage (TEXEL1 of the `tw` / `sav_win_w` CI4 shapes; TEXEL0 is the
##            scrolling cloth, exported separately and scrolled by
##            `inventory_shell_paper.gdshader`)
##   *_under  slot wells; *_over the frame drawn over the designs
##   *_raw    pieces whose PRIM/ENV change per album folder: intensity in R, alpha in A,
##            lerped at runtime by `design_mark.gdshader`.
_UI_SCALE = 3

## name -> (width, height, fmt, siz)
_UI_TEX: dict[str, tuple[int, int, int, int]] = {
	"inv_ori_tw1_tex_rgb_ci4": (64, 32, G_IM_FMT_CI, G_IM_SIZ_4b),
	"inv_ori_tw2_tex_rgb_ci4": (32, 32, G_IM_FMT_CI, G_IM_SIZ_4b),
	"inv_ori_tw3_tex_rgb_ci4": (32, 64, G_IM_FMT_CI, G_IM_SIZ_4b),
	"inv_ori_tw4_tex_rgb_ci4": (16, 16, G_IM_FMT_CI, G_IM_SIZ_4b),
	"inv_ori_w1_tex": (64, 32, G_IM_FMT_IA, G_IM_SIZ_8b),
	"inv_ori_w2_tex": (32, 32, G_IM_FMT_IA, G_IM_SIZ_8b),
	"inv_ori_w3_tex": (32, 64, G_IM_FMT_IA, G_IM_SIZ_8b),
	"inv_ori_w4_tex": (16, 16, G_IM_FMT_IA, G_IM_SIZ_8b),
	"inv_original_aw5_tex": (16, 16, G_IM_FMT_IA, G_IM_SIZ_8b),
	"sav_win_waku_tex": (32, 32, G_IM_FMT_I, G_IM_SIZ_4b),
	"inv_original_futa2_tex": (32, 32, G_IM_FMT_I, G_IM_SIZ_4b),
	"inv_original_cloth_tex_rgb_ci4": (32, 32, G_IM_FMT_CI, G_IM_SIZ_4b),
	"sav_win1_nuno_tex_rgb_ci4": (32, 32, G_IM_FMT_CI, G_IM_SIZ_4b),
	"sav_win_w1_tex_rgb_ci4": (64, 32, G_IM_FMT_CI, G_IM_SIZ_4b),
	"sav_win_w2_tex_rgb_ci4": (64, 32, G_IM_FMT_CI, G_IM_SIZ_4b),
	"sav_win_w3_tex_rgb_ci4": (64, 32, G_IM_FMT_CI, G_IM_SIZ_4b),
	"sav_win_w4_tex_rgb_ci4": (32, 64, G_IM_FMT_CI, G_IM_SIZ_4b),
	"sav_win_w5_tex_rgb_ci4": (32, 64, G_IM_FMT_CI, G_IM_SIZ_4b),
	"sav_win_w6_tex_rgb_ci4": (16, 16, G_IM_FMT_CI, G_IM_SIZ_4b),
	"sav_win_1_kage1_tex": (32, 32, G_IM_FMT_I, G_IM_SIZ_4b),
	"sav_win_1_kage2_tex": (32, 64, G_IM_FMT_I, G_IM_SIZ_4b),
	"sav_win1_aw1_tex": (64, 32, G_IM_FMT_IA, G_IM_SIZ_8b),
	"sav_win1_aw2_tex": (64, 32, G_IM_FMT_IA, G_IM_SIZ_8b),
	"sav_win1_aw3_tex": (64, 32, G_IM_FMT_IA, G_IM_SIZ_8b),
	"sav_win1_aw4_tex": (32, 64, G_IM_FMT_IA, G_IM_SIZ_8b),
	"sav_win1_aw5_tex": (32, 64, G_IM_FMT_IA, G_IM_SIZ_8b),
	"sav_win1_aw6_tex": (16, 16, G_IM_FMT_IA, G_IM_SIZ_8b),
	"ctl_win_waku1_tex": (64, 32, G_IM_FMT_IA, G_IM_SIZ_8b),
	"ctl_win_waku2_tex": (64, 32, G_IM_FMT_IA, G_IM_SIZ_8b),
	"ctl_win_tagu2_tex": (32, 16, G_IM_FMT_IA, G_IM_SIZ_8b),
	"ctl_win_tagu3_tex": (32, 16, G_IM_FMT_IA, G_IM_SIZ_8b),
}
_ORI_UE = ("lerp", (70, 40, 50, 255), (165, 145, 95, 255))  # `inv_original*_ueT_model`
_FUTA = ("prim", (60, 40, 30, 255))  # `inv_original_f_model` / `sav_win1_f_model`
_BOOK_COLOURS: dict[str, tuple] = {
	"inv_ori_w1_tex": _ORI_UE, "inv_ori_w2_tex": _ORI_UE, "inv_ori_w3_tex": _ORI_UE,
	"inv_ori_w4_tex": _ORI_UE, "inv_original_aw5_tex": _ORI_UE,
	"sav_win_waku_tex": ("prim", (165, 120, 70, 255)),  # `inv_original_waku_model`
	"inv_original_futa2_tex": _FUTA,
}
_ALBUM_COLOURS: dict[str, tuple] = {
	"sav_win_waku_tex": ("prim", (80, 50, 40, 255)),  # `sav_win1_waku_model`
	"inv_original_futa2_tex": _FUTA,
	"sav_win_1_kage1_tex": ("prim", (50, 50, 40, 205)),  # `sav_win1_kage_model`
	"sav_win_1_kage2_tex": ("prim", (50, 50, 40, 205)),
}


@dataclass(frozen=True)
class WindowSpec:
	vtx: str
	## left, top, width, height in window units (y up).
	bounds: tuple[float, float, float, float]
	layers: tuple[tuple[str, tuple[str, ...]], ...]
	colours: dict


_INV_ORI_W = tuple([f"inv_original_w{i}T_model" for i in range(1, 9)] + ["inv_original_w9_model"])
_INV_ORI2_W = tuple([f"inv_original2_w{i}T_model" for i in range(1, 9)] + ["inv_original2_w9_model"])
WINDOWS: list[WindowSpec] = [
	# The 8-slot book on its own (`mNW_set_frame_dl`).
	WindowSpec("inv_original_v", (-75.0, 90.0, 150.0, 180.0), (
		("book_mask", ("inv_original_w_model_before",) + _INV_ORI_W),
		("book_under", ("inv_original_ueT_model", "inv_original_waku_model")),
		("book_over", ("inv_original_f_model",)),
	), _BOOK_COLOURS),
	# The same book beside the album (`mNW_set_frame_dl_cpo`).
	WindowSpec("inv_original2_v", (-139.0, 81.0, 132.0, 158.0), (
		("book2_mask", ("inv_original_w_model_before",) + _INV_ORI2_W),
		("book2_under", ("inv_original2_ueT_model", "inv_original2_waku_model")),
		("book2_over", ("inv_original2_f_model",)),
	), _BOOK_COLOURS),
	# The album folder (`mCO_set_frame_main_dl` / `_ueT_dl` / `_tagS_dl`).
	WindowSpec("sav_win1_v", (-62.0, 86.0, 194.0, 163.0), (
		("album_mask", ("save_win1_w_before_model", "save_win1_w_all_model")),
		("album_under", ("sav_win1_waku_model",)),
		("album_over", ("sav_win1_f_model",)),
		("album_kage", ("sav_win1_kage_model",)),
		("album_rim_raw", ("sav_win1_ueT_model",)),
		("album_name_raw", ("sav_win1_nameT_model2",)),
	), _ALBUM_COLOURS),
]
## Loose textures: tabs (raw IA, per-folder PRIM/ENV) and the cloth fills.
_RAW_TEX = ("ctl_win_tagu2_tex", "ctl_win_tagu3_tex")
ALBUM_FOLDERS = 8


def _ui_texture(rel: RelData, by_name: dict[str, list[MapSymbol]], name: str, colours: dict,
		pal_name: str | None = None) -> Image.Image:
	w, h, fmt, siz = _UI_TEX[name]
	sym = _pick_symbol(by_name, name)
	pal = b""
	if fmt == G_IM_FMT_CI:
		pal_sym = _pick_symbol(by_name, pal_name or f"{name}_pal")
		pal = rel.slice_at(pal_sym.address, pal_sym.size)
	image = decode_gbi_texture(rel.slice_at(sym.address, sym.size), w, h, fmt, siz, pal).convert("RGBA")
	if re.match(r"(inv_ori_tw|sav_win_w)\d", name):
		# TEXEL1 only supplies coverage.
		white = Image.new("L", image.size, 255)
		return Image.merge("RGBA", (white, white, white, image.split()[3]))
	rule = colours.get(name)
	if rule is None:
		return image
	if rule[0] == "lerp":
		return _ia_prim_env(image, rule[1], rule[2])
	return _prim_i_alpha(image, rule[1])


def _prim_i_alpha(image: Image.Image, prim: tuple[int, int, int, int]) -> Image.Image:
	"""`PRIMITIVE` colour, alpha = TEXEL0 (x PRIM alpha) on an I texture (intensity in R)."""
	intensity = image.split()[0]
	if prim[3] < 255:
		intensity = intensity.point(lambda v, a=prim[3]: v * a // 255)
	solid = [Image.new("L", image.size, c) for c in prim[:3]]
	return Image.merge("RGBA", (*solid, intensity))


def _save_png(image: Image.Image, name: str, stage_dir: Path, out_dir: Path, project_root: Path) -> dict[str, Any]:
	png = image_png_bytes(image)
	for folder in (stage_dir, out_dir):
		(folder / f"{name}.png").write_bytes(png)
	write_import_sidecar(out_dir / f"{name}.png", project_root)
	return {"asset_id": name, "output_path": f"ui/{OUT_DIR_NAME}/{name}.png", "status": "converted", "error": None,
		"meta": {"width": image.width, "height": image.height}}


def _bake_window(cfg: PipelineConfig, rel: RelData, bank: TextureBank, by_name: dict[str, list[MapSymbol]],
		spec: WindowSpec, stage_dir: Path, out_dir: Path) -> list[dict[str, Any]]:
	vtx_sym = _pick_symbol(by_name, spec.vtx)
	verts = parse_vtx_blob(rel.slice_at(vtx_sym.address, vtx_sym.size), 1.0)
	textures: dict[str, Image.Image] = {}
	left, top, width, height = spec.bounds

	def to_px(v) -> tuple[float, float]:
		return ((v.x - left) * _UI_SCALE, (top - v.y) * _UI_SCALE)

	tex_state = TextureState()
	render = RenderState()
	records: list[dict[str, Any]] = []
	for layer, dls in spec.layers:
		try:
			image = Image.new("RGBA", (int(width * _UI_SCALE), int(height * _UI_SCALE)), (0, 0, 0, 0))
			raw = layer.endswith("_raw")
			for dl in dls:
				sym = _pick_symbol(by_name, dl)
				parts = parse_gfx(dl, rel.slice_at(sym.address, sym.size), verts, bank=bank, state=tex_state,
					vtx_base_addr=vtx_sym.address, render=render)
				for part in parts:
					if not part.triangles or part.texture_name not in _UI_TEX:
						continue
					key = part.texture_name + (":raw" if raw else "")
					if key not in textures:
						textures[key] = _ui_texture(rel, by_name, part.texture_name, {} if raw else spec.colours)
					tex = textures[key]
					for i0, i1, i2 in part.triangles:
						a, b, c = part.vertices[i0], part.vertices[i1], part.vertices[i2]
						_draw_textured_triangle(image, tex, to_px(a), to_px(b), to_px(c),
							(a.s, a.t), (b.s, b.t), (c.s, c.t), mode="mirror")
			rec = _save_png(image, layer, stage_dir, out_dir, cfg.project_root)
		except Exception as exc:  # noqa: BLE001
			rec = {"asset_id": layer, "status": "error", "error": f"{type(exc).__name__}: {exc}"}
		rec["source"] = ", ".join(dls)
		records.append(rec)
	return records


def _bake_design_book(
	cfg: PipelineConfig,
	rel: RelData,
	symbols: list[MapSymbol],
	by_name: dict[str, list[MapSymbol]],
	stage_dir: Path,
	out_dir: Path,
) -> list[dict[str, Any]]:
	try:
		bank = TextureBank(rel, symbols, cfg.extracted_archives)
	except Exception as exc:  # noqa: BLE001
		return [{"asset_id": "design_windows", "status": "error", "error": f"{type(exc).__name__}: {exc}"}]
	records: list[dict[str, Any]] = []
	for spec in WINDOWS:
		records.extend(_bake_window(cfg, rel, bank, by_name, spec, stage_dir, out_dir))
	loose: list[tuple[str, str, str | None]] = [("book_cloth", "inv_original_cloth_tex_rgb_ci4", None)]
	loose += [(f"album_cloth{i}", "sav_win1_nuno_tex_rgb_ci4", f"sav_win{i + 1}_nuno_tex_rgb_ci4_pal")
		for i in range(ALBUM_FOLDERS)]
	loose += [(name, name, None) for name in _RAW_TEX]
	for out_name, tex_name, pal_name in loose:
		try:
			image = _ui_texture(rel, by_name, tex_name, {}, pal_name)
			records.append(_save_png(image, out_name, stage_dir, out_dir, cfg.project_root))
		except Exception as exc:  # noqa: BLE001
			records.append({"asset_id": out_name, "status": "error", "error": f"{type(exc).__name__}: {exc}"})
	return records
