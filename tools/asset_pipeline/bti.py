from __future__ import annotations

import struct
from pathlib import Path

from PIL import Image

# GX texture formats (BTI / TPL).
I4, I8, IA4, IA8 = 0, 1, 2, 3
RGB565, RGB5A3, RGBA8 = 4, 5, 6
CI4, CI8, CI14X2, CMPR = 8, 9, 10, 14

_BLOCK = {
    I4: (8, 8, 4),
    I8: (8, 4, 8),
    IA4: (8, 4, 8),
    IA8: (4, 4, 16),
    RGB565: (4, 4, 16),
    RGB5A3: (4, 4, 16),
    RGBA8: (4, 4, 32),
    CI4: (8, 8, 4),
    CI8: (8, 4, 8),
    CMPR: (8, 8, 4),
}


def _rgb565(v: int) -> tuple[int, int, int, int]:
    r = ((v >> 11) & 0x1F) * 255 // 31
    g = ((v >> 5) & 0x3F) * 255 // 63
    b = (v & 0x1F) * 255 // 31
    return r, g, b, 255


def _rgb5a3(v: int) -> tuple[int, int, int, int]:
    if v & 0x8000:
        r = ((v >> 10) & 0x1F) * 255 // 31
        g = ((v >> 5) & 0x1F) * 255 // 31
        b = (v & 0x1F) * 255 // 31
        return r, g, b, 255
    a = ((v >> 12) & 0x7) * 255 // 7
    r = ((v >> 8) & 0xF) * 255 // 15
    g = ((v >> 4) & 0xF) * 255 // 15
    b = (v & 0xF) * 255 // 15
    return r, g, b, a


def _s3tc_rgb(v: int) -> tuple[int, int, int]:
    r, g, b, _ = _rgb565(v)
    return r, g, b


