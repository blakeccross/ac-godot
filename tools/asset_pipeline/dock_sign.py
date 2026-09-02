"""Build the dock bulletin as a single flat billboard texture.

Retail `PORT_SIGN` reads as a 2D wood board with a pinned note. The field kanban
mesh is two quads (`write_model` paper + `obj_sign_s_model` frame). Default
`my_original` slot 2 is a registration crosshair, not scribbled text, so the
dock export composites the wood frame with a bulletin note into one MASK PNG
on the frame quad.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw

from .config import PipelineConfig
from .glb import write_glb
from .godot_import import write_import_sidecar
from .gfx import MeshPart, Vertex
from .mapfile import index_by_name, parse_map
from .rel import RelData
from .texbank import GX_CLAMP, image_png_bytes


## Frame quad from `obj_s_kanban_v[4..7]` after pipeline scale (0.001 × GX).
_FRAME_VERTS = (
    (-2.0, 0.0, 1.0),
    (2.0, 0.0, 1.0),
    (2.0, 5.416, 0.045),
    (-2.0, 5.416, 0.045),
)


def build_dock_sign(cfg: PipelineConfig) -> dict[str, Any]:
    """Write `environment/dock_sign.glb` (composite wood + bulletin billboard)."""
    wood = _load_kanban_wood(cfg)
    if wood is None:
        if not cfg.rel_path.is_file() or not cfg.map_path.is_file():
            return {"converted": 0, "error": "foresta.rel / foresta.map missing"}
        symbols = parse_map(cfg.map_path)
        by_name = index_by_name(symbols)
        rel = RelData(cfg.rel_path)
        wood = _decode_ci4_symbol(rel, by_name, "obj_s_kanban_base_tex", "obj_kanban_pal", 32, 48)
    if wood is None:
        return {"converted": 0, "error": "obj_s_kanban_base_tex / obj_kanban_pal missing"}

    composite = _composite_bulletin(wood)
    png = image_png_bytes(composite)
    part = _billboard_part(png, composite.size)
    out = cfg.godot_generated / "environment" / "dock_sign.glb"
    out.parent.mkdir(parents=True, exist_ok=True)
    write_glb(out, [part], extras={"asset_id": "dock_sign", "kind": "dock_sign_billboard"})
    write_import_sidecar(out)
    work_out = cfg.converted / "environment" / "dock_sign.glb"
    if work_out.parent != out.parent:
        work_out.parent.mkdir(parents=True, exist_ok=True)
        work_out.write_bytes(out.read_bytes())
        write_import_sidecar(work_out)
    return {"converted": 1, "output": str(out.relative_to(cfg.godot_generated))}


def _load_kanban_wood(cfg: PipelineConfig) -> Image.Image | None:
    """Prefer the pipeline-decoded `obj_s_kanban` wood PNG when present."""
    import json
    import struct

    glb = cfg.godot_generated / "environment" / "obj_s_kanban.glb"
    if not glb.is_file():
        return None
    data = glb.read_bytes()
    off = 12
    root = bin_chunk = None
    while off < len(data):
        length, ctype = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off : off + length]
        off += length
        if ctype == 0x4E4F534A:
            root = json.loads(chunk)
        elif ctype == 0x004E4942:
            bin_chunk = chunk
    if root is None or bin_chunk is None:
        return None
    for img, mat in zip(root.get("images", []), root.get("materials", [])):
        name = str(mat.get("name", "")).lower()
        if "kanban_base" not in name and "base_tex" not in name:
            continue
        bv = root["bufferViews"][img["bufferView"]]
        start = bv.get("byteOffset", 0)
        png = bin_chunk[start : start + bv["byteLength"]]
        from io import BytesIO

        return Image.open(BytesIO(png)).convert("RGBA")
    ## Fallback: second image is usually the 32×48 wood frame.
    images = root.get("images", [])
    if len(images) >= 2:
        bv = root["bufferViews"][images[1]["bufferView"]]
        start = bv.get("byteOffset", 0)
        from io import BytesIO

        im = Image.open(BytesIO(bin_chunk[start : start + bv["byteLength"]])).convert("RGBA")
        if im.size == (32, 48):
            return im
    return None


def bulletin_paper_image(size: int = 32) -> Image.Image:
    """White note + red tack + scribbled lines (reference dock bulletin)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ## Paper inset leaves a wood margin when composited onto the board face.
    d.rectangle([1, 1, size - 2, size - 3], fill=(255, 255, 255, 255))
    ## Red tack at top center.
    cx = size // 2
    d.rectangle([cx - 1, 0, cx + 1, 2], fill=(220, 40, 40, 255))
    img.putpixel((cx, 1), (180, 20, 20, 255))
    ink = (40, 40, 80, 255)
    ## Three irregular scribble rows (reference: short dashed lines of text).
    rows = (
        ((5, 8), (10, 14), (16, 20), (22, 26)),
        ((6, 11), (13, 18), (20, 25)),
        ((7, 12), (14, 19), (21, 25)),
    )
    y0 = 8
    for row in rows:
        for x0, x1 in row:
            d.rectangle([x0, y0, x1, y0 + 1], fill=ink)
        y0 += 4
    for p in ((11, 9), (16, 13), (9, 17), (21, 17)):
        if 0 <= p[0] < size and 0 <= p[1] < size:
            img.putpixel(p, ink)
    return img


