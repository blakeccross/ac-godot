"""Walk 2D menu display lists and rasterise them with the real colour combiner.

Menus (`m_*_ovl.c`) are orthographic GBI geometry in 320x240 screen units: a handful
of textured quads per model, coloured by `gDPSetCombineLERP` with PRIM / ENV set
either inside the model or by the caller just before `gSPDisplayList`. This module
walks those lists (vertices, triangles, texture images, TLUTs, tiles, colours,
combiner, nested lists, `gSPSegment` bindings) and rasterises each triangle with the
two-cycle combiner evaluated per pixel, so a baked layer matches what the game draws
instead of approximating each piece by hand.

ACHD: every texture goes through `maybe_hd_png` first, so a configured HD pack is
sampled at its own resolution (UVs are normalised by the native size).

Draw calls are `Op`s: a list name plus the state the C code sets around it (prim,
env, segment textures, a translate in screen units). `bake_layer` rasterises a list
of ops into one RGBA image covering `bounds`.
"""

from __future__ import annotations

import io
import struct
from dataclasses import dataclass, field
from typing import Any

import numpy as np
from PIL import Image

from .achd import maybe_hd_png
from .gfx import _bits, _chunks, _tri_indices_init, _tri_indices_5b
from .mapfile import MapSymbol
from .rel import RelData
from .texbank import (
	G_IM_FMT_CI,
	G_IM_FMT_I,
	GX_CLAMP,
	GX_MIRROR,
	decode_gbi_texture,
	is_dolphin_loadtlut,
	parse_settile,
	parse_settilesize,
	gbi_to_gx,
	image_byte_size,
	parse_loadtlut,
	parse_settile_dolphin,
	parse_settimg,
)

G_VTX = 0x01
G_TRI1 = 0x05
G_TRI2 = 0x06
G_TRIN = 0x09
G_TRIN_INDEPEND = 0x0A
G_SETTILE_DOLPHIN = 0xD2
G_DL = 0xDE
G_ENDDL = 0xDF
G_LOADTLUT = 0xF0
G_SETTILESIZE = 0xF2
G_SETTILE = 0xF5
G_SETPRIMCOLOR = 0xFA
G_SETENVCOLOR = 0xFB
G_SETCOMBINE = 0xFC
G_SETTIMG = 0xFD


@dataclass
class Vtx:
	x: float
	y: float
	s: float
	t: float
	rgba: tuple[int, int, int, int]


@dataclass(frozen=True)
class Tile:
	addr: int
	width: int
	height: int
	fmt: int
	siz: int
	tlut: int  # address, 0 = none
	wrap_s: int
	wrap_t: int
	## Classic `gsDPLoadTextureBlock` data is N64 linear, not GX-tiled.
	linear: bool = False


@dataclass
class Batch:
	tris: list[tuple[Vtx, Vtx, Vtx]]
	tex0: Tile | None
	tex1: Tile | None
	prim: tuple[int, int, int, int]
	env: tuple[int, int, int, int]
	prim_lod: int
	combine: tuple[int, int]


@dataclass
class Op:
	"""One `gSPDisplayList` call and the state the caller sets around it."""

	dl: str
	prim: tuple[int, int, int, int] | None = None
	env: tuple[int, int, int, int] | None = None
	## `gSPSegment(seg, symbol)` bindings, e.g. {8: "kai_sousa_button1a_tex_rgb_ia8"}.
	segments: dict[int, str] = field(default_factory=dict)
	## `Matrix_translate` in screen units.
	offset: tuple[float, float] = (0.0, 0.0)


