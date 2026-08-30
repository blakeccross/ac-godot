from __future__ import annotations

import unittest
from pathlib import Path

from asset_pipeline.audio import (
    AUDIOROM_SIZE,
    BANK_OFFSET,
    SEQ_COUNT,
    SEQ_SIZE,
    WAVE_OFFSET,
    catalog_id_for_hour,
    decode_vadpcm_frame,
    parse_bgm_ids,
    parse_seq_entries,
    parse_seq_table,
)
from asset_pipeline.audio_bank import (
    Bank,
    Instrument,
    PcmSample,
    banks_for_seq,
    parse_arc_entries,
    parse_audiomap_bytes,
)
from asset_pipeline.audio_seq import render_sequence
from asset_pipeline.audio_adsr import Envelope, DEFAULT_ENV
from asset_pipeline.audio_tables import pcent, pcent2, pitch_ratio

DECOMP = Path("/Users/blakecross/Documents/ac-decomp")

SEQ_HEADER_SNIPPET = """
ArcHeader AudioseqHeaderStart ATTRIBUTE_ALIGN(1) = {
    249,
    {
        {
            /* entry 0 */
            0x00000000,           /* rom addr */
            0x000009A0,           /* size */
            MEDIUM_CART,
        },
        {
            /* entry 1 */
            0x000009A0,           /* rom addr */
            0x00000FC0,           /* size */
            MEDIUM_CART,
        },
    },
};
ArcHeader AudiobankHeaderStart = {
"""

SEQ_TABLE_SNIPPET = """
const u8 SEQ_TABLE[256] = {
    247,  81,  82,  83,
};
"""

BGM_SNIPPET = """
typedef enum bgm_e {
    BGM_SILENCE,
    BGM_FIELD_00,
    BGM_FIELD_01,
    BGM_RAIN,
    BGM_TITLE,
    BGM_TOTAKEKE_LIVE0 = 192,
} BGM_e;
"""


class AudioParseTests(unittest.TestCase):
    def test_region_layout(self) -> None:
        self.assertEqual(SEQ_SIZE, 0xCF700)
        self.assertEqual(BANK_OFFSET, SEQ_SIZE)
        self.assertEqual(WAVE_OFFSET, BANK_OFFSET + 0x67C80)
        self.assertEqual(AUDIOROM_SIZE, WAVE_OFFSET + 0x6B33E0)

    def test_seq_entries_from_c(self) -> None:
        entries = parse_seq_entries(SEQ_HEADER_SNIPPET)
        self.assertEqual(len(entries), 2)
        self.assertEqual(entries[0]["addr"], 0)
        self.assertEqual(entries[0]["size"], 0x9A0)
        self.assertEqual(entries[1]["addr"], 0x9A0)
        self.assertEqual(entries[1]["size"], 0xFC0)

    def test_seq_table_from_c(self) -> None:
        table = parse_seq_table(SEQ_TABLE_SNIPPET)
        self.assertEqual(table, [247, 81, 82, 83])

    def test_bgm_ids_and_hour_keys(self) -> None:
        ids = parse_bgm_ids(BGM_SNIPPET)
        self.assertEqual(ids["silence"], 0)
        self.assertEqual(ids["field_00"], 1)
        self.assertEqual(ids["field_01"], 2)
        self.assertEqual(ids["rain"], 3)
        self.assertEqual(ids["title"], 4)
        self.assertEqual(ids["totakeke_live0"], 192)
        self.assertEqual(catalog_id_for_hour(14), "field_14")
        self.assertEqual(catalog_id_for_hour(24), "field_00")

    def test_vadpcm_zero_frame(self) -> None:
        book = [[[0] * 8, [0] * 8]]
        hist = [0] * 8
        pcm = decode_vadpcm_frame(bytes(9), book, hist)
        self.assertEqual(pcm, [0] * 16)
        self.assertEqual(hist, [0] * 8)

    def test_vadpcm_scaled_nibble(self) -> None:
        book = [[[0] * 8, [0] * 8]]
        hist = [0] * 8
        # shift 0, predictor 0, first nibble = 1
        frame = bytes([0x00, 0x10, 0, 0, 0, 0, 0, 0, 0])
        pcm = decode_vadpcm_frame(frame, book, hist)
        self.assertEqual(pcm[0], 1)
        self.assertEqual(pcm[1], 0)

    def test_vadpcm_predictor_uses_prior_sample(self) -> None:
        # pred2[0] = 2048 means +1.0 * previous residual after >> 11.
        book = [[[0] * 8, [2048, 0, 0, 0, 0, 0, 0, 0]]]
        hist = [0] * 8
        frame = bytes([0x00, 0x11, 0, 0, 0, 0, 0, 0, 0])
        pcm = decode_vadpcm_frame(frame, book, hist)
        self.assertEqual(pcm[0], 1)
        self.assertEqual(pcm[1], 2)


