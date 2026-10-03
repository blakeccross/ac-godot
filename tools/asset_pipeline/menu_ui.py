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
from .texbank import G_IM_FMT_CI, G_IM_FMT_I as _I, G_IM_SIZ_4b, GX_REPEAT as _REPEAT
from .texbank import G_IM_FMT_IA as _IA, G_IM_SIZ_8b as _8B, GX_MIRROR as _MIRROR
from .ui_gbi import Op, TexRef, TextureCache, UiWalker, bake_layer, rasterize

OUT_DIR_NAME = "menu"
SCREEN = (-160.0, 120.0, 320.0, 240.0)
_NATIVE_SCALE = 3
## Stationery models span x -124..124, y -86..100 (screen units, centred).
PAPER_BOUNDS = (-124.0, 100.0, 248.0, 186.0)
PAPER_COUNT = 64
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
	# `m_editEndChk_ovl.c`: the "Is this OK?" plate (its text plate pulses blue at
	# runtime) and the 2- and 3-answer windows with their selection mark, all baked at
	# the origin; the runtime offsets them by `win_data`.
	"ee_q": [Op("lat_kakunin_DL_mode"), Op("lat_kakunin_wakuT_model")],
	"ee_q_c": [Op("lat_kakunin_DL_mode"), Op("lat_kakunin_c_model", prim=(0, 0, 255, 255))],
	"ee_a2": [Op("lat_kakunin_DL_mode"), Op("lat_sentaku2_winT_model")],
	"ee_a2_c": [Op("lat_kakunin_DL_mode"), Op("lat_sentaku2_c_model")],
	"ee_a3": [Op("lat_kakunin_DL_mode"), Op("lat_sentaku_winT_model")],
	"ee_a3_c": [Op("lat_kakunin_DL_mode"), Op("lat_sentaku_c_model")],
	# `mAD_set_first_tag`: the "Choose an addressee." window, at the origin.
	"adr_mes": [Op("lat_mes_winT_model")],
	# `mHB_set_frame_dl`: the house gyroid's message board.
	"hboard": [Op("hni_den_model")],
	# `mED_endCode_draw`: the end-of-text mark after the last character, at the origin.
	"kb_end": [Op("lat_end_cordT_model")],
	**{f"ledit_{w}": [Op("ledit_common_mode"), Op(f"{w}_win_mode"), Op(f"{w}_win_model")] for w in LEDIT_WINDOWS},
	# `m_bank_ovl.c`: the post office ABD and its Deposit / Withdrawal captions, lit (the
	# direction cash is moving, or no change) or dimmed (`mBN_set_frame_dl`).
	"bk_win": [Op("tyo_win_mode"), Op("tyo_win_model")],
	"bk_dep_on": [Op("tyo_win_mode"), Op("tyo_win_model", draw=False),
		Op("tyo_win_moji2T_model", prim=(165, 50, 50, 255), env=(255, 255, 255, 255))],
	"bk_dep_off": [Op("tyo_win_mode"), Op("tyo_win_model", draw=False),
		Op("tyo_win_moji2T_model", prim=(100, 80, 80, 255), env=(165, 155, 155, 255))],
	"bk_wd_on": [Op("tyo_win_mode"), Op("tyo_win_model", draw=False), Op("tyo_win_moji2T_model", draw=False),
		Op("tyo_win_moji3T_model", prim=(20, 205, 20, 255), env=(255, 255, 255, 255))],
	"bk_wd_off": [Op("tyo_win_mode"), Op("tyo_win_model", draw=False), Op("tyo_win_moji2T_model", draw=False),
		Op("tyo_win_moji3T_model", prim=(70, 95, 70, 255), env=(155, 165, 155, 255))],
	# `m_notice_ovl.c`: the community board's page (`kei_win`), key hints (`kei_hyouji`),
	# page arrows and the C-stick in each of its six poses (`kei_win_st_tex_tbl`).
	"nt_win": [Op("kei_win_model")],
	"nt_keys": [Op("kei_hyouji_model")],
	"nt_next": [Op("kei_hyouji_model", draw=False), Op("kei_win_yaji1T_mode"), Op("kei_win_yaji1T_model")],
	"nt_prev": [Op("kei_hyouji_model", draw=False), Op("kei_win_yaji1T_mode"), Op("kei_win_yaji2T_model")],
	**{f"nt_st{n}": [Op("kei_hyouji_model", draw=False), Op("kei_win_stT_model", segments={8: f"kei_win_st{n}_tex_rgb_ia8"})]
		for n in range(1, 7)},
	# `mDI_set_frame_dl` (`m_diary_ovl.c`): the diary is three sheets stacked down the page
	# (the runtime draws the second 194 and the third 358 units lower), the month tab
	# (`dia_win_tukiT_model` over the month's 64×16 IA8 word) and the month caption, all at the
	# origin.
	# `mBR_set_dl` (`m_birthday_ovl.c`): the window, and the month (`brt_win_month_model` on the
	# month's I4 word, segment 8) in red when picked, blue otherwise.
	"br_win": [Op("birthday_win_mode"), Op("birthday_win_model")],
	**{f"br_m{i + 1}_{state}": [Op("birthday_win_mode"), Op("birthday_win_model", draw=False),
		Op("brt_win_month_model", prim=prim, segments={8: f"tim_win_{m}_tex_rgb_i4"})]
		for i, m in enumerate(("january", "february", "march", "april", "may", "june", "july", "august",
			"september", "october", "november", "december"))
		for state, prim in (("on", (195, 0, 0, 255)), ("off", (70, 145, 225, 255)))},
	"dia_w1": [Op("dia_init_mode_letter"), Op("dia_win_wT_model"), Op("dia_win_fusenT_model")],
	"dia_w2": [Op("dia_init_mode_letter"), Op("dia_win2_wT_model"), Op("dia_win2_fusenT_model")],
	"dia_w3": [Op("dia_init_mode_letter"), Op("dia_win3_wT_model"), Op("dia_win3_fusenT_model")],
	"dia_moji": [Op("dia_init_mode_letter"), Op("dia_win_moji_model")],
	**{f"dia_m{i + 1}": [Op("dia_init_mode_letter"), Op("dia_win_tukiT_model", tiles={0: TexRef(
		f"dia_win_{m}_tex_rgb_ia8", 64, 16, _IA, _8B, wrap_s=_MIRROR, wrap_t=_MIRROR)})]
		for i, m in enumerate(("january", "february", "march", "april", "may", "june", "july", "august",
			"september", "october", "november", "december"))},
}

