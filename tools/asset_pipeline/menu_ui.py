"""Menu chrome baked through the UI display-list walker (`ui_gbi.py`).

Each layer is the exact sequence of `gSPDisplayList` calls a `m_*_ovl.c` draw function
makes, with the PRIM / ENV / segment textures it sets around them, rasterised over the
whole 320x240 screen so the runtime can stack layers at the menu's own position. Parts
that change at runtime (key highlight, typed text, selected mode) are separate layers
or plain textures.

Layers use ACHD textures when `achd_enabled` is set, and bake at twice the resolution.

Output: `assets/generated/ui/menu/` (gitignored — Nintendo art, not for commit).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from PIL import Image

from .achd import load_achd_pack
from .config import PipelineConfig
from .godot_import import write_import_sidecar
from .mapfile import parse_map
from .rel import RelData
from .texbank import image_png_bytes
from .ui_gbi import Op, TextureCache, UiWalker, bake_layer

OUT_DIR_NAME = "menu"
SCREEN = (-160.0, 120.0, 320.0, 240.0)
_NATIVE_SCALE = 3
_HD_SCALE = 6


def _seg(tex: str) -> dict[int, str]:
	return {8: tex}


## `mED_KeyDraw` (`m_editor_ovl.c`): the GameCube-pad keyboard. The L shoulder shows
## Caps (blue) or small (red) in letter mode and nothing in sign / mark mode
## (`mED_KeyDraw_L_button`); the Y block lights the current input mode.
_KB_MODE = Op("kai_sousa_mode")
_KB_BLUE = (30, 30, 215, 255)
_KB_RED = (215, 30, 30, 255)
_KB_Y_ON = (225, 255, 255, 255)
_KB_Y_OFF = (155, 155, 160, 255)


def _kb_l(prim: tuple[int, int, int, int], moji: str | None) -> list[Op]:
	ops = [_KB_MODE, Op("kai_sousa_lwaku_model", prim=prim)]
	if moji:
		ops.append(Op("kai_sousa_lmoji_model", segments=_seg(moji)))
	ops.append(Op("kai_sousa_lbuttonT_model", segments=_seg("kai_sousa_lbutton_tex_rgb_ia8")))
	return ops


def _kb_y(mode: int) -> list[Op]:
	ops = [_KB_MODE, Op("kai_sousa_kirikae_model", segments=_seg("kai_sousa_ybutton_tex_rgb_ia8"))]
	for i, dl in enumerate(("kai_sousa_letter_model", "kai_sousa_sign_model", "kai_sousa_mark_model")):
		ops.append(Op(dl, prim=_KB_Y_ON if i == mode else _KB_Y_OFF))
	ops.append(Op("kai_sousa_ybuttonT_model", segments=_seg("kai_sousa_ybutton_tex_rgb_ia8")))
	return ops


_KB_BODY = [
	_KB_MODE,
	Op("kai_sousa_rbuttonT_model", segments=_seg("kai_sousa_rbutton_tex_rgb_ia8")),
	Op("kai_sousa_spaceT_model"),
	Op("kai_sousa_shitaT_model"),
	Op("kai_sousa_controllerT_model"),
	Op("kai_sousa_controller2T_model"),
	Op("kai_sousa_mojibanT_model"),
	Op("kai_sousa_abuttonT_model", segments=_seg("kai_sousa_button1a_tex_rgb_ia8")),
	Op("kai_sousa_bbuttonT_model", segments=_seg("kai_sousa_button2a_tex_rgb_ia8")),
	Op("kai_sousa_cancelT_model"),
	Op("kai_sousa_henkan_model", segments=_seg("kai_sousa_xbutton_tex_rgb_ia8")),
	Op("kai_sousa_xbuttonT_model", segments=_seg("kai_sousa_xbutton_tex_rgb_ia8")),
	Op("kai_sousa_startbuttonT_model"),
	Op("kai_sousa_endT_model"),
	Op("kai_sousa_controllpadT_model", segments=_seg("kai_sousa_controllpad1_tex_rgb_ia8")),
	Op("kai_sousa_cursorT_model"),
	Op("kai_sousa_3DT_model"),
	# `mED_KeyDraw_3D_stick`: the stick head sits at (-110, -50), neutral texture.
	Op("kai_sousa_3DstT_model", segments=_seg("kai_sousa_3Dst_tex_rgb_ia8"), offset=(-110.0, -50.0)),
]

## `mED_InkPotDraw` (board / notice / diary only): pot and label. The ink itself is a
## scrolled texture drawn at runtime.
_KB_INK = [Op("kai_sousa_ink_mode"), Op("kai_sousa_inktuboT_model"), Op("kai_sousa_inkmojiT_model")]

## `mLE_win_data` (`m_ledit_ovl.c`): one window per text-entry purpose.
LEDIT_WINDOWS = ("nam", "mra", "ephrase", "rst", "req", "dna", "shi")

LAYERS: dict[str, list[Op]] = {
	"kb_l_caps": _kb_l(_KB_BLUE, "kai_sousa_caps_tex_rgb_i4"),
	"kb_l_small": _kb_l(_KB_RED, "kai_sousa_small_tex_rgb_i4"),
	"kb_l_none": _kb_l(_KB_BLUE, None),
	"kb_body": _KB_BODY,
	"kb_y0": _kb_y(0),
	"kb_y1": _kb_y(1),
	"kb_y2": _kb_y(2),
	"kb_ink": _KB_INK,
	**{f"ledit_{w}": [Op("ledit_common_mode"), Op(f"{w}_win_mode"), Op(f"{w}_win_model")] for w in LEDIT_WINDOWS},
}

def extract_menu_ui(cfg: PipelineConfig) -> dict[str, Any]:
	out_dir = cfg.godot_generated / "ui" / OUT_DIR_NAME
	stage_dir = cfg.converted / "ui" / OUT_DIR_NAME
	out_dir.mkdir(parents=True, exist_ok=True)
	stage_dir.mkdir(parents=True, exist_ok=True)
	try:
		rel = RelData(cfg.rel_path)
		symbols = parse_map(cfg.map_path)
	except Exception as exc:  # noqa: BLE001
		return {"error": f"{type(exc).__name__}: {exc}"}
	achd = load_achd_pack(cfg.achd_root, cfg.achd_cache) if cfg.achd_enabled and cfg.achd_root else None
	scale = _HD_SCALE if achd is not None else _NATIVE_SCALE
	textures = TextureCache(rel, achd)
	results: list[dict[str, Any]] = []
	for name, ops in LAYERS.items():
		rec: dict[str, Any] = {"asset_id": name, "output_path": f"ui/{OUT_DIR_NAME}/{name}.png", "error": None}
		try:
			image = bake_layer(UiWalker(rel, symbols), textures, ops, SCREEN, scale)
			_save(image, name, stage_dir, out_dir, cfg.project_root)
			rec["status"] = "converted"
		except Exception as exc:  # noqa: BLE001
			rec["status"] = "error"
			rec["error"] = f"{type(exc).__name__}: {exc}"
		results.append(rec)

	# Masks the runtime tints with the caller's PRIM: the key cap (`testbutton`, I4, in
	# `mED_KeyDraw_keyboard`) and the space-key "SP" glyph (`lat_sousa_sp_tex`, N64
	# linear I4, `mED_StringsDraw_spaceCode`).
	from .texbank import G_IM_FMT_I, G_IM_SIZ_4b, GX_MIRROR
	from .ui_gbi import Tile

	walker = UiWalker(rel, symbols)
	for out_name, sym_name, linear in (("kb_key", "testbutton", False), ("kb_space", "lat_sousa_sp_tex", True)):
		rec = {"asset_id": out_name, "output_path": f"ui/{OUT_DIR_NAME}/{out_name}.png", "error": None}
		try:
			sym = walker.symbol(sym_name)
			arr = textures.get(Tile(sym.address, 16, 16, G_IM_FMT_I, G_IM_SIZ_4b, 0, GX_MIRROR, GX_MIRROR, linear))
			alpha = Image.fromarray((arr[..., 3] * 255 + 0.5).astype("uint8"), "L")
			white = Image.new("L", alpha.size, 255)
			_save(Image.merge("RGBA", (white, white, white, alpha)), out_name, stage_dir, out_dir, cfg.project_root)
			rec["status"] = "converted"
		except Exception as exc:  # noqa: BLE001
			rec["status"] = "error"
			rec["error"] = f"{type(exc).__name__}: {exc}"
		results.append(rec)

	catalog = {"scale": scale, "screen": SCREEN, "achd_hits": textures.hits, "results": results}
	data = json.dumps(catalog, indent=2).encode()
	for folder in (stage_dir, out_dir):
		(folder / "catalog.json").write_bytes(data)
	converted = sum(1 for r in results if r["status"] == "converted")
	return {"results": results, "converted": converted, "output": str(out_dir), "achd_hits": textures.hits}


def _save(image, name: str, stage_dir: Path, out_dir: Path, project_root: Path) -> None:
	png = image_png_bytes(image)
	for folder in (stage_dir, out_dir):
		(folder / f"{name}.png").write_bytes(png)
	write_import_sidecar(out_dir / f"{name}.png", project_root)