class UiWalker:
	def __init__(self, rel: RelData, symbols: list[MapSymbol]) -> None:
		self.rel = rel
		self.by_name: dict[str, MapSymbol] = {}
		self.by_addr: dict[int, MapSymbol] = {}
		for sym in symbols:
			self.by_name.setdefault(sym.name, sym)
			if sym.size and (sym.address not in self.by_addr or not sym.name.startswith(".")):
				self.by_addr.setdefault(sym.address, sym)
		# Draw state persists across ops like the RDP's.
		self.prim = (255, 255, 255, 255)
		self.prim_lod = 255
		self.env = (0, 0, 0, 255)
		self.combine = (0, 0)
		self.tiles: dict[int, Tile] = {}
		self.tluts: dict[int, int] = {}
		self._img: tuple[int, int, int, int, int] | None = None
		self._img_bound = True
		self._classic_tile: tuple[int, int, int, int] | None = None
		self._classic_tlut = 0

	def symbol(self, name: str) -> MapSymbol:
		sym = self.by_name.get(name)
		if sym is None:
			raise KeyError(name)
		return sym

	def run(self, ops: list[Op]) -> list[Batch]:
		batches: list[Batch] = []
		for op in ops:
			if op.prim is not None:
				self.prim = op.prim
			if op.env is not None:
				self.env = op.env
			segs = {seg: self.symbol(name).address for seg, name in op.segments.items()}
			sym = self.symbol(op.dl)
			self._walk(self.rel.slice_at(sym.address, sym.size), segs, op.offset, batches, 0)
		return batches

	def _resolve(self, addr: int, segs: dict[int, int]) -> int:
		seg = addr >> 24
		if seg in segs:
			return segs[seg] + (addr & 0xFFFFFF)
		return addr

	def _walk(self, dl: bytes, segs: dict[int, int], offset: tuple[float, float], out: list[Batch], depth: int) -> None:
		if depth > 8:
			return
		cache: list[Vtx | None] = [None] * 32
		i = 0
		extra = 0
		pending: list[tuple[int, int, int]] = []

		def flush() -> None:
			if not pending:
				return
			if not self._img_bound:
				# SetTextureImage with no SetTile after it draws from tile 0's settings.
				self._bind(0, self.tiles.get(0))
				self._img_bound = True
			tris = []
			for a, b, c in pending:
				va, vb, vc = cache[a], cache[b], cache[c]
				if va is not None and vb is not None and vc is not None:
					tris.append((va, vb, vc))
			pending.clear()
			if tris:
				out.append(Batch(tris, self.tiles.get(0), self.tiles.get(1), self.prim, self.env,
					self.prim_lod, self.combine))

		while i + 8 <= len(dl):
			packet = dl[i : i + 8]
			i += 8
			if extra > 0:
				take = min(4, extra)
				pending.extend(_chunks(_tri_indices_5b(packet), 3)[:take])
				extra -= 4
				continue
			cmd = packet[0]
			w0 = int.from_bytes(packet[0:4], "big")
			w1 = int.from_bytes(packet[4:8], "big")
			if cmd == G_ENDDL:
				break
			if cmd == G_VTX:
				flush()
				n = _bits(w0, 12, 8)
				v0 = _bits(w0, 1, 7) - n
				addr = self._resolve(w1, segs)
				blob = self.rel.slice_at(addr, 16 * n)
				for k in range(n):
					x, y, _z, _f, s, t, r, g, b, a = struct.unpack_from(">hhhHhhBBBB", blob, 16 * k)
					if 0 <= v0 + k < 32:
						cache[v0 + k] = Vtx(x + offset[0], y + offset[1], s / 32.0, t / 32.0, (r, g, b, a))
			elif cmd in (G_TRIN, G_TRIN_INDEPEND):
				count = _bits(w0, 17, 7) + 1
				pending.extend(_chunks(_tri_indices_init(packet), 3)[: min(3, count)])
				extra = max(0, count - 3)
			elif cmd == G_TRI1:
				pending.append((_bits(w0, 16, 8) // 2, _bits(w0, 8, 8) // 2, _bits(w0, 0, 8) // 2))
			elif cmd == G_TRI2:
				pending.append((_bits(w0, 16, 8) // 2, _bits(w0, 8, 8) // 2, _bits(w0, 0, 8) // 2))
				pending.append((_bits(w1, 16, 8) // 2, _bits(w1, 8, 8) // 2, _bits(w1, 0, 8) // 2))
			else:
				flush()
				if cmd == G_SETPRIMCOLOR:
					self.prim_lod = w0 & 0xFF
					self.prim = ((w1 >> 24) & 0xFF, (w1 >> 16) & 0xFF, (w1 >> 8) & 0xFF, w1 & 0xFF)
				elif cmd == G_SETENVCOLOR:
					self.env = ((w1 >> 24) & 0xFF, (w1 >> 16) & 0xFF, (w1 >> 8) & 0xFF, w1 & 0xFF)
				elif cmd == G_SETCOMBINE:
					self.combine = (w0 & 0xFFFFFF, w1)
				elif cmd == G_SETTIMG:
					fmt, siz, width, height, addr = parse_settimg(w0, w1)
					self._img = (fmt, siz, width, height, self._resolve(addr, segs))
					self._img_bound = False
				elif cmd == G_LOADTLUT:
					if is_dolphin_loadtlut(w0):
						slot, _count, addr = parse_loadtlut(w0, w1)
						self.tluts[slot] = self._resolve(addr, segs)
					elif self._img is not None:
						# `gsDPLoadTLUT_pal16`: the palette is the preceding SetTextureImage.
						self._classic_tlut = self._img[4]
						self._img_bound = True
				elif cmd == G_SETTILE:
					# Classic `gsDPLoadTextureBlock`: the render tile's format and wrap; the
					# size follows in SetTileSize.
					if (w1 >> 24) & 7 == 0:
						fmt, siz, _pal, wrap_s, wrap_t, _tmem = parse_settile(w0, w1)
						self._classic_tile = (fmt, siz, wrap_s, wrap_t)
				elif cmd == G_SETTILESIZE:
					if (w1 >> 24) & 7 == 0 and self._img is not None and self._img[3] == 0 and self._classic_tile:
						width, height = parse_settilesize(w0, w1)
						fmt, siz, wrap_s, wrap_t = self._classic_tile
						tlut = self._classic_tlut if fmt == G_IM_FMT_CI else 0
						self.tiles[0] = Tile(self._img[4], width, height, fmt, siz, tlut, wrap_s, wrap_t, True)
						self._img_bound = True
				elif cmd == G_SETTILE_DOLPHIN:
					tile, pal_slot, wrap_s, wrap_t = parse_settile_dolphin(w0)
					if self._img is not None:
						fmt, siz, width, height, addr = self._img
						self.tiles[tile] = Tile(addr, width, height, fmt, siz,
							self.tluts.get(pal_slot, 0) if fmt == G_IM_FMT_CI else 0, wrap_s, wrap_t)
						self._img_bound = True
				elif cmd == G_DL:
					target = self._resolve(w1, segs)
					sym = self.by_addr.get(target)
					if sym is not None:
						self._walk(self.rel.slice_at(sym.address, sym.size), segs, offset, out, depth + 1)
					if (w0 >> 16) & 0xFF:  # branch: no return
						break
		flush()

	def _bind(self, tile: int, prev: Tile | None) -> None:
		if self._img is None:
			return
		fmt, siz, width, height, addr = self._img
		wrap_s = prev.wrap_s if prev else GX_CLAMP
		wrap_t = prev.wrap_t if prev else GX_CLAMP
		tlut = self.tluts.get(15, 0) if fmt == G_IM_FMT_CI else 0
		self.tiles[tile] = Tile(addr, width, height, fmt, siz, tlut, wrap_s, wrap_t)


# --- rasteriser -------------------------------------------------------------------

class TextureCache:
	def __init__(self, rel: RelData, achd: Any = None) -> None:
		self.rel = rel
		self.achd = achd
		self.hits = 0
		self._cache: dict[Tile, np.ndarray] = {}

	def get(self, tile: Tile) -> np.ndarray:
		if tile in self._cache:
			return self._cache[tile]
		if tile.linear:
			arr = _decode_linear(self.rel, tile)
			self._cache[tile] = arr
			return arr
		data = self.rel.slice_at(tile.addr, image_byte_size(tile.width, tile.height, tile.siz))
		pal = self.rel.slice_at(tile.tlut, 32 if tile.siz == 0 else 512) if tile.tlut else b""
		image = None
		hd = maybe_hd_png(self.achd, data, tile.width, tile.height, gbi_to_gx(tile.fmt, tile.siz), pal or None,
			wrap_s=tile.wrap_s, wrap_t=tile.wrap_t)
		if hd is not None:
			image = Image.open(io.BytesIO(hd)).convert("RGBA")
			self.hits += 1
		if image is None:
			image = decode_gbi_texture(data, tile.width, tile.height, tile.fmt, tile.siz, pal).convert("RGBA")
		arr = np.asarray(image, dtype=np.float32) / 255.0
		if tile.fmt == G_IM_FMT_I and arr[..., 3].min() >= 0.999:
			# I textures sample alpha = intensity.
			arr = arr.copy()
			arr[..., 3] = arr[..., 0]
		self._cache[tile] = arr
		return arr


def _rgba5551(v: int) -> tuple[int, int, int, int]:
	r = (v >> 11) & 0x1F
	g = (v >> 6) & 0x1F
	b = (v >> 1) & 0x1F
	return (r << 3 | r >> 2, g << 3 | g >> 2, b << 3 | b >> 2, 255 if v & 1 else 0)


def _decode_linear(rel: RelData, tile: Tile) -> np.ndarray:
	"""N64 linear texel data (I4/I8/IA4/IA8/IA16/RGBA16/CI4/CI8) as float RGBA."""
	w, h, fmt, siz = tile.width, tile.height, tile.fmt, tile.siz
	bits = (4, 8, 16, 32)[siz]
	data = rel.slice_at(tile.addr, (w * h * bits + 7) // 8)
	pal: list[tuple[int, int, int, int]] = []
	if fmt == G_IM_FMT_CI and tile.tlut:
		raw = rel.slice_at(tile.tlut, 32 if siz == 0 else 512)
		pal = [_rgba5551(int.from_bytes(raw[k : k + 2], "big")) for k in range(0, len(raw), 2)]
	out = np.zeros((h, w, 4), np.float32)
	for y in range(h):
		for x in range(w):
			i = y * w + x
			if bits == 4:
				byte = data[i // 2] if i // 2 < len(data) else 0
				v = (byte >> 4) if i % 2 == 0 else (byte & 0xF)
			elif bits == 8:
				v = data[i] if i < len(data) else 0
			else:
				v = int.from_bytes(data[2 * i : 2 * i + 2], "big") if 2 * i + 1 < len(data) else 0
			if fmt == G_IM_FMT_CI:
				px = pal[v] if v < len(pal) else (0, 0, 0, 0)
			elif fmt == G_IM_FMT_I:
				c = v * 17 if bits == 4 else v & 0xFF
				px = (c, c, c, c)
			elif fmt == 3:  # IA
				if bits == 4:
					c = ((v >> 1) & 7) * 255 // 7
					px = (c, c, c, 255 if v & 1 else 0)
				elif bits == 8:
					c = (v >> 4) * 17
					px = (c, c, c, (v & 0xF) * 17)
				else:
					c = v >> 8
					px = (c, c, c, v & 0xFF)
			else:  # RGBA16
				px = _rgba5551(v)
			out[y, x] = px
	return out / 255.0


def _wrap(idx: np.ndarray, size: int, mode: int) -> np.ndarray:
	if mode == GX_CLAMP:
		return np.clip(idx, 0, size - 1)
	if mode == GX_MIRROR:
		m = np.mod(idx, 2 * size)
		return np.where(m < size, m, 2 * size - 1 - m)
	return np.mod(idx, size)


def _sample(tex: np.ndarray, tile: Tile, s: np.ndarray, t: np.ndarray) -> np.ndarray:
	"""Bilinear fetch at native texel coords (s, t), scaled into the (maybe HD) image."""
	h, w = tex.shape[:2]
	u = s * (w / tile.width) - 0.5
	v = t * (h / tile.height) - 0.5
	u0 = np.floor(u)
	v0 = np.floor(v)
	fu = (u - u0)[:, None]
	fv = (v - v0)[:, None]
	u0 = u0.astype(np.int64)
	v0 = v0.astype(np.int64)
	x0 = _wrap(u0, w, tile.wrap_s)
	x1 = _wrap(u0 + 1, w, tile.wrap_s)
	y0 = _wrap(v0, h, tile.wrap_t)
	y1 = _wrap(v0 + 1, h, tile.wrap_t)
	top = tex[y0, x0] * (1 - fu) + tex[y0, x1] * fu
	bot = tex[y1, x0] * (1 - fu) + tex[y1, x1] * fu
	return top * (1 - fv) + bot * fv


def _combine_cycle(sel: tuple[int, int, int, int], asel: tuple[int, int, int, int], src: dict[str, np.ndarray],
		n: int) -> np.ndarray:
	a, b, c, d = sel
	aa, ab, ac, ad = asel
	zero = np.zeros((n, 3), np.float32)
	one = np.ones((n, 3), np.float32)
	rgb = {0: src["comb"][:, :3], 1: src["t0"][:, :3], 2: src["t1"][:, :3], 3: src["prim"][:, :3],
		4: src["shade"][:, :3], 5: src["env"][:, :3]}
	alpha = {0: src["comb"][:, 3], 1: src["t0"][:, 3], 2: src["t1"][:, 3], 3: src["prim"][:, 3],
		4: src["shade"][:, 3], 5: src["env"][:, 3]}
	ca = rgb.get(a, one if a == 6 else zero)
	cb = rgb.get(b, zero)
	c_map = dict(rgb)
	c_map.update({7: np.repeat(src["comb"][:, 3:4], 3, 1), 8: np.repeat(src["t0"][:, 3:4], 3, 1),
		9: np.repeat(src["t1"][:, 3:4], 3, 1), 10: np.repeat(src["prim"][:, 3:4], 3, 1),
		11: np.repeat(src["shade"][:, 3:4], 3, 1), 12: np.repeat(src["env"][:, 3:4], 3, 1),
		14: np.full((n, 3), src["lod"], np.float32)})
	cc = c_map.get(c, zero)
	cd = rgb.get(d, one if d == 6 else zero)
	out_rgb = (ca - cb) * cc + cd
	one1 = np.ones(n, np.float32)
	zero1 = np.zeros(n, np.float32)
	pa = alpha.get(aa, one1 if aa == 6 else zero1)
	pb = alpha.get(ab, one1 if ab == 6 else zero1)
	ac_map = {1: src["t0"][:, 3], 2: src["t1"][:, 3], 3: src["prim"][:, 3], 4: src["shade"][:, 3],
		5: src["env"][:, 3], 6: np.full(n, src["lod"], np.float32)}
	pc = ac_map.get(ac, zero1)
	pd = alpha.get(ad, one1 if ad == 6 else zero1)
	out_a = (pa - pb) * pc + pd
	return np.clip(np.concatenate([out_rgb, out_a[:, None]], 1), 0.0, 1.0)


def _decode_combine(w0: int, w1: int) -> list[tuple[tuple[int, ...], tuple[int, ...]]]:
	c0 = ((w0 >> 20) & 0xF, (w1 >> 28) & 0xF, (w0 >> 15) & 0x1F, (w1 >> 15) & 0x7)
	a0 = ((w0 >> 12) & 0x7, (w1 >> 12) & 0x7, (w0 >> 9) & 0x7, (w1 >> 9) & 0x7)
	c1 = ((w0 >> 5) & 0xF, (w1 >> 24) & 0xF, w0 & 0x1F, (w1 >> 6) & 0x7)
	a1 = ((w1 >> 21) & 0x7, (w1 >> 3) & 0x7, (w1 >> 18) & 0x7, w1 & 0x7)
	# gsDPSetCombineLERP stores `d` in 3 bits: 7 = 0 for colour d as well.
	return [(c0, a0), (c1, a1)]


def _edge(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> float:
	return float((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1]))


def _edge_fn(a: np.ndarray, b: np.ndarray, x: np.ndarray, y: np.ndarray) -> np.ndarray:
	return (b[0] - a[0]) * (y - a[1]) - (x - a[0]) * (b[1] - a[1])


def _covers(e: np.ndarray, a: np.ndarray, b: np.ndarray) -> np.ndarray:
	"""Top-left fill rule, so pixels on an edge shared by two triangles draw once."""
	dx, dy = b[0] - a[0], b[1] - a[1]
	top_left = (dy < 0) or (dy == 0 and dx > 0)
	return (e > 1e-9) | ((np.abs(e) <= 1e-9) & top_left)


def rasterize(batches: list[Batch], textures: TextureCache, bounds: tuple[float, float, float, float],
		scale: float, image: Image.Image | None = None) -> Image.Image:
	left, top, width, height = bounds
	w_px, h_px = int(round(width * scale)), int(round(height * scale))
	canvas = np.zeros((h_px, w_px, 4), np.float32)
	if image is not None:
		canvas = np.asarray(image.convert("RGBA"), dtype=np.float32) / 255.0
		canvas = canvas.copy()
	for batch in batches:
		cycles = _decode_combine(*batch.combine)
		t0 = textures.get(batch.tex0) if batch.tex0 else None
		t1 = textures.get(batch.tex1) if batch.tex1 else None
		prim = np.array(batch.prim, np.float32) / 255.0
		env = np.array(batch.env, np.float32) / 255.0
		for tri in batch.tris:
			px = np.array([((v.x - left) * scale, (top - v.y) * scale) for v in tri], np.float64)
			x0 = max(int(np.floor(px[:, 0].min())), 0)
			x1 = min(int(np.ceil(px[:, 0].max())), w_px)
			y0 = max(int(np.floor(px[:, 1].min())), 0)
			y1 = min(int(np.ceil(px[:, 1].max())), h_px)
			if x1 <= x0 or y1 <= y0:
				continue
			ys, xs = np.mgrid[y0:y1, x0:x1]
			cx = xs.ravel() + 0.5
			cy = ys.ravel() + 0.5
			area = _edge(px[0], px[1], px[2])
			if abs(area) < 1e-9:
				continue
			order = (0, 1, 2) if area > 0 else (0, 2, 1)
			p = [px[k] for k in order]
			e0 = _edge_fn(p[1], p[2], cx, cy)
			e1 = _edge_fn(p[2], p[0], cx, cy)
			e2 = _edge_fn(p[0], p[1], cx, cy)
			inside = _covers(e0, p[1], p[2]) & _covers(e1, p[2], p[0]) & _covers(e2, p[0], p[1])
			a = abs(area)
			bary = {order[0]: e0 / a, order[1]: e1 / a, order[2]: e2 / a}
			l0, l1, l2 = bary[0], bary[1], bary[2]
			if not inside.any():
				continue
			l0, l1, l2 = l0[inside], l1[inside], l2[inside]
			n = int(inside.sum())
			s = l0 * tri[0].s + l1 * tri[1].s + l2 * tri[2].s
			t = l0 * tri[0].t + l1 * tri[1].t + l2 * tri[2].t
			shade = (np.outer(l0, tri[0].rgba) + np.outer(l1, tri[1].rgba) + np.outer(l2, tri[2].rgba)) / 255.0
			src = {
				"t0": _sample(t0, batch.tex0, s, t) if t0 is not None else np.ones((n, 4), np.float32),
				"t1": _sample(t1, batch.tex1, s, t) if t1 is not None else np.ones((n, 4), np.float32),
				"prim": np.tile(prim, (n, 1)),
				"env": np.tile(env, (n, 1)),
				"shade": shade.astype(np.float32),
				"lod": batch.prim_lod / 255.0,
				"comb": np.zeros((n, 4), np.float32),
			}
			out = _combine_cycle(*cycles[0], src, n)
			src["comb"] = out
			out = _combine_cycle(*cycles[1], src, n)
			iy = ys.ravel()[inside]
			ix = xs.ravel()[inside]
			dst = canvas[iy, ix]
			sa = out[:, 3:4]
			da = dst[:, 3:4]
			oa = sa + da * (1 - sa)
			rgb = np.where(oa > 1e-6, (out[:, :3] * sa + dst[:, :3] * da * (1 - sa)) / np.maximum(oa, 1e-6), 0)
			canvas[iy, ix] = np.concatenate([rgb, oa], 1)
	return Image.fromarray((np.clip(canvas, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def bake_layer(walker: UiWalker, textures: TextureCache, ops: list[Op], bounds: tuple[float, float, float, float],
		scale: float) -> Image.Image:
	return rasterize(walker.run(ops), textures, bounds, scale)