## `mCD_set_base_dl` / `mCD_set_hyoji_dl` / `mCD_set_hyoji2_dl` (`m_calendar_ovl.c`): the
## calendar page with its month's backdrop (one CI4 pattern for January, another for the rest,
## each month its own palette), the year's digits (four places, `cal_win_nen_table` from the
## ones up), the month word, the day boxes in each day type's colours, the day numbers (white,
## tinted at runtime), the played / Tortimer marks, the cursor, the event plate and the key
## hints. Day cells sit at the first slot; the runtime moves them 32 across and 20 down.
## (`gDPLoadTextureBlock_8b_Dolphin` here passes height before width: the month words are
## 128×32 and the event plate 64×32.)
CAL_MONTHS = ("january", "february", "march", "april", "may", "june", "july", "august",
	"september", "october", "november", "december")
CAL_BOX_PRIM = ((120, 120, 95), (225, 195, 100), (245, 205, 165), (255, 245, 185), (185, 215, 185))
CAL_BOX_ENV = ((0x46, 0x46, 0x28), (0x69, 0x3C, 0x32), (0x69, 0x41, 0x41), (0x7D, 0x55, 0x55), (0x4B, 0x32, 0x3C))
CAL_MARK_PRIM = ((0x5F, 0x3C, 0x3C), (0xB9, 0x32, 0x32))
## `mCD_set_base_dl`'s order: later models reuse vertices and state the earlier ones leave.
_CAL_ORDER = ("needlework_before_model", "cal_win_tuki_model", "cal_win_shita_model", "cal_win_futi_model",
	"cal_win_nitiyouT_model", "cal_win_doyouT_model", "cal_win_hijituT_model", "cal_win_eventT_model",
	"cal_win_nen_before", "cal_win_nen4_model", "cal_win_nen3_model", "cal_win_nen2_model", "cal_win_nen1_model",
	"cal_win_monthT_model", "cal_win_boxT_model", "cal_win_suuji_model", "cal_icon_mark_model",
	"cal_icon_cursor_model", "cal_icon_sakana_model", "cal_icon_yajirushi_model")


def _cal_pre(model: str) -> list[Op]:
	"""Everything `mCD_set_base_dl` runs before `model`, for its state only."""
	return [Op(dl, draw=False) for dl in _CAL_ORDER[: _CAL_ORDER.index(model)]]


def _cal_tex(symbol: str, w: int, h: int, fmt: int, siz: int) -> dict[int, TexRef]:
	return {0: TexRef(symbol, w, h, fmt, siz, wrap_s=_MIRROR, wrap_t=_MIRROR)}


