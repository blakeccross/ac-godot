"""Design editor / design book / design album chrome (`m_design_ovl.c`, `m_needlework_ovl.c`,
`m_cporiginal_ovl.c`).

Two kinds of output:

- Plain textures the runtime draws piece by piece (`CHROME`): tool icons, digits,
  buttons, cursors and marks, with fixed `LERP(PRIM, ENV, TEXEL0, ENV)` colours baked
  in, or as white coverage masks the runtime tints with the draw's PRIM.
- Window layers rasterised from the models' own display lists by `ui_gbi` (the
  combiner, PRIM / ENV and all), split where runtime content goes between them.

Everything goes through the ACHD lookup first: a configured HD pack gives HD
textures (the runtime scales texel-space source rects by the texture's real size)
and window layers bake at twice the resolution.

Output is gitignored (Nintendo IP, not for commit).
"""

from __future__ import annotations

import io
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image

from .achd import load_achd_pack, maybe_hd_png
from .config import PipelineConfig
from .godot_import import write_import_sidecar
from .map_ui import _ia_prim_env, _pick_symbol
from .mapfile import MapSymbol, parse_map
from .rel import RelData
from .texbank import (
	G_IM_FMT_CI,
	G_IM_FMT_I,
	G_IM_FMT_IA,
	G_IM_SIZ_4b,
	G_IM_SIZ_8b,
	GX_MIRROR,
	GX_REPEAT,
	decode_gbi_texture,
	gbi_to_gx,
	image_png_bytes,
)
from .ui_gbi import Op, TextureCache, UiWalker, bake_layer

OUT_DIR_NAME = "design"
_NATIVE_SCALE = 3
_HD_SCALE = 6


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
	## CI textures: the TLUT symbol (default `<name>_pal`).
	pal: str | None = None


_TOOL_PRIM = (70, 80, 50, 255)  # `des_tool.c` icon PRIM/ENV
_TOOL_ENV = (235, 205, 145, 255)
_CURSOR_PRIM = (60, 70, 60, 255)  # `des_cursor.c`
_CURSOR_ENV = (235, 235, 225, 255)


def _i4(name: str, w: int = 16, h: int = 16) -> TexSpec:
	return TexSpec(name, w, h, G_IM_FMT_I, G_IM_SIZ_4b, mask=True)


def _ia8(name: str, prim, env, w: int = 32, h: int = 32) -> TexSpec:
	return TexSpec(name, w, h, G_IM_FMT_IA, G_IM_SIZ_8b, prim=prim, env=env)


## Plain pieces — sizes / formats from `des_win.c`, `des_tool.c`, `des_suuji.c`,
## `des_marking.c`, `des_cursor.c` and the album tabs.
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

ALBUM_FOLDERS = 8
CHROME += [
	# Album tabs: PRIM / ENV per folder, so raw IA (intensity in R) lerped at runtime.
	TexSpec("ctl_win_tagu2_tex", 32, 16, G_IM_FMT_IA, G_IM_SIZ_8b),
	TexSpec("ctl_win_tagu3_tex", 32, 16, G_IM_FMT_IA, G_IM_SIZ_8b),
	# Cloth fills, scrolled by `inventory_shell_paper.gdshader` under each window's mask.
	TexSpec("inv_original_cloth_tex_rgb_ci4", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, out_name="book_cloth"),
	*[TexSpec("sav_win1_nuno_tex_rgb_ci4", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, out_name=f"album_cloth{i}",
		pal=f"sav_win{i + 1}_nuno_tex_rgb_ci4_pal") for i in range(ALBUM_FOLDERS)],
]


# --- window layers ---------------------------------------------------------------

@dataclass(frozen=True)
class Layer:
	name: str
	ops: tuple[Op, ...]
	## Keep only the alpha as a white mask (cloth coverage; the cloth itself scrolls).
	mask: bool = False


@dataclass(frozen=True)
class Window:
	## left, top, width, height in screen units (y up).
	bounds: tuple[float, float, float, float]
	layers: tuple[Layer, ...]


def _ops(*names: str, **kw: Any) -> tuple[Op, ...]:
	return tuple(Op(n, **kw) for n in names)


_BOOK_W = ("inv_original_w_model_before",) + tuple(f"inv_original_w{i}T_model" for i in range(1, 9)) + (
	"inv_original_w9_model",)