def _composite_bulletin(wood: Image.Image) -> Image.Image:
    """Paste the note onto the board face of the 32×48 wood frame texture."""
    out = wood.convert("RGBA")
    paper = bulletin_paper_image(32)
    ## Keep orange cap, plank margins, and posts visible around the note.
    board_w, board_h = 16, 18
    paper_r = paper.resize((board_w, board_h), Image.NEAREST)
    ox = (out.width - board_w) // 2
    oy = 11
    out.alpha_composite(paper_r, (ox, oy))
    return out


def _billboard_part(png: bytes, size: tuple[int, int]) -> MeshPart:
    w, h = size
    verts: list[Vertex] = []
    ## UVs: V flips so texture top (orange cap) maps to +Y.
    uvs = ((0.0, 1.0), (1.0, 1.0), (1.0, 0.0), (0.0, 0.0))
    for (x, y, z), (u, v) in zip(_FRAME_VERTS, uvs):
        verts.append(
            Vertex(
                x=x,
                y=y,
                z=z,
                s=0.0,
                t=0.0,
                r=1.0,
                g=1.0,
                b=1.0,
                a=1.0,
                u=u,
                v=v,
                nx=0.0,
                ny=0.0,
                nz=1.0,
            )
        )
    return MeshPart(
        name="dock_sign",
        vertices=verts,
        triangles=[(0, 1, 2), (0, 2, 3)],
        texture_name="dock_sign_tex",
        texture_png=png,
        tex_width=w,
        tex_height=h,
        wrap_s=GX_CLAMP,
        wrap_t=GX_CLAMP,
        alpha_mode="MASK",
    )


def _decode_ci4_symbol(
    rel: RelData,
    by_name: dict,
    tex_name: str,
    pal_name: str,
    width: int,
    height: int,
) -> Image.Image | None:
    tex_sym = by_name.get(tex_name)
    pal_sym = by_name.get(pal_name)
    if tex_sym is None or pal_sym is None:
        return None
    tex = rel.slice_at(tex_sym.address, tex_sym.size)
    pal = rel.slice_at(pal_sym.address, pal_sym.size)
    needed = width * height // 2
    if len(tex) < needed or len(pal) < 32:
        return None
    img = Image.new("RGBA", (width, height))
    px = img.load()
    i = 0
    for y in range(height):
        for x in range(0, width, 2):
            byte = tex[i]
            i += 1
            for n, xi in enumerate((x, x + 1)):
                idx = (byte >> 4) if n == 0 else (byte & 0xF)
                word = (pal[idx * 2] << 8) | pal[idx * 2 + 1]
                if word & 0x8000:
                    r = ((word >> 10) & 0x1F) * 255 // 31
                    g = ((word >> 5) & 0x1F) * 255 // 31
                    b = (word & 0x1F) * 255 // 31
                    a = 255
                else:
                    a = ((word >> 12) & 0x7) * 255 // 7
                    r = ((word >> 8) & 0xF) * 255 // 15
                    g = ((word >> 4) & 0xF) * 255 // 15
                    b = (word & 0xF) * 255 // 15
                px[xi, y] = (r, g, b, a)
    return img
