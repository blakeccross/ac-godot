"""ADSR envelope processor (`Nas_EnvProcess` behavior)."""

from __future__ import annotations

from dataclasses import dataclass, field

from .audio_tables import FORCE_FADE_PER_UPDATE, UPDATES_PER_FRAME, decay_per_update

ADSR_DISABLE = 0
ADSR_HANG = -1
ADSR_GOTO = -2
ADSR_RESTART = -3
ADSR_SPECIAL4 = -4

DISABLED = 0
INITIAL = 1
LOOP = 3
FADE = 4
HANG = 5
DECAY = 6
RELEASE = 7
SUSTAIN = 8

# {delay, value} — DEFAULT_ENV in audiotable.c
DEFAULT_ENV: list[tuple[int, int]] = [
    (1, 32000),
    (1000, 32000),
    (ADSR_HANG, 0),
    (ADSR_DISABLE, 0),
]


def parse_env_table(data: bytes, ofs: int, limit: int = 16) -> list[tuple[int, int]]:
    """Read consecutive `envdat` {s16 delay, s16 value} pairs."""
    out: list[tuple[int, int]] = []
    if ofs <= 0 or ofs + 4 > len(data):
        return list(DEFAULT_ENV)
    for _ in range(limit):
        if ofs + 4 > len(data):
            break
        delay = int.from_bytes(data[ofs : ofs + 2], "big", signed=True)
        value = int.from_bytes(data[ofs + 2 : ofs + 4], "big", signed=True)
        out.append((delay, value))
        ofs += 4
        if delay == ADSR_DISABLE:
            break
    return out or list(DEFAULT_ENV)


@dataclass
class Envelope:
    table: list[tuple[int, int]] = field(default_factory=lambda: list(DEFAULT_ENV))
    decay_idx: int = 240
    sustain: float = 0.0
    status: int = INITIAL
    index: int = 0
    delay: int = 0
    current: float = 0.0
    target: float = 0.0
    velocity: float = 0.0
    fadeout: float = 0.0
    pending_decay: bool = False
    pending_release: bool = False

    def start(self) -> None:
        self.status = INITIAL
        self.index = 0
        self.delay = 0
        self.current = 0.0
        self.velocity = 0.0
        self.fadeout = 0.0
        self.pending_decay = False
        self.pending_release = False

    def decay(self) -> None:
        self.pending_decay = True
        self.fadeout = decay_per_update(self.decay_idx)

    def release(self) -> None:
        self.pending_release = True
        self.fadeout = FORCE_FADE_PER_UPDATE

    def finished(self) -> bool:
        return self.status == DISABLED or (self.status in (DECAY, RELEASE) and self.current <= 0.00001)

    def process(self) -> float:
        start = self.status
        if self.status == DISABLED:
            return 0.0
        if self.status == INITIAL:
            self.index = 0
            self.status = LOOP
        if self.status == LOOP:
            self._read_point()
        if self.status == FADE:
            self.current += self.velocity
            self.delay -= 1
            if self.delay <= 0:
                self.status = LOOP
        elif self.status in (DECAY, RELEASE):
            self.current -= self.fadeout
            if self.sustain > 0.0 and start == DECAY:
                if self.current < self.sustain:
                    self.current = self.sustain
                    self.delay = 128
                    self.status = SUSTAIN
            elif self.current < 0.00001:
                self.current = 0.0
                self.status = DISABLED
        elif self.status == SUSTAIN:
            self.delay -= 1
            if self.delay <= 0:
                self.status = RELEASE
                self.fadeout = FORCE_FADE_PER_UPDATE
        if self.pending_decay:
            self.status = DECAY
            self.pending_decay = False
        if self.pending_release:
            self.status = RELEASE
            self.pending_release = False
        if self.current < 0.0:
            return 0.0
        if self.current > 1.0:
            return 1.0
        return self.current

    def _read_point(self) -> None:
        for _ in range(16):
            if self.index >= len(self.table):
                self.status = DISABLED
                return
            delay, value = self.table[self.index]
            if delay == ADSR_DISABLE:
                self.status = DISABLED
                return
            if delay == ADSR_HANG:
                self.status = HANG
                return
            if delay == ADSR_GOTO:
                self.index = max(0, value)
                continue
            if delay == ADSR_RESTART:
                self.status = INITIAL
                self.index = 0
                return
            if delay == ADSR_SPECIAL4:
                self.index += 1
                continue
            scaled = int(delay * (UPDATES_PER_FRAME / 4.0))
            self.delay = scaled if scaled else 1
            self.target = (value / 32767.0) ** 2
            self.velocity = (self.target - self.current) / self.delay
            self.status = FADE
            self.index += 1
            return
        self.status = HANG
