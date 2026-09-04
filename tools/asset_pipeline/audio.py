"""Unpack `audiorom.img`, extract samples, and render test-set BGM to OGG."""

from __future__ import annotations

import json
import re
import struct
from pathlib import Path
from typing import Any, Optional

from .audio_bank import (
    SampleDecoder,
    banks_for_seq,
    load_bank,
    parse_arc_entries,
    parse_audiomap_bytes,
)
from .audio_seq import encode_ogg, render_sequence, write_wav
from .audio_vadpcm import decode_vadpcm_frame
from .config import PipelineConfig
from .fgdata import _guess_decomp

# `AudiodataHeaderStart` in ac-decomp `audioheaders.c`.
SEQ_OFFSET = 0x00000000
SEQ_SIZE = 0x000CF700
BANK_OFFSET = 0x000CF700
BANK_SIZE = 0x00067C80
WAVE_OFFSET = 0x00137380
WAVE_SIZE = 0x006B33E0
AUDIOROM_SIZE = WAVE_OFFSET + WAVE_SIZE
SEQ_COUNT = 249
BANK_COUNT = 159
WAVE_COUNT = 6

TEST_SET_IDS = (
    "title",
    "intro_kk",
    "intro_train",
    "intro_arrive",
    "field_08",
    "field_14",
    "field_20",
    "shop0",
    "rain",
    "enter_house",
)

## `Na_TTKK_ARM(TRUE)` during player-select (post-staffroll): mute intro_kk subtracks 0–2.
MUTE_SUBTRACKS_BY_ID: dict[str, tuple[int, ...]] = {
    "intro_kk": (0, 1, 2),
}

CATALOG_DIR = "audio"
BGM_SUBDIR = "bgm"


def find_audiorom(cfg: PipelineConfig) -> Optional[Path]:
    candidates = [
        cfg.extracted_disc / "files" / "audiorom.img",
        cfg.game_files / "files" / "audiorom.img" if cfg.game_files.is_dir() else None,
        cfg.game_files if cfg.game_files.is_file() and cfg.game_files.name == "audiorom.img" else None,
    ]
    files_dir = cfg.game_files if cfg.game_files.name == "files" else None
    if files_dir is not None:
        candidates.append(files_dir / "audiorom.img")
    for path in candidates:
        if path is not None and path.is_file():
            return path
    return None


def parse_seq_entries(src: str) -> list[dict[str, int]]:
    return [{"index": e.index, "addr": e.addr, "size": e.size} for e in parse_arc_entries(src, "AudioseqHeaderStart")]


def parse_seq_table(src: str) -> list[int]:
    match = re.search(r"SEQ_TABLE\[256\]\s*=\s*\{", src)
    if match is None:
        return []
    values = [int(v) for v in re.findall(r"\d+", src[match.end() : match.end() + 4000])]
    return values[:256]


def parse_bgm_ids(src: str) -> dict[str, int]:
    match = re.search(r"typedef enum bgm_e\s*\{(.*?)\}\s*BGM_e", src, re.S)
    if match is None:
        return {}
    out: dict[str, int] = {}
    index = 0
    for raw in match.group(1).split(","):
        line = raw.strip()
        if not line or line.startswith("/*"):
            continue
        line = re.sub(r"/\*.*?\*/", "", line).strip()
        if not line.startswith("BGM_"):
            continue
        if "=" in line:
            name, val = line.split("=", 1)
            name = name.strip()
            index = int(val.strip(), 0)
        else:
            name = line
        key = _bgm_key(name)
        out[key] = index
        index += 1
    return out


def _bgm_key(enum_name: str) -> str:
    return enum_name.removeprefix("BGM_").lower()


def catalog_id_for_hour(hour: int) -> str:
    return "field_%02d" % (hour % 24)


