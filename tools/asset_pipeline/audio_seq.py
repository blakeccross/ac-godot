"""Offline Neos sequence interpreter → PCM. Opcode meaning from ac-decomp `track.c`."""

from __future__ import annotations

import struct
import subprocess
import wave
from array import array
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from .audio_adsr import DEFAULT_ENV, Envelope, parse_env_table
from .audio_bank import Bank, Drum, Instrument, PcmSample
from .audio_mod import Sweep, Vibrato, VibratoParams, build_sweep
from .audio_tables import SUBTRACK_DECAY_IDX, UPDATES_PER_SEC, pcent, pcent2, pitch_ratio

AUDIO_TATUMS_PER_BEAT = 48
AUDIO_SUBTRACK_NUM = 16
NOTE_LAYERS = 4
NATIVE_RATE = 33476.156
MIX_RATE = 32000
MAX_TATUMS = 24000
MAX_CMDS = 8000
MAX_VOICES = 48
SCRIPT_END = -1
# 4 DSP updates per 60 Hz frame (`AG.audio_params.updates_per_frame`).
UPDATES_PER_SEC = 240.0
SUBTRACK_DECAY_IDX = 240

VOICE_PERCUSSION = 0
VOICE_SFX = 1
VOICE_INHERIT = 0xFF

DEFAULT_VTABLE = [12, 25, 38, 51, 57, 64, 71, 76, 83, 89, 96, 102, 109, 115, 121, 127]
DEFAULT_GTABLE = [229, 215, 201, 187, 173, 159, 145, 131, 117, 103, 89, 75, 61, 47, 33, 0]


def _s8(value: int) -> int:
    value &= 0xFF
    return value - 256 if value >= 128 else value


def _pitch(semitone: int) -> float:
    return pitch_ratio(semitone)


# SCOM_TABLE[cmd - 0xA0] from track.c (arg count in low 2 bits; type flags in 7..5).
SCOM_TABLE = [
    0x81, 0x00, 0x81, 0x00, 0x01, 0x00, 0x42, 0x01,  # A0-A7
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  # A8-AF
    0x81, 0x00, 0x81, 0x01, 0x00, 0x00, 0x00, 0x81,  # B0-B7
    0x01, 0x01, 0x01, 0x42, 0x81, 0x81, 0x01, 0x00,  # B8-BF
    0x00, 0x01, 0x81, 0x00, 0x00, 0x00, 0x01, 0x42,  # C0-C7
    0x01, 0x01, 0x01, 0x81, 0x01, 0x01, 0x81, 0x81,  # C8-CF
    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,  # D0-D7
    0x01, 0x01, 0x81, 0x01, 0x01, 0x01, 0x81, 0x01,  # D8-DF
    0x01, 0x03, 0x03, 0x01, 0x00, 0x01, 0x01, 0x81,  # E0-E7
    0x03, 0x01, 0x00, 0x02, 0x00, 0x01, 0x01, 0x82,  # E8-EF
    0x00, 0x01, 0x01, 0x01, 0x01, 0x81, 0x00, 0x00,  # F0-F7
    0x01, 0x81, 0x81, 0x81, 0x81, 0x00, 0x00, 0x00,  # F8-FF
]


class Cursor:
    def __init__(self, data: bytes, pc: int = 0) -> None:
        self.data = data
        self.pc = pc
        self.stack: list[int] = []
        self.loops: list[int] = []
        self.value = 0

    def u8(self) -> int:
        if self.pc >= len(self.data):
            return 0xFF
        b = self.data[self.pc]
        self.pc += 1
        return b

    def s16(self) -> int:
        hi = self.u8()
        lo = self.u8()
        value = (hi << 8) | lo
        return value - 0x10000 if value >= 0x8000 else value

    def u16(self) -> int:
        return self.s16() & 0xFFFF

    def varlen(self) -> int:
        value = self.u8()
        if value & 0x80:
            value = ((value & 0x7F) << 8) | self.u8()
        return value


@dataclass
class NotePlayer:
    cur: Cursor
    enabled: bool = False
    finished: bool = False
    muted: bool = False
    delay: int = 0
    last_delay: int = 0
    short_delay: int = 1
    gate_time: int = 128
    gate_delay: int = 0
    velocity: float = 0.0
    pan: int = 64
    transposition: int = 0
    inst_or_wave: int = VOICE_INHERIT
    inst_id: int = 0
    continuous: bool = False
    ignore_drum_pan: bool = False
    sample: Optional[PcmSample] = None
    freq_scale: float = 1.0
    sample_pos: float = 0.0
    playing: bool = False
    released: bool = False
    voice: Optional["Voice"] = None
    decay_idx: int = 0
    envelope: list[tuple[int, int]] = field(default_factory=lambda: list(DEFAULT_ENV))
    bend: float = 1.0
    porta_mode: int = 0
    porta_target: int = 0
    porta_time: int = 0