@unittest.skipUnless((DECOMP / "include" / "audio_defs.h").is_file(), "ac-decomp not present")
class AudioDecompTests(unittest.TestCase):
    def test_headers_match_known_counts(self) -> None:
        header = (DECOMP / "src" / "static" / "jaudio_NES" / "game" / "audioheaders.c").read_text(
            encoding="utf-8", errors="replace"
        )
        entries = parse_seq_entries(header)
        self.assertEqual(len(entries), SEQ_COUNT)
        self.assertEqual(entries[0]["addr"], 0)
        table = parse_seq_table(
            (DECOMP / "src" / "static" / "jaudio_NES" / "game" / "game64.c_inc").read_text(
                encoding="utf-8", errors="replace"
            )
        )
        self.assertEqual(len(table), 256)
        ids = parse_bgm_ids((DECOMP / "include" / "audio_defs.h").read_text(encoding="utf-8", errors="replace"))
        self.assertEqual(ids["field_00"], 1)
        self.assertEqual(ids["field_23"], 24)
        self.assertIn("title", ids)
        self.assertIn("rain", ids)
        self.assertEqual(table[ids["field_00"]], 81)


class AudioBankParseTests(unittest.TestCase):
    def test_bank_entry_params(self) -> None:
        src = """
ArcHeader AudiobankHeaderStart = {
    2,
    {
        {
            0x00000000,           /* rom addr */
            0x00003180,           /* size */
            MEDIUM_CART,
            CACHE_LOAD_PERMANENT,
            0x00FF,               /* param0 */
            0x4800,               /* param1 */
            0x0000,               /* param2 */
        },
        {
            0x00003180,           /* rom addr */
            0x00000B60,           /* size */
            MEDIUM_CART,
            CACHE_LOAD_TEMPORARY,
            0x01FF,               /* param0 */
            0x0E00,               /* param1 */
            0x0000,               /* param2 */
        },
    },
};
"""
        entries = parse_arc_entries(src, "AudiobankHeaderStart")
        self.assertEqual(len(entries), 2)
        self.assertEqual(entries[0].wave_bank_id0, 0)
        self.assertEqual(entries[0].wave_bank_id1, 0xFF)
        self.assertEqual(entries[0].num_instruments, 0x48)
        self.assertEqual(entries[0].num_drums, 0)
        self.assertEqual(entries[1].addr, 0x3180)

    def test_audiomap_seq_bank_list(self) -> None:
        src = """
u8 AudiomapHeaderStart[] = {
    0x00, 0x04,
    0x00, 0x07,
    0x02, 0x0A, 0x0B,
    0x01, 0x03,
};
"""
        blob = parse_audiomap_bytes(src)
        self.assertEqual(banks_for_seq(blob, 0), [0x0A, 0x0B])
        self.assertEqual(banks_for_seq(blob, 1), [0x03])

    def test_audiomap_decimal_count(self) -> None:
        src = """
u8 AudiomapHeaderStart[] = {
    0x00, 0x02,
    1, 0x04,
};
"""
        blob = parse_audiomap_bytes(src)
        self.assertEqual(banks_for_seq(blob, 0), [4])


