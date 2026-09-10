from __future__ import annotations

import math
import struct
from dataclasses import dataclass, replace
from typing import Optional

from .texbank import (
    GX_CLAMP,
    GX_REPEAT,
    I4,
    I8,
    IA4,
    IA8,
    TextureBank,
    TextureState,
    bake_beach_wet_png,
    bake_player_select_shade_png,
    bake_player_select_spot_png,
    bake_prim_env_texel_png,
    clear_png_alpha,
    coverage_from_othermode_l,
    demote_opaque_uv_alpha,
    flood_opaque_alpha,
    gbi_to_gx,
    harden_tex_edge_alpha,
    i4_png_as_alpha,
    image_png_bytes,
    intensity_format_opaque_alpha,
    is_dolphin_loadtlut,
    is_player_select_fog_tex,
    is_player_select_shade_tex,
    is_player_select_spot_tex,
    needs_stained_glass_revive,
    parse_loadtlut,
    parse_settile,
    parse_settile_dolphin,
    parse_settilesize,
    parse_settimg,
    png_is_aa_cutout,
    resolve_alpha_mode,
    revive_stained_glass_alpha,
    tmem_palette_slot,
    uv_samples_transparent,
)
from PIL import Image
import io

G_VTX = 0x01
G_TEXTURE = 0xD7
G_TRI1 = 0x05
G_TRI2 = 0x06
G_TRIN = 0x09
G_TRIN_INDEPEND = 0x0A
G_SETTILE_DOLPHIN = 0xD2
G_DL = 0xDE
G_ENDDL = 0xDF
G_SETOTHERMODE_L = 0xE2
G_SETOTHERMODE_H = 0xE3
G_LOADTLUT = 0xF0
G_SETTILESIZE = 0xF2
G_SETTILE = 0xF5
G_SETTIMG = 0xFD
G_MTX = 0xDA
G_SETPRIMCOLOR = 0xFA
G_SETENVCOLOR = 0xFB
G_SETCOMBINE = 0xFC
G_GEOMETRYMODE = 0xD9
## F3DEX2 / libultra geometry flag — when clear, Vtx.cn[] is RGBA shade.
G_LIGHTING = 0x00020000
## Spherical env-map UVs (balloon heads, tub water, lighthouse lens, …).
G_TEXTURE_GEN = 0x00040000

## `aFSN_actor_draw_before` type 0 — used when the static DL omits SetPrim/Env
## (``act_balloon_head_model``) but still combines ``(PRIM−ENV)×TEXEL+ENV``.
_FUUSEN_DEFAULT_PRIM = (255, 210, 200, 255)
_FUUSEN_DEFAULT_ENV = (255, 40, 0, 255)
MTX_STRIDE = 0x40
SEG_MTX = 0x0D

## G_SETOTHERMODE_L field: G_MDSFT_RENDERMODE=3, length=29.
_RENDERMODE_SFT = 3
_RENDERMODE_LEN = 29
## Unshifted render-mode ZMODE bits (same as texbank).
_ZMODE_DEC = 0xC00
_ZMODE_MASK = 0xC00


def apply_othermode(reg: int, w0: int, w1: int) -> int:
    """F3DEX2 gsSPSetOtherMode: insert `len` bits of `data` at `sft`."""
    length = (w0 & 0xFF) + 1
    sft = 32 - ((w0 >> 8) & 0xFF) - length
    mask = ((1 << length) - 1) << sft
    return (reg & ~mask) | ((w1 << sft) & mask)


def is_rendermode_update(w0: int) -> bool:
    length = (w0 & 0xFF) + 1
    sft = 32 - ((w0 >> 8) & 0xFF) - length
    return sft == _RENDERMODE_SFT and length == _RENDERMODE_LEN


def othermode_is_xlu_decal(othermode_l: int) -> bool:
    """True for G_RM_*_XLU_DECAL* (window ground spill)."""
    return ((othermode_l >> 3) & _ZMODE_MASK) == _ZMODE_DEC


def combine_is_unlit_fill(combine_w0: int, combine_w1: int) -> bool:
    """Prim/env fills that ignore SETTIMG for RGB (window panes, indoor outdoor-view).

    Authored packs use ``0xFCxxxxxx`` with low 24 bits all 1s; textured spill
    clears those bits (e.g. ``0xFCFF9DFF``). Shade curtains share that w0 but
    sample TEXEL for alpha — excluded here so they stay textured.
    """
    if combine_w0 == 0 and combine_w1 == 0:
        return False
    if (combine_w0 & 0x00FFFFFF) != 0x00FFFFFF:
        return False
    return not combine_alpha_uses_texel(combine_w0, combine_w1)


def combine_alpha_uses_texel(combine_w0: int, combine_w1: int) -> bool:
    """True when either cycle's alpha mux samples TEXEL0/1 (shade curtains)."""
    ## F3DEX2 SetCombine alpha fields (same layout as ``coverage`` helpers use).
    aa0 = (combine_w0 >> 12) & 7
    ac0 = (combine_w0 >> 9) & 7
    ab0 = (combine_w1 >> 12) & 7
    ad0 = (combine_w1 >> 9) & 7
    aa1 = (combine_w1 >> 21) & 7
    ac1 = (combine_w1 >> 18) & 7
    ab1 = (combine_w1 >> 3) & 7
    ad1 = combine_w1 & 7
    texel = {1, 2}  # G_ACMUX_TEXEL0 / TEXEL1
    return any(v in texel for v in (aa0, ab0, ac0, ad0, aa1, ab1, ac1, ad1))


## `G_ACMUX_PRIM_LOD_FRAC` — alpha multiplier gated by runtime lod (`lod_factor`).
_G_ACMUX_PRIM_LOD_FRAC = 6


def combine_is_prim_env_texel(combine_w0: int, combine_w1: int) -> bool:
    """True when cycle-0 RGB is ``(PRIM - ENV) * TEXEL0 + ENV``.

    Wet-sand / ocean-bed (`beachA`/`beachB`) and a few XLU cones share this
    lerp. Coverage + format gates elsewhere keep OPA beach distinct from spot.
    """
    if combine_w0 == 0 and combine_w1 == 0:
        return False
    ## F3DEX2 ``GCCc0w0`` / ``GCCc0w1``: a0,c0 in w0; b0,d0 in w1.
    a0 = (combine_w0 >> 20) & 0xF
    c0 = (combine_w0 >> 15) & 0x1F
    b0 = (combine_w1 >> 28) & 0xF
    d0 = (combine_w1 >> 15) & 0x7
    ## G_CCMUX_PRIMITIVE=3, ENVIRONMENT=5, TEXEL0=1 (d-mux ENV also 5).
    return a0 == 3 and b0 == 5 and c0 == 1 and d0 == 5