def _cal_layers() -> dict[str, list[Op]]:
	out: dict[str, list[Op]] = {}
	for i in range(12):
		back = TexRef("cal_win_tuki1_tex" if i == 0 else "cal_win_tuki2_tex", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b,
			f"cal_win_tuki{i + 1}_pal", _REPEAT, _REPEAT)
		out[f"cal_base_m{i + 1}"] = [Op("needlework_before_model"), Op("cal_win_tuki_model", tiles={0: back}),
			Op("cal_win_shita_model"), Op("cal_win_futi_model"), Op("cal_win_nitiyouT_model"),
			Op("cal_win_doyouT_model"), Op("cal_win_hijituT_model")]
		out[f"cal_month_m{i + 1}"] = [*_cal_pre("cal_win_monthT_model"), Op("cal_win_monthT_model",
			tiles=_cal_tex(f"cal_win_{CAL_MONTHS[i]}_tex_rgb_ia8", 128, 32, _IA, _8B))]
	for t, (prim, env) in enumerate(zip(CAL_BOX_PRIM, CAL_BOX_ENV)):
		out[f"cal_event_t{t}"] = [*_cal_pre("cal_win_eventT_model"), Op("cal_win_eventT_model", prim=(*prim, 255),
			env=(*env, 255), tiles=_cal_tex("cal_win_event_tex", 64, 32, _IA, _8B))]
		for name, tex in (("box", "cal_win_box_tex_rgb_ia8"), ("box2", "cal_win_box2_tex_rgb_ia8")):
			out[f"cal_{name}_t{t}"] = [*_cal_pre("cal_win_boxT_model"), Op("cal_win_boxT_model", prim=(*prim, 255),
				env=(*env, 255), tiles=_cal_tex(tex, 32, 32, _IA, _8B))]
	for place, model in enumerate(("cal_win_nen4_model", "cal_win_nen3_model", "cal_win_nen2_model", "cal_win_nen1_model")):
		for digit in range(10):
			out[f"cal_nen_p{place}_d{digit}"] = [*_cal_pre(model),
				Op(model, tiles=_cal_tex(f"cal_win_nen{digit}_tex_rgb_i4", 16, 16, _I, G_IM_SIZ_4b))]
	for day in range(1, 32):
		out[f"cal_num{day}"] = [*_cal_pre("cal_win_suuji_model"), Op("cal_win_suuji_model", prim=(255, 255, 255, 255),
			tiles=_cal_tex(f"cal_win_suuji{day}_tex_rgb_i4", 16, 16, _I, G_IM_SIZ_4b))]
	for k, prim in enumerate(CAL_MARK_PRIM):
		out[f"cal_mark{k + 1}"] = [*_cal_pre("cal_icon_mark_model"), Op("cal_icon_mark_model", prim=(*prim, 255))]
	out["cal_cursor"] = [*_cal_pre("cal_icon_cursor_model"), Op("cal_icon_cursor_model")]
	out["cal_sakana"] = [*_cal_pre("cal_icon_sakana_model"), Op("cal_icon_sakana_model")]
	for name, gfx in (("cal_yaji_a", "cal_icon_yajirushi_gfx"), ("cal_yaji_b", "cal_icon_yajirushi_gfx2")):
		out[name] = [*_cal_pre("cal_icon_yajirushi_model"),
			Op("cal_icon_yajirushi_model", prim=(0, 0, 255, 255)), Op(gfx)]
	out["cal_hy"] = [Op("cal_hyouji_3DT_model"), Op("cal_hyouji_shitaT_model"), Op("cal_hyouji_b2_model"),
		Op("cal_hyouji_amojiT_model")]
	_hy = [Op(dl, draw=False) for dl in ("cal_hyouji_3DT_model", "cal_hyouji_shitaT_model", "cal_hyouji_b2_model",
		"cal_hyouji_amojiT_model")]
	out["cal_hy_y"] = [*_hy, Op("cal_hyoji_yaji1T_model")]
	out["cal_hy_ya"] = [*_hy, Op("cal_hyoji_yaji1T_model", draw=False), Op("cal_hyoji_yajiA_gfx")]
	out["cal_hy_yb"] = [*_hy, Op("cal_hyoji_yaji1T_model", draw=False), Op("cal_hyoji_yajiB_gfx")]
	for n in (1, 5):
		out[f"cal_hy_st{n}"] = [*_hy, Op("cal_hyoji_yaji1T_model", draw=False), Op("cal_hyouji_stT_model",
			tiles=_cal_tex(f"cal_hyouji_st{n}_tex_rgb_ia8", 64, 64, _IA, _8B))]
	out["cal_hy2"] = [Op("cal_hyouji2_shitaT_model"), Op("cal_hyouji2_bt_model"), Op("cal_hyouji2_b2_model"),
		Op("cal_hyouji2_bmojiT_model"), Op("cal_hyouji2_amojiT_model")]
	return out


LAYERS.update(_cal_layers())

ADDRESS_MAX_ENTRIES = 8


