"""N64 VADPCM decode.

Matches the Ice Mario / Nintendo `decode_8` predictor (8-sample state, order-2
codebook), not a 2-tap IIR. Wrong predictors clip and sound like glitchy noise.
"""

from __future__ import annotations


FRAME_BYTES = 9
SAMPLES_PER_FRAME = 16
STATE_LEN = 8


def decode_vadpcm_frame(frame: bytes, book: list[list[list[int]]], hist: list[int]) -> list[int]:
    """Decode one 9-byte frame into 16 PCM samples. Mutates `hist` (length 8).

    `book[predictor]` is order rows of 8 coefficients (`pred1` then `pred2`).
    """
    if len(frame) < FRAME_BYTES:
        raise ValueError("VADPCM frame is 9 bytes")
    while len(hist) < STATE_LEN:
        hist.append(0)
    header = frame[0]
    scale = header >> 4
    predictor = header & 0x0F
    if not book:
        book = [[[0] * 8, [0] * 8]]
    if predictor >= len(book):
        predictor %= len(book)
    pred_rows = book[predictor]
    pred1 = pred_rows[0] if pred_rows else [0] * 8
    pred2 = pred_rows[1] if len(pred_rows) > 1 else [0] * 8
    samples: list[int] = []
    data_i = 1
    for _half in range(2):
        residual: list[int] = []
        for _ in range(4):
            byte = frame[data_i]
            data_i += 1
            for nibble in ((byte >> 4) & 0xF, byte & 0xF):
                if nibble >= 8:
                    nibble -= 16
                residual.append(nibble << scale)
        decoded = _decode_vector(residual, pred1, pred2, hist)
        samples.extend(decoded)
        hist[:] = decoded
    return samples


def _decode_vector(
    residual: list[int], pred1: list[int], pred2: list[int], lastsmp: list[int]
) -> list[int]:
    """One 8-sample vector. `lastsmp` is the previous vector (length 8)."""
    prev_a = lastsmp[6] if len(lastsmp) > 6 else 0
    prev_b = lastsmp[7] if len(lastsmp) > 7 else 0
    out = [0] * 8
    for i in range(8):
        total = pred1[i] * prev_a + pred2[i] * prev_b
        for x in range(i - 1, -1, -1):
            total += residual[i - 1 - x] * pred2[x]
        sample = ((residual[i] << 11) + total) >> 11
        if sample > 32767:
            sample = 32767
        elif sample < -32768:
            sample = -32768
        out[i] = sample
    return out


def book_from_shorts(order: int, n_predictors: int, table: list[int]) -> list[list[list[int]]]:
    book: list[list[list[int]]] = []
    expected = n_predictors * order * 8
    padded = list(table) + [0] * max(0, expected - len(table))
    idx = 0
    for _p in range(n_predictors):
        pred: list[list[int]] = []
        for _k in range(max(order, 1)):
            pred.append(padded[idx : idx + 8])
            idx += 8
        if len(pred) == 1:
            pred.append([0] * 8)
        book.append(pred)
    if not book:
        book = [[[0] * 8, [0] * 8]]
    return book


def decode_vadpcm(
    data: bytes,
    book: list[list[list[int]]],
    loop_start: int = 0,
    loop_end: int = 0,
    loop_state: list[int] | None = None,
) -> list[int]:
    hist = [0] * STATE_LEN
    pcm: list[int] = []
    n_frames = len(data) // FRAME_BYTES
    for i in range(n_frames):
        start = i * FRAME_BYTES
        pcm.extend(decode_vadpcm_frame(data[start : start + FRAME_BYTES], book, hist))
    _ = (loop_start, loop_end, loop_state)
    return pcm
