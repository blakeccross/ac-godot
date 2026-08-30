"""Parse Neos CTL banks and decode samples from `audiowave.bin`."""

from __future__ import annotations

import re
import struct
from dataclasses import dataclass, field
from typing import Optional

from .audio_adsr import DEFAULT_ENV, parse_env_table
from .audio_vadpcm import book_from_shorts, decode_vadpcm

CODEC_ADPCM = 0
CODEC_S8 = 1
CODEC_S16_INMEMORY = 2
CODEC_SMALL_ADPCM = 3
CODEC_S16 = 5


@dataclass
class ArcEntry:
    index: int
    addr: int
    size: int
    param0: int = 0
    param1: int = 0
    param2: int = 0

    @property
    def wave_bank_id0(self) -> int:
        return (self.param0 >> 8) & 0xFF

    @property
    def wave_bank_id1(self) -> int:
        return self.param0 & 0xFF

    @property
    def num_instruments(self) -> int:
        return (self.param1 >> 8) & 0xFF

    @property
    def num_drums(self) -> int:
        return self.param1 & 0xFF

    @property
    def num_sfx(self) -> int:
        return self.param2 & 0xFFFF


@dataclass
class PcmSample:
    pcm: list[int]
    loop_start: int
    loop_end: int
    tuning: float
    sample_rate_hint: int = 32000


@dataclass
class Instrument:
    low: Optional[PcmSample]
    normal: Optional[PcmSample]
    high: Optional[PcmSample]
    range_low: int
    range_high: int
    decay_idx: int = 0
    envelope: list[tuple[int, int]] = field(default_factory=list)

    def __post_init__(self) -> None:
        if not self.envelope:
            self.envelope = list(DEFAULT_ENV)

    def sample_for(self, semitone: int) -> Optional[PcmSample]:
        if semitone < self.range_low:
            return self.low or self.normal
        if semitone <= self.range_high:
            return self.normal
        return self.high or self.normal


@dataclass
class Drum:
    sample: Optional[PcmSample]
    pan: int
    decay_idx: int = 0
    envelope: list[tuple[int, int]] = field(default_factory=list)

    def __post_init__(self) -> None:
        if not self.envelope:
            self.envelope = list(DEFAULT_ENV)


@dataclass
class Bank:
    bank_id: int
    instruments: list[Optional[Instrument]] = field(default_factory=list)
    drums: list[Optional[Drum]] = field(default_factory=list)
    sfx: list[Optional[PcmSample]] = field(default_factory=list)
    wave_bank_id0: int = 0
    wave_bank_id1: int = 0xFF


def parse_arc_entries(src: str, header_name: str) -> list[ArcEntry]:
    start = src.find(header_name)
    if start < 0:
        return []
    stop = src.find("ArcHeader ", start + 1)
    if stop < 0:
        stop = src.find("u8 AudiomapHeaderStart", start)
    block = src[start:stop] if stop > start else src[start:]
    addrs = [int(m.group(1), 16) for m in re.finditer(r"0x([0-9A-Fa-f]+),\s*/\*\s*rom addr", block)]
    sizes = [int(m.group(1), 16) for m in re.finditer(r"0x([0-9A-Fa-f]+),\s*/\*\s*size", block)]
    p0s = [int(m.group(1), 16) for m in re.finditer(r"0x([0-9A-Fa-f]+),\s*/\*\s*param0", block)]
    p1s = [int(m.group(1), 16) for m in re.finditer(r"0x([0-9A-Fa-f]+),\s*/\*\s*param1", block)]
    p2s = [int(m.group(1), 16) for m in re.finditer(r"0x([0-9A-Fa-f]+),\s*/\*\s*param2", block)]
    n = min(len(addrs), len(sizes))
    out: list[ArcEntry] = []
    for i in range(n):
        out.append(
            ArcEntry(
                index=i,
                addr=addrs[i],
                size=sizes[i],
                param0=p0s[i] if i < len(p0s) else 0,
                param1=p1s[i] if i < len(p1s) else 0,
                param2=p2s[i] if i < len(p2s) else 0,
            )
        )
    return out