@dataclass
class SubTrack:
    idx: int
    cur: Cursor
    enabled: bool = False
    finished: bool = False
    stop_script: bool = False
    delay: int = 0
    bank_id: int = 0
    inst_or_wave: int = VOICE_INHERIT
    inst_id: int = 0
    has_instrument: bool = False
    volume: float = 1.0
    volume_scale: float = 1.0
    pan: int = 64
    transposition: int = 0
    freq_scale: float = 1.0
    large_notes: bool = False
    muted: bool = False
    notes: list[Optional[NotePlayer]] = field(default_factory=lambda: [None] * NOTE_LAYERS)
    pan_weight: int = 128
    adsr_decay: int = SUBTRACK_DECAY_IDX
    adsr_sustain: int = 0
    envelope: list[tuple[int, int]] = field(default_factory=lambda: list(DEFAULT_ENV))
    vibrato: VibratoParams = field(default_factory=VibratoParams)


@dataclass
class Group:
    cur: Cursor
    enabled: bool = True
    stop_script: bool = False
    delay: int = 0
    tempo: int = 120 * AUDIO_TATUMS_PER_BEAT
    bank_id: int = 0
    volume: float = 1.0
    transposition: int = 0
    vel_tbl: list[int] = field(default_factory=lambda: list(DEFAULT_VTABLE))
    gate_tbl: list[int] = field(default_factory=lambda: list(DEFAULT_GTABLE))
    port: list[int] = field(default_factory=lambda: [-1] * 8)
    subtracks: list[SubTrack] = field(default_factory=list)
    fade_volume: float = 1.0


@dataclass
class Voice:
    sample: PcmSample
    pos: float
    step: float
    left: float
    right: float
    envelope: Envelope = field(default_factory=Envelope)
    vibrato: Optional[Vibrato] = None
    sweep: Optional[Sweep] = None
    update_acc: float = 0.0
    env: float = 1.0
    released: bool = False


@dataclass
class RenderResult:
    pcm: bytes
    rate: int
    loop_start_sec: float
    duration_sec: float
    notes: int


def common_com(grp: Group, cur: Cursor, cmd: int, arg: int) -> int:
    if cmd == 0xFF:
        if not cur.stack:
            return SCRIPT_END
        cur.pc = cur.stack.pop()
        cur.loops.pop()
        return 0
    if cmd == 0xFD:
        return cur.varlen()
    if cmd == 0xFE:
        return 1
    if cmd == 0xFC:
        cur.stack.append(cur.pc)
        cur.loops.append(0)
        cur.pc = arg & 0xFFFF
        return 0
    if cmd == 0xF8:
        cur.loops.append(arg & 0xFF)
        cur.stack.append(cur.pc)
        return 0
    if cmd == 0xF7:
        if not cur.stack:
            return 0
        left = (cur.loops[-1] - 1) & 0xFF
        cur.loops[-1] = left
        if left != 0:
            cur.pc = cur.stack[-1]
        else:
            cur.stack.pop()
            cur.loops.pop()
        return 0
    if cmd == 0xF6:
        if cur.stack:
            cur.stack.pop()
            cur.loops.pop()
        return 0
    if cmd in (0xF5, 0xF9, 0xFA, 0xFB):
        addr = arg & 0xFFFF
        if cmd == 0xFA and cur.value != 0:
            return 0
        if cmd == 0xF9 and cur.value >= 0:
            return 0
        if cmd == 0xF5 and cur.value < 0:
            return 0
        cur.pc = addr
        return 0
    if cmd in (0xF2, 0xF3, 0xF4):
        rel = _s8(arg)
        if cmd == 0xF3 and cur.value != 0:
            return 0
        if cmd == 0xF2 and cur.value >= 0:
            return 0
        cur.pc += rel
        return 0
    return 0


def _read_scom_args(cur: Cursor, cmd: int) -> list[int]:
    bits = SCOM_TABLE[cmd - 0xA0] if 0xA0 <= cmd <= 0xFF else 0
    n = bits & 3
    args: list[int] = []
    for _ in range(n):
        if bits & 0x80:
            args.append(cur.s16())
        else:
            args.append(cur.u8())
        bits = (bits << 1) & 0xFF
    return args


def _open_sub(grp: Group, idx: int, pc: int) -> None:
    if idx < 0 or idx >= AUDIO_SUBTRACK_NUM:
        return
    sub = grp.subtracks[idx]
    sub.enabled = True
    sub.finished = False
    sub.stop_script = False
    sub.cur.pc = pc
    sub.cur.stack.clear()
    sub.cur.loops.clear()
    sub.delay = 0
    sub.notes = [None] * NOTE_LAYERS