class AudioSeqRenderTests(unittest.TestCase):
    def test_looping_sequence_plays_injected_sample(self) -> None:
        # tempo 120, vol 127, start sub 0 at 0x0C, delay 48, jump to delay.
        seq = bytes(
            [
                0xDD, 120, 0xDB, 127, 0x90, 0x00, 0x0C, 0xFD, 48, 0xFB, 0x00, 0x07,
                0xC1, 0x00, 0xDF, 127, 0xDD, 64, 0xC3, 0x88, 0x00, 0x19, 0xFD, 48, 0xFF,
                0xC1, 127, 0x00, 48, 0xFF,
            ]
        )
        tone = [2000 if (i // 40) % 2 == 0 else -2000 for i in range(4000)]
        sample = PcmSample(pcm=tone, loop_start=0, loop_end=4000, tuning=1.0)
        inst = Instrument(low=None, normal=sample, high=None, range_low=0, range_high=127)
        bank = Bank(bank_id=0, instruments=[inst])
        result = render_sequence(seq, {0: bank}, 0, [0])
        self.assertGreater(result.notes, 0)
        self.assertGreater(result.duration_sec, 0.2)
        peak = max(abs(int.from_bytes(result.pcm[i : i + 2], "little", signed=True)) for i in range(0, min(4000, len(result.pcm)), 2))
        self.assertGreater(peak, 100)

    def test_note_rings_after_script_delay(self) -> None:
        seq = bytes(
            [
                0xDD, 120, 0xDB, 127, 0x90, 0x00, 0x0A, 0xFD, 48, 0xFF,
                0xC1, 0x00, 0xDF, 127, 0xDD, 64, 0xC3, 0x88, 0x00, 0x17, 0xFD, 48, 0xFF,
                0xC1, 127, 0x27, 2, 0xFF,
            ]
        )
        tone = [4000 if (i // 20) % 2 == 0 else -4000 for i in range(4000)]
        sample = PcmSample(pcm=tone, loop_start=0, loop_end=4000, tuning=1.0)
        inst = Instrument(low=None, normal=sample, high=None, range_low=0, range_high=127, decay_idx=32)
        bank = Bank(bank_id=0, instruments=[inst])
        result = render_sequence(seq, {0: bank}, 0, [0])
        self.assertGreater(result.notes, 0)
        pcm = result.pcm
        mid = (len(pcm) // 4) * 2
        tail = pcm[mid:]
        peak = max(
            abs(int.from_bytes(tail[i : i + 2], "little", signed=True))
            for i in range(0, min(len(tail), 8000), 2)
        )
        self.assertGreater(peak, 100)


class AudioMixerBehaviorTests(unittest.TestCase):
    def test_pitch_unison_is_index_39(self) -> None:
        self.assertAlmostEqual(pitch_ratio(39), 1.0, places=5)
        self.assertAlmostEqual(pitch_ratio(51), 2.0, places=4)

    def test_cent_tables_unity_at_128(self) -> None:
        self.assertAlmostEqual(pcent(128), 1.0, places=5)
        self.assertAlmostEqual(pcent2(128), 1.0, places=5)
        self.assertAlmostEqual(pcent(0), 0.5, places=4)

    def test_default_envelope_attacks_then_hangs(self) -> None:
        env = Envelope(table=list(DEFAULT_ENV), decay_idx=240)
        env.start()
        level = 0.0
        for _ in range(8):
            level = env.process()
        self.assertGreater(level, 0.8)
        hung = env.process()
        self.assertGreater(hung, 0.8)
        env.decay()
        env.process()
        fading = env.process()
        self.assertLess(fading, hung)


@unittest.skipUnless((DECOMP / "include" / "audio_defs.h").is_file(), "ac-decomp not present")
class AudioDecompBankTests(unittest.TestCase):
    def test_bank_and_map_counts(self) -> None:
        header = (DECOMP / "src" / "static" / "jaudio_NES" / "game" / "audioheaders.c").read_text(
            encoding="utf-8", errors="replace"
        )
        banks = parse_arc_entries(header, "AudiobankHeaderStart")
        waves = parse_arc_entries(header, "AudiowaveHeaderStart")
        self.assertEqual(len(banks), 159)
        self.assertEqual(len(waves), 6)
        self.assertEqual(banks[0].num_instruments, 0x48)
        mapping = parse_audiomap_bytes(header)
        self.assertEqual(len(mapping), 0x3F0)
        self.assertEqual(banks_for_seq(mapping, 95), [4])


if __name__ == "__main__":
    unittest.main()