def combine_alpha_scaled_by_prim_lod_frac(combine_w0: int, combine_w1: int) -> bool:
    """True when cycle alpha multiplies by PRIM_LOD_FRAC (e.g. train shineglass).

    ``gsDPSetCombineLERP`` packs cycle-1 mA in w0 bits 9–11 and cycle-2 mA
    (``Ac1``) in w1 bits 18–20. Trees use PRIM_LOD_FRAC on RGB only — not here.
    """
    if combine_w0 == 0 and combine_w1 == 0:
        return False
    ac0 = (combine_w0 >> 9) & 7
    ac1 = (combine_w1 >> 18) & 7
    return ac0 == _G_ACMUX_PRIM_LOD_FRAC or ac1 == _G_ACMUX_PRIM_LOD_FRAC


def classify_water_surface(
    *,
    coverage: str | None,
    fmt0: int,
    fmt1: int | None,
    wrap0_s: int,
    wrap0_t: int,
    wrap1_s: int,
    wrap1_t: int,
    dual: bool,
    env: tuple[int, int, int, int] = (255, 255, 255, 255),
) -> str:
    """Name-free water kind from coverage + dual-tile formats/wraps + env."""
    from .texbank import G_IM_FMT_I, G_IM_FMT_IA, GX_CLAMP, GX_MIRROR

    if not dual or fmt1 is None:
        return ""
    ## Train shineglass is dual I4 + CLAMP with no SetRenderMode (coverage None) and
    ## α *= PRIM_LOD_FRAC — not water. Acre/fall water always sets XLU.
    if coverage != "xlu":
        return ""
    if fmt0 == G_IM_FMT_IA and fmt1 == G_IM_FMT_IA:
        return "ocean"
    if fmt0 == G_IM_FMT_I and fmt1 == G_IM_FMT_I:
        if wrap0_s == GX_MIRROR or wrap1_s == GX_MIRROR:
            return "waterfall"
        if wrap0_t == GX_CLAMP or wrap1_t == GX_CLAMP:
            return "waterfall"
        ## Outdoor river: env is saturated blue (inland 0,100,255 / mouth 0,60,255).
        ## Museum tanks share dual I4 + REPEAT but use dimmer env (0,30,120) — leave
        ## untagged so convert keeps texel alpha and Godot skips the acre river shader.
        er, eg, eb = int(env[0]), int(env[1]), int(env[2])
        if eb >= 200 and er <= 40 and eg >= 40:
            return "river"
        return ""
    return "splash"


def classify_beach_wet(
    *,
    coverage: str | None,
    fmt: int,
    dual: bool,
    prim: tuple[int, int, int, int],
    env: tuple[int, int, int, int],
    combine_w0: int = 0,
    combine_w1: int = 0,
) -> str:
    """OPA I4 wet-sand / ocean-bed: ``(PRIM−ENV)×I+ENV``.

    Static acre DLs set PRIM (sand / ocean-bed blue) but leave ENV white —
    ``aFD_MakeMarinScrollInfo`` pulses ENV at runtime. Detect the combiner
    lerp so white ENV still classifies; keep the authored-ENV fallback for
    DLs that bake both ends.
    """
    from .texbank import G_IM_FMT_I

    if dual or fmt != G_IM_FMT_I:
        return ""
    if coverage not in (None, "opa"):
        return ""
    if prim[:3] == (255, 255, 255):
        return ""
    ## Player-select shade curtain: RGB=PRIM black, A=I — not wet sand.
    if sum(int(c) for c in prim[:3]) < 24:
        return ""
    if combine_is_prim_env_texel(combine_w0, combine_w1):
        return "beach_wet"
    ## Fallback when combine words are unavailable but both ends are authored.
    if env[:3] == (255, 255, 255):
        return ""
    return "beach_wet"


def waterfall_layer_from_wraps(
    wrap0_s: int,
    wrap0_t: int,
    wrap1_s: int,
    wrap1_t: int,
    *,
    prim: tuple[int, int, int, int] = (255, 255, 255, 255),
    env: tuple[int, int, int, int] = (255, 255, 255, 255),
) -> str:
    """Map dual-tile wrap + prim/env to shader layer ids (at/bt/ct/dt)."""
    from .texbank import GX_CLAMP, GX_MIRROR, GX_REPEAT

    at_like = (
        wrap0_s == GX_REPEAT
        and wrap0_t == GX_CLAMP
        and wrap1_s == GX_REPEAT
        and wrap1_t == GX_REPEAT
    )
    bt_like = wrap0_s == GX_MIRROR and wrap1_s == GX_MIRROR
    pa = int(prim[3]) if len(prim) > 3 else 255
    er, eg, eb = int(env[0]), int(env[1]), int(env[2])
    if at_like:
        ## grpCT: prim alpha ~100, env (30,40,50). grpAT: opaque prim, env (20,30,40).
        if pa < 200 or (er, eg, eb) == (30, 40, 50):
            return "ct"
        return "at"
    if bt_like:
        ## grpDT vs grpBT share mirror wraps; DT keeps a lower LOD / alpha-only cycle1.
        ## Prefer bt when prim is the bright BT blue; otherwise dt.
        if (int(prim[0]), int(prim[1]), int(prim[2])) == (100, 140, 255) and pa >= 200:
            return "bt"
        return "dt"
    return ""


def _s8_unit(byte: int) -> float:
    """Signed GX normal component (s8) → roughly [-1, 1]."""
    signed = byte if byte < 128 else byte - 256
    return signed / 127.0


def unit_normal(nx: float, ny: float, nz: float) -> tuple[float, float, float]:
    length = math.sqrt(nx * nx + ny * ny + nz * nz)
    if length < 1e-8:
        return 0.0, 1.0, 0.0
    return nx / length, ny / length, nz / length


def assign_geometric_normals(
    vertices: list["Vertex"], triangles: list[tuple[int, int, int]]
) -> None:
    """Face-average normals when cn[] is shade color (no G_LIGHTING), not LightsN."""
    for vertex in vertices:
        vertex.nx = 0.0
        vertex.ny = 0.0
        vertex.nz = 0.0
    for i0, i1, i2 in triangles:
        a, b, c = vertices[i0], vertices[i1], vertices[i2]
        ux, uy, uz = b.x - a.x, b.y - a.y, b.z - a.z
        vx, vy, vz = c.x - a.x, c.y - a.y, c.z - a.z
        nx = uy * vz - uz * vy
        ny = uz * vx - ux * vz
        nz = ux * vy - uy * vx
        for idx in (i0, i1, i2):
            vertices[idx].nx += nx
            vertices[idx].ny += ny
            vertices[idx].nz += nz
    for vertex in vertices:
        vertex.nx, vertex.ny, vertex.nz = unit_normal(vertex.nx, vertex.ny, vertex.nz)


