from __future__ import annotations

import io
import re
import struct
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Optional

from PIL import Image

from .bti import CI4, CI8, I4, I8, IA4, IA8, RGB5A3, RGBA8, _rgb5a3, decode_gx_image, decode_linear_rgba5551
from .mapfile import MapSymbol, index_by_name
from .rel import RelData

if TYPE_CHECKING:
    from .achd import AchdPack

# GBI
G_IM_FMT_RGBA = 0
G_IM_FMT_CI = 2
G_IM_FMT_IA = 3
G_IM_FMT_I = 4
G_IM_SIZ_4b = 0
G_IM_SIZ_8b = 1
G_IM_SIZ_16b = 2
G_IM_SIZ_32b = 3

GX_CLAMP = 0
GX_REPEAT = 1
GX_MIRROR = 2

GLTF_CLAMP = 33071
GLTF_REPEAT = 10497
GLTF_MIRROR = 33648


def wrap_to_gltf(mode: int) -> int:
    if mode == GX_REPEAT:
        return GLTF_REPEAT
    if mode == GX_MIRROR:
        return GLTF_MIRROR
    return GLTF_CLAMP


def gbi_to_gx(fmt: int, siz: int) -> int:
    if fmt == G_IM_FMT_CI and siz == G_IM_SIZ_4b:
        return CI4
    if fmt == G_IM_FMT_CI and siz == G_IM_SIZ_8b:
        return CI8
    if fmt == G_IM_FMT_I and siz == G_IM_SIZ_4b:
        return I4
    if fmt == G_IM_FMT_I and siz == G_IM_SIZ_8b:
        return I8
    # Dolphin/N64 IA sizes are bits-per-texel; GX names differ by one step:
    # G_IM_SIZ_8b IA (I4+A4) → GX IA4; G_IM_SIZ_16b IA (I8+A8) → GX IA8.
    if fmt == G_IM_FMT_IA and siz == G_IM_SIZ_4b:
        return IA4
    if fmt == G_IM_FMT_IA and siz == G_IM_SIZ_8b:
        return IA4
    if fmt == G_IM_FMT_IA and siz == G_IM_SIZ_16b:
        return IA8
    if fmt == G_IM_FMT_RGBA and siz == G_IM_SIZ_16b:
        return RGB5A3
    if fmt == G_IM_FMT_RGBA and siz == G_IM_SIZ_32b:
        return RGBA8
    return CI4