_BOOK2_W = ("inv_original_w_model_before",) + tuple(f"inv_original2_w{i}T_model" for i in range(1, 9)) + (
	"inv_original2_w9_model",)

## `m_cporiginal_ovl.c` per-folder `sav_win1_ueT_model` (rim) and `sav_win1_nameT_model2`
## (name plate) colours; the plate's ENV is `env_table`.
_ALBUM_RIM_PRIM = [(0xA5, 0x87, 0x5A), (0x9B, 0x7D, 0x50), (0x91, 0x73, 0x46), (0x87, 0x69, 0x3C),
	(0x82, 0x64, 0x37), (0x78, 0x5A, 0x2D), (0x73, 0x55, 0x28), (0x6E, 0x50, 0x23)]
_ALBUM_RIM_ENV = [(0xEB, 0xD7, 0xAF), (0xE1, 0xCD, 0xA5), (0xD7, 0xC3, 0x9B), (0xCD, 0xB9, 0x91),
	(0xC3, 0xAF, 0x87), (0xB9, 0xA5, 0x7D), (0xAF, 0x9B, 0x73), (0xA5, 0x91, 0x69)]
_ALBUM_PLATE_PRIM = [(0x69, 0x50, 0x46), (0x3C, 0x32, 0x23), (0x4B, 0x37, 0x2D), (0x4B, 0x37, 0x2D),
	(0x41, 0x2D, 0x0F), (0x41, 0x37, 0x19), (0x41, 0x2D, 0x1E), (0x41, 0x37, 0x32)]
_ALBUM_ENV = [(0xFF, 0xF5, 0xA0), (0xFF, 0xD7, 0x96), (0xF5, 0xC3, 0x82), (0xE1, 0xAF, 0x6E),
	(0xCD, 0x9B, 0x5A), (0xB9, 0x87, 0x46), (0xA5, 0x73, 0x32), (0x9B, 0x5F, 0x28)]


def _rgba(c: tuple[int, int, int]) -> tuple[int, int, int, int]:
	return (c[0], c[1], c[2], 255)


WINDOWS: list[Window] = [
	# `mDE_set_frame_main_dl`: the editor's wooden board (`des_win_before_model`).
	Window((-180.0, 140.0, 360.0, 280.0), (Layer("window_shell", _ops("des_win_before_model")),)),
	# The 8-slot book on its own (`mNW_set_frame_dl`).
	Window((-75.0, 90.0, 150.0, 180.0), (
		Layer("book_mask", _ops(*_BOOK_W), mask=True),
		Layer("book_under", _ops("inv_original_ueT_model", "inv_original_waku_model")),
		Layer("book_over", _ops("inv_original_f_model")),
	)),
	# The same book beside the album (`mNW_set_frame_dl_cpo`).
	Window((-139.0, 81.0, 132.0, 158.0), (
		Layer("book2_mask", _ops(*_BOOK2_W), mask=True),
		Layer("book2_under", _ops("inv_original2_ueT_model", "inv_original2_waku_model")),
		Layer("book2_over", _ops("inv_original2_f_model")),
	)),
	# The album folder (`mCO_set_frame_main_dl` / `_ueT_dl` / `_tagS_dl`).
	Window((-62.0, 86.0, 194.0, 163.0), (
		Layer("album_mask", _ops("save_win1_w_before_model", "save_win1_w_all_model"), mask=True),
		Layer("album_under", _ops("sav_win1_waku_model")),
		Layer("album_over", _ops("sav_win1_f_model")),
		Layer("album_kage", _ops("sav_win1_kage_model")),
		*[Layer(f"album_rim{f}", (Op("sav_win1_ueT_model", prim=_rgba(_ALBUM_RIM_PRIM[f]),
			env=_rgba(_ALBUM_RIM_ENV[f])),)) for f in range(ALBUM_FOLDERS)],
		*[Layer(f"album_name{f}", (Op("sav_win1_nameT_model2", prim=_rgba(_ALBUM_PLATE_PRIM[f]),
			env=_rgba(_ALBUM_ENV[f])),)) for f in range(ALBUM_FOLDERS)],
	)),
]