def _address_card_ops(rel: RelData, symbols, count: int, part: str) -> list[Op]:
	"""`mAD_address_draw_init` for one page's vertices (page 0's; all three match)."""
	import struct

	sym = UiWalker(rel, symbols).symbol("lat_atena_v")
	blob = rel.slice_at(sym.address, 16 * 16)

	def y_of(i: int) -> int:
		return struct.unpack_from(">h", blob, 16 * i + 2)[0]

	ofs = int((count - 1) * (90.0 / (ADDRESS_MAX_ENTRIES - 1)))
	ys: dict[int, int] = {}
	ys[12] = y_of(9) - ofs
	ys[13] = y_of(11) - ofs
	ys[14] = ys[12] - 17
	ys[15] = ys[13] - 17
	ys[0] = y_of(4) - ofs
	ys[2] = y_of(5) - ofs
	ys[1] = ys[0] - 17
	ys[3] = ys[2] - 17
	vtx_y = {("lat_atena_v", i): y for i, y in ys.items()}
	segs = {8: ("lat_atena_v", 8 * 16), 9: ("lat_atena_v", 0)}
	shadow = Op("lat_atena_model", segments=segs, vtx_y=vtx_y)
	if part == "shadow":
		return [shadow]
	# The card samples the texture the shadow list loads: walk it for state only.
	return [
		Op("lat_atena_model", segments=segs, vtx_y=vtx_y, draw=False),
		Op("lat_atena_winT_model", prim=(255, 255, 255, 255), segments=segs, vtx_y=vtx_y),
	]


## `m_catalog_ovl.c`. Page units are screen units about the menu position (y up). The
## page is laid out so its left edge (-143) is where the paper pattern's s = 0 falls
## (`clg_win_waku1T_model`), which lets the runtime scroll the pattern in texels.
CATALOG_DIR = "catalog"
CATALOG_PAGE = (-143.0, 97.0, 280.0, 201.0)
CATALOG_MARK = (-8.0, 8.0, 16.0, 16.0)
## `mCL_win_data`: per page, the paper pattern and the tab models (`sel_gfx0/1`).
CATALOG_PAGES = (
	("ha", "ha", "haniwa"),
	("kabe", "kabe", "kabe"),
	("jyuutan", "jyuutan", "jyuutan"),
	("fuku", "fuku", "fuku"),
	("kasa", "kasa", "kasa"),
	("tegami", "tegami", "tegami"),
	("hani", "haniwa", "haniwa"),
	("hone", "hone", "hone"),
	("onpu", "onpu", "onpu"),
)


def _clg_pattern(tex: str) -> TexRef:
	return TexRef(f"clg_win_{tex}_tex_rgb_ci4", 32, 32, G_IM_FMT_CI, G_IM_SIZ_4b, f"clg_win_{tex}_tex_rgb_ci4_pal")


## `clg_mwin1_model` opens with 13 `clg_win_wakuNT_model` pieces: colour = the page's
## paper pattern (tile 0, `gDPLoadTLUT_Dolphin(14, win_pal)`), alpha = the frame mask.
_CLG_FILL_BATCHES = 13
_CLG_MWIN = [Op("clg_mwin_mode", tiles={0: _clg_pattern("ha")}), Op("clg_mwin1_model")]
_CLG_NAME_STATE = [*_CLG_MWIN[:1], Op("clg_mwin1_model", draw=False), Op("clg_name_mode")]


def _catalog_layers() -> dict[str, tuple[list[Op], tuple[float, float, float, float], slice | None]]:
	"""name -> (ops, bounds, batch slice) for `mCL_set_page_dl` / `mCL_set_wchange_dl`."""
	out: dict[str, tuple[list[Op], tuple[float, float, float, float], slice | None]] = {
		"clg_fill": (_CLG_MWIN, CATALOG_PAGE, slice(0, _CLG_FILL_BATCHES)),
		"clg_frame": (_CLG_MWIN, CATALOG_PAGE, slice(_CLG_FILL_BATCHES, None)),
		"clg_info": ([*_CLG_NAME_STATE, Op("clg_mwin2_model"), Op("clg_win_cbT_model")], CATALOG_PAGE, None),
		"clg_bell": ([*_CLG_NAME_STATE, Op("clg_win_beruT_model")], CATALOG_PAGE, None),
		# PRIM (0, 50, 255, alpha) x texel: white here, the runtime tints and pulses it.
		"clg_arrow": ([*_CLG_NAME_STATE, Op("clg_win_shirushi1T_model", prim=(255, 255, 255, 255))], CATALOG_MARK,
			None),
		"clg_star": ([Op("mCL_lat_letter_mode"), Op("clg_win_hoshiT_model")], CATALOG_MARK, None),
		"clg_music": ([Op("mCL_lat_letter_mode"), Op("mCL_music_model")], (-40.0, 40.0, 80.0, 80.0), None),
	}
	# Name rows (`clg_win_na1T_model`..`na7T`): the selected one red, the rest navy.
	for row in range(7):
		for on in (True, False):
			prim = (205, 0, 0, 255) if on else (10, 10, 50, 255)
			out[f"clg_slot{row}_{'on' if on else 'off'}"] = (
				[*_CLG_NAME_STATE, Op(f"clg_win_na{row + 1}T_model", prim=prim)], CATALOG_PAGE, None)
	for i, (_pat, tab, _pic) in enumerate(CATALOG_PAGES):
		for on in (True, False):
			win_prim, win_env, pic_prim = (((0, 20, 110, 255), (50, 50, 255, 255), (255, 255, 255, 255)) if on
				else ((0, 0, 0, 255), (50, 50, 125, 255), (145, 145, 205, 255)))
			ops = [Op("clg_mwin_mode"), Op("clg_tag_win_mode", prim=win_prim, env=win_env),
				Op(f"clg_win_{tab}T_model"), Op("clg_tag_picture_mode", prim=pic_prim), Op(f"clg_win_{tab}2T_model")]
			out[f"clg_tab{i}_{'on' if on else 'off'}"] = (ops, CATALOG_PAGE, None)
	return out


