#!/usr/bin/env python3
"""Offline composite of the talk window matching `m_msg` metrics for visual compare."""

from __future__ import annotations

import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from asset_pipeline.message_ui import (  # noqa: E402
    FONT_CHAR_H,
    FONT_CHAR_W,
    FONT_OFFSETS,
)

MSG_DIR = ROOT / "assets" / "generated" / "ui" / "message"
REF = Path(
    "/Users/blakecross/.cursor/projects/Users-blakecross-Documents-Code-ac-godot"
    "/assets/image-2cb61115-956b-4f8c-ac14-a662c785d5f1.png"
)

# Screen placement from baked verts / mMsg_init.
CLOUD = (37.0, 133.4, 260.0, 104.0)
NAMEPLATE = (48.0, 123.4, 98.0, 28.0)
BODY_ORIGIN = (64.0, 153.4)
LINE_PITCH = 16.0
ARROW = (257.0, 205.4, 8.0, 8.0)  # approx from UV on cloud

NAME_BG = (235, 140, 210, 255)
NAME_FG = (45, 0, 30, 255)
BODY_FG = (50, 60, 50, 255)
ARROW_FG = (120, 100, 220, 255)

TEXT = [
    "Whoa! You look so weird!",
    "And not weird in a hip way,",
    'either. More like, "weird"',
    'as in "makes me wanna barf."',
]


def _load_atlas() -> Image.Image:
    path = MSG_DIR / "msg_font_atlas.png"
    return Image.open(path).convert("RGBA")


def _glyph(atlas: Image.Image, ch: str) -> tuple[Image.Image, int]:
    code = ord(ch)
    if code > 255:
        code = ord("?")
    cut = max(1, FONT_CHAR_W - FONT_OFFSETS[code])
    col = code & 0xF
    row = code >> 4
    cell = atlas.crop(
        (col * FONT_CHAR_W, row * FONT_CHAR_H, col * FONT_CHAR_W + cut, row * FONT_CHAR_H + FONT_CHAR_H)
    )
    return cell, cut


def _blit_text(
    dest: Image.Image,
    atlas: Image.Image,
    text: str,
    origin: tuple[float, float],
    color: tuple[int, int, int, int],
    *,
    scale: int,
) -> None:
    x, y = origin
    for ch in text:
        glyph, adv = _glyph(atlas, ch)
        gx = int(round(x * scale))
        gy = int(round(y * scale))
        if scale != 1:
            glyph = glyph.resize((glyph.width * scale, glyph.height * scale), Image.NEAREST)
        # Tint white glyph by color using alpha.
        tinted = Image.new("RGBA", glyph.size, color)
        tinted.putalpha(glyph.split()[3])
        dest.alpha_composite(tinted, (gx, gy))
        x += adv


def render(scale: int = 3) -> Image.Image:
    cloud = Image.open(MSG_DIR / "msg_window_cloud.png").convert("RGBA")
    plate = Image.open(MSG_DIR / "msg_nameplate_cloud.png").convert("RGBA")
    atlas = _load_atlas()

    w, h = int(320 * scale), int(240 * scale)
    canvas = Image.new("RGBA", (w, h), (34, 90, 48, 255))
    # Checker grass hint
    draw = ImageDraw.Draw(canvas)
    cell = 8 * scale
    for yy in range(0, h, cell):
        for xx in range(0, w, cell):
            if ((xx // cell) + (yy // cell)) % 2 == 0:
                draw.rectangle((xx, yy, xx + cell - 1, yy + cell - 1), fill=(40, 110, 55, 255))

    cx, cy, cw, ch = CLOUD
    cloud_r = cloud.resize((int(cw * scale), int(ch * scale)), Image.NEAREST)
    canvas.alpha_composite(cloud_r, (int(cx * scale), int(cy * scale)))

    px, py, pw, ph = NAMEPLATE
    plate_r = plate.resize((int(pw * scale), int(ph * scale)), Image.NEAREST)
    # White plate → sex tint
    tinted = Image.new("RGBA", plate_r.size, NAME_BG)
    tinted.putalpha(plate_r.split()[3])
    canvas.alpha_composite(tinted, (int(px * scale), int(py * scale)))

    # Center "Cheri" in nameplate (ANIMAL_NAME_LEN*9 slot centres inside plate).
    name = "Cheri"
    name_w = sum(max(1, FONT_CHAR_W - FONT_OFFSETS[ord(c)]) for c in name)
    name_x = px + (pw - name_w) * 0.5
    name_y = py + (ph - FONT_CHAR_H) * 0.5
    _blit_text(canvas, atlas, name, (name_x, name_y), NAME_FG, scale=scale)

    bx, by = BODY_ORIGIN
    for i, line in enumerate(TEXT):
        _blit_text(canvas, atlas, line, (bx, by + i * LINE_PITCH), BODY_FG, scale=scale)

    # Continue arrow (down triangle)
    ax, ay, aw, ah = ARROW
    tri = [
        (int(ax * scale), int(ay * scale)),
        (int((ax + aw) * scale), int(ay * scale)),
        (int((ax + aw * 0.5) * scale), int((ay + ah) * scale)),
    ]
    ImageDraw.Draw(canvas).polygon(tri, fill=ARROW_FG)

    # Crop dialogue band
    top = int((py - 4) * scale)
    return canvas.crop((0, top, w, h))


def side_by_side() -> Path:
    ours = render(3)
    ref = Image.open(REF).convert("RGBA")
    # Scale ref dialogue region to match ours height
    # Focus on bottom dialogue of ref
    rw, rh = ref.size
    ref_crop = ref.crop((0, int(rh * 0.28), rw, rh))
    target_h = ours.height
    ratio = target_h / ref_crop.height
    ref_r = ref_crop.resize((max(1, int(ref_crop.width * ratio)), target_h), Image.NEAREST)
    gap = 12
    label_h = 28
    out = Image.new("RGBA", (ours.width + gap + ref_r.width, target_h + label_h), (20, 20, 24, 255))
    draw = ImageDraw.Draw(out)
    draw.text((8, 6), "Ours (FONT_nes + m_msg layout)", fill=(230, 230, 230, 255))
    draw.text((ours.width + gap + 8, 6), "Original capture", fill=(230, 230, 230, 255))
    out.paste(ours, (0, label_h))
    out.paste(ref_r, (ours.width + gap, label_h))
    dest = MSG_DIR / "_compare_cheri_dialogue.png"
    out.save(dest)
    ours.save(MSG_DIR / "_python_cheri_dialogue.png")
    return dest


def main() -> None:
    path = side_by_side()
    print(path)


if __name__ == "__main__":
    main()