def _start_note(sub: SubTrack, idx: int, pc: int, seq: bytes) -> None:
    if idx < 0 or idx >= NOTE_LAYERS:
        return
    note = NotePlayer(cur=Cursor(seq, pc), enabled=True)
    note.envelope = list(sub.envelope)
    note.decay_idx = sub.adsr_decay
    sub.notes[idx] = note


def _program(sub: SubTrack, inst_id: int) -> None:
    sub.inst_id = inst_id
    if inst_id >= 128:
        sub.inst_or_wave = inst_id
        sub.has_instrument = True
    elif inst_id == 0x7F:
        sub.inst_or_wave = VOICE_PERCUSSION
        sub.has_instrument = True
    elif inst_id == 0x7E:
        sub.inst_or_wave = VOICE_SFX
        sub.has_instrument = True
    else:
        sub.inst_or_wave = inst_id + 2
        sub.has_instrument = True


class SeqRenderer:
    def __init__(
        self,
        seq: bytes,
        banks: dict[int, Bank],
        default_bank: int,
        seq_banks: Optional[list[int]] = None,
        mute_subtracks: Optional[list[int]] = None,
    ) -> None:
        self.seq = seq
        self.banks = banks
        self.seq_banks = seq_banks or [default_bank]
        self.grp = Group(cur=Cursor(seq, 0), bank_id=default_bank)
        self.grp.subtracks = [
            SubTrack(idx=i, cur=Cursor(seq, 0), bank_id=default_bank) for i in range(AUDIO_SUBTRACK_NUM)
        ]
        for idx in mute_subtracks or ():
            if 0 <= idx < len(self.grp.subtracks):
                self.grp.subtracks[idx].muted = True
        self.note_count = 0
        self.voices: list[Voice] = []
        self.pc_first_time: dict[int, float] = {}
        self.loop_start_sec = 0.0
        self.loop_end_sec: Optional[float] = None
        self.seconds = 0.0

    def bank(self, bank_id: int) -> Optional[Bank]:
        return self.banks.get(bank_id) or self.banks.get(self.grp.bank_id)

    def _resolve_bank(self, selector: int) -> int:
        banks = self.seq_banks
        if not banks:
            return self.grp.bank_id
        idx = len(banks) - selector
        if 0 <= idx < len(banks):
            return banks[idx]
        return banks[-1]

    def run(self) -> RenderResult:
        mix = array("f")
        tatum = 0
        while tatum < MAX_TATUMS and self.loop_end_sec is None:
            running = self._tick_group()
            chunk = self._samples_per_tatum()
            self._mix_tatum(mix, chunk)
            self.seconds += chunk / MIX_RATE
            tatum += 1
            if not running and not self._voices_active():
                break
            if running and self._all_idle() and not self._voices_active() and tatum > 8:
                break
        if self.loop_end_sec is not None:
            n = int(self.loop_end_sec * MIX_RATE) * 2
            del mix[n:]
            duration = self.loop_end_sec
        else:
            duration = self.seconds
        pcm = _clamp_pcm(mix)
        return RenderResult(
            pcm=pcm,
            rate=MIX_RATE,
            loop_start_sec=self.loop_start_sec,
            duration_sec=duration,
            notes=self.note_count,
        )

    def _samples_per_tatum(self) -> float:
        tempo = max(1, self.grp.tempo)
        return MIX_RATE * 60.0 / tempo

    def _all_idle(self) -> bool:
        if self.grp.enabled and not self.grp.stop_script:
            return False
        for sub in self.grp.subtracks:
            if sub.enabled and not sub.stop_script:
                return False
            for note in sub.notes:
                if note is not None and note.enabled and not note.finished:
                    return False
        return True

    def _tick_group(self) -> bool:
        grp = self.grp
        if not grp.enabled:
            return False
        if grp.stop_script:
            self._tick_subs()
            return True
        if grp.delay > 1:
            grp.delay -= 1
            self._tick_subs()
            return True
        cur = grp.cur
        cmds = 0
        while cmds < MAX_CMDS:
            cmds += 1
            pc_before = cur.pc
            if pc_before not in self.pc_first_time:
                self.pc_first_time[pc_before] = self.seconds
            cmd = cur.u8()
            if cmd >= 0xF2:
                arg = 0
                bits = SCOM_TABLE[cmd - 0xA0]
                if (bits & 3) == 1:
                    arg = cur.s16() if bits & 0x80 else cur.u8()
                if cmd == 0xFB:
                    target = arg & 0xFFFF
                    if target in self.pc_first_time and target <= pc_before:
                        self.loop_start_sec = self.pc_first_time[target]
                        self.loop_end_sec = self.seconds
                        return True
                delay = common_com(grp, cur, cmd, arg)
                if delay == SCRIPT_END:
                    grp.enabled = False
                    return False
                if delay:
                    grp.delay = delay
                    break
                continue
            if cmd >= 0xC0:
                self._group_c0(cmd)
                if grp.stop_script or not grp.enabled:
                    break
                continue
            if cmd == 0xBE:
                cur.u8()
                continue
            lo = cmd & 0x0F
            hi = cmd & 0xF0
            if hi == 0x00:
                cur.value = 0 if grp.subtracks[lo].enabled else 1
            elif hi == 0x40:
                self._silence_sub(grp.subtracks[lo])
                grp.subtracks[lo].enabled = False
                grp.subtracks[lo].notes = [None] * NOTE_LAYERS
            elif hi == 0x50:
                cur.value -= grp.port[lo & 7]
            elif hi == 0x60:
                cur.u8()
                cur.u8()
            elif hi == 0x70:
                grp.port[lo & 7] = cur.value
            elif hi == 0x80:
                cur.value = grp.port[lo & 7]
                if lo < 2:
                    grp.port[lo] = -1
            elif hi == 0x90:
                _open_sub(grp, lo, cur.u16())
            elif hi == 0xA0:
                rel = cur.s16()
                _open_sub(grp, lo, cur.pc + rel)
            elif hi == 0xB0:
                cur.u8()
                cur.u16()
        self._tick_subs()
        return True

    def _group_c0(self, cmd: int) -> None:
        cur = self.grp.cur
        grp = self.grp
        if cmd == 0xC2:
            temp = cur.u16()
            if cur.value != -1:
                ofs = temp + (cur.value << 1)
                cur.pc = (self.seq[ofs] << 8) + self.seq[ofs + 1] if ofs + 1 < len(self.seq) else cur.pc
        elif cmd == 0xC3:
            cur.u16()
        elif cmd == 0xC4:
            cur.u8()
            cur.u8()
        elif cmd == 0xC5:
            cur.u16()
        elif cmd == 0xC6:
            grp.stop_script = True
        elif cmd == 0xC7:
            cur.u8()
            cur.u16()
        elif cmd == 0xC8:
            cur.value -= _s8(cur.u8())
        elif cmd == 0xC9:
            cur.value &= cur.u8()
        elif cmd == 0xCC:
            cur.value = cur.u8()
        elif cmd == 0xCD:
            temp = cur.u16()
            if cur.value != -1:
                ofs = temp + (cur.value << 1)
                cur.stack.append(cur.pc)
                cur.loops.append(0)
                if ofs + 1 < len(self.seq):
                    cur.pc = (self.seq[ofs] << 8) + self.seq[ofs + 1]
        elif cmd == 0xCE:
            n = cur.u8()
            cur.value = 0 if n == 0 else 0
        elif cmd == 0xD0:
            cur.u8()
        elif cmd in (0xD1, 0xD2):
            addr = cur.u16()
            tbl = list(self.seq[addr : addr + 16])
            if len(tbl) == 16:
                if cmd == 0xD2:
                    grp.vel_tbl = tbl
                else:
                    grp.gate_tbl = tbl
        elif cmd == 0xD3:
            cur.u8()
        elif cmd == 0xD5:
            cur.u8()
        elif cmd == 0xD6:
            cur.u16()
        elif cmd == 0xD7:
            cur.u16()
        elif cmd == 0xD9:
            cur.u8()
        elif cmd == 0xDA:
            cur.u8()
            cur.u16()
        elif cmd == 0xDB:
            grp.volume = cur.u8() / 127.0
        elif cmd == 0xDC:
            grp.tempo = max(1, grp.tempo + _s8(cur.u8()) * AUDIO_TATUMS_PER_BEAT)
        elif cmd == 0xDD:
            grp.tempo = max(1, cur.u8() * AUDIO_TATUMS_PER_BEAT)
        elif cmd == 0xDE:
            grp.transposition += _s8(cur.u8())
        elif cmd == 0xDF:
            grp.transposition = _s8(cur.u8())
        elif cmd == 0xEF:
            cur.u16()
            cur.u8()
        elif cmd == 0xF1:
            cur.u8()

    def _tick_subs(self) -> None:
        for sub in self.grp.subtracks:
            if sub.enabled:
                self._tick_sub(sub)

    def _tick_sub(self, sub: SubTrack) -> None:
        if not sub.stop_script:
            if sub.delay > 1:
                sub.delay -= 1
            else:
                self._run_sub_script(sub)
        if sub.muted:
            self._silence_sub(sub)
            return
        for i, note in enumerate(sub.notes):
            if note is not None and note.enabled:
                self._tick_note(sub, i, note)

    def _run_sub_script(self, sub: SubTrack) -> None:
        cur = sub.cur
        cmds = 0
        while cmds < MAX_CMDS:
            cmds += 1
            if cur.pc >= len(cur.data):
                sub.stop_script = True
                return
            cmd = cur.u8()
            if cmd >= 0xA0:
                args = _read_scom_args(cur, cmd)
                if cmd >= 0xF2:
                    delay = common_com(self.grp, cur, cmd, args[0] if args else 0)
                    if delay == SCRIPT_END:
                        sub.enabled = False
                        sub.stop_script = True
                        return
                    if delay:
                        sub.delay = delay
                        return
                    continue
                if not self._sub_a0(sub, cmd, args):
                    return
                continue
            lo = cmd & 0x0F
            hi = cmd & 0xF0
            if hi == 0x00:
                sub.delay = lo
                if lo == 0:
                    continue
                return
            if hi == 0x10:
                continue
            if hi == 0x20:
                _open_sub(self.grp, lo, cur.u16())
            elif hi == 0x30:
                cur.u8()
            elif hi == 0x40:
                cur.u8()
            elif hi == 0x70:
                if 8 <= lo <= 11:
                    rel = cur.s16()
                    _start_note(sub, lo - 8, cur.pc + rel, self.seq)
            elif hi == 0x80:
                if lo <= 3:
                    layer = sub.notes[lo]
                    cur.value = 1 if layer is None or layer.finished else 0
                elif 8 <= lo <= 11:
                    _start_note(sub, lo - 8, cur.u16(), self.seq)
            elif hi == 0x90:
                if lo <= 3:
                    layer = sub.notes[lo]
                    if layer is not None:
                        self._release_note(layer, force=True)
                    sub.notes[lo] = None
                elif 8 <= lo <= 11:
                    continue

    def _sub_a0(self, sub: SubTrack, cmd: int, args: list[int]) -> bool:
        a0 = args[0] if args else 0
        a1 = args[1] if len(args) > 1 else 0
        if cmd == 0xC1:
            _program(sub, a0 & 0xFF)
        elif cmd == 0xC3:
            sub.large_notes = False
        elif cmd == 0xC4:
            sub.large_notes = True
        elif cmd in (0xC6, 0xEB):
            sub.bank_id = self._resolve_bank(a0 & 0xFF)
            if cmd == 0xEB:
                _program(sub, a1 & 0xFF)
        elif cmd == 0xCD:
            idx = a0 & 0x0F
            if idx < AUDIO_SUBTRACK_NUM:
                self.grp.subtracks[idx].enabled = False
                self._silence_sub(self.grp.subtracks[idx])
        elif cmd == 0xCC:
            sub.cur.value = _s8(a0)
        elif cmd == 0xC8:
            sub.cur.value -= _s8(a0)
        elif cmd == 0xC9:
            sub.cur.value &= a0 & 0xFF
        elif cmd == 0xDB:
            sub.transposition = _s8(a0)
        elif cmd == 0xDC:
            sub.pan_weight = a0 & 0xFF
        elif cmd == 0xDD:
            sub.pan = a0 & 0xFF
        elif cmd == 0xDE:
            sub.freq_scale = (a0 & 0xFFFF) / 0x8000
        elif cmd == 0xDF:
            sub.volume = (a0 & 0xFF) / 127.0
        elif cmd == 0xE0:
            sub.volume_scale = (a0 & 0xFF) / 128.0
        elif cmd == 0xD3:
            sub.freq_scale = pcent((a0 & 0xFF) + 128)
        elif cmd == 0xEE:
            sub.freq_scale = pcent2((a0 & 0xFF) + 128)
        elif cmd == 0xD7:
            sub.vibrato.rate_target = (a0 & 0xFF) * 32
            sub.vibrato.rate_start = sub.vibrato.rate_target
            sub.vibrato.rate_change_delay = 0
        elif cmd == 0xD8:
            sub.vibrato.depth_target = (a0 & 0xFF) * 8
            sub.vibrato.depth_start = 0
            sub.vibrato.depth_change_delay = 0
        elif cmd == 0xE1:
            sub.vibrato.rate_start = (a0 & 0xFF) * 32
            sub.vibrato.rate_target = (a1 & 0xFF) * 32
            sub.vibrato.rate_change_delay = (args[2] & 0xFF) * 16 if len(args) > 2 else 0
        elif cmd == 0xE2:
            sub.vibrato.depth_start = (a0 & 0xFF) * 8
            sub.vibrato.depth_target = (a1 & 0xFF) * 8
            sub.vibrato.depth_change_delay = (args[2] & 0xFF) * 16 if len(args) > 2 else 0
        elif cmd == 0xE3:
            sub.vibrato.delay = (a0 & 0xFF) * 16
        elif cmd == 0xEC:
            sub.freq_scale = 1.0
            sub.vibrato = VibratoParams()
            sub.adsr_sustain = 0
        elif cmd == 0xDA:
            sub.envelope = parse_env_table(self.seq, a0 & 0xFFFF)
        elif cmd == 0xD9:
            sub.adsr_decay = a0 & 0xFF
        elif cmd == 0xD2:
            sub.adsr_sustain = a0 & 0xFF
        elif cmd == 0xEA:
            sub.stop_script = True
            return False
        elif cmd == 0xE9:
            pass
        return True

    def _tick_note(self, sub: SubTrack, _idx: int, note: NotePlayer) -> None:
        if note.delay > 1:
            note.delay -= 1
            if not note.muted and note.delay <= note.gate_delay:
                self._release_note(note, force=False)
                note.muted = True
            return
        if not note.continuous:
            self._release_note(note, force=False)
        cmds = 0
        while cmds < MAX_CMDS:
            cmds += 1
            cmd = self._note_command(sub, note)
            if cmd == SCRIPT_END:
                self._release_note(note, force=True)
                note.enabled = False
                note.finished = True
                note.playing = False
                return
            cmd = self._set_note(sub, note, cmd)
            if cmd == SCRIPT_END:
                if note.delay == 0:
                    continue
                return
            self._set_voice(sub, note, cmd)
            return

    def _note_command(self, sub: SubTrack, note: NotePlayer) -> int:
        cur = note.cur
        while True:
            if cur.pc >= len(cur.data):
                return SCRIPT_END
            cmd = cur.u8()
            if cmd <= 0xC0:
                return cmd
            if cmd >= 0xF2:
                arg = 0
                bits = SCOM_TABLE[cmd - 0xA0]
                if (bits & 3) == 1:
                    arg = cur.s16() if bits & 0x80 else cur.u8()
                delay = common_com(self.grp, cur, cmd, arg)
                if delay:
                    return SCRIPT_END
                continue
            if cmd in (0xC1, 0xCA):
                value = cur.u8()
                if cmd == 0xC1:
                    note.velocity = (value * value) / (127.0 * 127.0)
                else:
                    note.pan = value
            elif cmd in (0xC2, 0xC9):
                value = cur.u8()
                if cmd == 0xC9:
                    note.gate_time = value
                else:
                    note.transposition = _s8(value)
            elif cmd == 0xC3:
                note.short_delay = cur.varlen()
            elif cmd == 0xC4:
                note.continuous = True
            elif cmd == 0xC5:
                note.continuous = False
            elif cmd == 0xC6:
                inst = cur.u8()
                if inst >= 0x7E:
                    if inst == 0x7E:
                        note.inst_or_wave = VOICE_SFX
                    elif inst == 0x7F:
                        note.inst_or_wave = VOICE_PERCUSSION
                    else:
                        note.inst_or_wave = inst
                    note.inst_id = inst
                else:
                    note.inst_id = inst
                    note.inst_or_wave = inst + 2
            elif cmd == 0xC7:
                note.porta_mode = cur.u8()
                target = cur.u8() + sub.transposition + note.transposition + self.grp.transposition
                if (note.porta_mode & 0x7F) not in (6, 7) and target > 127:
                    target = 0
                note.porta_target = target & 0xFF
                if note.porta_mode & 0x80:
                    note.porta_time = cur.u8()
                else:
                    note.porta_time = cur.varlen()
            elif cmd == 0xC8:
                note.porta_mode = 0
            elif cmd == 0xCB:
                note.envelope = parse_env_table(self.seq, cur.u16())
                note.decay_idx = cur.u8()
            elif cmd == 0xCF:
                note.decay_idx = cur.u8()
            elif cmd == 0xCC:
                note.ignore_drum_pan = True
            elif cmd == 0xCD:
                note.bend = pcent2((cur.u8() + 128) & 0xFF)
            elif cmd in (0xCE, 0xF1):
                cur.u8()
            elif cmd == 0xF0:
                cur.u16()
            elif (cmd & 0xF0) == 0xD0:
                vel = self.grp.vel_tbl[cmd & 0xF]
                note.velocity = (vel * vel) / (127.0 * 127.0)
            elif (cmd & 0xF0) == 0xE0:
                note.gate_time = self.grp.gate_tbl[cmd & 0xF]

    def _set_note(self, sub: SubTrack, note: NotePlayer, cmd: int) -> int:
        cur = note.cur
        if cmd == 0xC0:
            note.delay = cur.varlen()
            note.muted = True
            self._release_note(note, force=False)
            note.playing = False
            return SCRIPT_END
        note.muted = False
        delay = note.last_delay
        if sub.large_notes:
            kind = cmd & 0xC0
            if kind == 0x00:
                delay = cur.varlen()
                vel = cur.u8()
                note.gate_time = cur.u8()
                note.last_delay = delay
            elif kind == 0x40:
                delay = cur.varlen()
                vel = cur.u8()
                note.gate_time = 0
                note.last_delay = delay
            else:
                vel = cur.u8()
                note.gate_time = cur.u8()
            vel = 127 if vel > 127 else vel
            note.velocity = (vel * vel) / (127.0 * 127.0)
            cmd &= 0x3F
        else:
            kind = cmd & 0xC0
            if kind == 0x00:
                delay = cur.varlen()
                note.last_delay = delay
            elif kind == 0x40:
                delay = note.short_delay
            cmd &= 0x3F
        note.delay = delay
        note.gate_delay = (note.gate_time * delay) >> 8
        note.released = False
        return cmd

    def _set_voice(self, sub: SubTrack, note: NotePlayer, semitone: int) -> None:
        inst_or_wave = note.inst_or_wave
        if inst_or_wave == VOICE_INHERIT:
            if not sub.has_instrument:
                note.muted = True
                note.playing = False
                self._release_note(note, force=True)
                return
            inst_or_wave = sub.inst_or_wave
        bank = self.bank(sub.bank_id)
        sample: Optional[PcmSample] = None
        pan = note.pan
        freq = 1.0
        decay_idx = note.decay_idx or sub.adsr_decay or SUBTRACK_DECAY_IDX
        env_table = list(note.envelope or sub.envelope or DEFAULT_ENV)
        sweep: Optional[Sweep] = None
        if inst_or_wave == VOICE_PERCUSSION:
            key = semitone + note.transposition
            if bank and 0 <= key < len(bank.drums) and bank.drums[key] is not None:
                drum: Drum = bank.drums[key]  # type: ignore[assignment]
                sample = drum.sample
                decay_idx = drum.decay_idx or decay_idx
                env_table = list(drum.envelope or env_table)
                if not note.ignore_drum_pan:
                    pan = drum.pan
                freq = sample.tuning if sample else 1.0
        elif inst_or_wave == VOICE_SFX:
            key = semitone + (note.transposition << 6)
            if bank and 0 <= key < len(bank.sfx):
                sample = bank.sfx[key]
                freq = sample.tuning if sample else 1.0
        else:
            key = semitone + self.grp.transposition + note.transposition + sub.transposition
            inst_id = note.inst_id if note.inst_or_wave != VOICE_INHERIT else sub.inst_id
            inst: Optional[Instrument] = None
            if bank and 0 <= inst_id < len(bank.instruments):
                inst = bank.instruments[inst_id]
            if inst is None or key > 127:
                note.muted = True
                note.playing = False
                self._release_note(note, force=True)
                return
            sample = inst.sample_for(key)
            decay_idx = inst.decay_idx or decay_idx
            env_table = list(inst.envelope or env_table)
            tuning = sample.tuning if sample else 1.0
            if note.porta_mode:
                sweep, freq = build_sweep(
                    note.porta_mode, key, note.porta_target, tuning, max(1, note.porta_time), max(1, note.delay)
                )
            else:
                freq = _pitch(key) * tuning
            freq *= sub.freq_scale * note.bend
        note.sample = sample
        note.freq_scale = freq
        note.pan = pan
        note.sample_pos = 0.0
        note.playing = sample is not None and not note.muted
        note.decay_idx = decay_idx
        note.envelope = env_table
        if note.playing and sample is not None:
            self.note_count += 1
            self._start_voice(note, sample, freq, pan, sub, decay_idx, env_table, sweep)
        elif not note.playing:
            self._release_note(note, force=True)

    def _start_voice(
        self,
        note: NotePlayer,
        sample: PcmSample,
        freq: float,
        pan: int,
        sub: SubTrack,
        decay_idx: int,
        env_table: list[tuple[int, int]],
        sweep: Optional[Sweep],
    ) -> None:
        if not note.continuous:
            self._release_note(note, force=False)
        vol = sub.volume * sub.volume_scale * self.grp.volume * self.grp.fade_volume
        amp = max(0.0, note.velocity) * vol * vol
        mixed_pan = (sub.pan * sub.pan_weight + pan * (128 - sub.pan_weight)) >> 7
        pan_f = max(0, min(127, mixed_pan)) / 127.0
        envelope = Envelope(table=list(env_table), decay_idx=decay_idx, sustain=sub.adsr_sustain / 256.0)
        envelope.start()
        vibrato = Vibrato(params=sub.vibrato) if sub.vibrato.depth_target or sub.vibrato.depth_start else None
        voice = Voice(
            sample=sample,
            pos=0.0,
            step=freq * (NATIVE_RATE / MIX_RATE),
            left=amp * (1.0 - pan_f),
            right=amp * pan_f,
            envelope=envelope,
            vibrato=vibrato,
            sweep=sweep,
            env=0.0,
        )
        if note.continuous and note.voice is not None and note.voice.env > 0:
            note.voice.sample = sample
            note.voice.pos = 0.0
            note.voice.step = voice.step
            note.voice.left = voice.left
            note.voice.right = voice.right
            note.voice.envelope = envelope
            note.voice.vibrato = vibrato
            note.voice.sweep = sweep
            note.voice.released = False
            note.voice.env = note.voice.envelope.process()
            return
        self._release_note(note, force=False)
        if len(self.voices) >= MAX_VOICES:
            self._steal_voice()
        self.voices.append(voice)
        voice.env = voice.envelope.process()
        note.voice = voice

    def _release_note(self, note: NotePlayer, force: bool) -> None:
        voice = note.voice
        if voice is None:
            return
        note.voice = None
        note.playing = False
        if voice.envelope.finished():
            return
        voice.released = True
        if force:
            voice.envelope.release()
        else:
            voice.envelope.decay()

    def _silence_sub(self, sub: SubTrack) -> None:
        for note in sub.notes:
            if note is not None:
                self._release_note(note, force=True)

    def _steal_voice(self) -> None:
        if not self.voices:
            return
        released = [v for v in self.voices if v.released]
        victim = min(released or self.voices, key=lambda v: v.env)
        victim.envelope.status = 0
        victim.env = 0.0
        self.voices = [v for v in self.voices if v is not victim]
        for sub in self.grp.subtracks:
            for note in sub.notes:
                if note is not None and note.voice is victim:
                    note.voice = None

    def _voices_active(self) -> bool:
        return any(not v.envelope.finished() for v in self.voices)

    def _mix_tatum(self, mix: array, n_samples: float) -> None:
        n = max(1, int(round(n_samples)))
        start = len(mix)
        mix.extend([0.0] * (n * 2))
        samples_per_update = MIX_RATE / UPDATES_PER_SEC
        alive: list[Voice] = []
        for voice in self.voices:
            if voice.envelope.finished() and voice.env <= 0.00001:
                continue
            pcm = voice.sample.pcm
            loop_start = voice.sample.loop_start
            loop_end = voice.sample.loop_end if voice.sample.loop_end > loop_start else 0
            pos = voice.pos
            env = voice.env
            acc = voice.update_acc
            step = voice.step
            finished = False
            for i in range(n):
                acc += 1.0
                while acc >= samples_per_update:
                    acc -= samples_per_update
                    env = voice.envelope.process()
                    vib = voice.vibrato.process() if voice.vibrato else 1.0
                    porta = voice.sweep.process() if voice.sweep else 1.0
                    step = voice.step * vib * porta
                    if voice.envelope.finished():
                        env = 0.0
                        finished = True
                        break
                if finished:
                    break
                idx = int(pos)
                if loop_end and idx >= loop_end:
                    span = loop_end - loop_start
                    if span > 0:
                        pos = loop_start + (pos - loop_start) % span
                        idx = int(pos)
                if idx >= len(pcm):
                    env = 0.0
                    finished = True
                    break
                nxt = idx + 1
                sample = float(pcm[idx])
                if nxt < len(pcm):
                    frac = pos - idx
                    sample += (float(pcm[nxt]) - sample) * frac
                mix[start + i * 2] += sample * voice.left * env
                mix[start + i * 2 + 1] += sample * voice.right * env
                pos += step
            voice.pos = pos
            voice.env = env if env > 0.0 else 0.0
            voice.update_acc = acc
            if not finished and not voice.envelope.finished():
                alive.append(voice)
        self.voices = alive