@dataclass
class Vertex:
    x: float
    y: float
    z: float
    s: float
    t: float
    r: float
    g: float
    b: float
    a: float
    u: float = 0.0
    v: float = 0.0
    ## Vtx.cn[] under G_LIGHTING — authored lighting normal, not albedo.
    nx: float = 0.0
    ny: float = 1.0
    nz: float = 0.0
    mtx_index: int = -1
    joint_index: int = -1
    # Stable index into the source Vtx blob. Used as a dict key instead of id(),
    # which Python may reuse after G_VTX overwrites the vertex cache.
    src_index: int = -1


@dataclass
class MeshPart:
    name: str
    vertices: list[Vertex]
    triangles: list[tuple[int, int, int]]
    joint_index: int = -1
    texture_name: str = ""
    texture_png: bytes | None = None
    tex_width: int = 0
    tex_height: int = 0
    wrap_s: int = 0
    wrap_t: int = 0
    alpha_mode: str = "OPAQUE"
    ## Combiner ignores SETTIMG (window panes / indoor outdoor-view).
    unlit_fill: bool = False
    ## RGBA for unlit fills. Panes default black; indoor outdoor-view uses prim/white.
    unlit_rgba: tuple[float, float, float, float] = (0.0, 0.0, 0.0, 1.0)
    ## Soft ground XLU decal (window spill / prop glow).
    ground_spill: bool = False
    ## Second GX tile (river water2 / ocean wave2 or wave3). Packed as glTF occlusionTexture.
    layer1_png: bytes | None = None
    layer1_name: str = ""
    ## Tile1 wrap (wave2 is REPEAT S / CLAMP T). Not tile0 — that stays on wrap_s/wrap_t.
    layer1_wrap_s: int = GX_REPEAT
    layer1_wrap_t: int = GX_REPEAT
    ## `river` / `ocean` / `splash` / `waterfall` (XLU scroll) or `beach_wet` (OPA env pulse).
    water_kind: str = ""
    ## at/bt/ct/dt for dual-scroll waterfall combiner variants.
    waterfall_layer: str = ""
    ## glTF baseColorFactor (usually white). beach_wet bakes prim/env into the PNG.
    base_color: tuple[float, float, float, float] = (1.0, 1.0, 1.0, 1.0)
    ## DL prim RGBA 0–255 for beach_wet extras (runtime shader env pulse).
    beach_prim: tuple[int, int, int, int] | None = None
    ## True when the DL had G_LIGHTING — cn[] was a lighting normal.
    ## False → cn[] is RGBA shade (museum / house walls: ceiling AO as vertex color).
    uses_lighting: bool = True
    ## From G_SETOTHERMODE_L: opa / tex_edge / xlu, or None if never set in this DL.
    coverage: str | None = None


@dataclass
class RenderState:
    """Render-mode / combine state shared across sequential static DLs (`*_setmode` → `*_modelT`)."""

    othermode_l: int = 0
    othermode_h: int = 0
    coverage: str | None = None
    combine_w0: int = 0
    combine_w1: int = 0


## Decomp OPA beach2 / beachB under ocean (dark-blue floor), not shore wet sand.
_OCEAN_BED_PRIM = (32, 48, 144)


def is_ocean_bed_part(part: MeshPart) -> bool:
    """True for dark-blue beachB/beach2 underdraw (ocean floor) via authored prim."""
    prim = part.beach_prim
    if prim is not None and len(prim) >= 3:
        return (int(prim[0]), int(prim[1]), int(prim[2])) == _OCEAN_BED_PRIM
    return False


def parse_vtx_blob(blob: bytes, scale: float, flip_z: bool = False) -> list[Vertex]:
    """Decode a GX Vtx blob. Keep GX Z by default so static Gfx match cKF (+Z south).

    `scale` is the pipeline multiplier (default 0.001), not the draw matrix:
    actors are `Matrix_scale(0.01)`, acres `Matrix_scale(0.0625)`.
    """
    if len(blob) % 16 != 0:
        raise ValueError("Vtx blob is not a multiple of 16 bytes")
    vertices: list[Vertex] = []
    for i in range(0, len(blob), 16):
        x, y, z, _flag, u_raw, v_raw, r, g, b, a = struct.unpack_from(">hhhHhhBBBB", blob, i)
        z_out = -z * scale if flip_z else z * scale
        nx, ny, nz = unit_normal(_s8_unit(r), _s8_unit(g), _s8_unit(b))
        if flip_z:
            nz = -nz
        s = u_raw / 32.0
        t = v_raw / 32.0
        vertices.append(
            Vertex(
                x=x * scale,
                y=y * scale,
                z=z_out,
                s=s,
                t=t,
                r=r / 255.0,
                g=g / 255.0,
                b=b / 255.0,
                a=a / 255.0,
                u=s / 16.0,
                v=t / 16.0,
                nx=nx,
                ny=ny,
                nz=nz,
            )
        )
    return vertices


def _bits(value: int, offset: int, size: int) -> int:
    return (value >> offset) & ((1 << size) - 1)


def _tri_indices_init(packet: bytes) -> list[int]:
    upper = int.from_bytes(packet[0:4], "big")
    lower = int.from_bytes(packet[4:8], "big")
    spread = (upper << 32) | lower
    return [
        _bits(lower, 4, 5),
        _bits(lower, 9, 5),
        _bits(lower, 14, 5),
        _bits(lower, 19, 5),
        _bits(lower, 24, 5),
        _bits(spread, 29, 5),
        _bits(upper, 2, 5),
        _bits(upper, 7, 5),
        _bits(upper, 12, 5),
    ]


def _tri_indices_5b(packet: bytes) -> list[int]:
    upper = int.from_bytes(packet[0:4], "big")
    lower = int.from_bytes(packet[4:8], "big")
    spread = (upper << 32) | lower
    return [
        _bits(lower, 4, 5),
        _bits(lower, 9, 5),
        _bits(lower, 14, 5),
        _bits(lower, 19, 5),
        _bits(lower, 24, 5),
        _bits(spread, 29, 5),
        _bits(upper, 2, 5),
        _bits(upper, 7, 5),
        _bits(upper, 12, 5),
        _bits(upper, 17, 5),
        _bits(upper, 22, 5),
        _bits(upper, 27, 5),
    ]


def _chunks(values: list[int], n: int) -> list[tuple[int, ...]]:
    out: list[tuple[int, ...]] = []
    for i in range(0, len(values) - (n - 1), n):
        out.append(tuple(values[i : i + n]))
    return out