def parse_audiomap_bytes(src: str) -> bytes:
    start = src.find("AudiomapHeaderStart")
    if start < 0:
        return b""
    brace = src.find("{", start)
    end = src.find("};", brace)
    if brace < 0 or end < 0:
        return b""
    block = src[brace + 1 : end]
    block = re.sub(r"/\*.*?\*/", "", block, flags=re.S)
    block = re.sub(r"//.*?$", "", block, flags=re.M)
    values = [int(tok, 0) for tok in re.findall(r"0x[0-9A-Fa-f]+|\b\d+\b", block)]
    return bytes(v & 0xFF for v in values)


def banks_for_seq(map_bytes: bytes, seq_id: int) -> list[int]:
    if seq_id < 0 or seq_id * 2 + 1 >= len(map_bytes):
        return []
    idx = (map_bytes[seq_id * 2] << 8) | map_bytes[seq_id * 2 + 1]
    if idx >= len(map_bytes):
        return []
    count = map_bytes[idx]
    start = idx + 1
    return list(map_bytes[start : start + count])


def _u32(data: bytes, ofs: int) -> int:
    if ofs < 0 or ofs + 4 > len(data):
        return 0
    return struct.unpack_from(">I", data, ofs)[0]


def _s32(data: bytes, ofs: int) -> int:
    if ofs < 0 or ofs + 4 > len(data):
        return 0
    return struct.unpack_from(">i", data, ofs)[0]


def _f32(data: bytes, ofs: int) -> float:
    if ofs < 0 or ofs + 4 > len(data):
        return 1.0
    value = struct.unpack_from(">f", data, ofs)[0]
    if value != value or value == 0.0:  # noqa: PLR0124  (NaN)
        return 1.0
    return float(value)


def _u16(data: bytes, ofs: int) -> int:
    if ofs < 0 or ofs + 2 > len(data):
        return 0
    return struct.unpack_from(">H", data, ofs)[0]


def _s16_table(data: bytes, ofs: int, count: int) -> list[int]:
    end = min(len(data), ofs + count * 2)
    n = (end - ofs) // 2
    return list(struct.unpack_from(">" + "h" * n, data, ofs))


class SampleDecoder:
    def __init__(self, wave_groups: list[bytes]):
        self._wave_groups = wave_groups
        self._cache: dict[tuple[int, int, int, int], list[int]] = {}

    def decode_wavetable(self, bank: bytes, wt_ofs: int, wave0: bytes, wave1: bytes) -> Optional[tuple[list[int], int, int]]:
        if wt_ofs == 0 or wt_ofs + 16 > len(bank):
            return None
        flags = _u32(bank, wt_ofs)
        codec = (flags >> 28) & 0x7
        medium = (flags >> 26) & 0x3
        size = flags & 0xFFFFFF
        sample_ofs = _u32(bank, wt_ofs + 4)
        loop_ofs = _u32(bank, wt_ofs + 8)
        book_ofs = _u32(bank, wt_ofs + 12)
        wave = wave0 if medium in (0, 2, 3) else wave1
        if medium == 1:
            wave = wave1
        key = (id(wave), sample_ofs, size, book_ofs)
        pcm = self._cache.get(key)
        if pcm is None:
            blob = wave[sample_ofs : sample_ofs + size] if sample_ofs < len(wave) else b""
            if codec in (CODEC_S16, CODEC_S16_INMEMORY):
                n = len(blob) // 2
                pcm = list(struct.unpack(">" + "h" * n, blob[: n * 2])) if n else []
            elif codec == CODEC_S8:
                pcm = [b - 256 if b >= 128 else b for b in blob]
                pcm = [s << 8 for s in pcm]
            else:
                order = _s32(bank, book_ofs) if book_ofs else 2
                npred = _s32(bank, book_ofs + 4) if book_ofs else 2
                if order < 1 or order > 8:
                    order = 2
                if npred < 1 or npred > 16:
                    npred = 2
                shorts = _s16_table(bank, book_ofs + 8, order * npred * 8)
                book = book_from_shorts(order, npred, shorts)
                pcm = decode_vadpcm(blob, book)
            self._cache[key] = pcm
        loop_start = 0
        loop_end = 0
        if loop_ofs and loop_ofs + 16 <= len(bank):
            loop_start = _u32(bank, loop_ofs)
            loop_end = _u32(bank, loop_ofs + 4)
            count = _u32(bank, loop_ofs + 8)
            sample_end = _u32(bank, loop_ofs + 12)
            if loop_end <= loop_start:
                loop_end = sample_end
            if count == 0:
                loop_start = 0
                loop_end = 0
        return pcm, loop_start, loop_end


