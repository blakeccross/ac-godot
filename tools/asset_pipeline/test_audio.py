from __future__ import annotations

import unittest
from pathlib import Path

from asset_pipeline.audio import (
    ARM_SUBTRACKS_BY_ID,
    AUDIO_SUBTRACK_NUM,
    AUDIOROM_SIZE,
    BANK_OFFSET,
    SEQ_COUNT,
    SEQ_SIZE,
    WAVE_OFFSET,
    catalog_id_for_hour,
    decode_vadpcm_frame,
    parse_bgm_ids,
    parse_se_ids,
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
from asset_pipeline.audio_seq import (
    SeqRenderer,
    render_se,
    render_sequence,
    se_port_values,
)
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

SE_SNIPPET = """
typedef enum audio_sound_effects {
    NA_SE_START,
    NA_SE_CURSOL,
    NA_SE_MENU_EXIT,
    NA_SE_6 = 0x6,
    NA_SE_PAGE_OKURI = 0xB,
    NA_SE_BEBE = MONO(0x6D),
    NA_SE_HANABI0 = SE_DIST_REVERB(0x10F),
    NA_SE_GASAGOSO = 0x69,
    // Footsteps
    NA_SE_FOOTSTEP_BEGIN = SE_ECHO(0x200),
    NA_SE_FOOTSTEP_GRASS,
    NA_SE_FOOTSTEP_SOIL,
} AudioSE;
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

    def test_se_ids_macros_and_keys(self) -> None:
        ids = parse_se_ids(SE_SNIPPET)
        self.assertEqual(ids["start"], 0)
        self.assertEqual(ids["cursol"], 1)
        self.assertEqual(ids["menu_exit"], 2)
        self.assertEqual(ids["6"], 0x6)
        self.assertEqual(ids["page_okuri"], 0xB)
        self.assertEqual(ids["bebe"], 0x106D)
        self.assertEqual(ids["hanabi0"], 0x210F)
        self.assertEqual(ids["gasagoso"], 0x69)
        self.assertEqual(ids["footstep_begin"], 0x4200)
        self.assertEqual(ids["footstep_grass"], 0x4201)
        self.assertEqual(ids["footstep_soil"], 0x4202)
        self.assertNotIn("NA_SE_CURSOL", ids)

    def test_se_port_values_mono(self) -> None:
        lo, hi, sub = se_port_values(0x106D)
        self.assertEqual(lo, 0x6D)
        self.assertEqual(hi, 0)
        self.assertEqual(sub, 14)
        lo2, hi2, sub2 = se_port_values(0x210F)
        self.assertEqual(lo2, 0x0F)
        self.assertEqual(hi2, 0x1)
        self.assertEqual(sub2, 0)

    def test_intro_kk_arm_subtracks(self) -> None:
        arm = ARM_SUBTRACKS_BY_ID["intro_kk"]
        self.assertEqual(arm, (0, 1, 2))
        bed_mute = [i for i in range(AUDIO_SUBTRACK_NUM) if i not in set(arm)]
        self.assertNotIn(0, bed_mute)
        self.assertIn(3, bed_mute)
        self.assertEqual(len(bed_mute), AUDIO_SUBTRACK_NUM - len(arm))

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

    def test_mute_subtracks_silences_notes(self) -> None:
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
        muted = render_sequence(seq, {0: bank}, 0, [0], mute_subtracks=[0])
        peak = max(
            abs(int.from_bytes(muted.pcm[i : i + 2], "little", signed=True))
            for i in range(0, min(len(muted.pcm), 8000), 2)
        )
        self.assertLess(peak, 50)

    def test_subtrack_port_gate_plays_note(self) -> None:
        # Group opens sub 0; sub polls port 0 (0x60) until set, then plays one note.
        seq = bytes(
            [
                0xDD, 120, 0xDB, 127, 0x90, 0x00, 0x0C, 0xFD, 96, 0xFF,
                0x00, 0x00,
                0x60, 0xF9, 0x00, 0x0C,
                0xC1, 0x00, 0xDF, 127, 0xDD, 64, 0xC3, 0x88, 0x00, 0x1D, 0xFD, 48, 0xFF,
                0xC1, 127, 0x00, 48, 0xFF,
            ]
        )
        tone = [2000 if (i // 40) % 2 == 0 else -2000 for i in range(4000)]
        sample = PcmSample(pcm=tone, loop_start=0, loop_end=4000, tuning=1.0)
        inst = Instrument(low=None, normal=sample, high=None, range_low=0, range_high=127)
        bank = Bank(bank_id=0, instruments=[inst])
        renderer = SeqRenderer(seq, {0: bank}, 0, [0])
        renderer.ignore_loop_end = True
        renderer.set_subtrack_ports(0, {0: 0x01})
        result = renderer.run(max_sec=1.0, stop_after_notes=True)
        self.assertGreater(result.notes, 0)
        peak = max(
            abs(int.from_bytes(result.pcm[i : i + 2], "little", signed=True))
            for i in range(0, min(4000, len(result.pcm)), 2)
        )
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
    def test_note_bend_is_ce_not_stereo_phase_cd(self) -> None:
        """0xCE sets bend (PCENTTABLE2); 0xCD is stereo phase and must not retune."""
        tone = [2000 if (i // 40) % 2 == 0 else -2000 for i in range(4000)]
        sample = PcmSample(pcm=tone, loop_start=0, loop_end=4000, tuning=1.0)
        inst = Instrument(low=None, normal=sample, high=None, range_low=0, range_high=127)
        bank = Bank(bank_id=0, instruments=[inst])

        def freqs_for(layer_prefix: list[int]) -> list[float]:
            # Mirror AudioSeqRenderTests layout; layer_prefix inserts before the note.
            layer = [*layer_prefix, 0xC1, 127, 0x27, 24, 0xFF]
            layer_off = 0x14  # placeholder; patched below once length known
            sub = [0xC1, 0x00, 0xDF, 127, 0xDD, 64, 0xC3, 0x88, 0x00, layer_off, 0xFD, 48, 0xFF]
            # group ends with jump-back; sub starts at 0x0C
            group = [0xDD, 120, 0xDB, 127, 0x90, 0x00, 0x0C, 0xFD, 48, 0xFB, 0x00, 0x07]
            layer_off = len(group) + len(sub)
            sub[9] = layer_off
            seq = bytes(group + sub + layer)
            seen: list[float] = []
            orig = SeqRenderer._start_voice

            def capture(self, note, sample, freq, layer_freq, pan, sub, decay_idx, env_table, sweep):  # noqa: ANN001
                seen.append(freq * layer_freq)
                return orig(self, note, sample, freq, layer_freq, pan, sub, decay_idx, env_table, sweep)

            SeqRenderer._start_voice = capture  # type: ignore[method-assign]
            try:
                render_sequence(seq, {0: bank}, 0, [0])
            finally:
                SeqRenderer._start_voice = orig  # type: ignore[method-assign]
            return seen

        base = freqs_for([])
        after_phase = freqs_for([0xCD, 0x40])
        after_bend = freqs_for([0xCE, 0x40])
        self.assertEqual(len(base), 1)
        self.assertAlmostEqual(after_phase[0], base[0], places=5)
        self.assertNotAlmostEqual(after_bend[0], base[0], places=5)
        self.assertAlmostEqual(after_bend[0] / base[0], pcent2(0x40 + 128), places=5)

    def test_subtrack_small_bend_wraps_u8(self) -> None:
        """0xEE uses PCENTTABLE2[(u8)(arg+128)]; args ≥128 are downward scoops, not clamp-to-sharp."""
        self.assertAlmostEqual(pcent2((211 + 128) & 0xFF), pcent2(83), places=5)
        self.assertLess(pcent2((211 + 128) & 0xFF), 1.0)
        # Without wrap, 211+128 clamps to 255 and reads as a sharp bend (intro_kk bug).
        self.assertGreater(pcent2(min(255, 211 + 128)), 1.1)

    def test_layer_freq_updates_while_note_sounds(self) -> None:
        """effect.c reapplies subtrack frequency_scale every update (KK bass/harmonica scoops)."""
        # Hold a long note, then 0xEE from the subtrack script after a delay.
        seq = bytes(
            [
                0xDD, 120, 0xDB, 127, 0x90, 0x00, 0x0C, 0xFD, 48, 0xFB, 0x00, 0x07,
                # sub0: program, vol, pan, small notes off→on layer, then delay and scoop
                0xC1, 0x00, 0xDF, 127, 0xDD, 64, 0xC3,
                0x88, 0x00, 0x1A,  # start layer at 0x1A
                0xFD, 24,  # wait half beat
                0xEE, 211,  # scoop flat
                0xFD, 48, 0xFF,
                # layer: vel, note 39 for long delay
                0xC1, 127, 0x27, 96, 0xFF,
            ]
        )
        # Fix layer offset: group=12 bytes, sub until layer start...
        # Recompute properly:
        group = [0xDD, 120, 0xDB, 127, 0x90, 0x00, 0x0C, 0xFD, 48, 0xFB, 0x00, 0x07]
        layer = [0xC1, 127, 0x27, 96, 0xFF]
        sub_head = [0xC1, 0x00, 0xDF, 127, 0xDD, 64, 0xC3, 0x88, 0x00, 0]  # offset placeholder
        sub_tail = [0xFD, 24, 0xEE, 211, 0xFD, 48, 0xFF]
        layer_off = len(group) + len(sub_head) + len(sub_tail)
        sub_head[9] = layer_off
        seq = bytes(group + sub_head + sub_tail + layer)

        tone = [2000 if (i // 40) % 2 == 0 else -2000 for i in range(8000)]
        sample = PcmSample(pcm=tone, loop_start=0, loop_end=8000, tuning=1.0)
        inst = Instrument(low=None, normal=sample, high=None, range_low=0, range_high=127)
        bank = Bank(bank_id=0, instruments=[inst])

        seen: list[float] = []
        orig_mix = SeqRenderer._mix_tatum

        def capture(self, mix, n_samples):  # noqa: ANN001
            for v in self.voices:
                seen.append(v.layer_freq)
            return orig_mix(self, mix, n_samples)

        SeqRenderer._mix_tatum = capture  # type: ignore[method-assign]
        try:
            render_sequence(seq, {0: bank}, 0, [0])
        finally:
            SeqRenderer._mix_tatum = orig_mix  # type: ignore[method-assign]

        self.assertTrue(any(abs(f - 1.0) < 1e-6 for f in seen[:5]))
        scoop = pcent2((211 + 128) & 0xFF)
        self.assertTrue(any(abs(f - scoop) < 1e-4 for f in seen), seen[:20])

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
class AudioDecompHeaderTests(unittest.TestCase):
    def test_bgm_and_se_enums(self) -> None:
        header = (DECOMP / "include" / "audio_defs.h").read_text(encoding="utf-8", errors="replace")
        bgm = parse_bgm_ids(header)
        se = parse_se_ids(header)
        self.assertIn("title", bgm)
        self.assertIn("field_14", bgm)
        self.assertIn("cursol", se)
        self.assertEqual(se["bebe"], 0x106D)
        self.assertEqual(se["hanabi0"], 0x210F)
        self.assertGreater(len(se), 100)


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
        self.assertEqual(banks_for_seq(mapping, 242), [2, 155, 154, 153])


if __name__ == "__main__":
    unittest.main()
