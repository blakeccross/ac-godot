"""Combiner and rasteriser checks for `ui_gbi` (synthetic batches, no disc needed)."""

from __future__ import annotations

import unittest

from .ui_gbi import Batch, Vtx, _decode_combine, rasterize


def _combine(a: int, b: int, c: int, d: int, aa: int, ab: int, ac: int, ad: int) -> tuple[int, int]:
	"""Encode one `gsDPSetCombineLERP` cycle into both cycles, like the macro does."""
	w0 = (a << 20) | (c << 15) | (aa << 12) | (ac << 9) | (a << 5) | c
	w1 = (b << 28) | (b << 24) | (aa << 21) | (ac << 18) | (d << 15) | (ab << 12) | (ad << 9) | (d << 6) | (ab << 3) | ad
	return w0, w1


PRIM, ENV, ONE, ZERO_A, ZERO_B, ZERO_C = 3, 5, 6, 15, 15, 31


def _quad(x0: float, y0: float, x1: float, y1: float) -> list[tuple[Vtx, Vtx, Vtx]]:
	w = (255, 255, 255, 255)
	a, b, c, d = Vtx(x0, y1, 0, 0, w), Vtx(x1, y1, 0, 0, w), Vtx(x1, y0, 0, 0, w), Vtx(x0, y0, 0, 0, w)
	return [(a, b, c), (a, c, d)]


class _NoTextures:
	def get(self, _tile):  # pragma: no cover - untextured batches never ask
		raise AssertionError("no textures expected")


class UiGbiTest(unittest.TestCase):
	def test_decode_prim_fill(self) -> None:
		(c0, a0), (c1, a1) = _decode_combine(*_combine(ZERO_A, ZERO_B, ZERO_C, PRIM, 7, 7, 7, PRIM))
		self.assertEqual(c0[3], PRIM)
		self.assertEqual(a0[3], PRIM)
		self.assertEqual(c1[3], PRIM)

	def test_prim_quad_fills_its_pixels_once(self) -> None:
		combine = _combine(ZERO_A, ZERO_B, ZERO_C, PRIM, 7, 7, 7, PRIM)
		batch = Batch(_quad(-4, -4, 4, 4), None, None, (200, 100, 50, 128), (0, 0, 0, 255), 255, combine)
		image = rasterize([batch], _NoTextures(), (-8, 8, 16, 16), 1)
		self.assertEqual(image.getpixel((8, 8)), (200, 100, 50, 128))
		# Pixels on the shared diagonal draw once (top-left rule), not blended twice.
		self.assertEqual(image.getpixel((6, 6))[3], 128)
		self.assertEqual(image.getpixel((1, 1))[3], 0)

	def test_lerp_prim_env_by_constant(self) -> None:
		# (PRIM - ENV) * PRIM_ALPHA + ENV: an opaque prim wins outright.
		combine = _combine(PRIM, ENV, 10, ENV, 7, 7, 7, ONE)
		batch = Batch(_quad(-4, -4, 4, 4), None, None, (255, 0, 0, 255), (0, 0, 255, 255), 255, combine)
		image = rasterize([batch], _NoTextures(), (-8, 8, 16, 16), 1)
		self.assertEqual(image.getpixel((8, 8)), (255, 0, 0, 255))


if __name__ == "__main__":
	unittest.main()