def _tuned(decoder: SampleDecoder, bank: bytes, ofs: int, wave0: bytes, wave1: bytes) -> Optional[PcmSample]:
    if ofs + 8 > len(bank):
        return None
    wt_ofs = _u32(bank, ofs)
    tuning = _f32(bank, ofs + 4)
    decoded = decoder.decode_wavetable(bank, wt_ofs, wave0, wave1)
    if decoded is None or not decoded[0]:
        return None
    pcm, loop_start, loop_end = decoded
    return PcmSample(pcm=pcm, loop_start=loop_start, loop_end=loop_end, tuning=tuning)


def load_bank(
    bank_bytes: bytes,
    entry: ArcEntry,
    wave_groups: list[bytes],
    decoder: Optional[SampleDecoder] = None,
) -> Bank:
    decoder = decoder or SampleDecoder(wave_groups)
    n_inst = min(entry.num_instruments, 126)
    n_drums = entry.num_drums
    n_sfx = entry.num_sfx
    wave0 = _wave(wave_groups, entry.wave_bank_id0)
    wave1 = _wave(wave_groups, entry.wave_bank_id1)
    loaded = Bank(
        bank_id=entry.index,
        wave_bank_id0=entry.wave_bank_id0,
        wave_bank_id1=entry.wave_bank_id1,
    )
    perc_ofs = _u32(bank_bytes, 0)
    sfx_ofs = _u32(bank_bytes, 4)
    if perc_ofs and n_drums:
        for i in range(n_drums):
            ptr = _u32(bank_bytes, perc_ofs + i * 4)
            if ptr == 0 or ptr + 16 > len(bank_bytes):
                loaded.drums.append(None)
                continue
            decay_idx = bank_bytes[ptr]
            pan = bank_bytes[ptr + 1]
            sample = _tuned(decoder, bank_bytes, ptr + 4, wave0, wave1)
            env_ofs = _u32(bank_bytes, ptr + 12)
            loaded.drums.append(
                Drum(
                    sample=sample,
                    pan=pan,
                    decay_idx=decay_idx,
                    envelope=parse_env_table(bank_bytes, env_ofs),
                )
            )
    else:
        loaded.drums = [None] * n_drums
    if sfx_ofs and n_sfx:
        for i in range(n_sfx):
            loaded.sfx.append(_tuned(decoder, bank_bytes, sfx_ofs + i * 8, wave0, wave1))
    else:
        loaded.sfx = [None] * n_sfx
    for i in range(n_inst):
        inst_ofs = _u32(bank_bytes, 8 + i * 4)
        if inst_ofs == 0 or inst_ofs + 0x20 > len(bank_bytes):
            loaded.instruments.append(None)
            continue
        range_low = bank_bytes[inst_ofs + 1]
        range_high = bank_bytes[inst_ofs + 2]
        decay_idx = bank_bytes[inst_ofs + 3]
        env_ofs = _u32(bank_bytes, inst_ofs + 4)
        low = _tuned(decoder, bank_bytes, inst_ofs + 8, wave0, wave1) if range_low else None
        normal = _tuned(decoder, bank_bytes, inst_ofs + 16, wave0, wave1)
        high = _tuned(decoder, bank_bytes, inst_ofs + 24, wave0, wave1) if range_high != 0x7F else None
        loaded.instruments.append(
            Instrument(
                low=low,
                normal=normal,
                high=high,
                range_low=range_low,
                range_high=range_high,
                decay_idx=decay_idx,
                envelope=parse_env_table(bank_bytes, env_ofs),
            )
        )
    return loaded


def _wave(groups: list[bytes], wave_id: int) -> bytes:
    if wave_id == 0xFF or wave_id < 0 or wave_id >= len(groups):
        return groups[0] if groups else b""
    return groups[wave_id]