def apply_texture_commands(blob: bytes, bank: TextureBank, state: TextureState, depth: int = 0) -> None:
    """Walk a DL for SETTIMG / LOADTLUT / SETTILE_DOLPHIN only (material DLs)."""
    if depth > 8:
        return
    i = 0
    extra = 0
    while i + 8 <= len(blob):
        packet = blob[i : i + 8]
        if extra > 0:
            extra -= 4
            i += 8
            continue
        cmd = packet[0]
        w0 = int.from_bytes(packet[0:4], "big")
        w1 = int.from_bytes(packet[4:8], "big")
        if cmd == G_ENDDL:
            break
        if cmd in (G_TRIN, G_TRIN_INDEPEND):
            extra = max(0, _bits(w0, 17, 7) + 1 - 3)
        elif cmd == G_SETTIMG:
            _apply_settimg(w0, w1, bank, state)
        elif cmd == G_LOADTLUT:
            _apply_loadtlut(w0, w1, bank, state)
        elif cmd == G_SETTILE:
            _apply_settile(w0, w1, state)
        elif cmd == G_SETTILESIZE:
            _apply_settilesize(w0, w1, state)
        elif cmd == G_SETTILE_DOLPHIN:
            _apply_settile_dolphin(w0, state)
        elif cmd == G_SETPRIMCOLOR:
            state.prim = ((w1 >> 24) & 0xFF, (w1 >> 16) & 0xFF, (w1 >> 8) & 0xFF, w1 & 0xFF)
            state.prim_set = True
        elif cmd == G_SETENVCOLOR:
            state.env = ((w1 >> 24) & 0xFF, (w1 >> 16) & 0xFF, (w1 >> 8) & 0xFF, w1 & 0xFF)
        elif cmd == G_DL:
            _follow_dl(w1, bank, state, depth + 1)
        i += 8


def _apply_settimg(w0: int, w1: int, bank: TextureBank, state: TextureState) -> None:
    fmt, siz, width, height, addr = parse_settimg(w0, w1)
    state.fmt = fmt
    state.siz = siz
    state.img_addr = addr
    ## New image: drop prior tile size so UVs follow this SETTIMG until SETTILESIZE.
    state.tile_w = 0
    state.tile_h = 0
    if height:
        ## Dolphin SETTIMG carries real pixel width/height.
        state.width = width
        state.height = height
    elif addr >> 24 and (addr >> 24) in bank.segment_images:
        seg = bank.segment_images[addr >> 24]
        if seg.width and seg.height:
            state.width = seg.width
            state.height = seg.height
    else:
        ## Classic `gsDPLoadTextureBlock*` uses SETTIMG width=1; wait for SETTILESIZE.
        state.width = 0
        state.height = 0


def _apply_loadtlut(w0: int, w1: int, bank: TextureBank, state: TextureState) -> None:
    slot, count, addr = parse_loadtlut(w0, w1)
    dolphin = is_dolphin_loadtlut(w0)
    if not dolphin:
        ## Classic `gsDPLoadTLUT_pal16`: DRAM was the previous SETTIMG; slot is TMEM.
        addr = state.img_addr
        mapped = tmem_palette_slot(state.tmem)
        slot = mapped if mapped is not None else state.pal_slot
    pal = bank.load_palette(addr, count or 16)
    if pal and slot >= 0:
        state.palettes[slot] = pal
        state.pal_slot = slot
    elif dolphin and slot >= 0 and pal is None:
        ## Missed anime TLUT must not keep the previous face/skin slot, and must not
        ## fall back to the current SETTIMG (boy hat: skin texels-as-TLUT → gray BLEND).
        ## Clearing lets `_palette_for` use `SegmentTex.palette` on the shirt segment.
        state.palettes.pop(slot, None)
        state.pal_slot = slot


def _apply_settile(w0: int, w1: int, state: TextureState) -> None:
    fmt, siz, pal_slot, wrap_s, wrap_t, tmem = parse_settile(w0, w1)
    state.fmt = fmt
    state.siz = siz
    state.pal_slot = pal_slot
    state.tmem = tmem
    state.wrap_s = wrap_s
    state.wrap_t = wrap_t


def _apply_settile_dolphin(w0: int, state: TextureState) -> None:
    """Bind wrap and snapshot the current SETTIMG onto Dolphin tile 0 or 1."""
    tile, pal_slot, wrap_s, wrap_t = parse_settile_dolphin(w0)
    state.pal_slot = pal_slot
    state.wrap_s = wrap_s
    state.wrap_t = wrap_t
    snap = {
        "img_addr": state.img_addr,
        "width": state.width,
        "height": state.height,
        "fmt": state.fmt,
        "siz": state.siz,
        "wrap_s": wrap_s,
        "wrap_t": wrap_t,
    }
    if tile == 0:
        state.tile0 = snap
    elif tile == 1:
        state.tile1 = snap


def _decode_snap(
    bank: TextureBank, state: TextureState, snap: dict, *, skip_prim: bool
) -> tuple[bytes | None, str, str]:
    tmp = replace(
        state,
        img_addr=int(snap["img_addr"]),
        width=int(snap["width"] or 0),
        height=int(snap["height"] or 0),
        fmt=int(snap["fmt"]),
        siz=int(snap["siz"]),
        wrap_s=int(snap["wrap_s"]),
        wrap_t=int(snap["wrap_t"]),
        prim=(255, 255, 255, 255) if skip_prim else state.prim,
    )
    return bank.decode_current(tmp)


def _apply_settilesize(w0: int, w1: int, state: TextureState) -> None:
    width, height = parse_settilesize(w0, w1)
    state.tile_w = width
    state.tile_h = height
    ## Classic SETTIMG often omits height; then the tile size is the image size.
    if state.width <= 0:
        state.width = width
    if state.height <= 0:
        state.height = height


def _follow_dl(addr: int, bank: TextureBank, state: TextureState, depth: int) -> None:
    if depth > 8:
        return
    symbol = bank.addr_to_sym.get(addr)
    if symbol is None or symbol.size <= 0:
        return
    try:
        nested = bank.rel.slice_at(symbol.address, symbol.size)
    except ValueError:
        return
    apply_texture_commands(nested, bank, state, depth)