def decode_gx_image(data: bytes, width: int, height: int, fmt: int, palette: list[tuple[int, int, int, int]] | None = None) -> Image.Image:
    bw, bh, bpp = _BLOCK[fmt]
    img = Image.new("RGBA", (width, height))
    pixels = img.load()
    src = 0

    def take(n: int) -> bytes:
        nonlocal src
        chunk = data[src : src + n]
        src += n
        return chunk

    for by in range(0, max(height, 1), bh):
        for bx in range(0, max(width, 1), bw):
            if fmt == CMPR:
                for ty in range(2):
                    for tx in range(2):
                        c0, c1 = struct.unpack(">HH", take(4))
                        bits = int.from_bytes(take(4), "big")
                        cols = [_s3tc_rgb(c0), _s3tc_rgb(c1)]
                        if c0 > c1:
                            cols.append(tuple((2 * cols[0][i] + cols[1][i]) // 3 for i in range(3)))
                            cols.append(tuple((cols[0][i] + 2 * cols[1][i]) // 3 for i in range(3)))
                            alphas = (255, 255, 255, 255)
                        else:
                            cols.append(tuple((cols[0][i] + cols[1][i]) // 2 for i in range(3)))
                            cols.append((0, 0, 0))
                            alphas = (255, 255, 255, 0)
                        for py in range(4):
                            for px in range(4):
                                idx = (bits >> (30 - (py * 4 + px) * 2)) & 3
                                x, y = bx + tx * 4 + px, by + ty * 4 + py
                                if x < width and y < height:
                                    r, g, b = cols[idx]
                                    pixels[x, y] = (r, g, b, alphas[idx])
                continue
            for py in range(bh):
                for px in range(bw):
                    x, y = bx + px, by + py
                    if fmt == I4:
                        byte = data[src + (py * bw + px) // 2]
                        v = (byte >> 4) if px % 2 == 0 else (byte & 0xF)
                        v = v * 17
                        color = (v, v, v, 255)
                    elif fmt == CI4:
                        byte = data[src + (py * bw + px) // 2]
                        v = (byte >> 4) if px % 2 == 0 else (byte & 0xF)
                        color = palette[v] if palette and v < len(palette) else (255, 0, 255, 255)
                    elif fmt == IA4:
                        ## GX IA4 packs AAAAIIII — alpha high, intensity low.
                        byte = data[src + py * bw + px]
                        alpha = (byte >> 4) * 17
                        intensity = (byte & 0xF) * 17
                        color = (intensity, intensity, intensity, alpha)
                    elif fmt == I8:
                        v = data[src + py * bw + px]
                        color = (v, v, v, 255)
                    elif fmt == CI8:
                        v = data[src + py * bw + px]
                        color = palette[v] if palette and v < len(palette) else (v, v, v, 255)
                    elif fmt == IA8:
                        off = (py * bw + px) * 2
                        i8, a8 = data[src + off], data[src + off + 1]
                        color = (i8, i8, i8, a8)
                    elif fmt == RGB565:
                        off = (py * bw + px) * 2
                        color = _rgb565(int.from_bytes(data[src + off : src + off + 2], "big"))
                    elif fmt == RGB5A3:
                        off = (py * bw + px) * 2
                        color = _rgb5a3(int.from_bytes(data[src + off : src + off + 2], "big"))
                    elif fmt == RGBA8:
                        # Two-cache-line: AR then GB, 4x4.
                        idx = py * bw + px
                        ar = data[src + idx * 2 : src + idx * 2 + 2]
                        gb = data[src + 32 + idx * 2 : src + 32 + idx * 2 + 2]
                        color = (gb[0], gb[1], ar[1], ar[0])
                    else:
                        color = (255, 0, 255, 255)
                    if 0 <= x < width and 0 <= y < height:
                        pixels[x, y] = color
            src += bw * bh * bpp // 8
    return img


def decode_bti(data: bytes) -> Image.Image:
    fmt = data[0]
    width, height = struct.unpack_from(">HH", data, 2)
    pal_fmt = data[9]
    pal_count = struct.unpack_from(">H", data, 10)[0]
    image_off = struct.unpack_from(">I", data, 28)[0]
    pal_off = struct.unpack_from(">I", data, 12)[0]
    palette = None
    if fmt in (CI4, CI8, CI14X2) and pal_count:
        palette = []
        for i in range(pal_count):
            v = int.from_bytes(data[pal_off + i * 2 : pal_off + i * 2 + 2], "big")
            palette.append(_rgb5a3(v) if pal_fmt == 2 else _rgb565(v) if pal_fmt == 1 else _rgb5a3(v))
    return decode_gx_image(data[image_off:], width, height, fmt, palette)


def bti_raw_parts(data: bytes) -> tuple[int, int, int, bytes, bytes]:
    """Return (fmt, width, height, texel_bytes, palette_bytes)."""
    fmt = data[0]
    width, height = struct.unpack_from(">HH", data, 2)
    pal_count = struct.unpack_from(">H", data, 10)[0]
    image_off = struct.unpack_from(">I", data, 28)[0]
    pal_off = struct.unpack_from(">I", data, 12)[0]
    bw, bh, bpp = _BLOCK[fmt]
    ew = (width + bw - 1) // bw * bw
    eh = (height + bh - 1) // bh * bh
    nbytes = ew * eh * bpp // 8
    texels = data[image_off : image_off + nbytes]
    pal = b""
    if fmt in (CI4, CI8, CI14X2) and pal_count:
        pal = data[pal_off : pal_off + pal_count * 2]
    return fmt, width, height, texels, pal


def bti_to_png(src: Path, dest: Path, achd=None) -> dict:
    raw = src.read_bytes()
    dest.parent.mkdir(parents=True, exist_ok=True)
    if achd is not None:
        from .achd import maybe_hd_png

        fmt, width, height, texels, pal = bti_raw_parts(raw)
        hd = maybe_hd_png(achd, texels, width, height, fmt, pal)
        if hd is not None:
            dest.write_bytes(hd)
            image = Image.open(dest)
            return {
                "width": image.width,
                "height": image.height,
                "mode": image.mode,
                "achd": True,
                "native_width": width,
                "native_height": height,
            }
    image = decode_bti(raw)
    image.save(dest)
    return {"width": image.width, "height": image.height, "mode": image.mode, "achd": False}
