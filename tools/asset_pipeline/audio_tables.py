"""Pitch, cent, and release tables used by the Neos mixer.

Values follow the same formulas as ac-decomp `audiotable.c` / `MakeReleaseTable`.
Do not copy Nintendo's float dumps; regenerate from the math.
"""

from __future__ import annotations

import math

UPDATES_PER_FRAME = 4
UPDATES_PER_SEC = 60.0 * UPDATES_PER_FRAME
SUBTRACK_DECAY_IDX = 240
PITCH_UNISON = 39  # PITCHTABLE[39] == 1.0 (decomp comment says 48; the table does not)


def pitch_ratio(semitone: int) -> float:
    semitone = max(0, min(127, semitone))
    return 2.0 ** ((semitone - PITCH_UNISON) / 12.0)


def pcent(index: int) -> float:
    """~9.375 cents/step, index 128 = 1.0. Used by large pitch bend and portamento."""
    index = max(0, min(255, index))
    return 2.0 ** ((index - 128) * (1200.0 / 128.0) / 1200.0)


def pcent2(index: int) -> float:
    """~1.5625 cents/step, index 128 = 1.0. Used by small pitch bend."""
    index = max(0, min(255, index))
    return 2.0 ** ((index - 128) * (200.0 / 128.0) / 1200.0)


def vibrato_sine() -> list[int]:
    return [int(round(32767.0 * math.sin(2.0 * math.pi * i / 64.0))) for i in range(64)]


VIBRATO_SINE = vibrato_sine()


def _release(val: float) -> float:
    return 0.0 if val == 0.0 else (1.0 / UPDATES_PER_FRAME) / val


def _decay_table() -> list[float]:
    table = [0.0] * 256
    table[0xFF] = _release(0.25)
    table[0xFE] = _release(0.33)
    table[0xFD] = _release(0.5)
    table[0xFC] = _release(0.66)
    table[0xFB] = _release(0.75)
    for i in range(0x80, 0xFB):
        table[i] = _release(0xFB - i)
    for i in range(0x10, 0x80):
        table[i] = _release((0x80 - i) * 4 + 0x3C)
    for i in range(1, 0x10):
        table[i] = _release((0xF - i) * 0x3C + 0x1E0)
    return table


DECAY_PER_UPDATE = _decay_table()
FORCE_FADE_PER_UPDATE = 1.0 / UPDATES_PER_FRAME


def decay_per_update(decay_idx: int) -> float:
    idx = decay_idx & 0xFF
    if idx == 0:
        idx = SUBTRACK_DECAY_IDX
    return DECAY_PER_UPDATE[idx]