def parse_gfx(
    name: str,
    blob: bytes,
    all_vertices: list[Vertex],
    bank: TextureBank | None = None,
    state: TextureState | None = None,
    vtx_base_addr: int | None = None,
    render: RenderState | None = None,
) -> list[MeshPart]:
    """Walk a Dolphin-GBI display list and emit triangle groups, split on texture changes."""
    cache: list[Optional[Vertex]] = [None] * 32
    vtx_cursor = 0
    triangles: list[tuple[int, int, int]] = []
    unique: list[Vertex] = []
    index_of: dict[tuple, int] = {}
    parts: list[MeshPart] = []
    tex_state = state if state is not None else TextureState()
    current_key: tuple | None = None
    current_mtx = -1
    ## Nested `gsSPDisplayList` keeps its own symbol name so indoor edge/out
    ## groups are not labeled with the parent `room01_model`.
    current_dl_name = name
    ## Default on (actors / outdoor acres). Indoor shells LoadGeometryMode without G_LIGHTING.
    geometry_mode = G_LIGHTING
    rs = render if render is not None else RenderState()
    othermode_l = rs.othermode_l
    othermode_h = rs.othermode_h
    ## None until a SetRenderMode packet; trees often set mode at draw time only.
    coverage: str | None = rs.coverage
    combine_w0 = rs.combine_w0
    combine_w1 = rs.combine_w1
    if bank is not None and name:
        bank.current_gfx = name

    def tex_key() -> tuple:
        # Include palette bytes, not just slot index — LOADTLUT reuses slot 15.
        pal = b""
        if bank is not None:
            found = bank._palette_for(tex_state)
            if found:
                pal = found
        return (
            tex_state.img_addr,
            tex_state.width,
            tex_state.height,
            tex_state.fmt,
            tex_state.siz,
            pal,
            tex_state.prim,
            (tex_state.tile0 or {}).get("img_addr", 0),
            (tex_state.tile1 or {}).get("img_addr", 0),
            coverage,
            combine_w0,
            combine_w1,
            (othermode_l >> 3) & _ZMODE_MASK,
        )

    def uv_dims() -> tuple[int, int]:
        tw = tex_state.width or 16
        th = tex_state.height or 16
        if tex_state.tile0 and tex_state.tile0.get("width"):
            tw = int(tex_state.tile0["width"]) or tw
            th = int(tex_state.tile0["height"]) or th
        return tw, th

    def uv_for(src: Vertex) -> tuple[float, float]:
        # Match GC T directly. Flipping V put the nose above the eyes.
        # Divide by SETTIMG image size (not SETTILESIZE). Boy shirts have S up to
        # ~80 on a 32×32 image (U≈2.5) with wrapS=REPEAT; the 128-wide tile size
        # is only for HW wrap bounds and must not shrink U into [0,1].
        # Dual-tile water: keep UVs in tile0 space (wave2 is often 32×64).
        tw, th = uv_dims()
        return src.s / tw, src.t / th

    def flush() -> None:
        nonlocal triangles, unique, index_of, current_key
        if not triangles:
            unique = []
            index_of = {}
            return
        png = None
        tex_name = ""
        texel_mode = "OPAQUE"
        part_name = current_dl_name or name
        ## Structure panes often SETTIMG a wall tile after an unlit combine; the
        ## combiner still ignores it for RGB. Shade curtains share the unlit RGB
        ## w0 but sample TEXEL for alpha — ``combine_is_unlit_fill`` excludes those.
        unlit = combine_is_unlit_fill(combine_w0, combine_w1)
        ## Bright authored prim = indoor outdoor-view; default/black prim = facade pane.
        ## `rom_*` shells never SETPRIMCOLOR — `Global_kankyo_set_room_prim` tints at
        ## draw time. Bake them bright so Godot does not treat them as night facade panes.
        outdoor = unlit and bool(getattr(tex_state, "prim_set", False)) and sum(tex_state.prim[:3]) > 0
        dl_name = current_dl_name or name or ""
        if unlit and not outdoor and dl_name.startswith("rom_"):
            outdoor = True
        spill = coverage == "xlu" and othermode_is_xlu_decal(othermode_l)
        layer1_png = None
        layer1_name = ""
        layer1_wrap_s = GX_REPEAT
        layer1_wrap_t = GX_REPEAT
        water_kind = ""
        base_color = (1.0, 1.0, 1.0, 1.0)
        beach_prim: tuple[int, int, int, int] | None = None
        waterfall_layer = ""
        wrap_s = tex_state.wrap_s
        wrap_t = tex_state.wrap_t
        gx = gbi_to_gx(tex_state.fmt, tex_state.siz)
        force_alpha_mode: str | None = None
        dual = bool(tex_state.tile0 and tex_state.tile1)
        fmt0 = int((tex_state.tile0 or {}).get("fmt", tex_state.fmt))
        fmt1 = int(tex_state.tile1["fmt"]) if tex_state.tile1 else None
        wrap0_s = int((tex_state.tile0 or {}).get("wrap_s", wrap_s))
        wrap0_t = int((tex_state.tile0 or {}).get("wrap_t", wrap_t))
        wrap1_s = int((tex_state.tile1 or {}).get("wrap_s", GX_REPEAT)) if tex_state.tile1 else GX_REPEAT
        wrap1_t = int((tex_state.tile1 or {}).get("wrap_t", GX_REPEAT)) if tex_state.tile1 else GX_REPEAT
        if bank is not None and not unlit:
            name0 = bank._name_for(int((tex_state.tile0 or {}).get("img_addr") or tex_state.img_addr))
            name1 = bank._name_for(int((tex_state.tile1 or {}).get("img_addr") or 0)) if tex_state.tile1 else ""
            water_kind = classify_water_surface(
                coverage=coverage,
                fmt0=fmt0,
                fmt1=fmt1,
                wrap0_s=wrap0_s,
                wrap0_t=wrap0_t,
                wrap1_s=wrap1_s,
                wrap1_t=wrap1_t,
                dual=dual,
                env=tex_state.env,
            )
            if not water_kind:
                water_kind = classify_beach_wet(
                    coverage=coverage,
                    fmt=fmt0,
                    dual=dual,
                    prim=tex_state.prim,
                    env=tex_state.env,
                    combine_w0=combine_w0,
                    combine_w1=combine_w1,
                )
            ## Spot/shade I tiles share OPA+I with wet sand; name wins.
            if (
                is_player_select_fog_tex(name0)
                or is_player_select_fog_tex(name1)
                or is_player_select_spot_tex(name0)
                or is_player_select_spot_tex(name1)
                or is_player_select_shade_tex(name0)
                or is_player_select_shade_tex(name1)
            ):
                water_kind = ""
                waterfall_layer = ""
            if water_kind == "waterfall":
                waterfall_layer = waterfall_layer_from_wraps(
                    wrap0_s,
                    wrap0_t,
                    wrap1_s,
                    wrap1_t,
                    prim=tex_state.prim,
                    env=tex_state.env,
                )
            skip_prim = bool(water_kind)
            if water_kind in ("river", "ocean", "splash", "waterfall") and tex_state.tile0 and tex_state.tile1:
                png, tex_name, _alpha = _decode_snap(bank, tex_state, tex_state.tile0, skip_prim=True)
                layer1_png, layer1_name, _a1 = _decode_snap(bank, tex_state, tex_state.tile1, skip_prim=True)
                texel_mode = "BLEND"
                wrap_s = int(tex_state.tile0["wrap_s"])
                wrap_t = int(tex_state.tile0["wrap_t"])
                ## wave2 shore is REPEAT S / CLAMP T; wave3 open is REPEAT/REPEAT.
                layer1_wrap_s = int(tex_state.tile1["wrap_s"])
                layer1_wrap_t = int(tex_state.tile1["wrap_t"])
            else:
                saved_prim = tex_state.prim
                saved_env = tex_state.env
                ## Player-select spot/shade need raw I before prim/env bake.
                psel_xlu = is_player_select_spot_tex(name0) or is_player_select_shade_tex(name0)
                if not psel_xlu and name1:
                    psel_xlu = is_player_select_spot_tex(name1) or is_player_select_shade_tex(name1)
                ## XLU I4/I8 cards (rain, feel glyphs): keep raw intensity so
                ## `i4_png_as_alpha` can promote I→A; PRIM/ENV tint at runtime.
                xlu_intensity = (
                    coverage == "xlu"
                    and not dual
                    and gx in (I4, I8)
                )
                ## Balloon heads / pens: ``(PRIM−ENV)×TEXEL+ENV`` on I/IA intensity.
                ## Skip when `xlu_intensity` — train door/car glass share that combiner but
                ## need I→alpha + ENV tint (`i4_png_as_alpha`), not an opaque RGB bake.
                prim_env_intensity = (
                    not bool(water_kind)
                    and not xlu_intensity
                    and combine_is_prim_env_texel(combine_w0, combine_w1)
                    and gx in (I4, I8, IA4, IA8)
                )
                saved_prim_set = bool(getattr(tex_state, "prim_set", False))
                ## Prefer the cone tile (tile1) over scrolling fog (tile0) when both are bound.
                if (
                    is_player_select_spot_tex(name1)
                    and is_player_select_fog_tex(name0)
                    and tex_state.tile1
                ):
                    ## UVs were divided by tile0 32×32; cone is 32×64 — scale V to cone space.
                    th0 = float(tex_state.tile0.get("height") or 32) or 32.0
                    th1 = float(tex_state.tile1.get("height") or 64) or 64.0
                    if abs(th0 - th1) > 0.5:
                        scale_v = th0 / th1
                        for vertex in unique:
                            vertex.v *= scale_v
                    wrap_s = int(tex_state.tile1["wrap_s"])
                    wrap_t = int(tex_state.tile1["wrap_t"])
                    png, tex_name, _alpha = _decode_snap(
                        bank, tex_state, tex_state.tile1, skip_prim=True
                    )
                    texel_mode = "BLEND"
                    tex_state.prim = saved_prim
                    if png:
                        png = bake_player_select_spot_png(
                            png, saved_prim, (saved_env[0], saved_env[1], saved_env[2])
                        )
                        force_alpha_mode = "BLEND"
                else:
                    if skip_prim or psel_xlu or xlu_intensity or prim_env_intensity:
                        tex_state.prim = (255, 255, 255, 255)
                    png, tex_name, texel_mode = bank.decode_current(tex_state)
                    tex_state.prim = saved_prim
                    if water_kind == "beach_wet" and png:
                        texel_mode = "OPAQUE"
                        beach_prim = saved_prim
                        ## RGB ≈ (PRIM-ENV)*I+ENV; alpha = I for runtime env pulse.
                        png = bake_beach_wet_png(png, saved_prim)
                    elif is_player_select_spot_tex(tex_name) and png:
                        ## Baked yellow cone; GC dual-tile fog scroll is not a Godot shader.
                        png = bake_player_select_spot_png(
                            png, saved_prim, (saved_env[0], saved_env[1], saved_env[2])
                        )
                        texel_mode = "BLEND"
                        force_alpha_mode = "BLEND"
                    elif is_player_select_shade_tex(tex_name) and png:
                        ## Black curtain: RGB=PRIM, A=I.
                        png = bake_player_select_shade_png(png, saved_prim)
                        texel_mode = "BLEND"
                        force_alpha_mode = "BLEND"
                    elif prim_env_intensity and png:
                        bake_prim = saved_prim
                        bake_env = saved_env
                        ## ``act_balloon_head``: no SetPrim/Env in the DL; fuusen sets
                        ## both at draw. IA + TEXTURE_GEN + unset ends → type-0 pair.
                        if (
                            not saved_prim_set
                            and bake_prim[:3] == (255, 255, 255)
                            and bake_env[:3] == (255, 255, 255)
                            and gx in (IA4, IA8)
                            and bool(geometry_mode & G_TEXTURE_GEN)
                        ):
                            bake_prim = _FUUSEN_DEFAULT_PRIM
                            bake_env = _FUUSEN_DEFAULT_ENV
                        ## White/white with no runtime-IA hint: leave intensity (UI).
                        if bake_prim[:3] != (255, 255, 255) or bake_env[:3] != (255, 255, 255):
                            png = bake_prim_env_texel_png(png, bake_prim, bake_env)
                    elif (
                        ## Shineglass omits SetRenderMode in the static DL (runtime XLU);
                        ## still promote opaque I4/I8 intensity to alpha.
                        coverage in (None, "xlu")
                        and gx in (I4, I8)
                        and png
                        and intensity_format_opaque_alpha(png)
                    ):
                        ## I → alpha; keep RGB white so ENV/PRIM tint can land at runtime.
                        png = i4_png_as_alpha(png)
                        texel_mode = "BLEND"
                        er, eg, eb, _ea = saved_env
                        if er + eg + eb > 0:
                            ## Cloud DL sets ENV (127,127,100); bake as baseColorFactor.
                            base_color = (er / 255.0, eg / 255.0, eb / 255.0, 1.0)
                    elif coverage == "xlu" and png:
                        image = Image.open(io.BytesIO(png)).convert("RGBA")
                        if needs_stained_glass_revive(image):
                            png = image_png_bytes(revive_stained_glass_alpha(image))
                            texel_mode = "BLEND"
        if spill and png and intensity_format_opaque_alpha(png):
            ## Ground spill: I→A when still opaque grayscale.
            png = i4_png_as_alpha(png)
            texel_mode = "BLEND"
        ## α *= PRIM_LOD_FRAC (`lod_factor`) — invisible until runtime scales it.
        ## Only when coverage is unset (train shineglass). XLU tank/acre water also
        ## uses PRIM_LOD_FRAC but must keep texel alpha for standard BLEND / shaders.
        if (
            png
            and coverage is None
            and combine_alpha_scaled_by_prim_lod_frac(combine_w0, combine_w1)
        ):
            png = clear_png_alpha(png)
            texel_mode = "BLEND"
            force_alpha_mode = "BLEND"
        samples_transparent: bool | None = None
        if png and coverage in ("tex_edge", None) and texel_mode in ("MASK", "BLEND"):
            image = Image.open(io.BytesIO(png)).convert("RGBA")
            samples_transparent = uv_samples_transparent(
                image, unique, triangles, wrap_s=wrap_s, wrap_t=wrap_t
            )
        if water_kind in ("river", "ocean", "splash", "waterfall"):
            alpha_mode = "BLEND"
        elif water_kind == "beach_wet":
            alpha_mode = "OPAQUE"
        elif unlit:
            alpha_mode = "OPAQUE"
        elif force_alpha_mode is not None:
            alpha_mode = force_alpha_mode
        else:
            alpha_mode = resolve_alpha_mode(
                coverage, texel_mode, samples_transparent=samples_transparent
            )
        ## Body DLs with no SetRenderMode still share a cutout atlas with the door.
        ## If this part's UVs never hit transparent texels, keep it opaque — including
        ## when ACHD softens the shared atlas to BLEND (not only hard MASK).
        alpha_mode = demote_opaque_uv_alpha(
            coverage, alpha_mode, samples_transparent=samples_transparent
        )
        ## ACHD soft AA on an alpha-compare silhouette: keep the HD sheet but bin
        ## alpha to 0/255 so alphaMode stays MASK. TEX_EDGE says so outright; a DL
        ## that never set a rendermode (structure sub-DL inheriting the actor setup)
        ## is judged from the texture — a hard cutout + a UV footprint that lands on
        ## its holes is alpha-compare on hardware, not a real gradient. Leaving soft
        ## BLEND put structure walls in Godot's transparent pass with depth write
        ## off — they drew in front of the whole town.
        if (
            samples_transparent
            and png
            and texel_mode == "BLEND"
            and force_alpha_mode is None
            and not spill
            and (
                coverage == "tex_edge"
                or (coverage is None and png_is_aa_cutout(png))
            )
        ):
            png = harden_tex_edge_alpha(png)
            texel_mode = "MASK"
            alpha_mode = resolve_alpha_mode(
                "tex_edge", texel_mode, samples_transparent=True
            )
        ## Tank / sea-tank env glass + caustics share the TEX_EDGE frame's wall planes.
        ## Godot's depth test flickers coplanar XLU against the depth-writing MASK
        ## frame, so pull each XLU wall layer inward by a distinct amount: the frame
        ## keeps its plane, `evw` sits just inside it, the `water*` caustics inside
        ## that. Horizontal (`mizu`) surface planes are left alone — scaling them in
        ## opens a gap at the waterline.
        _tank_inset = 0.0
        if coverage == "xlu" and tex_name and unique:
            low = tex_name.lower()
            if "evw" in low:
                _tank_inset = 0.97
            elif "water1" in low:
                _tank_inset = 0.955
            elif "water2" in low or "_mizu2" in low:
                _tank_inset = 0.94
        if _tank_inset:
            for vertex in unique:
                vertex.x *= _tank_inset
                vertex.z *= _tank_inset
        ## Always flood when the surface is opaque — ACHD soft fringe at A=250–254
        ## still classifies as OPAQUE texel, and leaving it in the PNG made Godot /
        ## stale BLEND exports draw NPC bodies in front of the scene.
        ## beach_wet keeps I in alpha for the runtime ENV pulse — do not flood.
        if alpha_mode == "OPAQUE" and png and water_kind != "beach_wet":
            png = flood_opaque_alpha(png)
        # Indoor outdoor-view uses G_CC_PRIMITIVE (sky/fill). Default prim is white.
        if outdoor:
            pr, pg, pb, pa = tex_state.prim
            unlit_rgba = (pr / 255.0, pg / 255.0, pb / 255.0, pa / 255.0)
        else:
            unlit_rgba = (0.0, 0.0, 0.0, 1.0)
        uses_lighting = bool(geometry_mode & G_LIGHTING)
        if not uses_lighting:
            assign_geometric_normals(unique, triangles)
        parts.append(
            MeshPart(
                name=part_name if not tex_name else f"{part_name}:{tex_name}",
                vertices=unique,
                triangles=triangles,
                texture_name=tex_name,
                texture_png=png,
                tex_width=int((tex_state.tile0 or {}).get("width") or tex_state.width),
                tex_height=int((tex_state.tile0 or {}).get("height") or tex_state.height),
                wrap_s=wrap_s,
                wrap_t=wrap_t,
                alpha_mode=alpha_mode,
                unlit_fill=unlit,
                unlit_rgba=unlit_rgba,
                ground_spill=spill,
                layer1_png=layer1_png,
                layer1_name=layer1_name,
                layer1_wrap_s=layer1_wrap_s,
                layer1_wrap_t=layer1_wrap_t,
                water_kind=water_kind,
                waterfall_layer=waterfall_layer,
                base_color=base_color,
                beach_prim=beach_prim,
                uses_lighting=uses_lighting,
                coverage=coverage,
            )
        )
        triangles = []
        unique = []
        index_of = {}

    def emit(i0: int, i1: int, i2: int) -> None:
        nonlocal current_key
        for idx in (i0, i1, i2):
            if idx < 0 or idx >= 32 or cache[idx] is None:
                return
        key = tex_key()
        if current_key is None:
            current_key = key
        elif key != current_key and triangles:
            flush()
            current_key = key
        keys = []
        tw, th = uv_dims()
        for idx in (i0, i1, i2):
            src = cache[idx]
            assert src is not None
            u, v = uv_for(src)
            # src_index is stable across cache reloads; id(src) is not (CPython reuses it).
            vert_key = (src.src_index, tw, th, src.mtx_index)
            if vert_key not in index_of:
                index_of[vert_key] = len(unique)
                unique.append(
                    Vertex(
                        x=src.x,
                        y=src.y,
                        z=src.z,
                        s=src.s,
                        t=src.t,
                        r=src.r,
                        g=src.g,
                        b=src.b,
                        a=src.a,
                        u=u,
                        v=v,
                        nx=src.nx,
                        ny=src.ny,
                        nz=src.nz,
                        mtx_index=src.mtx_index,
                        src_index=src.src_index,
                    )
                )
            keys.append(index_of[vert_key])
        triangles.append((keys[0], keys[1], keys[2]))

    def walk(dl: bytes, depth: int = 0, dl_name: str | None = None) -> None:
        nonlocal vtx_cursor, current_mtx, current_key, current_dl_name, geometry_mode
        nonlocal othermode_l, othermode_h, coverage, combine_w0, combine_w1
        if depth > 8:
            return
        prev_name = current_dl_name
        if dl_name:
            current_dl_name = dl_name
            if bank is not None:
                bank.current_gfx = dl_name
        i = 0
        remaining_extra = 0
        while i + 8 <= len(dl):
            packet = dl[i : i + 8]
            if remaining_extra > 0:
                indices = _tri_indices_5b(packet)
                take = min(4, remaining_extra)
                for a, b, c in _chunks(indices, 3)[:take]:
                    emit(a, b, c)
                remaining_extra -= 4
                i += 8
                continue

            cmd = packet[0]
            w0 = int.from_bytes(packet[0:4], "big")
            w1 = int.from_bytes(packet[4:8], "big")
            if cmd == G_ENDDL:
                break
            if cmd == G_MTX:
                if (w1 >> 24) == SEG_MTX:
                    current_mtx = (w1 & 0xFFFFFF) // MTX_STRIDE
            elif cmd == G_TEXTURE:
                ## gsSPTexture — state only; no geometry.
                pass
            elif cmd == G_SETOTHERMODE_L:
                new_l = apply_othermode(othermode_l, w0, w1)
                new_cov = coverage
                if is_rendermode_update(w0):
                    new_cov = coverage_from_othermode_l(new_l)
                if triangles and (
                    new_cov != coverage
                    or ((new_l >> 3) & _ZMODE_MASK) != ((othermode_l >> 3) & _ZMODE_MASK)
                ):
                    flush()
                    current_key = None
                othermode_l = new_l
                if is_rendermode_update(w0):
                    coverage = new_cov
            elif cmd == G_SETOTHERMODE_H:
                othermode_h = apply_othermode(othermode_h, w0, w1)
            elif cmd == G_SETCOMBINE:
                if triangles and (w0 != combine_w0 or w1 != combine_w1):
                    flush()
                    current_key = None
                combine_w0, combine_w1 = w0, w1
                ## Prim/env fills ignore SETTIMG — drop inherited wall/floor tiles so
                ## outdoor-view / pane groups do not keep a stale albedo key.
                if combine_is_unlit_fill(w0, w1) and bank is not None:
                    tex_state.img_addr = 0
                    tex_state.width = 0
                    tex_state.height = 0
                    tex_state.tile_w = 0
                    tex_state.tile_h = 0
                    tex_state.tile0 = None
                    tex_state.tile1 = None
            elif cmd == G_GEOMETRYMODE:
                ## gsSPGeometryMode(clear, set): mode = (mode & ~clear) | set.
                clear = (~(w0 & 0xFFFFFF)) & 0xFFFFFF
                new_mode = (geometry_mode & ~clear) | w1
                old_lit = bool(geometry_mode & G_LIGHTING)
                new_lit = bool(new_mode & G_LIGHTING)
                if triangles and old_lit != new_lit:
                    flush()
                    current_key = None
                geometry_mode = new_mode
            elif cmd == G_VTX:
                n = _bits(w0, 12, 8)
                vn = _bits(w0, 1, 7)
                v0 = vn - n
                seg = w1 >> 24
                if seg in range(0x08, 0x10):
                    ## Runtime `gSPSegment(anime_N_txt, …)` — DL stores 0x08xxxxxx.
                    src0 = (w1 & 0xFFFFFF) // 16
                elif vtx_base_addr is not None:
                    src0 = (w1 - vtx_base_addr) // 16
                else:
                    src0 = vtx_cursor
                for k in range(n):
                    src = src0 + k
                    if 0 <= v0 + k < 32 and 0 <= src < len(all_vertices):
                        cache[v0 + k] = replace(
                            all_vertices[src],
                            mtx_index=current_mtx,
                            src_index=src,
                        )
                vtx_cursor += n
            elif cmd in (G_TRIN, G_TRIN_INDEPEND):
                count = _bits(w0, 17, 7) + 1
                indices = _tri_indices_init(packet)
                for a, b, c in _chunks(indices, 3)[: min(3, count)]:
                    emit(a, b, c)
                remaining_extra = max(0, count - 3)
            elif cmd == G_TRI1:
                emit(_bits(w0, 16, 8) // 2, _bits(w0, 8, 8) // 2, _bits(w0, 0, 8) // 2)
            elif cmd == G_TRI2:
                emit(_bits(w0, 16, 8) // 2, _bits(w0, 8, 8) // 2, _bits(w0, 0, 8) // 2)
                emit(_bits(w1, 16, 8) // 2, _bits(w1, 8, 8) // 2, _bits(w1, 0, 8) // 2)
            elif cmd == G_SETTIMG and bank is not None:
                if triangles:
                    flush()
                    current_key = None
                _apply_settimg(w0, w1, bank, tex_state)
            elif cmd == G_LOADTLUT and bank is not None:
                # Skin/horn tris often sit in the buffer when the next TLUT (shirt) arrives.
                if triangles:
                    flush()
                    current_key = None
                _apply_loadtlut(w0, w1, bank, tex_state)
            elif cmd == G_SETTILE and bank is not None:
                fmt, siz, pal_slot, wrap_s, wrap_t, _tmem = parse_settile(w0, w1)
                if triangles and (
                    pal_slot != tex_state.pal_slot
                    or wrap_s != tex_state.wrap_s
                    or wrap_t != tex_state.wrap_t
                    or fmt != tex_state.fmt
                    or siz != tex_state.siz
                ):
                    flush()
                    current_key = None
                _apply_settile(w0, w1, tex_state)
            elif cmd == G_SETTILESIZE and bank is not None:
                width, height = parse_settilesize(w0, w1)
                if triangles and (width != tex_state.tile_w or height != tex_state.tile_h):
                    flush()
                    current_key = None
                _apply_settilesize(w0, w1, tex_state)
            elif cmd == G_SETTILE_DOLPHIN and bank is not None:
                _tile, pal_slot, wrap_s, wrap_t = parse_settile_dolphin(w0)
                if triangles and (
                    pal_slot != tex_state.pal_slot
                    or wrap_s != tex_state.wrap_s
                    or wrap_t != tex_state.wrap_t
                ):
                    flush()
                    current_key = None
                _apply_settile_dolphin(w0, tex_state)
            elif cmd == G_SETPRIMCOLOR and bank is not None:
                if triangles:
                    flush()
                    current_key = None
                tex_state.prim = ((w1 >> 24) & 0xFF, (w1 >> 16) & 0xFF, (w1 >> 8) & 0xFF, w1 & 0xFF)
                tex_state.prim_set = True
            elif cmd == G_SETENVCOLOR and bank is not None:
                if triangles:
                    flush()
                    current_key = None
                tex_state.env = ((w1 >> 24) & 0xFF, (w1 >> 16) & 0xFF, (w1 >> 8) & 0xFF, w1 & 0xFF)
            elif cmd == G_DL and bank is not None:
                symbol = bank.addr_to_sym.get(w1)
                if symbol is not None and symbol.size > 0:
                    try:
                        nested = bank.rel.slice_at(symbol.address, symbol.size)
                    except ValueError:
                        nested = b""
                    if nested:
                        ## Finish the current group before switching DL names.
                        if triangles:
                            flush()
                            current_key = None
                        walk(nested, depth + 1, symbol.name)
            i += 8
        if dl_name is not None and triangles:
            flush()
            current_key = None
        current_dl_name = prev_name
        if bank is not None and prev_name:
            bank.current_gfx = prev_name

    walk(blob)
    flush()
    if render is not None:
        render.othermode_l = othermode_l
        render.othermode_h = othermode_h
        render.coverage = coverage
        render.combine_w0 = combine_w0
        render.combine_w1 = combine_w1
    return parts