## `mCL_wall_draw` / `mCL_carpet_draw`: the room sample's model and which segment each
## surface samples (wallpaper pages on 8 / 9, carpet pages on 8–B; the palettes ride
## segment A / D). Placeholder symbols stand in for the pages so batches can be told apart.
_CLG_ROOM_PAGES = [f"kan_win_suuji{n}_tex_rgb_ia8" for n in range(1, 5)]


def _catalog_room_meshes(rel: RelData, symbols) -> dict[str, list]:
	"""Each room sample as triangles: [page, [x, y, u, v, r, g, b, a] x 3], at the origin."""
	probe = UiWalker(rel, symbols)
	page_of = {probe.symbol(n).address: i for i, n in enumerate(_CLG_ROOM_PAGES)}
	out: dict[str, list] = {}
	for kind, model, pal_seg in (("wall", "mCL_rom_myhome1_wall_model", 0xA), ("floor", "mCL_rom_myhome1_floor_model", 0xD)):
		segs: dict[int, str] = {8 + i: n for i, n in enumerate(_CLG_ROOM_PAGES)}
		if kind == "wall":
			segs[pal_seg] = "kan_win_suuji5_tex_rgb_ia8"
		else:
			segs[pal_seg] = "kan_win_suuji5_tex_rgb_ia8"
		tris: list = []
		for batch in UiWalker(rel, symbols).run([Op("mCL_lat_letter_mode"), Op(model, segments=segs)]):
			tile = batch.tex0
			if tile is None or tile.addr not in page_of:
				continue
			for tri in batch.tris:
				tris.append([page_of[tile.addr], [[v.x, v.y, v.s / tile.width, v.t / tile.height, *v.rgba] for v in tri]])
		out[kind] = tris
	return out


def _bake_catalog(rel: RelData, symbols, textures: TextureCache, scale: int, cfg: PipelineConfig) -> list[dict[str, Any]]:
	out_dir = cfg.godot_generated / "ui" / CATALOG_DIR
	stage_dir = cfg.converted / "ui" / CATALOG_DIR
	out_dir.mkdir(parents=True, exist_ok=True)
	stage_dir.mkdir(parents=True, exist_ok=True)
	results: list[dict[str, Any]] = []
	for name, (ops, bounds, part) in _catalog_layers().items():
		rec: dict[str, Any] = {"asset_id": name, "output_path": f"ui/{CATALOG_DIR}/{name}.png", "error": None}
		try:
			batches = UiWalker(rel, symbols).run(ops)
			if part is not None:
				batches = batches[part]
			image = rasterize(batches, textures, bounds, scale)
			_save(image, name, stage_dir, out_dir, cfg.project_root)
			rec["status"] = "converted"
		except Exception as exc:  # noqa: BLE001
			rec["status"] = "error"
			rec["error"] = f"{type(exc).__name__}: {exc}"
		results.append(rec)
	# The paper patterns on their own (32x32 CI4, ACHD-sized when the pack has them) for
	# the runtime's scrolling fill.
	walker = UiWalker(rel, symbols)
	for i, (pat, _tab, _pic) in enumerate(CATALOG_PAGES):
		name = f"clg_pattern{i}"
		rec = {"asset_id": name, "output_path": f"ui/{CATALOG_DIR}/{name}.png", "error": None}
		try:
			ref = _clg_pattern(pat)
			from .ui_gbi import Tile
			tile = Tile(walker.symbol(ref.symbol).address, 32, 32, ref.fmt, ref.siz, walker.symbol(ref.tlut).address,
				ref.wrap_s, ref.wrap_t)
			arr = textures.get(tile)
			image = Image.fromarray((arr * 255 + 0.5).clip(0, 255).astype("uint8"), "RGBA")
			_save(image, name, stage_dir, out_dir, cfg.project_root)
			rec["status"] = "converted"
		except Exception as exc:  # noqa: BLE001
			rec["status"] = "error"
			rec["error"] = f"{type(exc).__name__}: {exc}"
		results.append(rec)
	meta = {"scale": scale, "page": CATALOG_PAGE, "mark": CATALOG_MARK, "music": (-40.0, 40.0, 80.0, 80.0),
		"room": _catalog_room_meshes(rel, symbols)}
	data = json.dumps(meta, indent=2).encode()
	for folder in (stage_dir, out_dir):
		(folder / "catalog.json").write_bytes(data)
	return results


