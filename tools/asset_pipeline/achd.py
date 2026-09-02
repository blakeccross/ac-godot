"""Dolphin ACHD (hi-res) texture pack lookup for the convert pipeline.

Hashes raw GX texels (+ trimmed TLUT) the same way Dolphin's TextureInfo does,
then swaps in decoded ACHD DDS/PNG when a stem matches.
"""

from __future__ import annotations

import io
import re
import struct
from pathlib import Path
from typing import Optional

import xxhash
from PIL import Image

from .bti import (
    CI4,
    CI8,
    CI14X2,
    _BLOCK,
)

try:
    import texture2ddecoder
except ImportError:  # pragma: no cover
    texture2ddecoder = None  # type: ignore

# DXGI_FORMAT_BC7_UNORM / BC7_UNORM_SRGB
_DXGI_BC7 = {98, 99}

_STEM_RE = re.compile(
    r"^tex1_(\d+)x(\d+)(?:_m)?_([0-9a-f$]+)(?:_([0-9a-f$]+))?_(\d+)(?:_arb)?$",
    re.IGNORECASE,
)

## Field BG / acre terrain / trees. HD swaps break wrap-bake atlases and season
## re-tiling (native tiles × UV repeats → atlas; ACHD is many× larger, then the
## seasons pack still ships native tiles and over-tiles into that atlas).
_FIELD_TEXTURE_RE = re.compile(
    r"(mFM_grd_|mFM_obj_tree_|mFM_obj_palm_|mFM_obj_.*flower|"
    r"grass_tex|earth_tex|cliff_tex|bush_[ab]_tex|"
    r"sand_tex|beach|river_tex|rail_tex|stone_tex|"
    r"obj_[sfw]_tree|obj_[sfw]_cedar|obj_[sfw]_palm|"
    r"obj_[sfw]_cstump|obj_[sfw]_pstump|obj_[sfw]_stump|"
    r"obj_[sfw]_stone|obj_stone|"
    r"obj_x_tree|ef_[sfw]_tree|ef_[sfw]_cedar|ef_[sfw]_palm|"
    r"ef_[sfw]_young|ef_[sfw]_yung|"
    r"obj_tree_|obj_cedar_|obj_palm_)",
    re.IGNORECASE,
)

_TREE_PREFIX_RE = re.compile(
    r"^(obj_[sfwx]_|ef_[sfw]_)?(tree|cedar|palm|cstump|pstump|stump|stone|youngtree|young_cedar|young_palm|yungtree)",
    re.IGNORECASE,
)


def is_field_terrain_texture(name: str, prefix: str = "") -> bool:
    """True for acre/field/tree/season tiles that must stay native resolution."""
    stem = prefix.split(":")[0] if prefix else ""
    if stem.startswith("grd_"):
        return True
    if stem and _TREE_PREFIX_RE.search(stem):
        return True
    if not name:
        return False
    return _FIELD_TEXTURE_RE.search(name) is not None


def align_up(value: int, align: int) -> int:
    return (value + align - 1) // align * align


def gx_texture_byte_size(width: int, height: int, fmt: int) -> int:
    bw, bh, bpp = _BLOCK[fmt]
    return align_up(width, bw) * align_up(height, bh) * bpp // 8


def gx_palette_byte_size(fmt: int) -> int:
    if fmt == CI4:
        return 16 * 2
    if fmt == CI8:
        return 256 * 2
    if fmt == CI14X2:
        return 16384 * 2
    return 0


def _trim_tlut(texture: bytes, tlut: bytes, full_tlut_size: int) -> bytes:
    """Match Dolphin TextureInfo::CalculateTextureName palette min/max trim."""
    if full_tlut_size <= 0:
        return b""
    padded = tlut[:full_tlut_size]
    if len(padded) < full_tlut_size:
        padded = padded + bytes(full_tlut_size - len(padded))
    mn = 0xFFFF
    mx = 0
    if full_tlut_size == 16 * 2:
        for byte in texture:
            lo = byte & 0xF
            hi = byte >> 4
            mn = min(mn, lo, hi)
            mx = max(mx, lo, hi)
    elif full_tlut_size == 256 * 2:
        for byte in texture:
            mn = min(mn, byte)
            mx = max(mx, byte)
    elif full_tlut_size == 16384 * 2:
        for i in range(0, len(texture), 2):
            half = int.from_bytes(texture[i : i + 2], "big") & 0x3FFF
            mn = min(mn, half)
            mx = max(mx, half)
    else:
        return padded
    used = 2 * (mx + 1 - mn)
    return padded[2 * mn : 2 * mn + used]


def dolphin_texture_stem(
    texture: bytes,
    width: int,
    height: int,
    fmt: int,
    tlut: bytes | None = None,
    *,
    has_mipmaps: bool = False,
) -> str:
    """Build `tex1_WxH[_m]_texhash[_tluthash]_fmt` (no extension)."""
    size = gx_texture_byte_size(width, height, fmt)
    data = texture[:size]
    if len(data) < size:
        data = data + bytes(size - len(data))
    tex_hash = xxhash.xxh64(data, seed=0).hexdigest()
    mip = "_m" if has_mipmaps else ""
    full_pal = gx_palette_byte_size(fmt)
    if full_pal:
        trimmed = _trim_tlut(data, tlut or b"", full_pal)
        tlut_hash = xxhash.xxh64(trimmed, seed=0).hexdigest()
        return f"tex1_{width}x{height}{mip}_{tex_hash}_{tlut_hash}_{fmt}"
    return f"tex1_{width}x{height}{mip}_{tex_hash}_{fmt}"


