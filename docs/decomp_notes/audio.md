# Audio (BGM, town tune, SFX)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only.

**Do not commit Nintendo music.** Convert a disc you own into gitignored `assets/generated/audio/`, same as dialogue banks and GLBs. Hand-authored tracks live in `assets/custom/`.

**Godot:** expand the existing `Audio` autoload (`play_bgm` / `stop_bgm`). `BgmCatalog` (`RefCounted`, not an autoload) maps BGM ids → generated `.ogg`. Do **not** port Neos / `Nas_*` / JAM into GDScript. `--kind audio` unpacks `audiorom.img`, decodes bank samples, and renders the test-set sequences to looping OGG. Missing files are silence.

**Read before implementing:** this note, [asset_pipeline.md](../asset_pipeline.md), `scripts/systems/audio.gd`, `Clock.hour_changed`.

## Decomp sources

| File | Role |
| --- | --- |
| `files/audiorom.img` | Packed sequences + banks + ADPCM waves (disc) |
| `src/static/jaudio_NES/game/audioheaders.c` | Sequence / bank / wave / data ArcHeaders |
| `src/static/jaudio_NES/internal/system.c` | `Nas_InitAudio`, load seq/bank/wave |
| `src/static/jaudio_NES/internal/neosthread.c` | Load `audiorom.img` into ARAM; DSP mix thread |
| `src/static/jaudio_NES/internal/track.c` | Sequence bytecode interpreter |
| `src/static/jaudio_NES/game/game64.c_inc` | `Na_BgmStart`, `SEQ_TABLE`, weather remap |
| `src/static/jaudio_NES/game/melody.c` | Town-tune arrangement (seq 248 + 16 notes) |
| `src/game/m_bgm.c` | BGM priority stack, hourly field, silence window |
| `src/game/m_melody.c` / `m_mscore_ovl.c` | Save 16-nibble tune; editor UI |
| `include/audio_defs.h` | `BGM_*` ids, SE ids |
| `include/audio.h` | Game → audio API (`sAdo_BgmStart`, …) |
| `src/audio.c` | Thin wrap `sAdo_*` → `Na_*` |

This is **N64 `libultra` audio on the GameCube DSP** (Neos), not Wind Waker JaiSeq. Boot jingles in `main.dol` use leftover JSystem JAM; town BGM does not.

## What does the original system do?

Almost nothing is a streamed WAV. Composers authored **sequence scripts** (group + 16 subtracks, 48 tatums/beat). Scripts pick **instruments** from **banks**, which point at **ADPCM waves**. The mixer turns that into PCM every audio frame.

`audiorom.img` is three concatenated blobs (from `AudiodataHeaderStart`):

| Region | Offset | Size | Contents |
| --- | --- | --- | --- |
| Audioseq | `0x00000000` | `0xCF700` | 249 sequence files |
| Audiobank | `0x000CF700` | `0x67C80` | 159 instrument banks |
| Audiowave | `0x00137380` | `0x6B33E0` | 6 wave groups (samples) |

Per-sequence offsets live in `AudioseqHeaderStart`. Game BGM ids (`BGM_FIELD_10`, `BGM_SHOP0`, …) are **not** sequence indices. `SEQ_TABLE[bgm_id]` maps them.

`m_bgm` is a **priority stack**, not a single “now playing” track: fanfare → wipe/quiet → demo → room → hourly silence → field events → **field normal**. Two sequence groups crossfade (`NA_GROUP1` / `NA_GROUP3`).

Field music is **24 separate sequences**, one per clock hour (`BGM_FIELD_00` … `BGM_FIELD_23` → `bgm_table[hour] = hour + 1`). At `:00:00` the field layer restarts. The field goes **silent XX:59:52–XX:00:16**; at `:00:00` the **town tune** plays.

Weather:

- Fine / snow / sakura: **mute subtracks** on the same hourly sequence.
- Rain: **replace** the BGM with `BGM_RAIN` (`id = 0x45` in `Sou_BgmTenkiConv`).

