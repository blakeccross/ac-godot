from __future__ import annotations

import math
import struct
from dataclasses import dataclass, field, replace
from typing import Optional

from .texbank import (
    TextureBank,
    TextureState,
    alpha_mode_for_png,
    parse_loadtlut,
    parse_settile,
    parse_settile_dolphin,
    parse_settilesize,
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
G_SETTIMG = 0xFD
G_MTX = 0xDA
G_SETPRIMCOLOR = 0xFA
MTX_STRIDE = 0x40
SEG_MTX = 0x0D


def _s8_unit(byte: int) -> float:
    """Signed GX normal component (s8) → roughly [-1, 1]."""
    signed = byte if byte < 128 else byte - 256
    return signed / 127.0


def unit_normal(nx: float, ny: float, nz: float) -> tuple[float, float, float]:
    length = math.sqrt(nx * nx + ny * ny + nz * nz)
    if length < 1e-8:
        return 0.0, 1.0, 0.0
    return nx / length, ny / length, nz / length


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


def count_loaded_vertices(blob: bytes) -> int:
    """Count vertices consumed by G_VTX in a display list (shared-stream advance)."""
    used = 0
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
        if cmd == G_ENDDL:
            break
        if cmd == G_VTX:
            used += _bits(w0, 12, 8)
        elif cmd in (G_TRIN, G_TRIN_INDEPEND):
            extra = max(0, _bits(w0, 17, 7) + 1 - 3)
        i += 8
    return used


def apply_texture_commands(blob: bytes, bank: TextureBank, state: TextureState) -> None:
    """Walk a DL for SETTIMG / LOADTLUT / SETTILE_DOLPHIN only (material DLs)."""
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
            _tile, pal_slot, wrap_s, wrap_t = parse_settile_dolphin(w0)
            state.pal_slot = pal_slot
            state.wrap_s = wrap_s
            state.wrap_t = wrap_t
        elif cmd == G_SETPRIMCOLOR:
            state.prim = ((w1 >> 24) & 0xFF, (w1 >> 16) & 0xFF, (w1 >> 8) & 0xFF, w1 & 0xFF)
        elif cmd == G_DL:
            _follow_dl(w1, bank, state)
        i += 8


def _apply_settimg(w0: int, w1: int, bank: TextureBank, state: TextureState) -> None:
    fmt, siz, width, height, addr = parse_settimg(w0, w1)
    state.fmt = fmt
    state.siz = siz
    state.img_addr = addr
    if width:
        state.width = width
    if height:
        state.height = height
    elif addr >> 24 and (addr >> 24) in bank.segment_images:
        seg = bank.segment_images[addr >> 24]
        if seg.width and seg.height:
            state.width = seg.width
            state.height = seg.height


def _apply_loadtlut(w0: int, w1: int, bank: TextureBank, state: TextureState) -> None:
    slot, count, addr = parse_loadtlut(w0, w1)
    pal = bank.load_palette(addr, count)
    # Classic GBI LOADTLUT w1 is a TMEM dest; the palette is the last SETTIMG.
    if pal is None and state.img_addr:
        pal = bank.load_palette(state.img_addr, count or 16)
    if pal:
        state.palettes[slot] = pal
        state.pal_slot = slot


def _apply_settile(w0: int, w1: int, state: TextureState) -> None:
    fmt, siz, pal_slot, wrap_s, wrap_t = parse_settile(w0, w1)
    state.fmt = fmt
    state.siz = siz
    state.pal_slot = pal_slot
    state.wrap_s = wrap_s
    state.wrap_t = wrap_t


def _apply_settilesize(w0: int, w1: int, state: TextureState) -> None:
    width, height = parse_settilesize(w0, w1)
    state.width = width
    state.height = height


def _follow_dl(addr: int, bank: TextureBank, state: TextureState) -> None:
    symbol = bank.addr_to_sym.get(addr)
    if symbol is None or symbol.size <= 0:
        return
    try:
        nested = bank.rel.slice_at(symbol.address, symbol.size)
    except ValueError:
        return
    apply_texture_commands(nested, bank, state)


def parse_gfx(
    name: str,
    blob: bytes,
    all_vertices: list[Vertex],
    bank: TextureBank | None = None,
    state: TextureState | None = None,
    vtx_base_addr: int | None = None,
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
        )

    def uv_for(src: Vertex) -> tuple[float, float]:
        # Match GC T directly. Flipping V put the nose above the eyes.
        if tex_state.width > 0 and tex_state.height > 0:
            return src.s / tex_state.width, src.t / tex_state.height
        return src.s / 16.0, src.t / 16.0

    def flush() -> None:
        nonlocal triangles, unique, index_of, current_key
        if not triangles:
            unique = []
            index_of = {}
            return
        png = None
        tex_name = ""
        if bank is not None:
            png, tex_name = bank.decode_current(tex_state)
        parts.append(
            MeshPart(
                name=name if not tex_name else f"{name}:{tex_name}",
                vertices=unique,
                triangles=triangles,
                texture_name=tex_name,
                texture_png=png,
                tex_width=tex_state.width,
                tex_height=tex_state.height,
                wrap_s=tex_state.wrap_s,
                wrap_t=tex_state.wrap_t,
                alpha_mode=alpha_mode_for_png(png),
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
        tw = tex_state.width or 16
        th = tex_state.height or 16
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

    def walk(dl: bytes, depth: int = 0) -> None:
        nonlocal vtx_cursor, current_mtx, current_key
        if depth > 8:
            return
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
            elif cmd == G_VTX:
                n = _bits(w0, 12, 8)
                vn = _bits(w0, 1, 7)
                v0 = vn - n
                if vtx_base_addr is not None:
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
                fmt, siz, pal_slot, wrap_s, wrap_t = parse_settile(w0, w1)
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
                if triangles and (width != tex_state.width or height != tex_state.height):
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
                tex_state.pal_slot = pal_slot
                tex_state.wrap_s = wrap_s
                tex_state.wrap_t = wrap_t
            elif cmd == G_SETPRIMCOLOR and bank is not None:
                if triangles:
                    flush()
                    current_key = None
                tex_state.prim = ((w1 >> 24) & 0xFF, (w1 >> 16) & 0xFF, (w1 >> 8) & 0xFF, w1 & 0xFF)
            elif cmd == G_DL and bank is not None:
                symbol = bank.addr_to_sym.get(w1)
                if symbol is not None and symbol.size > 0:
                    try:
                        nested = bank.rel.slice_at(symbol.address, symbol.size)
                    except ValueError:
                        nested = b""
                    if nested:
                        walk(nested, depth + 1)
            i += 8

    walk(blob)
    flush()
    return parts
