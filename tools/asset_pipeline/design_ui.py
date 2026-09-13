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
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image

from .config import PipelineConfig
from .godot_import import write_import_sidecar
from .map_ui import _draw_textured_triangle, _ia_prim_env, _mirror_tile, _parse_ui_vtx, _pick_symbol
from .mapfile import MapSymbol, parse_map
from .rel import RelData
from .texbank import G_IM_FMT_I, G_IM_FMT_IA, G_IM_SIZ_4b, G_IM_SIZ_8b, decode_gbi_texture, gbi_to_gx, image_png_bytes

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


## Plain chrome pieces — decoded as-is, no geometry baking. Sizes/formats transcribed
## from `des_win.c`'s `gsDPSetTextureImage_Dolphin` calls and `des_marking.c`.
CHROME: list[TexSpec] = [
	TexSpec("des_win_sen_tex", 16, 16, G_IM_FMT_I, G_IM_SIZ_4b),
	TexSpec("des_win_kirikae_tex", 32, 32, G_IM_FMT_IA, G_IM_SIZ_8b),
	TexSpec("des_win_cwaku_tex", 16, 16, G_IM_FMT_I, G_IM_SIZ_4b),
	TexSpec("des_win_color_tex", 16, 16, G_IM_FMT_I, G_IM_SIZ_4b),
	TexSpec("des_win_start_tex", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b),
	TexSpec("des_win_marking_tex", 16, 16, G_IM_FMT_I, G_IM_SIZ_4b),
	TexSpec("des_win_marking3_tex", 16, 16, G_IM_FMT_IA, G_IM_SIZ_8b),
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