MSCORE_DIR = "mscore"
MSCORE_NOTE = (-12.0, 22.0, 24.0, 44.0)
MSCORE_MARK = (-8.0, 8.0, 16.0, 16.0)
MSCORE_SEN = (-70.0, 60.0, 140.0, 120.0)
## `onp_win_*`: the X / Y / START / R caps on segments 8-11, released.
_MS_BUTTONS = {8: "onp__x_tex_rgb_ia8", 9: "onp__y_tex_rgb_ia8", 10: "start_tex_rgb_ia8", 11: "onp_win_rbutton_tex_rgb_ia8"}
## `note_frame`: model and the idle / playing texture on segment 8.
_MS_FRAMES = [
	("onp_hyouji_waku1T_model", ("onp_win_test1_tex_rgb_ia8", "onp_win_test2_tex_rgb_ia8")),
	("onp_hyouji_waku2T_model", ("onp_win_test2_tex_rgb_ia8", "onp_win_test3_tex_rgb_ia8")),
	("onp_hyouji_waku3T_model", ("onp_win_test5_tex_rgb_ia8", "onp_win_shimari_tex_rgb_ia8")),
	("onp_hyouji_waku4T_model", ("onp_win_test10_tex_rgb_ia8", "onp_win_test11_tex_rgb_ia8")),
]
## `note_moji`: frame, letter, PRIM, ENV for notes 0-15 (G low … E, random, rest, off).
_MS_NORMAL, _MS_REST, _MS_OFF, _MS_RANDOM = 0, 1, 2, 3
MSCORE_NOTES: list[tuple[int, str, tuple[int, int, int], tuple[int, int, int]]] = [
	(_MS_NORMAL, "g", (0, 10, 0), (70, 155, 255)), (_MS_NORMAL, "a", (0, 10, 0), (0, 200, 205)),
	(_MS_NORMAL, "b", (0, 20, 0), (0, 225, 150)), (_MS_NORMAL, "c", (0, 40, 0), (20, 235, 0)),
	(_MS_NORMAL, "d", (0, 40, 0), (90, 245, 0)), (_MS_NORMAL, "e", (0, 40, 0), (130, 255, 0)),
	(_MS_NORMAL, "f", (0, 50, 0), (155, 255, 0)), (_MS_NORMAL, "g", (0, 50, 0), (175, 255, 0)),
	(_MS_NORMAL, "a", (0, 60, 0), (195, 255, 0)), (_MS_NORMAL, "b", (0, 60, 0), (225, 255, 0)),
	(_MS_NORMAL, "c", (0, 60, 0), (255, 235, 0)), (_MS_NORMAL, "d", (0, 60, 0), (255, 215, 0)),
	(_MS_NORMAL, "e", (0, 70, 0), (255, 175, 0)), (_MS_RANDOM, "q", (70, 60, 30), (255, 110, 110)),
	(_MS_REST, "z", (10, 10, 0), (165, 100, 255)), (_MS_OFF, "onpu8", (60, 0, 60), (255, 50, 255)),
]


def _mscore_layers() -> dict[str, tuple[list[Op], tuple[float, float, float, float]]]:
	"""`mMS_set_dl` pieces: the window in place, the rest at the origin for the runtime."""
	win = ["onp_win_model", "onp_win_mojiT_model", "onp_win_zT_model", "onp_win_rT_model", "onp_win_sT_model",
		"onp_win_rmoji_model"]
	layers: dict[str, tuple[list[Op], tuple[float, float, float, float]]] = {
		"ms_win": ([Op(m, segments=dict(_MS_BUTTONS)) for m in win], SCREEN),
		## END, after the window lists so their state carries over (the text is PRIM).
		"ms_owari_on": ([*(Op(m, segments=dict(_MS_BUTTONS), draw=False) for m in win),
			Op("onp_win_owariT_model", prim=(255, 0, 0, 255))], SCREEN),
		"ms_owari_off": ([*(Op(m, segments=dict(_MS_BUTTONS), draw=False) for m in win),
			Op("onp_win_owariT_model", prim=(0, 0, 255, 255))], SCREEN),
		## The stick takes the PRIM left by END (blue while the cursor is on a step); baked white.
		"ms_bou": ([Op("onp_hyouji_moji_mode"), Op("onp_hyouji_bouT_model", prim=(255, 255, 255, 255))], MSCORE_MARK),
		"ms_sen": ([Op("sen_item2_DL_mode"), Op("sen_win_wakuT_model", prim=(225, 255, 175, 255), env=(0, 255, 40, 255))],
			MSCORE_SEN),
		"ms_sen_cursor": ([Op("sen_item2_DL_mode"), Op("sen_win_cursor_model", prim=(235, 60, 60, 255))], MSCORE_MARK),
	}
	for n, (frame, _moji, prim, env) in enumerate(MSCORE_NOTES):
		model, texs = _MS_FRAMES[frame]
		for playing, tex in enumerate(texs):
			layers[f"ms_note{n}_{playing}"] = (
				[Op("onp_hyouji_waku_mode"), Op(model, prim=(*prim, 255), env=(*env, 255), segments={8: tex})],
				MSCORE_NOTE)
	for moji in sorted({m for _f, m, _p, _e in MSCORE_NOTES}):
		layers[f"ms_moji_{moji}"] = (
			[Op("onp_hyouji_moji_mode"), Op("onp_hyouji_moji1T_model", prim=(255, 255, 255, 255),
				segments={9: f"onp_win_{moji}_tex_rgb_i4"})],
			MSCORE_MARK)
	return layers