Town tune: 16 nibbles in save (`u64 melody`). Values 0–12 = pitches G(low)–E, 13 = random, 14 = rest, 15 = hold. Playback copies a pre-authored **arrangement** from sequence **248**, then feeds the 16 notes into the live sequence. Nintendo wrote the arrangements; the player only supplies the melody. [scope.md](../scope.md) keeps the **editor** out until earned.

K.K. / minidisks are ordinary sequences (`BGM_MD0`–`BGM_MD54`). Gyroids are a small rhythm sequencer, not full songs.

## Important states

- Current BGM id + which of the two groups is active.
- Weather (`sou_tenki`) for mute / rain swap.
- Town melody (16 nibbles).
- Stack entries (room vs field vs fanfare).
- Talk / fishing / insect volume ducks.

## Reproduce (first playable slice)

- **Hear original hourly town BGM** when a converted library is present.
- Switch track on `Clock.hour_changed` while outdoors.
- Play **title** BGM on the title scene; **intro_kk** on the K.K. opening; **intro_train** on the Rover train; **intro_arrive** on station arrival; **shop** (or house) BGM indoors.
- **Rain** (`Game.weather == &"rain"`) swaps to the rain track.
- Missing `assets/generated/audio/` → silence (same as missing GLBs).
- Crossfade ~1 s between tracks (original uses long fades; keep it short).

## Simplify

- **Offline render** sequences to looping OGG in the pipeline. Godot only plays streams.
- Do not port Neos, DSP ADPCM, or sequence bytecode into GDScript.
- Ignore fanfares, festival overrides, bee chase, train, staff roll, K.K. live mouth-sync, gyroids, furniture stereos, animalese.
- Ignore snow/sakura **subtrack mutes** until a second render pass (or accept the “fine” mix). `intro_kk` bakes `Na_TTKK_ARM` mute on subtracks 0–2.
- Ignore DSP filters / reverb and random velocity-gate (non-deterministic).
- Ignore the 24 s hourly silence and town-tune chime until a later slice (editor stays out of scope).
- Talk volume-duck can wait; pause can mute the Music bus.

## Ignore

- Mechanical translation of `track.c` / `jammain_2.c` into GDScript.
- Committing OGG/WAV/MIDI/SF2 from the disc.
- Emulator DSP dumps as the pipeline (not reproducible from `audiorom.img`).
- Playing Nintendo music from `assets/custom/` (that folder is hand-authored recreation only).

## Why not a live sequencer in Godot?

A faithful in-engine player would be a second game: ADPCM, banks, 16 subtracks, ports, vibrato, the town-tune patcher. That copies C architecture and delays anything playable. The Gfx analog is **convert to GLB**, not a GBI interpreter at runtime. Audio should convert to OGG.

Town tune later, if earned: a small Godot arranger that plays **original samples** (from the wave convert) against the 16 notes — still not a Nas port.

## Pipeline (`--kind audio`)

Mirror dialogue: Python in `tools/asset_pipeline/`, wired from `tools/build_assets.py`. Nintendo output stays under `assets/generated/` (already gitignored).

```
files/audiorom.img
  + decomp audioheaders.c / SEQ_TABLE / BGM_* names
  → slice seq / bank / wave
  → decode ADPCM samples
  → interpret sequence → mix PCM
  → OGG (+ loop start)
  → assets/generated/audio/
```

Needs a local disc (`game_files`) and `decomp_root` (same as FG / villagers) for headers and the BGM→seq map. Do not copy `audioheaders.c` into this repo; parse it at convert time.

### Output layout

```
assets/generated/audio/          # gitignored
  catalog.json                   # bgm_num, seq index, path, loop_start_sec
  bgm/
    title.ogg
    field_00.ogg … field_23.ogg
    rain.ogg
    shop0.ogg
    …
  waves/                         # optional debug WAVs; not loaded by the game
```

`catalog.json` keys use decomp enum names (`field_10`, `title`), not invented song titles.

### Test set vs `--full`

Default `test_set_only` (and `--kind audio` without `--full`) renders only:

