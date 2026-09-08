"""Unpack `audiorom.img`, extract samples, and render BGM / SE / voice to OGG."""

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
from .audio_seq import (
    SE_BANKS,
    SE_SEQ_INDEX,
    VOICE_BANKS,
    VOICE_SEQ_BY_SPEC,
    encode_ogg,
    render_se,
    render_sequence,
    render_voice_phoneme,
    write_wav,
)
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

## Phoneme instrument ids after henkan / digraph (`0x00`–`0x77`, `Na_VoiceSe` cap).
VOICE_PHONEME_MAX = 0x77

## `Na_TTKK_ARM` toggles these guitar subtracks live. Bed OGG bakes them muted;
## a matching `*_arm` stem keeps only those tracks for runtime mute/unmute.
ARM_SUBTRACKS_BY_ID: dict[str, tuple[int, ...]] = {
    "intro_kk": (0, 1, 2),
}
AUDIO_SUBTRACK_NUM = 16

CATALOG_DIR = "audio"
BGM_SUBDIR = "bgm"
SFX_SUBDIR = "sfx"
VOICE_SUBDIR = "voice"


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


def _se_key(enum_name: str) -> str:
    return enum_name.removeprefix("NA_SE_").lower()


def _eval_se_expr(expr: str, known: Optional[dict[str, int]] = None) -> Optional[int]:
    """Evaluate `0x6D`, `MONO(0x6D)`, `SE_DIST_REVERB(0x10F)`, or a prior `NA_SE_*` name."""
    expr = expr.strip()
    if not expr:
        return None
    known = known or {}
    mono = re.fullmatch(r"MONO\((.+)\)", expr)
    if mono:
        inner = _eval_se_expr(mono.group(1), known)
        return None if inner is None else (inner | 0x1000) & 0xFFFF
    for name, bit in (
        ("SE_DIST_REVERB", 0x2000),
        ("SE_ECHO", 0x4000),
        ("SE_SINGLETON", 0x8000),
    ):
        m = re.fullmatch(rf"{name}\((.+)\)", expr)
        if m:
            inner = _eval_se_expr(m.group(1), known)
            return None if inner is None else (inner | bit) & 0xFFFF
    if expr in known:
        return known[expr]
    if expr.startswith("NA_SE_"):
        key = _se_key(expr)
        if key in known:
            return known[key]
        # Allow resolving by full enum name stored as key.
        return known.get(expr)
    try:
        return int(expr, 0) & 0xFFFF
    except ValueError:
        return None