def _bake_mscore(rel: RelData, symbols, textures: TextureCache, scale: int, cfg: PipelineConfig) -> list[dict[str, Any]]:
	out_dir = cfg.godot_generated / "ui" / MSCORE_DIR
	stage_dir = cfg.converted / "ui" / MSCORE_DIR
	out_dir.mkdir(parents=True, exist_ok=True)
	stage_dir.mkdir(parents=True, exist_ok=True)
	results: list[dict[str, Any]] = []
	for name, (ops, bounds) in _mscore_layers().items():
		rec: dict[str, Any] = {"asset_id": name, "output_path": f"ui/{MSCORE_DIR}/{name}.png", "error": None}
		try:
			image = bake_layer(UiWalker(rel, symbols), textures, ops, bounds, scale)
			_save(image, name, stage_dir, out_dir, cfg.project_root)
			rec["status"] = "converted"
		except Exception as exc:  # noqa: BLE001
			rec["status"] = "error"
			rec["error"] = f"{type(exc).__name__}: {exc}"
		results.append(rec)
	meta = {"scale": scale, "screen": SCREEN, "note": MSCORE_NOTE, "mark": MSCORE_MARK, "sen": MSCORE_SEN}
	data = json.dumps(meta, indent=2).encode()
	for folder in (stage_dir, out_dir):
		(folder / "mscore.json").write_bytes(data)
	return results


MAP_DIR = "map_screen"
MAP_MARK = (-16.0, 16.0, 32.0, 32.0)
## `mMP_set_win_dl`: segment 10's label frame by label count (0, 1, 2, 3, 4).
_MP_FRAMES = ["kan_waku_w1T_model", "kan_win_wakuT_model", "kan_waku_w2T_model", "kan_waku_w3T_model",
	"kan_waku_w4T_model"]
_MP_NUMS = [f"kan_win_suuji{n}_tex_rgb_ia8" for n in range(1, 6)]
_MP_LETTERS = [f"kan_win_{c}_tex_rgb_ia8" for c in "abcdef"]
## Label icons (`mMP_label_data`) and field marks, drawn at the origin.
_MP_MARKS = ["kan_win_npcT_1_model", "kan_win_npcT_2_model", "kan_win_npcT_3_model", "kan_win_playerT_model",
	"kan_win_omiseT_model", "kan_win_koubanT_model", "kan_win_yuuT_model", "kan_win_yashiroT_model",
	"kan_win_ekiT_model", "kan_win_gomiT_model", "kan_win_mu_model", "kan_win_ta_model", "kan_win_funeT_model",
	"kan_win_npc2T_1_model", "kan_win_npc2T_2_model", "kan_win_npc2T_3_model", "kan_win_genzaiT_model"]


