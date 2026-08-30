"""Vibrato and portamento (`Nas_Modulator` / `Nas_SweepCalculator`)."""

from __future__ import annotations

from dataclasses import dataclass

from .audio_tables import UPDATES_PER_FRAME, VIBRATO_SINE, pcent, pitch_ratio

PORTAMENTO_OFF = 0


@dataclass
class VibratoParams:
    rate_start: int = 2048
    rate_target: int = 2048
    rate_change_delay: int = 0
    depth_start: int = 0
    depth_target: int = 0
    depth_change_delay: int = 0
    delay: int = 0


@dataclass
class Vibrato:
    params: VibratoParams
    depth: float = 0.0
    rate: float = 0.0
    time: int = 0
    delay: int = 0
    depth_timer: int = 0
    rate_timer: int = 0

    def __post_init__(self) -> None:
        p = self.params
        self.delay = p.delay
        if p.depth_change_delay == 0:
            self.depth = float(p.depth_target)
            self.depth_timer = 0
        else:
            self.depth = float(p.depth_start)
            self.depth_timer = p.depth_change_delay
        if p.rate_change_delay == 0:
            self.rate = float(p.rate_target)
            self.rate_timer = 0
        else:
            self.rate = float(p.rate_start)
            self.rate_timer = p.rate_change_delay

    def process(self) -> float:
        if self.delay > 0:
            self.delay -= 1
            return 1.0
        p = self.params
        if self.depth_timer != 0:
            if self.depth_timer == 1:
                self.depth = float(p.depth_target)
            else:
                self.depth += (p.depth_target - self.depth) / self.depth_timer
            self.depth_timer -= 1
        elif p.depth_target != int(self.depth):
            self.depth_timer = p.depth_change_delay
            if self.depth_timer == 0:
                self.depth = float(p.depth_target)
        if self.rate_timer != 0:
            if self.rate_timer == 1:
                self.rate = float(p.rate_target)
            else:
                self.rate += (p.rate_target - self.rate) / self.rate_timer
            self.rate_timer -= 1
        elif p.rate_target != int(self.rate):
            self.rate_timer = p.rate_change_delay
            if self.rate_timer == 0:
                self.rate = float(p.rate_target)
        if self.depth == 0.0:
            return 1.0
        self.time += int(self.rate)
        mod = VIBRATO_SINE[(self.time >> 10) & 0x3F]
        depth = 1.0 + (self.depth / 4096.0)
        inv = 1.0 / depth
        return 1.0 / ((depth - inv) * (mod + 32768.0) / 65536.0 + inv)


@dataclass
class Sweep:
    mode: int = 0
    extent: float = 0.0
    speed: int = 0
    current: int = 0

    def process(self) -> float:
        mode = self.mode & 0x7F
        if mode == PORTAMENTO_OFF:
            return 1.0
        self.current += self.speed
        lo = (self.current >> 8) & 0xFF
        if lo >= 127:
            lo = 127
            self.mode = PORTAMENTO_OFF
        return 1.0 + self.extent * (pcent(lo + 128) - 1.0)


def build_sweep(
    mode: int,
    semitone: int,
    target_note: int,
    tuning: float,
    porta_time: int,
    delay: int,
) -> tuple[Sweep, float]:
    """Return (sweep, starting frequency_scale) from `__SetVoice` portamento."""
    kind = mode & 0x7F
    special = bool(mode & 0x80)
    t0 = tuning * pitch_ratio(semitone)
    dest = target_note
    if kind in (6, 7):
        dest = target_note + semitone
    dest = max(0, min(127, dest))
    t1 = tuning * pitch_ratio(dest)
    if kind in (1, 3, 5, 6, 7):
        freq_scale, freq_scale2 = t1, t0
    elif kind in (2, 4):
        freq_scale, freq_scale2 = t0, t1
    else:
        freq_scale = freq_scale2 = t0
    extent = (freq_scale2 / freq_scale) - 1.0 if freq_scale else 0.0
    if special:
        speed = 0x10000 // max(1, porta_time * max(1, delay))
    else:
        speed = (2 * 0x10000) // max(1, porta_time * UPDATES_PER_FRAME)
    speed = max(1, min(0x7FFF, speed))
    return Sweep(mode=mode, extent=extent, speed=speed, current=0), freq_scale