def convert_audio(cfg: PipelineConfig, decomp_root: Optional[Path] = None) -> dict[str, Any]:
    src = find_audiorom(cfg)
    if src is None:
        return {
            "error": "audiorom.img not found. Extract the disc (files/) first.",
            "converted": 0,
        }
    blob = src.read_bytes()
    if len(blob) < AUDIOROM_SIZE:
        return {
            "error": f"audiorom.img is {len(blob)} bytes; expected at least {AUDIOROM_SIZE}",
            "converted": 0,
        }

    decomp = decomp_root or cfg.decomp_root or _guess_decomp(cfg)
    seq_entries = _load_seq_entries(decomp)
    seq_table = _load_seq_table(decomp)
    bgm_ids = _load_bgm_ids(decomp)

    stage = cfg.converted / CATALOG_DIR
    stage.mkdir(parents=True, exist_ok=True)
    (stage / "audioseq.bin").write_bytes(blob[SEQ_OFFSET : SEQ_OFFSET + SEQ_SIZE])
    (stage / "audiobank.bin").write_bytes(blob[BANK_OFFSET : BANK_OFFSET + BANK_SIZE])
    (stage / "audiowave.bin").write_bytes(blob[WAVE_OFFSET : WAVE_OFFSET + WAVE_SIZE])

    seq_dir = stage / "seq"
    seq_dir.mkdir(parents=True, exist_ok=True)
    wanted_seq = _wanted_seq_indices(cfg, bgm_ids, seq_table)
    sliced = 0
    seq_blobs: dict[int, bytes] = {}
    for entry in seq_entries:
        if wanted_seq and entry["index"] not in wanted_seq:
            continue
        start = entry["addr"]
        end = start + entry["size"]
        if start < 0 or end > SEQ_SIZE:
            continue
        data = blob[SEQ_OFFSET + start : SEQ_OFFSET + end]
        (seq_dir / f"{entry['index']:03d}.bin").write_bytes(data)
        seq_blobs[entry["index"]] = data
        sliced += 1

    header_src = _header_source(decomp)
    bank_entries = parse_arc_entries(header_src, "AudiobankHeaderStart") if header_src else []
    wave_entries = parse_arc_entries(header_src, "AudiowaveHeaderStart") if header_src else []
    map_bytes = parse_audiomap_bytes(header_src) if header_src else b""
    audiobank = blob[BANK_OFFSET : BANK_OFFSET + BANK_SIZE]
    audiowave = blob[WAVE_OFFSET : WAVE_OFFSET + WAVE_SIZE]
    wave_groups = _slice_wave_groups(audiowave, wave_entries)

    entries = _catalog_entries(cfg, bgm_ids, seq_table, seq_entries)
    wanted_banks = _wanted_bank_ids(entries, map_bytes)
    decoder = SampleDecoder(wave_groups)
    loaded_banks = {}
    bank_dir = stage / "bank"
    bank_dir.mkdir(parents=True, exist_ok=True)
    for entry in bank_entries:
        if wanted_banks and entry.index not in wanted_banks:
            continue
        start = entry.addr
        end = start + entry.size
        if start < 0 or end > len(audiobank):
            continue
        raw = audiobank[start:end]
        (bank_dir / f"{entry.index:03d}.bin").write_bytes(raw)
        loaded_banks[entry.index] = load_bank(raw, entry, wave_groups, decoder)

    wave_debug = _write_debug_waves(stage / "waves", loaded_banks)
    rendered = _render_entries(cfg, entries, seq_blobs, loaded_banks, map_bytes, stage)
    any_rendered = any(e.get("rendered") for e in entries)
    catalog = {
        "source": "files/audiorom.img",
        "seq_count": len(seq_entries) or SEQ_COUNT,
        "bank_count": len(bank_entries) or BANK_COUNT,
        "wave_count": len(wave_entries) or WAVE_COUNT,
        "test_set_only": bool(cfg.test_set_only),
        "rendered": any_rendered,
        "bgm": entries,
    }
    out_dir = cfg.godot_generated / CATALOG_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / BGM_SUBDIR).mkdir(parents=True, exist_ok=True)
    text = json.dumps(catalog, indent=2) + "\n"
    (out_dir / "catalog.json").write_text(text, encoding="utf-8")
    (stage / "catalog.json").write_text(text, encoding="utf-8")
    (stage / "manifest.json").write_text(
        json.dumps(
            {
                "audiorom": str(src),
                "size": len(blob),
                "seq_entries": len(seq_entries),
                "seq_sliced": sliced,
                "banks_loaded": len(loaded_banks),
                "debug_waves": wave_debug,
                "bgm": len(entries),
                "rendered": rendered,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    return {
        "converted": 1,
        "output": str(out_dir),
        "seq_entries": len(seq_entries),
        "seq_sliced": sliced,
        "banks_loaded": len(loaded_banks),
        "bgm": len(entries),
        "rendered": rendered,
    }


def _load_seq_entries(decomp: Optional[Path]) -> list[dict[str, int]]:
    if decomp is None:
        return []
    path = decomp / "src" / "static" / "jaudio_NES" / "game" / "audioheaders.c"
    if not path.is_file():
        return []
    return parse_seq_entries(path.read_text(encoding="utf-8", errors="replace"))


def _load_seq_table(decomp: Optional[Path]) -> list[int]:
    if decomp is None:
        return []
    path = decomp / "src" / "static" / "jaudio_NES" / "game" / "game64.c_inc"
    if not path.is_file():
        return []
    return parse_seq_table(path.read_text(encoding="utf-8", errors="replace"))


def _load_bgm_ids(decomp: Optional[Path]) -> dict[str, int]:
    if decomp is None:
        return {}
    path = decomp / "include" / "audio_defs.h"
    if not path.is_file():
        return {}
    return parse_bgm_ids(path.read_text(encoding="utf-8", errors="replace"))


def _wanted_seq_indices(
    cfg: PipelineConfig, bgm_ids: dict[str, int], seq_table: list[int]
) -> set[int]:
    if not cfg.test_set_only:
        return set()
    wanted: set[int] = set()
    for key in TEST_SET_IDS:
        bgm_num = bgm_ids.get(key)
        if bgm_num is None or bgm_num < 0 or bgm_num >= len(seq_table):
            continue
        wanted.add(seq_table[bgm_num])
    return wanted


def _catalog_entries(
    cfg: PipelineConfig,
    bgm_ids: dict[str, int],
    seq_table: list[int],
    seq_entries: list[dict[str, int]],
) -> list[dict[str, Any]]:
    keys = list(TEST_SET_IDS) if cfg.test_set_only else _all_catalog_keys(bgm_ids)
    size_by_index = {e["index"]: e["size"] for e in seq_entries}
    out: list[dict[str, Any]] = []
    for key in keys:
        bgm_num = bgm_ids.get(key, -1)
        seq = seq_table[bgm_num] if 0 <= bgm_num < len(seq_table) else -1
        out.append(
            {
                "id": key,
                "bgm_num": bgm_num,
                "seq": seq,
                "seq_size": size_by_index.get(seq, 0),
                "path": f"{BGM_SUBDIR}/{key}.ogg",
                "loop": True,
                "loop_start_sec": 0.0,
                "rendered": False,
            }
        )
    return out


def _all_catalog_keys(bgm_ids: dict[str, int]) -> list[str]:
    skip = {"silence"}
    keys = [k for k, _n in sorted(bgm_ids.items(), key=lambda kv: kv[1]) if k not in skip]
    return keys


def _header_source(decomp: Optional[Path]) -> str:
    if decomp is None:
        return ""
    path = decomp / "src" / "static" / "jaudio_NES" / "game" / "audioheaders.c"
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def _slice_wave_groups(audiowave: bytes, wave_entries: list) -> list[bytes]:
    groups: list[bytes] = []
    for entry in wave_entries:
        start = entry.addr
        end = start + entry.size
        if start < 0 or end > len(audiowave):
            groups.append(b"")
            continue
        groups.append(audiowave[start:end])
    if not groups:
        groups.append(audiowave)
    return groups


def _wanted_bank_ids(entries: list[dict[str, Any]], map_bytes: bytes) -> set[int]:
    wanted: set[int] = set()
    for rec in entries:
        seq = int(rec.get("seq", -1))
        for bank_id in banks_for_seq(map_bytes, seq):
            wanted.add(bank_id)
    return wanted


def _write_debug_waves(wave_dir: Path, banks: dict) -> int:
    wave_dir.mkdir(parents=True, exist_ok=True)
    written = 0
    for bank_id, bank in list(banks.items())[:2]:
        for inst_i, inst in enumerate(bank.instruments[:8]):
            if inst is None or inst.normal is None:
                continue
            pcm = inst.normal.pcm
            frames = b"".join(int(s).to_bytes(2, "little", signed=True) for s in pcm)
            # stereo-less mono wav via audio_seq helper expects interleaved stereo; write mono here.
            path = wave_dir / f"bank{bank_id:03d}_inst{inst_i:02d}.wav"
            _write_mono_wav(path, frames, 32000)
            written += 1
            if written >= 8:
                return written
    return written


def _write_mono_wav(path: Path, pcm: bytes, rate: int) -> None:
    import wave as _wave

    path.parent.mkdir(parents=True, exist_ok=True)
    with _wave.open(str(path), "w") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(pcm)


def _render_entries(
    cfg: PipelineConfig,
    entries: list[dict[str, Any]],
    seq_blobs: dict[int, bytes],
    banks: dict,
    map_bytes: bytes,
    stage: Path,
) -> int:
    wav_dir = stage / "wav"
    wav_dir.mkdir(parents=True, exist_ok=True)
    out_bgm = cfg.godot_generated / CATALOG_DIR / BGM_SUBDIR
    out_bgm.mkdir(parents=True, exist_ok=True)
    rendered = 0
    for rec in entries:
        seq_idx = int(rec.get("seq", -1))
        seq = seq_blobs.get(seq_idx)
        if not seq:
            continue
        seq_banks = banks_for_seq(map_bytes, seq_idx)
        default_bank = seq_banks[-1] if seq_banks else 0
        used = {b: banks[b] for b in seq_banks if b in banks}
        if not used:
            continue
        try:
            mute = list(MUTE_SUBTRACKS_BY_ID.get(str(rec.get("id", "")), ()))
            result = render_sequence(seq, used, default_bank, seq_banks, mute_subtracks=mute)
        except (ValueError, struct.error, IndexError) as exc:
            rec["render_error"] = str(exc)
            continue
        if result.notes <= 0 or result.duration_sec < 0.4:
            rec["render_error"] = f"silent ({result.notes} notes, {result.duration_sec:.2f}s)"
            continue
        wav_path = wav_dir / f"{rec['id']}.wav"
        write_wav(wav_path, result.pcm, result.rate)
        ogg_path = out_bgm / f"{rec['id']}.ogg"
        wav_out = out_bgm / f"{rec['id']}.wav"
        if encode_ogg(wav_path, ogg_path):
            rec["path"] = f"{BGM_SUBDIR}/{rec['id']}.ogg"
        else:
            wav_out.write_bytes(wav_path.read_bytes())
            rec["path"] = f"{BGM_SUBDIR}/{rec['id']}.wav"
        rec["rendered"] = True
        rec["loop_start_sec"] = round(result.loop_start_sec, 3)
        rec["duration_sec"] = round(result.duration_sec, 3)
        rec["notes"] = result.notes
        rec.pop("render_error", None)
        rendered += 1
    return rendered