def extract_design_ui(cfg: PipelineConfig) -> dict[str, Any]:
	stage_dir = cfg.converted / "ui" / OUT_DIR_NAME
	out_dir = cfg.godot_generated / "ui" / OUT_DIR_NAME
	stage_dir.mkdir(parents=True, exist_ok=True)
	out_dir.mkdir(parents=True, exist_ok=True)

	try:
		rel = RelData(cfg.rel_path)
		symbols = parse_map(cfg.map_path)
	except Exception as exc:  # noqa: BLE001
		return {"error": f"{type(exc).__name__}: {exc}"}
	achd = load_achd_pack(cfg.achd_root, cfg.achd_cache) if cfg.achd_enabled and cfg.achd_root else None
	scale = _HD_SCALE if achd is not None else _NATIVE_SCALE

	by_name: dict[str, list[MapSymbol]] = {}
	for sym in symbols:
		by_name.setdefault(sym.name, []).append(sym)

	results: list[dict[str, Any]] = []
	for spec in CHROME:
		results.append(_extract_plain(rel, by_name, spec, stage_dir, out_dir, cfg.project_root, achd))

	textures = TextureCache(rel, achd)
	for window in WINDOWS:
		for layer in window.layers:
			rec: dict[str, Any] = {"asset_id": layer.name, "output_path": f"ui/{OUT_DIR_NAME}/{layer.name}.png",
				"error": None}
			try:
				image = bake_layer(UiWalker(rel, symbols), textures, list(layer.ops), window.bounds, scale)
				if layer.mask:
					white = Image.new("L", image.size, 255)
					image = Image.merge("RGBA", (white, white, white, image.split()[3]))
				_save_png(image, layer.name, stage_dir, out_dir, cfg.project_root)
				rec["status"] = "converted"
				rec["meta"] = {"width": image.width, "height": image.height}
			except Exception as exc:  # noqa: BLE001
				rec["status"] = "error"
				rec["error"] = f"{type(exc).__name__}: {exc}"
			results.append(rec)

	converted = sum(1 for r in results if r.get("status") == "converted")
	achd_hits = textures.hits + sum(1 for r in results if (r.get("meta") or {}).get("achd"))
	catalog = {"scale": scale, "achd_hits": achd_hits, "results": results}
	catalog_bytes = json.dumps(catalog, indent=2).encode("utf-8")
	for folder in (stage_dir, out_dir):
		(folder / "catalog.json").write_bytes(catalog_bytes)
	shell = next((r for r in results if r["asset_id"] == "window_shell"), None)
	return {"results": results, "converted": converted, "output": str(out_dir), "window_shell": shell,
		"achd_hits": achd_hits}


def _extract_plain(
	rel: RelData,
	by_name: dict[str, list[MapSymbol]],
	spec: TexSpec,
	stage_dir: Path,
	out_dir: Path,
	project_root: Path,
	achd: Any = None,
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
		pal = b""
		if spec.fmt == G_IM_FMT_CI:
			pal_sym = _pick_symbol(by_name, spec.pal or f"{spec.name}_pal")
			pal = rel.slice_at(pal_sym.address, pal_sym.size)
		wrap = GX_REPEAT if spec.fmt == G_IM_FMT_CI else GX_MIRROR
		hd = maybe_hd_png(achd, data, spec.width, spec.height, gbi_to_gx(spec.fmt, spec.siz), pal or None,
			wrap_s=wrap, wrap_t=wrap)
		if hd is not None:
			image = Image.open(io.BytesIO(hd)).convert("RGBA")
		else:
			image = decode_gbi_texture(data, spec.width, spec.height, spec.fmt, spec.siz, pal).convert("RGBA")
		if spec.prim is not None and spec.env is not None:
			image = _ia_prim_env(image, spec.prim, spec.env)
		elif spec.mask:
			intensity = image.split()[0]
			white = Image.new("L", image.size, 255)
			image = Image.merge("RGBA", (white, white, white, intensity))
		_save_png(image, out_stem, stage_dir, out_dir, project_root)
		record["status"] = "converted"
		record["meta"] = {"width": image.width, "height": image.height, "native": [spec.width, spec.height],
			"achd": hd is not None, "address": f"0x{sym.address:08X}"}
	except Exception as exc:  # noqa: BLE001
		record["status"] = "error"
		record["error"] = f"{type(exc).__name__}: {exc}"
	return record


def _save_png(image: Image.Image, name: str, stage_dir: Path, out_dir: Path, project_root: Path) -> None:
	png = image_png_bytes(image)
	for folder in (stage_dir, out_dir):
		(folder / f"{name}.png").write_bytes(png)
	write_import_sidecar(out_dir / f"{name}.png", project_root)