def parse_se_ids(src: str) -> dict[str, int]:
    """Parse `typedef enum audio_sound_effects` → `{cursol: 1, bebe: 0x106D, …}`."""
    match = re.search(
        r"typedef enum audio_sound_effects\s*\{(.*?)\}\s*AudioSE",
        src,
        re.S,
    )
    if match is None:
        return {}
    out: dict[str, int] = {}
    index = 0
    for raw in match.group(1).split(","):
        line = raw.strip()
        if not line or line.startswith("/*"):
            continue
        line = re.sub(r"/\*.*?\*/", "", line)
        # `// Footsteps` etc. can sit on the same comma-chunk as the next enumerator.
        line = re.sub(r"//.*?$", "", line, flags=re.M).strip()
        if not line.startswith("NA_SE_"):
            continue
        if "=" in line:
            name, val = line.split("=", 1)
            name = name.strip()
            parsed = _eval_se_expr(val.strip(), out)
            if parsed is None:
                continue
            index = parsed
        else:
            name = line
        key = _se_key(name)
        out[key] = index & 0xFFFF
        # Also stash under full enum for nested MONO(NA_SE_…) refs.
        out[name] = index & 0xFFFF
        index = (index + 1) & 0xFFFF
    # Drop full-enum aliases from the public catalog map.
    return {k: v for k, v in out.items() if not k.startswith("NA_SE_")}


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
    se_ids = _load_se_ids(decomp)

    stage = cfg.converted / CATALOG_DIR
    stage.mkdir(parents=True, exist_ok=True)
    (stage / "audioseq.bin").write_bytes(blob[SEQ_OFFSET : SEQ_OFFSET + SEQ_SIZE])
    (stage / "audiobank.bin").write_bytes(blob[BANK_OFFSET : BANK_OFFSET + BANK_SIZE])
    (stage / "audiowave.bin").write_bytes(blob[WAVE_OFFSET : WAVE_OFFSET + WAVE_SIZE])

    seq_dir = stage / "seq"
    seq_dir.mkdir(parents=True, exist_ok=True)
    sliced = 0
    seq_blobs: dict[int, bytes] = {}
    for entry in seq_entries:
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

    entries = _catalog_entries(bgm_ids, seq_table, seq_entries)
    sfx_entries = _sfx_catalog_entries(se_ids)
    voice_entries = _voice_catalog_entries()
    wanted_banks = _wanted_bank_ids(entries, map_bytes)
    wanted_banks |= set(SE_BANKS)
    for seq_idx in VOICE_BANKS:
        wanted_banks.add(VOICE_BANKS[seq_idx])
        for bank_id in banks_for_seq(map_bytes, seq_idx):
            wanted_banks.add(bank_id)
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
    sfx_rendered = _render_sfx_entries(cfg, sfx_entries, seq_blobs, loaded_banks, map_bytes, stage)
    voice_rendered = _render_voice_entries(cfg, voice_entries, seq_blobs, loaded_banks, map_bytes, stage)
    any_rendered = any(e.get("rendered") for e in entries) or any(
        e.get("rendered") for e in sfx_entries
    ) or any(e.get("rendered") for e in voice_entries)
    catalog = {
        "source": "files/audiorom.img",
        "seq_count": len(seq_entries) or SEQ_COUNT,
        "bank_count": len(bank_entries) or BANK_COUNT,
        "wave_count": len(wave_entries) or WAVE_COUNT,
        "rendered": any_rendered,
        "bgm": entries,
        "sfx": sfx_entries,
        "voice": voice_entries,
    }
    out_dir = cfg.godot_generated / CATALOG_DIR
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / BGM_SUBDIR).mkdir(parents=True, exist_ok=True)
    (out_dir / SFX_SUBDIR).mkdir(parents=True, exist_ok=True)
    (out_dir / VOICE_SUBDIR).mkdir(parents=True, exist_ok=True)
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
                "sfx": len(sfx_entries),
                "voice": len(voice_entries),
                "rendered": rendered,
                "sfx_rendered": sfx_rendered,
                "voice_rendered": voice_rendered,
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
        "sfx": len(sfx_entries),
        "voice": len(voice_entries),
        "rendered": rendered,
        "sfx_rendered": sfx_rendered,
        "voice_rendered": voice_rendered,
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


def _load_se_ids(decomp: Optional[Path]) -> dict[str, int]:
    if decomp is None:
        return {}
    path = decomp / "include" / "audio_defs.h"
    if not path.is_file():
        return {}
    return parse_se_ids(path.read_text(encoding="utf-8", errors="replace"))


def _catalog_entries(
    bgm_ids: dict[str, int],
    seq_table: list[int],
    seq_entries: list[dict[str, int]],
) -> list[dict[str, Any]]:
    keys = _all_catalog_keys(bgm_ids)
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


def _sfx_catalog_entries(se_ids: dict[str, int]) -> list[dict[str, Any]]:
    keys = [k for k, _n in sorted(se_ids.items(), key=lambda kv: (kv[1], kv[0]))]
    out: list[dict[str, Any]] = []
    for key in keys:
        se_num = int(se_ids[key])
        out.append(
            {
                "id": key,
                "se_num": se_num,
                "seq": SE_SEQ_INDEX,
                "path": f"{SFX_SUBDIR}/{key}.ogg",
                "loop": False,
                "rendered": False,
            }
        )
    return out