def image_byte_size(width: int, height: int, siz: int) -> int:
    bpp = {G_IM_SIZ_4b: 4, G_IM_SIZ_8b: 8, G_IM_SIZ_16b: 16, G_IM_SIZ_32b: 32}.get(siz, 4)
    return max(1, (width * height * bpp) // 8)


def palette_from_rgb5a3(blob: bytes) -> list[tuple[int, int, int, int]]:
    colors: list[tuple[int, int, int, int]] = []
    for i in range(0, len(blob) - 1, 2):
        colors.append(_rgb5a3(int.from_bytes(blob[i : i + 2], "big")))
    return colors


def revive_stained_glass_alpha(image: Image.Image) -> Image.Image:
    """Museum/tailor `*_mado*` CI uses RGB5A3 glass colors with A=0 (clear in TMEM).

    XLU stained glass still needs those RGBs visible in Godot; boost coverage so
    panes read as translucent color instead of empty holes. Lead/came (dark
    opaque browns) stay unchanged.
    """
    img = image.convert("RGBA")
    pixels = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a < 8 and (r > 16 or g > 16 or b > 16):
                pixels[x, y] = (r, g, b, 220)
    return img


def apply_prim(image: Image.Image, prim: tuple[int, int, int, int]) -> Image.Image:
    """Modulate texel RGB by G_SETPRIMCOLOR (TEXEL * PRIM), as the game combiner does."""
    pr, pg, pb, pa = prim
    if pr == pg == pb == 255 and pa == 255:
        return image
    r, g, b, a = image.convert("RGBA").split()
    r = r.point(lambda v, p=pr: v * p // 255)
    g = g.point(lambda v, p=pg: v * p // 255)
    b = b.point(lambda v, p=pb: v * p // 255)
    a = a.point(lambda v, p=pa: v * p // 255)
    return Image.merge("RGBA", (r, g, b, a))


def image_png_bytes(image: Image.Image) -> bytes:
    buf = io.BytesIO()
    image.save(buf, format="PNG")
    return buf.getvalue()


def i4_png_as_alpha(png: bytes) -> bytes:
    """I4 is baked as grayscale RGB with opaque A. Window spill uses I × LOD as alpha."""
    image = Image.open(io.BytesIO(png)).convert("RGBA")
    r, _g, _b, _a = image.split()
    white = Image.new("L", image.size, 255)
    return image_png_bytes(Image.merge("RGBA", (white, white, white, r)))


def bake_beach_wet_png(
    png: bytes,
    prim: tuple[int, int, int, int],
    env: tuple[int, int, int] = (144, 128, 96),
) -> bytes:
    """Bake `(PRIM-ENV)*I+ENV` into RGB; keep I in alpha for the runtime env pulse.

    Open-ocean beachB clamps V onto a solid-white I row (→ PRIM blue). Wet-sand
    beachA is mostly black I (→ ENV brown). Multiplying DL prim by I4 in
    baseColorFactor made that wet strip jet black — wrong vs decomp.
    """
    image = Image.open(io.BytesIO(png)).convert("RGBA")
    pr, pg, pb, _pa = prim
    er, eg, eb = env
    out = Image.new("RGBA", image.size)
    px_in = image.load()
    px_out = out.load()
    for y in range(image.size[1]):
        for x in range(image.size[0]):
            intensity = int(px_in[x, y][0])
            t = intensity / 255.0
            px_out[x, y] = (
                int(round(er + (pr - er) * t)),
                int(round(eg + (pg - eg) * t)),
                int(round(eb + (pb - eb) * t)),
                intensity,
            )
    return image_png_bytes(out)


def alpha_mode_for_image(image: Image.Image) -> str:
    """glTF alphaMode from a decoded RGBA image: cutout CI leaves → MASK, soft IA → BLEND."""
    alpha = image.convert("RGBA").getchannel("A")
    hist = alpha.histogram()
    total = image.size[0] * image.size[1]
    if hist[255] >= total:
        return "OPAQUE"
    if hist[0] + hist[255] >= total:
        return "MASK"
    return "BLEND"


def alpha_mode_for_png(png: bytes | None) -> str:
    """glTF alphaMode from PNG: cutout CI leaves → MASK, soft IA → BLEND."""
    if not png:
        return "OPAQUE"
    return alpha_mode_for_image(Image.open(io.BytesIO(png)))


# Decomp `structure_pal.c`: Japanese mesh prefixes vs English palette symbols.
_STRUCTURE_PALETTE_ALIASES = {
    "yubinkyoku": "post_office",
    "kouban": "police_box",
}

## Museum wall canvases (`obj_art*_art_tex`) use different CI4 than house FTR
## (`int_sum_art*` / `int_ike_art*`). ACHD indexes the house hashes — fall back so
## museum displays get the same HD painting instead of native 32×48 CI4.
_MUSEUM_ART_HOUSE_TWIN: dict[str, tuple[str, str]] = {
    "obj_art01_art_tex": ("int_sum_art01_monariza_tex", "int_sum_art01_pal"),
    "obj_art04_art_tex": ("int_sum_art04_binas_tex", "int_sum_art04_pal"),
    "obj_art05_art_tex": ("int_sum_art05_himawari_tex", "int_sum_art05_pal"),
    "obj_art06_art_tex": ("int_sum_art06_ochiba_tex", "int_sum_art06_pal"),
    "obj_art08_art_tex": ("int_sum_art08_odoriko_tex", "int_sum_art08_pal"),
    "obj_art09_art_tex": ("int_sum_art09_seurat_tex", "int_sum_art09_pal"),
    "obj_art10_art_tex": ("int_sum_art10_rautrec_tex", "int_sum_art10_pal"),
    "obj_art11_art_tex": ("int_sum_art11_kiss_tex", "int_sum_art11_pal"),
    "obj_art12_art_tex": ("int_sum_art12_manet_tex", "int_sum_art12_pal"),
    "obj_art13_art_tex": ("int_sum_art13_cezanne_tex", "int_sum_art13_pal"),
    "obj_art14_art_tex": ("int_sum_art14_gogyan_tex", "int_sum_art14_pal"),
    "obj_art15_art_tex": ("int_sum_art15_megami_tex", "int_sum_art15_pal"),
    "obj_art_ang_art_tex": ("int_ike_art_ang_tex", "int_ike_art_ang_pal"),
    "obj_art_sya_art_tex": ("int_ike_art_sya_tex", "int_ike_art_sya_pal"),
    "obj_art_fel_art_tex": ("int_ike_art_fel1_tex", "int_ike_art_fel_pal"),
}

## Museum frames + nameplates share CI4 with the canvas on `obj_art01`/`04`… style
## DLs. After ACHD replaces the canvas, that TLUT reads as neon on plate texels.
## Prefer house wood-tone pals for sum frames/names. Ike museum models (`ang` /
## `sya` / `fel`) keep a separate `*_etc_pal` for name+gaku — use that, not the
## canvas `*_art_pal` / house `int_ike_art_*_pal`.
_MUSEUM_PLATE_PAL: dict[str, str] = {
    "obj_art01_gaku_tex": "int_sum_art01_pal",
    "obj_art01_name_tex": "int_sum_art01_pal",
    "obj_art04_gaku_tex": "int_sum_art04_pal",
    "obj_art04_name_tex": "int_sum_art04_pal",
    "obj_art05_gaku_tex": "int_sum_art05_pal",
    "obj_art05_name_tex": "int_sum_art05_pal",
    "obj_art06_gaku_tex": "int_sum_art06_pal",
    "obj_art06_name_tex": "int_sum_art06_pal",
    "obj_art08_gaku_tex": "int_sum_art08_pal",
    "obj_art08_name_tex": "int_sum_art08_pal",
    "obj_art09_gaku_tex": "int_sum_art09_pal",
    "obj_art09_name_tex": "int_sum_art09_pal",
    "obj_art10_gaku_tex": "int_sum_art10_pal",
    "obj_art10_name_tex": "int_sum_art10_pal",
    "obj_art11_gaku_tex": "int_sum_art11_pal",
    "obj_art11_name_tex": "int_sum_art11_pal",
    "obj_art12_gaku_tex": "int_sum_art12_pal",
    "obj_art12_name_tex": "int_sum_art12_pal",
    "obj_art13_gaku_tex": "int_sum_art13_pal",
    "obj_art13_name_tex": "int_sum_art13_pal",
    "obj_art14_gaku_tex": "int_sum_art14_pal",
    "obj_art14_name_tex": "int_sum_art14_pal",
    "obj_art15_gaku_tex": "int_sum_art15_pal",
    "obj_art15_name_tex": "int_sum_art15_pal",
    "obj_art_ang_gaku_tex": "obj_art_ang_etc_pal",
    "obj_art_ang_name_tex": "obj_art_ang_etc_pal",
    "obj_art_sya_gaku_tex": "obj_art_sya_etc_pal",
    "obj_art_sya_name_tex": "obj_art_sya_etc_pal",
    "obj_art_fel_gaku_tex": "obj_art_fel_etc_pal",
    "obj_art_fel_name_tex": "obj_art_fel_etc_pal",
}


def museum_art_house_twin(tex_name: str) -> tuple[str, str] | None:
    """House FTR (tex, pal) twin for a museum canvas symbol, if any."""
    return _MUSEUM_ART_HOUSE_TWIN.get(tex_name)


def museum_gaku_house_palette(tex_name: str) -> str | None:
    """Palette symbol for a museum frame / nameplate (`*_gaku_tex` / `*_name_tex`)."""
    return _MUSEUM_PLATE_PAL.get(tex_name)


def is_museum_plate_texture(tex_name: str) -> bool:
    """Donated-art nameplates/frames stay native CI4 — ACHD false-hits scrap boards.

    Empty-frame `obj_art_dummy*` are excluded: most ship neon CI4 in REL and need
    ACHD or the dummy03 wood twin instead.
    """
    if not tex_name.startswith("obj_art") or "dummy" in tex_name:
        return False
    return tex_name.endswith("_name_tex") or tex_name.endswith("_gaku_tex")


def is_indoor_mado_texture(tex_name: str) -> bool:
    """Indoor stained-glass / window CI (`*_mado*_tex`). ACHD hits unrelated red sheets."""
    return "_mado" in tex_name


def is_house_clock_texture(tex_name: str) -> bool:
    """`HOUSE_CLOCK` RGBA16 sheets. ACHD swaps wrong sizes and breaks wrap/UVs."""
    return tex_name.startswith("obj_clock_")


def is_museum_clock_texture(tex_name: str) -> bool:
    """`obj_clock_museum1_*` is N64 linear RGBA5551, not GX-tiled RGB5A3."""
    return tex_name.startswith("obj_clock_museum1_")


def skips_achd_texture(tex_name: str) -> bool:
    """Textures whose Dolphin hashes collide with unrelated ACHD sheets."""
    return (
        is_museum_plate_texture(tex_name)
        or is_indoor_mado_texture(tex_name)
        or is_house_clock_texture(tex_name)
    )


def house_clock_alpha_mode(tex_name: str, fallback: str) -> str:
    """Body DLs are `OPA_SURF` (ignore texel A); hands are `TEX_EDGE` cutouts."""
    if not is_house_clock_texture(tex_name):
        return fallback
    if "hari" in tex_name:
        return "MASK"
    return "OPAQUE"


def museum_dummy_wood_twin(tex_name: str) -> tuple[str, str] | None:
    """Map neon empty-frame CI4 to `obj_art_dummy03` wood (tex, pal).

    dummy03 is the only empty-frame bank whose REL palette is wood-tone and
    whose ACHD hashes resolve; other dummies share a green/magenta CI4 bank.
    """
    if not tex_name.startswith("obj_art_dummy") or tex_name.startswith("obj_art_dummy03"):
        return None
    for suf in ("_name_tex", "_back_tex", "_tex"):
        if tex_name.endswith(suf):
            return (f"obj_art_dummy03{suf}", "obj_art_dummy03_pal")
    return None


def structure_palette_names(prefix: str) -> list[str]:
    """Candidate `structure_pal` symbols for a cKF/static structure prefix.

    Shop keeps its stage digit (`obj_shop1_pal`). Player house drops it
    (`obj_s_myhome1` → `obj_s_myhome_a_pal`). Post office is an alias
    (`obj_s_yubinkyoku` → `obj_s_post_office_pal` / winter `*_winter_pal`).
    """
    names: list[str] = []

    def add(*cands: str) -> None:
        for name in cands:
            if name and name not in names:
                names.append(name)

    add(f"{prefix}_a_pal", f"{prefix}_pal")
    m = re.match(r"^obj_([swf])_(.+)$", prefix)
    if not m:
        return names
    season, rest = m.group(1), m.group(2)
    add(f"obj_{rest}_pal", f"obj_{rest}_a_pal")
    destaged = re.sub(r"\d+$", "", rest)
    if destaged and destaged != rest:
        add(
            f"obj_{season}_{destaged}_a_pal",
            f"obj_{season}_{destaged}_pal",
            f"obj_{destaged}_pal",
            f"obj_{destaged}_a_pal",
        )
    alias = _STRUCTURE_PALETTE_ALIASES.get(rest) or _STRUCTURE_PALETTE_ALIASES.get(destaged)
    if alias:
        add(f"obj_{season}_{alias}_pal", f"obj_{season}_{alias}_a_pal", f"obj_s_{alias}_pal", f"obj_{alias}_pal")
        if season == "w":
            add(f"obj_s_{alias}_winter_pal", f"obj_{alias}_winter_pal")
    return names


# Runtime gSPSegment banks (`anime_1_txt`…`anime_6_txt`). DLs store dummy
# SEGMENT_ADDR values; the actor binds a real pal/tex before draw.
ANIME_TXT_SEGMENTS = frozenset(range(0x08, 0x10))

## Authored field-sign note (white + red tack + scribbles). Retail `my_original`
## slot 2 is a registration crosshair — do not bake that design onto field signs.
KANBAN_DEFAULT_DESIGN_SLOT = 2
KANBAN_DEFAULT_PALETTE_IDX = 7
MY_ORIGINAL_DESIGN_BYTES = 512
MY_ORIGINAL_REL_PATH = Path("forest_2nd/data/my_original.bin")


def _set_rgb555(pal: bytearray, idx: int, r: int, g: int, b: int) -> None:
    r5 = r * 31 // 255
    g5 = g * 31 // 255
    b5 = b * 31 // 255
    ## Game palettes are RGB555 (`0x8000`); without it `_rgb5a3` treats entries as
    ## RGB5A3 and ink indices decode near-transparent.
    word = 0x8000 | (r5 << 10) | (g5 << 5) | b5
    pal[idx * 2] = (word >> 8) & 0xFF
    pal[idx * 2 + 1] = word & 0xFF


def _kanban_bulletin_palette(base: bytes) -> bytes:
    """Remap CI indices to bulletin colors on export.

    Bulletin paper CI4 uses indices 5 (paper), 7 (tack), 8 (ink).
    """
    pal = bytearray(base[:32] if len(base) >= 32 else bytes(32))
    _set_rgb555(pal, 5, 255, 255, 255)
    _set_rgb555(pal, 7, 220, 40, 40)
    _set_rgb555(pal, 8, 40, 40, 80)
    return bytes(pal)


def bulletin_paper_image(size: int = 32):
    """White note + red tack + scribbled lines for field `SIGNBOARD` paper."""
    from PIL import Image, ImageDraw

    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([1, 1, size - 2, size - 3], fill=(255, 255, 255, 255))
    cx = size // 2
    d.rectangle([cx - 1, 0, cx + 1, 2], fill=(220, 40, 40, 255))
    img.putpixel((cx, 1), (180, 20, 20, 255))
    ink = (40, 40, 80, 255)
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


def encode_bulletin_paper_ci4() -> tuple[bytes, bytes]:
    """32×32 CI4 tex + RGB555 palette for field-sign note paper."""
    img = bulletin_paper_image(32).convert("RGBA")
    pal = bytearray(32)
    ## idx 0 = transparent hole (unused on opaque paper quad)
    _set_rgb555(pal, 0, 0, 0, 0)
    _set_rgb555(pal, 5, 255, 255, 255)
    _set_rgb555(pal, 7, 220, 40, 40)
    _set_rgb555(pal, 8, 40, 40, 80)
    tex = bytearray(32 * 32 // 2)
    px = img.load()
    i = 0
    for y in range(32):
        for x in range(0, 32, 2):
            idxs: list[int] = []
            for xi in (x, x + 1):
                r, g, b, a = px[xi, y]
                if a < 128:
                    idxs.append(0)
                elif r > 200 and g < 80 and b < 80:
                    idxs.append(7)
                elif r < 80 and g < 80 and b < 120:
                    idxs.append(8)
                else:
                    idxs.append(5)
            tex[i] = ((idxs[0] & 0xF) << 4) | (idxs[1] & 0xF)
            i += 1
    return bytes(tex), bytes(pal)


_SYMBOL_STOPWORDS = frozenset(
    {
        "obj",
        "s",
        "w",
        "f",
        "e",
        "c",
        "r",
        "model",
        "gfx",
        "mat",
        "txt",
        "tex",
        "pal",
        "pic",
        "i4",
        "i8",
        "ia4",
        "ia8",
        "ta",
        "dl",
        "mode",
        "v",
        "ckf",
        "bs",
        "ba",
        "je",
        "tbl",
    }
)
_PLANT_PARTS = frozenset({"leaf", "trunk", "cedar", "palm", "flower", "tree", "stump"})
_GENERIC_LEAF_PARTS = frozenset({"leaf", "trunk"})


def symbol_tokens(name: str) -> set[str]:
    """Distinctive tokens from a REL symbol or Gfx name (drop obj/season/tex/model)."""
    split = re.sub(r"([a-z])([A-Z])", r"\1_\2", name)
    split = re.sub(r"([A-Za-z])(\d)", r"\1_\2", split)
    split = re.sub(r"(\d)([A-Za-z])", r"\1_\2", split)
    out: set[str] = set()
    for part in re.split(r"[^a-zA-Z0-9]+", split.lower()):
        if not part or part in _SYMBOL_STOPWORDS or part.isdigit() or len(part) < 2:
            continue
        if re.fullmatch(r"t\d+", part):
            continue
        out.add(part)
    return out


def season_of_prefix(prefix: str) -> str:
    m = re.match(r"^(?:obj|grd)_([swf])_", prefix)
    return m.group(1) if m else ""


## Representative `tree_pal_idx_table` / field rows for baked seasonal converts.
## Mid-season picks: summer term~7 → 3, autumn term~12 → 7, winter term~0 → 10.
_TREE_PAL_ROW_BY_SEASON = {"s": 3, "f": 7, "w": 10}
_FIELD_PAL_ROW_BY_SEASON = {"s": 2, "f": 6, "w": 9}


def gfx_part_tokens(prefix: str, gfx: str) -> set[str]:
    """Tokens after the object prefix: `obj_s_shrine_leaf_model` → {leaf}."""
    gl, pl = gfx.lower(), prefix.lower()
    if pl and gl.startswith(pl):
        rest = gfx[len(prefix) :].lstrip("_")
    else:
        rest = gfx
    rest = re.sub(r"(_gfx)?_model$", "", rest, flags=re.IGNORECASE)
    return symbol_tokens(rest)


def dummy_name_score(symbol_name: str, part: set[str], prefix_toks: set[str]) -> int:
    """Rank a REL tex/pal as a stand-in for an unbound anime segment."""
    name_toks = symbol_tokens(symbol_name)
    part_hits = name_toks & part
    if part and not part_hits:
        return 0
    prefix_hits = name_toks & prefix_toks
    if not part_hits and not prefix_hits:
        return 0
    score = 0
    if part_hits:
        score += 10 * len(part_hits)
        if part and part <= name_toks:
            score += 5
    score += len(prefix_hits)
    return score


def dummy_palette_score(symbol_name: str, part: set[str], prefix_toks: set[str]) -> int:
    """Like dummy_name_score, but the pal must belong to the same object family.

    Generic part words (`front`, `door`, `light`, `leaf`) hit furniture and UI
    pals across the REL. Using those as `anime_1_txt` overwrites the structure
    TLUT and recolors the whole house/shop.
    """
    if prefix_toks and not (symbol_tokens(symbol_name) & prefix_toks):
        return 0
    return dummy_name_score(symbol_name, part, prefix_toks)


def is_image_symbol(name: str) -> bool:
    if name.startswith("cKF_") or name.startswith("."):
        return False
    lower = name.lower()
    if lower.endswith(("_pal", "_model", "_v")):
        return False
    return "_tex" in lower or lower.endswith("_txt") or "_pic_" in lower


def decode_gbi_texture(
    data: bytes,
    width: int,
    height: int,
    fmt: int,
    siz: int,
    palette_blob: bytes | None,
) -> Image.Image:
    palette = palette_from_rgb5a3(palette_blob) if palette_blob else None
    gx = gbi_to_gx(fmt, siz)
    needed = image_byte_size(width, height, siz)
    if len(data) < needed:
        data = data + bytes(needed - len(data))
    return decode_gx_image(data[:needed], width, height, gx, palette)


@dataclass
class SegmentTex:
    data: bytes
    width: int
    height: int
    fmt: int = G_IM_FMT_CI
    siz: int = G_IM_SIZ_4b
    palette: bytes | None = None


## Dolphin `gsDPLoadTLUT_Dolphin` sets bits 22–23 to this (`G_TLUT_DOLPHIN`).
G_TLUT_DOLPHIN = 2


@dataclass
class TextureState:
    palettes: dict[int, bytes] = field(default_factory=dict)
    img_addr: int = 0
    fmt: int = G_IM_FMT_CI
    siz: int = G_IM_SIZ_4b
    ## Texel image size from G_SETTIMG (what we decode).
    width: int = 0
    height: int = 0
    ## Tile size from G_SETTILESIZE (HW wrap bounds). Kept separate from width so
    ## boy shirts (32×32 image, 128×32 tile) decode without zero-pad MASK holes.
    ## UVs still divide by the SETTIMG image size; REPEAT is baked in glb.py.
    tile_w: int = 0
    tile_h: int = 0
    pal_slot: int = 15
    ## Classic G_SETTILE TMEM word. `gsDPLoadTLUT_pal16` stores the slot as
    ## `256 + pal * 16` here; the following G_LOADTLUT command does not.
    tmem: int = 0
    wrap_s: int = GX_CLAMP
    wrap_t: int = GX_CLAMP
    prim: tuple[int, int, int, int] = (255, 255, 255, 255)
    ## Dual-tile water (river water1+water2, ocean wave1+wave2/3): snapshot on
    ## G_SETTILE_DOLPHIN tile 0 / tile 1 before the next SETTIMG overwrites img_addr.
    tile0: dict | None = None
    tile1: dict | None = None


class TextureBank:
    """Resolve SETTIMG / LOADTLUT addresses to decoded PNGs."""

    def __init__(
        self,
        rel: RelData,
        symbols: list[MapSymbol],
        archives: Path | None = None,
        achd: Optional["AchdPack"] = None,
    ) -> None:
        self.rel = rel
        self.symbols = symbols
        self.archives = archives
        self.achd = achd
        self.by_name = index_by_name(symbols)
        self.addr_to_sym: dict[int, MapSymbol] = {}
        self._pal_symbols: list[MapSymbol] = []
        for symbol in symbols:
            existing = self.addr_to_sym.get(symbol.address)
            if existing is None or symbol.name[0] != ".":
                self.addr_to_sym[symbol.address] = symbol
            if symbol.name.endswith("_pal") and symbol.size >= 32:
                self._pal_symbols.append(symbol)
        self._pal_symbols.sort(key=lambda s: s.address)
        self._image_symbols: list[MapSymbol] = [
            s for s in symbols if is_image_symbol(s.name) and s.size > 0
        ]
        self.segment_images: dict[int, SegmentTex] = {}
        self.segment_palettes: dict[int, bytes] = {}
        self._segment_offset_names: dict[int, dict[int, str]] = {}
        self._png_cache: dict[tuple, tuple[bytes, str]] = {}
        self.current_prefix = ""
        self.current_gfx = ""
        self._tree_pal: bytes | None = None
        for symbol in symbols:
            if symbol.name == "obj_tree_pal":
                self._tree_pal = rel.slice_at(symbol.address, min(symbol.size, 32))
                break
        # Runtime FG TLUTs (`mFM_SetFGPal`). Static DLs set pal_slot 6/7 but never LOADTLUT.
        # 14 seasonal rows × 16 RGB5A3; row 4 is a mid-year green (`tree_pal_idx_table`).
        # The map's `mFM_obj_tree_01_pal` blob does not CI-decode leaf/trunk art (pastel
        # garbage). `mFM_obj_tree_01_pal_dol` and museum `obj_tree_pal` do — use those.
        self._tree_fg_pal = self._fg_pal_row("mFM_obj_tree_01_pal_dol") or self._tree_pal
        self._cedar_pal = self._fg_pal_row("mFM_obj_tree_01_pal_dol") or self._tree_fg_pal
        self._palm_pal = self._fg_pal_row("mFM_obj_palm_01_pal")
        self._flower_pal = self._fg_pal_row("mFM_obj_a_01_flower_pal")
        ## Hole DLs SETTILE pal_slot 4/5 and never LOADTLUT. `bg_item` binds
        ## `obj_g_hole_pal` / `obj_b_hole_pal` (`bIT_PAL_HOLE_G` / `_S`).
        self._hole_g_pal = self._symbol_bytes("obj_g_hole_pal")
        self._hole_s_pal = self._symbol_bytes("obj_b_hole_pal")

    def _apply_seasonal_fg_pals(self, prefix: str) -> None:
        """Pick term-representative FG palette rows for the mesh season infix."""
        season = season_of_prefix(prefix) or "s"
        row = _TREE_PAL_ROW_BY_SEASON.get(season, 4)
        self._tree_fg_pal = self._fg_pal_row("mFM_obj_tree_01_pal_dol", row) or self._tree_pal
        self._cedar_pal = self._fg_pal_row("mFM_obj_tree_01_pal_dol", row) or self._tree_fg_pal
        self._palm_pal = self._fg_pal_row("mFM_obj_palm_01_pal", row)
        flower_row = {"s": 1, "f": 5, "w": 8}.get(season, 1)
        self._flower_pal = self._fg_pal_row("mFM_obj_a_01_flower_pal", flower_row)

    def bind_field_bg(self, season: str = "s", variant: int = 0, *, pal_row: int | None = None) -> None:
        """Map acre/field segment 0x80 from l_bg_tex_segment_rom_start_* tables.

        Display lists address grass/earth/cliff/… as 0x80xxxxxx dummies; the game
        DMA's the seasonal bank there at runtime. We materialize that bank in-memory.
        Winter uses `l_bg_tex_segment_rom_start_w_*` (`mFM_LoadBGCommonTex`).
        """
        table = f"l_bg_tex_segment_rom_start_{season}_{variant}"
        common_sym = self._find_symbol("l_bg_tex_common_dummy")
        rom_sym = self._find_symbol(table)
        if common_sym is None or rom_sym is None:
            return
        common = self.rel.slice_at(common_sym.address, common_sym.size)
        rom = self.rel.slice_at(rom_sym.address, rom_sym.size)
        n = min(len(common) // 8, len(rom) // 4)
        mem = bytearray(0x9000)
        names: dict[int, str] = {}
        for i in range(n):
            seg_addr, entry_size = struct.unpack_from(">II", common, i * 8)
            ptr = struct.unpack_from(">I", rom, i * 4)[0]
            if (seg_addr >> 24) != 0x80:
                continue
            off = seg_addr & 0xFFFFFF
            src = self.addr_to_sym.get(ptr)
            if src is None or src.size <= 0:
                continue
            nbytes = src.size if entry_size == 0 else min(src.size, entry_size)
            try:
                data = self.rel.slice_at(src.address, nbytes)
            except ValueError:
                continue
            end = off + len(data)
            if end > len(mem):
                mem.extend(bytes(end - len(mem)))
            mem[off : off + len(data)] = data
            names[off] = src.name

        pal_common = self._find_symbol("l_bg_pal_common_dummy")
        pal_rom = self._find_symbol("l_bg_pal_segment_rom_start")
        if pal_common is not None and pal_rom is not None:
            pc = self.rel.slice_at(pal_common.address, pal_common.size)
            pr = self.rel.slice_at(pal_rom.address, pal_rom.size)
            pn = min(len(pc) // 8, len(pr) // 4)
            ## `mFM_LoadBGCommonMonthlyPal` indexes earth/cliff/bush/rail/beach by term.
            row = _FIELD_PAL_ROW_BY_SEASON.get(season, 0) if pal_row is None else pal_row
            for i in range(pn):
                seg_addr, entry_size = struct.unpack_from(">II", pc, i * 8)
                ptr = struct.unpack_from(">I", pr, i * 4)[0]
                if (seg_addr >> 24) != 0x80:
                    continue
                off = seg_addr & 0xFFFFFF
                src = self.addr_to_sym.get(ptr)
                if src is None:
                    continue
                pal_size = min(entry_size or 32, 32)
                ## Each field pal table is 12 rows × 16 RGB5A3 (`mFM_FIELD_PAL_NUM`).
                src_off = row * pal_size
                try:
                    data = self.rel.slice_at(src.address + src_off, pal_size)
                except ValueError:
                    try:
                        data = self.rel.slice_at(src.address, pal_size)
                    except ValueError:
                        continue
                end = off + len(data)
                if end > len(mem):
                    mem.extend(bytes(end - len(mem)))
                mem[off : off + len(data)] = data
                names[off] = src.name

        self.segment_images[0x80] = SegmentTex(bytes(mem), 0, 0)
        self._segment_offset_names[0x80] = names

    def bind_player_room(
        self,
        floor_index: int = 0,
        wall_index: int = 0,
        *,
        bind_floor: bool = True,
        bind_wall: bool = True,
    ) -> None:
        """Bind player-house floor/wall CI4 tiles into segments 0x08–0x0C."""
        if self.archives is None:
            return
        data = self.archives / "forest_2nd" / "data"
        if bind_floor:
            floor_path = data / "player_room_floor.bin"
            if floor_path.is_file():
                blob = floor_path.read_bytes()
                n = len(blob) // 0x2020
                if n > 0:
                    idx = max(0, min(floor_index, n - 1))
                    base = 0x2020 * idx
                    pal = blob[base : base + 0x20]
                    self.segment_palettes[0x0C] = pal
                    for i, seg in enumerate((0x08, 0x09, 0x0A, 0x0B)):
                        tex = blob[base + 0x20 + 0x800 * i : base + 0x20 + 0x800 * (i + 1)]
                        self.segment_images[seg] = SegmentTex(tex, 64, 64, palette=pal)
                        self.segment_palettes[seg] = pal
                        self._segment_offset_names[seg] = {0: f"player_room_floor_{idx}_{i}"}
        if bind_wall:
            wall_path = data / "player_room_wall.bin"
            if wall_path.is_file():
                blob = wall_path.read_bytes()
                n = len(blob) // 0x1020
                if n > 0:
                    idx = max(0, min(wall_index, n - 1))
                    base = 0x1020 * idx
                    pal = blob[base : base + 0x20]
                    for i, seg in enumerate((0x08, 0x09)):
                        tex = blob[base + 0x20 + 0x800 * i : base + 0x20 + 0x800 * (i + 1)]
                        self.segment_images[seg] = SegmentTex(tex, 64, 64, palette=pal)
                        self.segment_palettes[seg] = pal
                        self._segment_offset_names[seg] = {0: f"player_room_wall_{idx}_{i}"}
                    self.segment_palettes.setdefault(0x0C, pal)

    def bind_static_segments(self, prefix: str) -> None:
        """Bind runtime segment banks needed by static grd_/rom_ display lists."""
        self.current_prefix = prefix
        self._apply_seasonal_fg_pals(prefix)
        if (
            prefix.startswith("grd_")
            or prefix.startswith("rom_")
            or prefix.startswith("mCL_rom_")
        ):
            season = season_of_prefix(prefix) or "s"
            ## Acre DLs only sample summer/winter CI banks (`mFM_LoadBGCommonTex`).
            if season == "f":
                season = "s"
            self.bind_field_bg(season=season)
        if (
            prefix.startswith("rom_")
            or prefix.startswith("mCL_rom_")
            or prefix in {"police_indoor", "room01"}
        ):
            is_wall = "wall" in prefix
            is_floor = "floor" in prefix
            self.bind_player_room(
                bind_floor=is_floor or not is_wall,
                bind_wall=is_wall or not is_floor,
            )
        if prefix in {"obj_s_kanban", "obj_w_kanban"}:
            self._bind_kanban_paper_segments()

    def _find_symbol(self, name: str) -> MapSymbol | None:
        return self.by_name.get(name)

    def bind_model_segments(self, prefix: str, shirt_index: int = 0) -> None:
        """Bind segment banks for any cKF prefix from REL symbols and optional archive bins.

        Same path for player, villagers, and furniture:
        - `{prefix}_pal`, `{prefix}_eye1_TA_tex_txt`, `{prefix}_mouth1_TA_tex_txt`, `{prefix}_tmem_txt`
        - archive `face_{species}.bin` / `tex_{species}.bin` / `pallet_{species}.bin` when present
          (player eyes/mouth/shirt live there; species is prefix without trailing `_N`)
        Dummy `anime_N_txt` SETTIMG/LOADTLUT (house mark, shrine leaf, …) resolve
        later from REL symbols — see `_resolve_dummy_image` / `_resolve_dummy_palette`.
        """
        self.current_prefix = prefix
        self._apply_seasonal_fg_pals(prefix)
        pal = self._symbol_bytes(f"{prefix}_pal")
        if pal is None:
            pal = self._structure_palette(prefix)
        eye1 = self._symbol_bytes(f"{prefix}_eye1_TA_tex_txt")
        mouth1 = self._symbol_bytes(f"{prefix}_mouth1_TA_tex_txt")
        tmem = self._symbol_bytes(f"{prefix}_tmem_txt")
        if pal:
            for seg in (0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0E, 0x0F):
                self.segment_palettes[seg] = pal
        if eye1:
            self.segment_images[0x08] = SegmentTex(eye1, 32, 16, palette=pal)
        if mouth1:
            self.segment_images[0x09] = SegmentTex(mouth1, 32, 16, palette=pal)
        if tmem:
            bank = SegmentTex(tmem, 0, 0, palette=pal)
            self.segment_images[0x0A] = bank
            self.segment_images[0x0B] = bank

        if self.archives is None:
            return
        species = re.sub(r"_\d+$", "", prefix)
        data = self.archives / "forest_1st" / "data"
        face_path = data / f"face_{species}.bin"
        if face_path.is_file() and 0x08 not in self.segment_images:
            face = face_path.read_bytes()
            face_pal = face[0xE00:0xE20]
            self.segment_palettes[0x0C] = face_pal
            # face_*.bin face 0: eyes 0–7 then mouths 8–13, each 32×16 CI4.
            self.segment_images[0x08] = SegmentTex(face[0:0x100], 32, 16, palette=face_pal)
            self.segment_images[0x09] = SegmentTex(face[0x800:0x900], 32, 16, palette=face_pal)
        tex_path = data / f"tex_{species}.bin"
        pal_path = data / f"pallet_{species}.bin"
        if tex_path.is_file() and pal_path.is_file() and 0x0A not in self.segment_images:
            tex_blob = tex_path.read_bytes()
            pal_blob = pal_path.read_bytes()
            n_shirts = min(len(tex_blob) // 0x200, len(pal_blob) // 0x20)
            if n_shirts <= 0:
                return
            idx = max(0, min(shirt_index, n_shirts - 1))
            shirt = tex_blob[idx * 0x200 : (idx + 1) * 0x200]
            shirt_pal = pal_blob[idx * 0x20 : (idx + 1) * 0x20]
            self.segment_palettes[0x0B] = shirt_pal
            self.segment_images[0x0A] = SegmentTex(shirt, 32, 32, palette=shirt_pal)

    def _structure_palette(self, prefix: str) -> bytes | None:
        """Houses/shops load CI palettes from `anime_1_txt` (segment 0x08), not `{prefix}_pal`.

        Decomp: `structure_pal_adrs_nowinter` — `obj_s_house1_a_pal`, `obj_shop1_pal`,
        `obj_s_myhome_a_pal` (stage digit stripped), `obj_s_post_office_pal` (yubinkyoku alias).
        """
        for name in structure_palette_names(prefix):
            blob = self._symbol_bytes(name)
            if blob:
                return blob
        return None


    def _symbol_bytes(self, name: str) -> bytes | None:
        symbol = self.by_name.get(name)
        if symbol is None or symbol.size <= 0:
            return None
        return self.rel.slice_at(symbol.address, symbol.size)

    def _size_fits(self, symbol_size: int, needed: int) -> bool:
        if symbol_size < needed:
            return False
        # 32-byte GX align padding is normal; a whole extra tile is not.
        return symbol_size - needed < 32

    def _bind_kanban_paper_segments(self) -> None:
        """Bind `write_model` anime segments for field sign export.

        `ac_sign` loads palette to ANIME_1 (seg 0x08) and texture to ANIME_2 (seg 0x09).
        Dock / default field signs use an authored bulletin note (not `my_original` slot 2).
        """
        paper_tex, paper_pal = encode_bulletin_paper_ci4()
        tex_name = "bulletin_paper_tex"
        pal_name = "bulletin_paper_pal"
        self.segment_palettes[0x08] = paper_pal
        self.segment_palettes[0x09] = paper_pal
        self.segment_images[0x09] = SegmentTex(paper_tex, 32, 32, palette=paper_pal)
        self._segment_offset_names.setdefault(0x08, {})[0] = pal_name
        self._segment_offset_names.setdefault(0x09, {})[0] = tex_name

    def _kanban_default_paper_tex(self) -> bytes | None:
        tex, _pal = encode_bulletin_paper_ci4()
        return tex

    def _kanban_default_paper_palette(self) -> bytes | None:
        _tex, pal = encode_bulletin_paper_ci4()
        return pal

    def _resolve_dummy_palette(self, seg: int) -> None:
        """Fill anime_N palettes from the current Gfx part, FG plant TLUTs, or structure pal."""
        if (
            self.current_prefix in {"obj_s_kanban", "obj_w_kanban"}
            and seg in self.segment_palettes
        ):
            return
        blob, kind = self._pick_dummy_palette()
        if blob is None:
            return
        if kind == 2:
            self.segment_palettes[seg] = blob
        elif seg not in self.segment_palettes:
            self.segment_palettes[seg] = blob

    def _pick_dummy_palette(self) -> tuple[bytes | None, int]:
        """Return (palette bytes, specificity). 2 = Gfx-part symbol, 1 = FG plant, 0 = structure."""
        part = gfx_part_tokens(self.current_prefix, self.current_gfx)
        prefix_toks = symbol_tokens(self.current_prefix)
        best: MapSymbol | None = None
        best_score = 0
        for pal in self._pal_symbols:
            score = dummy_palette_score(pal.name, part, prefix_toks)
            if score > best_score:
                best_score = score
                best = pal
        if best is not None and best_score >= 10:
            return self.rel.slice_at(best.address, min(best.size, 512)), 2
        if "hole" in prefix_toks and self._hole_g_pal:
            return self._hole_g_pal, 1
        if part & _PLANT_PARTS:
            if "palm" in part and self._palm_pal:
                return self._palm_pal, 1
            if "flower" in part and self._flower_pal:
                return self._flower_pal, 1
            fg = self._cedar_pal or self._tree_fg_pal
            if fg:
                return fg, 1
        struct_pal = self._structure_palette(self.current_prefix) or self._symbol_bytes(
            f"{self.current_prefix}_pal"
        )
        if struct_pal:
            return struct_pal, 0
        return None, 0

    def _resolve_dummy_image(self, state: TextureState) -> None:
        """Bind an unbound anime_N SETTIMG from a same-size REL texture.

        Actor draw (`gSPSegment`) supplies the real pointer. We pick a stand-in by
        matching SETTIMG byte size plus Gfx-part tokens (`leaf`, `mark`, …) so
        shrine leaves get `obj_*_tree*_leaf_tex` and house marks get
        `obj_myhome_mark_tex_txt` without a per-object map.
        """
        addr = state.img_addr
        seg = addr >> 24
        if seg not in ANIME_TXT_SEGMENTS or (addr & 0xFFFFFF):
            return
        if seg in self.segment_images:
            return
        if state.width <= 0 or state.height <= 0:
            return
        needed = image_byte_size(state.width, state.height, state.siz)
        data, name = self._pick_dummy_image(needed)
        if data is None:
            return
        pal = self.segment_palettes.get(seg)
        self.segment_images[seg] = SegmentTex(
            data, state.width, state.height, state.fmt, state.siz, pal
        )
        self._segment_offset_names.setdefault(seg, {})[0] = name

    def _pick_dummy_image(self, needed: int) -> tuple[bytes | None, str]:
        part = gfx_part_tokens(self.current_prefix, self.current_gfx)
        prefix_toks = symbol_tokens(self.current_prefix)
        season = season_of_prefix(self.current_prefix)
        # Prefix-only matches glue random same-size tiles onto dummy banks
        # (and can overwrite a palette segment). Require a Gfx part token.
        if not part:
            return None, ""

        def usable(sym: MapSymbol) -> bool:
            if not self._size_fits(sym.size, needed):
                return False
            name_toks = symbol_tokens(sym.name)
            if part:
                return bool(name_toks & part)
            return bool(name_toks & prefix_toks)

        cands = [s for s in self._image_symbols if usable(s)]
        if not cands:
            return None, ""

        def rank(sym: MapSymbol) -> int:
            score = dummy_name_score(sym.name, part, prefix_toks)
            name_toks = symbol_tokens(sym.name)
            if season and f"obj_{season}_" in sym.name:
                score += 2
            if "gold" in name_toks and "gold" not in prefix_toks and "gold" not in part:
                score -= 4
            # Unqualified leaf/trunk DLs share hardwood FG art, not cedar/palm.
            if part <= _GENERIC_LEAF_PARTS and part:
                if "tree" in name_toks:
                    score += 3
                if name_toks & {"cedar", "palm", "flower"}:
                    score -= 2
            if sym.size != needed:
                score -= 1
            return score

        best = max(cands, key=rank)
        if rank(best) <= 0:
            return None, ""
        try:
            return self.rel.slice_at(best.address, needed), best.name
        except ValueError:
            return None, ""

    def load_palette(self, addr: int, count: int) -> bytes | None:
        nbytes = max(32, count * 2)
        if addr >> 24:
            seg = addr >> 24
            off = addr & 0xFFFFFF
            if seg in ANIME_TXT_SEGMENTS and off == 0:
                self._resolve_dummy_palette(seg)
                blob = self.segment_palettes.get(seg)
                if blob:
                    return blob[:nbytes] if len(blob) >= 32 else blob
            # Field BG bank stores pals at offsets inside segment 0x80.
            seg_img = self.segment_images.get(seg)
            if seg_img is not None and off < len(seg_img.data):
                chunk = bytes(seg_img.data[off : off + nbytes])
                if len(chunk) >= 32:
                    return chunk[:nbytes]
            if off == 0:
                blob = self.segment_palettes.get(seg)
                if blob:
                    return blob
            return None
        try:
            return self.rel.slice_at(addr, nbytes)
        except ValueError:
            return None

    def decode_current(self, state: TextureState) -> tuple[bytes | None, str, str]:
        if state.width <= 0 or state.height <= 0 or state.img_addr == 0:
            return None, "", "OPAQUE"
        if state.img_addr >> 24:
            self._resolve_dummy_image(state)
        pal = self._palette_for(state)
        name = self._name_for(state.img_addr)
        key = (state.img_addr, state.width, state.height, state.fmt, state.siz, pal or b"", state.prim)
        cached = self._png_cache.get(key)
        if cached is not None:
            return cached[0], name, cached[1]
        data = self._image_bytes(state)
        if data is None:
            return None, name, "OPAQUE"
        gx = gbi_to_gx(state.fmt, state.siz)
        if self.achd is not None:
            from .achd import is_field_terrain_texture, maybe_hd_png

            ## Museum plates / indoor mado / house clocks: ACHD hash collisions swap
            ## scrap boards, red sheets, or wrong-size RGBA. Keep native below.
            if not skips_achd_texture(name) and not is_field_terrain_texture(
                name, self.current_prefix
            ):
                ## Neon empty frames: skip hashing their own CI4 (false hits / garbage
                ## natives) and take dummy03 wood ACHD or decode.
                if museum_dummy_wood_twin(name) is not None:
                    hd = self._museum_dummy_wood_png(name, state.width, state.height, gx)
                else:
                    hd = maybe_hd_png(self.achd, data, state.width, state.height, gx, pal)
                    if hd is None:
                        hd = self._museum_art_house_achd(name, state.width, state.height, gx)
                if hd is not None:
                    mode = house_clock_alpha_mode(name, alpha_mode_for_png(hd))
                    self._png_cache[key] = (hd, mode)
                    return hd, name, mode
        ## Neon empty-frame CI4 (non-dummy03): decode dummy03 wood instead.
        twin_png = self._museum_dummy_wood_png(name, state.width, state.height, None)
        if twin_png is not None:
            mode = alpha_mode_for_png(twin_png)
            self._png_cache[key] = (twin_png, mode)
            return twin_png, name, mode
        ## Frame / nameplate TLUT: house wood (sum) or museum `*_etc_pal` (ike).
        gaku_pal_name = museum_gaku_house_palette(name)
        if gaku_pal_name:
            house_pal = self._symbol_bytes(gaku_pal_name)
            if house_pal:
                pal = house_pal
                key = (
                    state.img_addr,
                    state.width,
                    state.height,
                    state.fmt,
                    state.siz,
                    pal,
                    state.prim,
                )
                cached = self._png_cache.get(key)
                if cached is not None:
                    return cached[0], name, cached[1]
        try:
            if is_museum_clock_texture(name):
                ## REL keeps N64 row-major RGBA5551; GX 4×4 RGB5A3 reads as neon noise.
                image = decode_linear_rgba5551(data, state.width, state.height)
            else:
                image = decode_gbi_texture(data, state.width, state.height, state.fmt, state.siz, pal)
            image = apply_prim(image, state.prim)
        except (KeyError, ValueError, IndexError):
            return None, name, "OPAQUE"
        if is_indoor_mado_texture(name):
            image = revive_stained_glass_alpha(image)
        mode = house_clock_alpha_mode(name, alpha_mode_for_image(image))
        png = image_png_bytes(image)
        self._png_cache[key] = (png, mode)
        return png, name, mode

    def _palette_for(self, state: TextureState) -> bytes | None:
        pal = state.palettes.get(state.pal_slot)
        if pal:
            return pal
        addr = state.img_addr
        if addr >> 24:
            seg_i = addr >> 24
            seg = self.segment_images.get(seg_i)
            if seg and seg.palette:
                return seg.palette
            pal = self.segment_palettes.get(seg_i)
            if pal:
                return pal
            for key in (0x0E, 0x0F, 0x0C, 0x0B, 0x0A):
                pal = self.segment_palettes.get(key)
                if pal:
                    return pal
        return self._fallback_palette(addr)

    def _image_bytes(self, state: TextureState) -> bytes | None:
        addr = state.img_addr
        if addr >> 24:
            if (addr >> 24) not in self.segment_images:
                self._resolve_dummy_image(state)
            seg = self.segment_images.get(addr >> 24)
            if seg is None:
                return None
            offset = addr & 0xFFFFFF
            if state.width == 0:
                state.width = seg.width
                state.height = seg.height
            if offset >= len(seg.data):
                return None
            return seg.data[offset:]
        needed = image_byte_size(state.width, state.height, state.siz)
        try:
            return self.rel.slice_at(addr, needed)
        except ValueError:
            symbol = self.addr_to_sym.get(addr)
            if symbol is None:
                return None
            try:
                return self.rel.slice_at(symbol.address, symbol.size)
            except ValueError:
                return None

    def _name_for(self, addr: int) -> str:
        if addr >> 24:
            off = addr & 0xFFFFFF
            named = self._segment_offset_names.get(addr >> 24, {}).get(off)
            if named:
                return named
            base = f"seg_{addr >> 24:02X}"
            return base if off == 0 else f"{base}_{off:x}"
        symbol = self.addr_to_sym.get(addr)
        return symbol.name if symbol else f"tex_{addr:08X}"

    def _museum_art_house_achd(
        self, tex_name: str, width: int, height: int, gx: int
    ) -> bytes | None:
        """ACHD via house-furniture twin when museum canvas hashes miss the pack."""
        twin = museum_art_house_twin(tex_name)
        if twin is None or self.achd is None:
            return None
        from .achd import maybe_hd_png

        house_tex, house_pal = twin
        data = self._symbol_bytes(house_tex)
        pal = self._symbol_bytes(house_pal)
        if data is None or pal is None:
            return None
        needed = image_byte_size(width, height, G_IM_SIZ_4b)
        if needed <= 0 or len(data) < needed:
            return None
        return maybe_hd_png(self.achd, data[:needed], width, height, gx, pal)

    def _museum_dummy_wood_png(
        self, tex_name: str, width: int, height: int, gx: int | None
    ) -> bytes | None:
        """Empty-frame stand-in: ACHD (preferred) or native decode of dummy03 wood."""
        twin = museum_dummy_wood_twin(tex_name)
        if twin is None:
            return None
        wood_tex, wood_pal = twin
        data = self._symbol_bytes(wood_tex)
        pal = self._symbol_bytes(wood_pal)
        if data is None or pal is None:
            return None
        needed = image_byte_size(width, height, G_IM_SIZ_4b)
        if needed <= 0 or len(data) < needed:
            ## back_tex is 32×48; name/tex are 16×16 — use twin's authored size when
            ## the caller asked for a mismatched tile (should not happen in practice).
            if wood_tex.endswith("_back_tex"):
                width, height = 32, 48
            else:
                width, height = 16, 16
            needed = image_byte_size(width, height, G_IM_SIZ_4b)
            if needed <= 0 or len(data) < needed:
                return None
        data = data[:needed]
        if self.achd is not None and gx is not None:
            from .achd import maybe_hd_png

            hd = maybe_hd_png(self.achd, data, width, height, gx, pal)
            if hd is not None:
                return hd
        try:
            image = decode_gbi_texture(data, width, height, G_IM_FMT_CI, G_IM_SIZ_4b, pal)
        except (KeyError, ValueError, IndexError):
            return None
        return image_png_bytes(image)

    def _fg_pal_row(self, name: str, row: int = 4) -> bytes | None:
        symbol = self._find_symbol(name)
        if symbol is None or symbol.size < 32:
            return None
        blob = self.rel.slice_at(symbol.address, min(symbol.size, 0x1C0))
        off = row * 32
        if off + 32 <= len(blob):
            return blob[off : off + 32]
        return blob[:32]

    def _fallback_palette(self, img_addr: int) -> bytes | None:
        if img_addr >> 24:
            return self.segment_palettes.get(img_addr >> 24)
        symbol = self.addr_to_sym.get(img_addr)
        name = symbol.name.lower() if symbol else ""
        if "palm" in name and self._palm_pal:
            return self._palm_pal
        if "cedar" in name and self._cedar_pal:
            return self._cedar_pal
        if "flower" in name and self._flower_pal:
            return self._flower_pal
        if "obj_hole" in name:
            return self._hole_g_pal
        if "tree" in name:
            return self._tree_fg_pal or self._tree_pal
        best: MapSymbol | None = None
        for pal in self._pal_symbols:
            if pal.address >= img_addr:
                break
            if img_addr - pal.address < 0x1000:
                best = pal
        if best is not None:
            return self.rel.slice_at(best.address, min(best.size, 512))
        return None


def parse_settimg(w0: int, w1: int) -> tuple[int, int, int, int, int]:
    """Return fmt, siz, width, height, addr. height is 0 for standard (non-Dolphin) SETTIMG."""
    fmt = (w0 >> 21) & 7
    siz = (w0 >> 19) & 3
    dolphin = (w0 >> 18) & 1
    if dolphin:
        height = (((w0 >> 10) & 0xFF) + 1) * 4
        width = (w0 & 0x3FF) + 1
    else:
        height = 0
        width = (w0 & 0xFFF) + 1
    return fmt, siz, width, height, w1


def is_dolphin_loadtlut(w0: int) -> bool:
    return ((w0 >> 22) & 3) == G_TLUT_DOLPHIN


def parse_loadtlut(w0: int, w1: int) -> tuple[int, int, int]:
    """Return slot, color_count, dram_addr.

    Dolphin packs slot/count/addr on the command. Classic `gsDPLoadTLUTCmd` has
    no slot or DRAM — callers use the prior SETTIMG + SETTILE TMEM instead and
    pass `slot=-1` / `addr=0` as sentinels.
    """
    if is_dolphin_loadtlut(w0):
        slot = (w0 >> 16) & 0xF
        count = w0 & 0x3FFF
        return slot, count, w1
    ## Classic: w1 = tile<<24 | count<<14; count is last index (15 → 16 colors).
    count = ((w1 >> 14) & 0x3FF) + 1
    return -1, count, 0


def parse_settile_dolphin(w0: int) -> tuple[int, int, int, int]:
    pal_slot = (w0 >> 12) & 0xF
    wrap_s = (w0 >> 10) & 3
    wrap_t = (w0 >> 8) & 3
    tile = (w0 >> 16) & 7
    return tile, pal_slot, wrap_s, wrap_t


def _n64_wrap_to_gx(mode: int) -> int:
    """Map G_TX_WRAP/MIRROR/CLAMP (cms/cmt) to GX wrap constants."""
    if mode & 2:  # G_TX_CLAMP
        return GX_CLAMP
    if mode & 1:  # G_TX_MIRROR
        return GX_MIRROR
    return GX_REPEAT


def parse_settile(w0: int, w1: int) -> tuple[int, int, int, int, int, int]:
    """Classic G_SETTILE: fmt, siz, pal_slot, wrap_s, wrap_t, tmem."""
    fmt = (w0 >> 21) & 7
    siz = (w0 >> 19) & 3
    tmem = w0 & 0x1FF
    pal_slot = (w1 >> 20) & 0xF
    wrap_s = _n64_wrap_to_gx((w1 >> 8) & 3)
    wrap_t = _n64_wrap_to_gx((w1 >> 18) & 3)
    return fmt, siz, pal_slot, wrap_s, wrap_t, tmem


def tmem_palette_slot(tmem: int) -> int | None:
    """Palette index for a TLUT load into TMEM (`256 + pal * 16`)."""
    if tmem < 256:
        return None
    slot = (tmem - 256) // 16
    if slot < 0 or slot > 15:
        return None
    return slot


def parse_settilesize(w0: int, w1: int) -> tuple[int, int]:
    """Classic G_SETTILESIZE: (width, height) from 10.2 uls/ult/lrs/lrt."""
    uls = (w0 >> 12) & 0xFFF
    ult = w0 & 0xFFF
    lrs = (w1 >> 12) & 0xFFF
    lrt = w1 & 0xFFF
    width = max(1, (lrs - uls) // 4 + 1)
    height = max(1, (lrt - ult) // 4 + 1)
    return width, height
