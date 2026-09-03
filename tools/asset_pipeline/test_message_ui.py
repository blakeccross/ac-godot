"""Tests for `m_msg` cloud bake / solidify."""

from __future__ import annotations

import unittest

from PIL import Image, ImageDraw

from asset_pipeline.message_ui import CLOUD_COMPOSITED_RGBA, _solidify_cloud_interior


class TestSolidifyCloudInterior(unittest.TestCase):
    def _blob(self, size: int = 120) -> Image.Image:
        """Opaque rounded rect with a bright rim + darker body (simulates a textured bake)."""
        im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(im)
        draw.rounded_rectangle((10, 10, size - 11, size - 11), radius=24, fill=(255, 255, 255, 255))
        draw.rounded_rectangle((18, 18, size - 19, size - 19), radius=18, fill=(90, 110, 90, 220))
        return im

    def _rim_band(self, im: Image.Image) -> int:
        fill = CLOUD_COMPOSITED_RGBA[:3]
        a = im.getchannel("A")
        y = im.height // 2
        x0 = next(x for x in range(im.width) if a.getpixel((x, y)) > 48)
        band = 0
        for x in range(x0, min(x0 + 80, im.width)):
            r, g, b, _aa = im.getpixel((x, y))
            if abs(r - fill[0]) + abs(g - fill[1]) + abs(b - fill[2]) < 18:
                break
            band += 1
        return band

    def test_rim_scales_with_bake_space_pixels(self) -> None:
        src = self._blob()
        thin = _solidify_cloud_interior(src, rim_px=2)
        thick = _solidify_cloud_interior(src, rim_px=16)
        self.assertGreater(self._rim_band(thick), self._rim_band(thin) * 2)

    def test_default_rim_matches_two_px(self) -> None:
        src = self._blob()
        self.assertEqual(self._rim_band(_solidify_cloud_interior(src)), self._rim_band(_solidify_cloud_interior(src, rim_px=2)))


if __name__ == "__main__":
    unittest.main()