def decode_dds(path: Path) -> Image.Image:
    """Decode ACHD DDS (DX10 BC7) to RGBA. PNG paths load via Pillow."""
    if path.suffix.lower() == ".png":
        return Image.open(path).convert("RGBA")
    blob = path.read_bytes()
    if blob[:4] != b"DDS ":
        raise ValueError(f"not a DDS file: {path}")
    height, width = struct.unpack_from("<II", blob, 12)
    fourcc = blob[84:88]
    if fourcc != b"DX10":
        raise ValueError(f"unsupported DDS fourcc {fourcc!r} in {path}")
    dxgi = struct.unpack_from("<I", blob, 128)[0]
    payload = blob[148:]
    if dxgi not in _DXGI_BC7:
        raise ValueError(f"unsupported DXGI format {dxgi} in {path}")
    if texture2ddecoder is None:
        raise RuntimeError("texture2ddecoder is required to decode ACHD BC7 DDS")
    raw = texture2ddecoder.decode_bc7(payload, width, height)
    return Image.frombytes("RGBA", (width, height), raw, "raw", "BGRA")


def image_png_bytes(image: Image.Image) -> bytes:
    buf = io.BytesIO()
    image.convert("RGBA").save(buf, format="PNG")
    return buf.getvalue()


class AchdPack:
    """Indexed ACHD / Dolphin Load/Textures tree."""

    def __init__(self, root: Path, cache_dir: Path | None = None) -> None:
        self.root = root
        self.cache_dir = cache_dir
        self._by_stem: dict[str, Path] = {}
        self._png_mem: dict[str, bytes] = {}
        self.hits = 0
        self.misses = 0
        self.decode_errors = 0
        self._index()

    def _index(self) -> None:
        if not self.root.is_dir():
            return
        for path in self.root.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix.lower() not in {".dds", ".png"}:
                continue
            stem = path.stem
            if not _STEM_RE.match(stem):
                continue
            key = stem.lower()
            # Prefer PNG over DDS when both exist; first wins otherwise.
            existing = self._by_stem.get(key)
            if existing is None or (existing.suffix.lower() == ".dds" and path.suffix.lower() == ".png"):
                self._by_stem[key] = path

    @property
    def size(self) -> int:
        return len(self._by_stem)

    def resolve_stem(self, stem: str) -> Path | None:
        key = stem.lower()
        hit = self._by_stem.get(key)
        if hit is not None:
            return hit
        m = _STEM_RE.match(stem)
        if not m:
            return None
        width, height, tex_h, tlut_h, fmt = m.group(1), m.group(2), m.group(3), m.group(4), m.group(5)
        # Dolphin wildcard order: exact already tried; then tex+$ ; then $+tlut.
        if tlut_h:
            for candidate in (
                f"tex1_{width}x{height}_{tex_h.lower()}_${fmt}",
                f"tex1_{width}x{height}_${tlut_h.lower()}_{fmt}",
            ):
                hit = self._by_stem.get(candidate.lower())
                if hit is not None:
                    return hit
            # mip variant wildcards are rare; skip.
        return None

    def png_for_stem(self, stem: str) -> bytes | None:
        path = self.resolve_stem(stem)
        if path is None:
            self.misses += 1
            return None
        key = path.stem.lower()
        cached = self._png_mem.get(key)
        if cached is not None:
            self.hits += 1
            return cached
        if self.cache_dir is not None:
            disk = self.cache_dir / f"{path.stem}.png"
            if disk.is_file():
                cached = disk.read_bytes()
                self._png_mem[key] = cached
                self.hits += 1
                return cached
        try:
            image = decode_dds(path)
            png = image_png_bytes(image)
        except Exception:
            self.decode_errors += 1
            self.misses += 1
            return None
        self._png_mem[key] = png
        if self.cache_dir is not None:
            self.cache_dir.mkdir(parents=True, exist_ok=True)
            disk = self.cache_dir / f"{path.stem}.png"
            if not disk.exists():
                disk.write_bytes(png)
        self.hits += 1
        return png

    def lookup_png(
        self,
        texture: bytes,
        width: int,
        height: int,
        fmt: int,
        tlut: bytes | None = None,
    ) -> bytes | None:
        if width <= 0 or height <= 0 or fmt not in _BLOCK:
            self.misses += 1
            return None
        stem = dolphin_texture_stem(texture, width, height, fmt, tlut)
        return self.png_for_stem(stem)

    def stats(self) -> dict[str, int]:
        return {
            "indexed": self.size,
            "hits": self.hits,
            "misses": self.misses,
            "decode_errors": self.decode_errors,
        }


_pack_singleton: AchdPack | None = None
_pack_key: tuple[str, str] | None = None


def load_achd_pack(root: Optional[Path], cache_dir: Optional[Path] = None) -> AchdPack | None:
    """Load/index an ACHD tree. Returns None when disabled or missing."""
    global _pack_singleton, _pack_key
    if root is None:
        return None
    root = root.expanduser().resolve()
    if not root.is_dir():
        return None
    cache = (cache_dir.expanduser().resolve() if cache_dir else None)
    key = (str(root), str(cache) if cache else "")
    if _pack_singleton is not None and _pack_key == key:
        return _pack_singleton
    pack = AchdPack(root, cache)
    _pack_singleton = pack
    _pack_key = key
    return pack


def clear_achd_cache() -> None:
    global _pack_singleton, _pack_key
    _pack_singleton = None
    _pack_key = None


def maybe_hd_png(
    pack: AchdPack | None,
    texture: bytes,
    width: int,
    height: int,
    fmt: int,
    tlut: bytes | None = None,
) -> bytes | None:
    if pack is None:
        return None
    return pack.lookup_png(texture, width, height, fmt, tlut)