def _bake_map_screen(rel: RelData, symbols, textures: TextureCache, scale: int, cfg: PipelineConfig) -> list[dict[str, Any]]:
	"""`mMP_set_dl`: the window (per colour set), the second window without its acre number
	and letter (per label frame), the numbers and letters on their own, and the marks."""
	out_dir = cfg.godot_generated / "ui" / MAP_DIR
	stage_dir = cfg.converted / "ui" / MAP_DIR
	out_dir.mkdir(parents=True, exist_ok=True)
	stage_dir.mkdir(parents=True, exist_ok=True)
	results: list[dict[str, Any]] = []

	def emit(name: str, make) -> None:
		rec: dict[str, Any] = {"asset_id": name, "output_path": f"ui/{MAP_DIR}/{name}.png", "error": None}
		try:
			_save(make(), name, stage_dir, out_dir, cfg.project_root)
			rec["status"] = "converted"
		except Exception as exc:  # noqa: BLE001
			rec["status"] = "error"
			rec["error"] = f"{type(exc).__name__}: {exc}"
		results.append(rec)

	probe = UiWalker(rel, symbols)
	num_addr = {probe.symbol(n).address: i for i, n in enumerate(_MP_NUMS)}
	let_addr = {probe.symbol(n).address: i for i, n in enumerate(_MP_LETTERS)}

	def win_batches(color: int, frame: int, num: int = 0, let: int = 0):
		seg = {8: _MP_NUMS[num], 9: _MP_LETTERS[let], 10: _MP_FRAMES[frame], 11: f"kan_win_color{color}_mode"}
		return UiWalker(rel, symbols).run([Op("kan_win_model", segments=seg, draw=False), Op("kan_win_model2", segments=seg)])

	def is_num(b) -> bool:
		return b.tex0 is not None and b.tex0.addr in num_addr

	def is_let(b) -> bool:
		return b.tex0 is not None and b.tex0.addr in let_addr

	for color in (0, 1):
		seg = {11: f"kan_win_color{color}_mode"}
		emit(f"mp_base{color}", lambda seg=seg: bake_layer(UiWalker(rel, symbols), textures, [Op("kan_win_model", segments=seg)], SCREEN, scale))
		for frame in range(len(_MP_FRAMES)):
			emit(f"mp_win{color}_{frame}", lambda c=color, f=frame: rasterize(
				[b for b in win_batches(c, f) if not is_num(b) and not is_let(b)], textures, SCREEN, scale))
	for i in range(len(_MP_NUMS)):
		emit(f"mp_num{i + 1}", lambda i=i: rasterize([b for b in win_batches(0, 0, num=i) if is_num(b)], textures, SCREEN, scale))
	for i in range(len(_MP_LETTERS)):
		emit(f"mp_let{'abcdef'[i]}", lambda i=i: rasterize([b for b in win_batches(0, 0, let=i) if is_let(b)], textures, SCREEN, scale))
	for m in _MP_MARKS:
		name = "mp_" + m.removeprefix("kan_win_").removesuffix("_model")
		emit(name, lambda m=m: bake_layer(UiWalker(rel, symbols), textures,
			[Op("kan_win_mode", segments={11: "kan_win_color0_mode"}), Op(m)], MAP_MARK, scale))
	emit("mp_cursor", lambda: bake_layer(UiWalker(rel, symbols), textures,
		[Op("kan_win_mode", segments={11: "kan_win_color0_mode"}), Op("kan_win_cursorT_model", prim=(255, 255, 255, 255))],
		MAP_MARK, scale))
	meta = {"scale": scale, "screen": SCREEN, "mark": MAP_MARK}
	data = json.dumps(meta, indent=2).encode()
	for folder in (stage_dir, out_dir):
		(folder / "map_screen.json").write_bytes(data)
	return results


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

	# Address cards (`mAD_set_addressSel_tag_field`): `mAD_address_draw_init` stretches
	# the card to its page's entry count by moving vertices, so one card per count
	# (1-8), at the origin: the shadow as drawn and the card in white for the runtime
	# to tint with the page's PRIM (the card is PRIM x texel).
	for count in range(1, ADDRESS_MAX_ENTRIES + 1):
		for part in ("shadow", "card"):
			name = f"adr_{part}_{count}"
			rec = {"asset_id": name, "output_path": f"ui/{OUT_DIR_NAME}/{name}.png", "error": None}
			try:
				ops = _address_card_ops(rel, symbols, count, part)
				image = bake_layer(UiWalker(rel, symbols), textures, ops, SCREEN, scale)
				_save(image, name, stage_dir, out_dir, cfg.project_root)
				rec["status"] = "converted"
			except Exception as exc:  # noqa: BLE001
				rec["status"] = "error"
				rec["error"] = f"{type(exc).__name__}: {exc}"
			results.append(rec)

	# Stationery (`mBD_set_frame_dl`): the paper model and, where it has one, its ruled
	# lines (`paper_disp_sen_model`), into `ui/letter/paperNN.png` for `LetterChrome`.
	letter_dir = cfg.godot_generated / "ui" / "letter"
	letter_stage = cfg.converted / "ui" / "letter"
	letter_dir.mkdir(parents=True, exist_ok=True)
	letter_stage.mkdir(parents=True, exist_ok=True)
	for n in range(1, PAPER_COUNT + 1):
		name = f"paper{n:02d}"
		rec = {"asset_id": name, "output_path": f"ui/letter/{name}.png", "error": None}
		try:
			walker = UiWalker(rel, symbols)
			model = "lat_letter63_win_model" if n == 63 else f"lat_letter{n:02d}_model"
			ops = [Op("lat_letter_mode"), Op(model)]
			for sen in (f"lat_letter{n:02d}_sen_model", f"lat_letter{n:02d}_senT_model"):
				if sen in walker.by_name:
					ops += [Op("lat_letter_sen_mode"), Op(sen)]
					break
			image = bake_layer(walker, textures, ops, PAPER_BOUNDS, scale)
			_save(image, name, letter_stage, letter_dir, cfg.project_root)
			rec["status"] = "converted"
		except Exception as exc:  # noqa: BLE001
			rec["status"] = "error"
			rec["error"] = f"{type(exc).__name__}: {exc}"
		results.append(rec)

	results.extend(_bake_catalog(rel, symbols, textures, scale, cfg))
	results.extend(_bake_mscore(rel, symbols, textures, scale, cfg))
	results.extend(_bake_map_screen(rel, symbols, textures, scale, cfg))

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