| BGM id | Why |
| --- | --- |
| `BGM_TITLE` | Title scene |
| `BGM_INTRO_KK` | K.K. player-select opening |
| `BGM_INTRO_TRAIN` | Rover train character creation |
| `BGM_INTRO_ARRIVE` | Station arrival / get-off demo |
| `BGM_FIELD_08`, `_14`, `_20` | Morning / afternoon / evening smoke test |
| `BGM_SHOP0` | Indoor |
| `BGM_RAIN` | Weather swap |
| `BGM_ENTER_HOUSE` | Optional door sting if cheap |

`--full` / `"test_set_only": false` renders every `BGM_*` that `SEQ_TABLE` maps to a real sequence (skip unused `247` placeholders if they are silence).

### Converter stages (stop if a stage is unreliable)

1. **Unpack** — slice `audiorom.img` with the three data-header offsets; list 249 seq sizes; write `work_root/converted/audio/manifest.json`. Unit-test offsets and counts (no disc audio in git).
2. **Waves** — N64 ADPCM → WAV. Proof: a handful of instruments are audible in a player.
3. **Render** — sequence interpreter + mixer → WAV → OGG. Proof: `field_14.ogg` loops and is recognizably the afternoon theme.
4. **Catalog** — copy into `assets/generated/audio/` + `catalog.json` with loop starts.

Stage 3 is the large piece (same order of work as `gfx.py`). Prefer a **Python renderer** that follows decomp opcode meaning, not a GDScript port. Fallback if that stalls: sequence → MIDI + bank/wave → SoundFont, then `fluidsynth` CLI to WAV. MIDI loses portamento / exact mute; use it only to unblock hearing tracks, then replace.

Optional tools (download to `tools/.cache/` like `dtk`, do not vendor Nintendo data): a small ADPCM decoder; `oggenc` / `ffmpeg` for encode. Do not add a GameCube emulator as a dependency.

### Loop points

N64 sequences usually loop after an intro. The renderer should emit `loop_start_sec` in `catalog.json`. Godot `AudioStreamOggVorbis.loop` + `loop_offset` consumes that at load time.

## In-game systems

Keep `Audio` as the only autoload. Add play methods there; put lookup in a `RefCounted` catalog so tests do not need the tree.

| Piece | Role |
| --- | --- |
| `BgmCatalog` | Load `catalog.json` if present; `stream_for(bgm_id) -> AudioStream` |
| `Audio.play_bgm(id)` | Crossfade two `AudioStreamPlayer`s on the Music bus; no-op if missing |
| `Audio.stop_bgm()` | Fade out |
| Title scene | `play_bgm(&"title")` |
| World | `Clock.hour_changed` + `Game.weather` → `field_HH` or `rain` |
| Interior | Shop / house ids from room kind (one shop track is enough at first) |

Do not put BGM ids on every furniture actor. Do not autoload a second music manager.

Priority for v1: last `play_bgm` wins (title vs world vs interior). The original stack can wait.

## Tests

- Python: unpack offsets, VADPCM on a synthetic buffer, audiomap bank lists, injected-sample sequence mix. Skip disc-backed extract when `audiorom.img` is absent.
- GdUnit: `BgmCatalog` returns null without generated files; `Audio.play_bgm` does not crash; hour `14` requests `field_14`. Do not assert waveform identity.

## Phased work

1. **Unpack + catalog stub** — done. `--kind audio` writes region blobs, test-set seq slices, and `catalog.json`.
2. **Wave decode** — done. CTL banks relocate against `audiowave.bin`; VADPCM uses the N64 8-sample matrix predictor (not a 2-tap IIR). Debug WAVs go under the work root `converted/audio/waves/`.
3. **Sequence render** — test-set mixer follows Neos note path: bank envelopes, ADSR decay/release, vibrato, portamento, freq scale / pitch bend, squared volume. Filters, reverb, and random gate/velocity are still skipped (DSP / non-deterministic).
4. **Playback** — done. Title, outdoor hour, rain swap, shop interior; silence when files are missing.
5. **Later (earned)** — remaining BGM ids, talk duck, hourly silence, default-melody chime, SFX one-shots, town-tune arranger.

## Interacts with

- **Time** — `hour_changed` for field BGM.
- **Game** — `weather`, title vs play vs interior.
- **Pipeline** — disc + decomp headers.
- **Save** — town melody later; not required for hourly BGM.