def _voice_catalog_entries() -> list[dict[str, Any]]:
    phonemes = list(range(VOICE_PHONEME_MAX + 1))
    out: list[dict[str, Any]] = []
    for spec, seq_idx in sorted(VOICE_SEQ_BY_SPEC.items()):
        for phoneme in phonemes:
            out.append(
                {
                    "id": f"spec_{spec}/ph_{phoneme:02x}",
                    "spec": spec,
                    "phoneme": phoneme,
                    "seq": seq_idx,
                    "path": f"{VOICE_SUBDIR}/spec_{spec}/ph_{phoneme:02x}.ogg",
                    "loop": False,
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
        track_id = str(rec.get("id", ""))
        arm_tracks = list(ARM_SUBTRACKS_BY_ID.get(track_id, ()))
        try:
            result = render_sequence(
                seq, used, default_bank, seq_banks, mute_subtracks=arm_tracks
            )
        except (ValueError, struct.error, IndexError) as exc:
            rec["render_error"] = str(exc)
            continue
        if result.notes <= 0 or result.duration_sec < 0.4:
            rec["render_error"] = f"silent ({result.notes} notes, {result.duration_sec:.2f}s)"
            continue
        if not _write_bgm_file(wav_dir, out_bgm, track_id, result, rec):
            continue
        rec["rendered"] = True
        rec["loop_start_sec"] = round(result.loop_start_sec, 3)
        rec["duration_sec"] = round(result.duration_sec, 3)
        rec["notes"] = result.notes
        rec.pop("render_error", None)
        rendered += 1
        if not arm_tracks:
            continue
        # Solo the Na_TTKK_ARM guitar subtracks for runtime mute with the bed.
        bed_mute = [i for i in range(AUDIO_SUBTRACK_NUM) if i not in set(arm_tracks)]
        try:
            arm = render_sequence(
                seq, used, default_bank, seq_banks, mute_subtracks=bed_mute
            )
        except (ValueError, struct.error, IndexError) as exc:
            rec["arm_render_error"] = str(exc)
            continue
        if arm.notes <= 0:
            rec["arm_render_error"] = f"silent arm ({arm.notes} notes)"
            continue
        arm_rec: dict[str, Any] = {}
        if _write_bgm_file(wav_dir, out_bgm, f"{track_id}_arm", arm, arm_rec):
            rec["arm_path"] = arm_rec["path"]
            rec["arm_notes"] = arm.notes
            rec.pop("arm_render_error", None)
            rendered += 1
    return rendered


def _render_sfx_entries(
    cfg: PipelineConfig,
    entries: list[dict[str, Any]],
    seq_blobs: dict[int, bytes],
    banks: dict,
    map_bytes: bytes,
    stage: Path,
) -> int:
    seq = seq_blobs.get(SE_SEQ_INDEX)
    if not seq:
        for rec in entries:
            rec["render_error"] = f"missing seq {SE_SEQ_INDEX}"
        return 0
    seq_banks = banks_for_seq(map_bytes, SE_SEQ_INDEX) or list(SE_BANKS)
    default_bank = seq_banks[-1] if seq_banks else SE_BANKS[-1]
    used = {b: banks[b] for b in seq_banks if b in banks}
    if not used:
        for rec in entries:
            rec["render_error"] = "missing SE banks"
        return 0
    wav_dir = stage / "wav" / "sfx"
    wav_dir.mkdir(parents=True, exist_ok=True)
    out_sfx = cfg.godot_generated / CATALOG_DIR / SFX_SUBDIR
    out_sfx.mkdir(parents=True, exist_ok=True)
    rendered = 0
    for rec in entries:
        se_id = int(rec.get("se_num", -1))
        track_id = str(rec.get("id", ""))
        try:
            result = render_se(seq, used, default_bank, se_id, seq_banks)
        except (ValueError, struct.error, IndexError) as exc:
            rec["render_error"] = str(exc)
            continue
        if result.notes <= 0:
            rec["render_error"] = f"silent ({result.notes} notes, {result.duration_sec:.2f}s)"
            continue
        if not _write_oneshot_file(wav_dir, out_sfx, track_id, result, rec, SFX_SUBDIR):
            continue
        rec["rendered"] = True
        rec["duration_sec"] = round(result.duration_sec, 3)
        rec["notes"] = result.notes
        rec.pop("render_error", None)
        rendered += 1
    return rendered


def _render_voice_entries(
    cfg: PipelineConfig,
    entries: list[dict[str, Any]],
    seq_blobs: dict[int, bytes],
    banks: dict,
    map_bytes: bytes,
    stage: Path,
) -> int:
    wav_dir = stage / "wav" / "voice"
    wav_dir.mkdir(parents=True, exist_ok=True)
    out_voice = cfg.godot_generated / CATALOG_DIR / VOICE_SUBDIR
    out_voice.mkdir(parents=True, exist_ok=True)
    rendered = 0
    for rec in entries:
        seq_idx = int(rec.get("seq", -1))
        seq = seq_blobs.get(seq_idx)
        if not seq:
            rec["render_error"] = f"missing seq {seq_idx}"
            continue
        seq_banks = banks_for_seq(map_bytes, seq_idx)
        if not seq_banks:
            bank = VOICE_BANKS.get(seq_idx)
            seq_banks = [bank] if bank is not None else []
        default_bank = seq_banks[-1] if seq_banks else 0
        used = {b: banks[b] for b in seq_banks if b in banks}
        if not used:
            rec["render_error"] = "missing voice banks"
            continue
        phoneme = int(rec.get("phoneme", 0))
        spec = int(rec.get("spec", 1))
        file_id = f"spec_{spec}/ph_{phoneme:02x}"
        try:
            result = render_voice_phoneme(
                seq,
                used,
                default_bank,
                phoneme,
                seq_banks,
                voice_seq_ready=spec,
            )
        except (ValueError, struct.error, IndexError) as exc:
            rec["render_error"] = str(exc)
            continue
        if result.notes <= 0:
            rec["render_error"] = f"silent ({result.notes} notes, {result.duration_sec:.2f}s)"
            continue
        rel_dir = out_voice / f"spec_{spec}"
        rel_dir.mkdir(parents=True, exist_ok=True)
        stage_dir = wav_dir / f"spec_{spec}"
        stage_dir.mkdir(parents=True, exist_ok=True)
        if not _write_oneshot_file(
            stage_dir, rel_dir, f"ph_{phoneme:02x}", result, rec, f"{VOICE_SUBDIR}/spec_{spec}"
        ):
            continue
        rec["rendered"] = True
        rec["duration_sec"] = round(result.duration_sec, 3)
        rec["notes"] = result.notes
        rec.pop("render_error", None)
        rendered += 1
    return rendered


def _write_bgm_file(
    wav_dir: Path,
    out_bgm: Path,
    file_id: str,
    result: Any,
    rec: dict[str, Any],
) -> bool:
    wav_path = wav_dir / f"{file_id}.wav"
    write_wav(wav_path, result.pcm, result.rate)
    ogg_path = out_bgm / f"{file_id}.ogg"
    wav_out = out_bgm / f"{file_id}.wav"
    if encode_ogg(wav_path, ogg_path):
        rec["path"] = f"{BGM_SUBDIR}/{file_id}.ogg"
        return True
    wav_out.write_bytes(wav_path.read_bytes())
    rec["path"] = f"{BGM_SUBDIR}/{file_id}.wav"
    return True


def _write_oneshot_file(
    wav_dir: Path,
    out_dir: Path,
    file_id: str,
    result: Any,
    rec: dict[str, Any],
    path_prefix: str,
) -> bool:
    wav_path = wav_dir / f"{file_id}.wav"
    write_wav(wav_path, result.pcm, result.rate)
    ogg_path = out_dir / f"{file_id}.ogg"
    wav_out = out_dir / f"{file_id}.wav"
    if encode_ogg(wav_path, ogg_path):
        rec["path"] = f"{path_prefix}/{file_id}.ogg"
        return True
    wav_out.write_bytes(wav_path.read_bytes())
    rec["path"] = f"{path_prefix}/{file_id}.wav"
    return True