def _clamp_pcm(mix: array) -> bytes:
    out = bytearray()
    peak = 1.0
    for v in mix:
        a = abs(v)
        if a > peak:
            peak = a
    scale = 1.0 if peak <= 32000 else 32000.0 / peak
    for v in mix:
        s = int(v * scale)
        s = max(-32767, min(32767, s))
        out += struct.pack("<h", s)
    return bytes(out)


def write_wav(path: Path, pcm: bytes, rate: int, channels: int = 2) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "w") as handle:
        handle.setnchannels(channels)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(pcm)


def encode_ogg(wav_path: Path, ogg_path: Path) -> bool:
    ffmpeg = _which("ffmpeg")
    if ffmpeg is None:
        return False
    ogg_path.parent.mkdir(parents=True, exist_ok=True)
    attempts = (
        [ffmpeg, "-y", "-i", str(wav_path), "-c:a", "libvorbis", "-q:a", "4", str(ogg_path)],
        [ffmpeg, "-y", "-i", str(wav_path), "-c:a", "vorbis", "-strict", "-2", str(ogg_path)],
    )
    for cmd in attempts:
        result = subprocess.run(cmd, capture_output=True, check=False)
        if result.returncode == 0 and ogg_path.is_file() and ogg_path.stat().st_size > 0:
            return True
    return False


def _which(name: str) -> Optional[str]:
    from shutil import which

    return which(name)


def render_sequence(
    seq: bytes,
    banks: dict[int, Bank],
    default_bank: int,
    seq_banks: Optional[list[int]] = None,
    mute_subtracks: Optional[list[int]] = None,
) -> RenderResult:
    return SeqRenderer(seq, banks, default_bank, seq_banks, mute_subtracks).run()
