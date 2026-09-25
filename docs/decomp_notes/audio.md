# Audio (BGM, town tune, SFX, animalese)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only.

**Do not commit Nintendo music or SFX.** Convert a disc you own into gitignored `assets/generated/audio/`, same as dialogue banks and GLBs. Hand-authored tracks live in `assets/custom/`.

**Godot:** `Audio` autoload (`play_bgm` / `stop_bgm` / `play_se` / `play_voice`). Catalogs (`BgmCatalog`, `SeCatalog`, `VoiceCatalog`) map ids → generated streams. `--kind audio` unpacks `audiorom.img`, decodes bank samples, renders BGM sequences, SE one-shots (seq 242), and animalese phonemes (seqs 243–245) to OGG. Missing files are silence.

**Read before implementing:** this note, [asset_pipeline.md](../asset_pipeline.md), `scripts/systems/audio.gd`, `Clock.hour_changed`.

## Decomp sources

| File | Role |
| --- | --- |
| `files/audiorom.img` | Packed sequences + banks + ADPCM waves (disc) |
| `src/static/jaudio_NES/game/audioheaders.c` | Sequence / bank / wave / data ArcHeaders |
| `src/static/jaudio_NES/internal/system.c` | `Nas_InitAudio`, load seq/bank/wave |
| `src/static/jaudio_NES/internal/neosthread.c` | Load `audiorom.img` into ARAM; DSP mix thread |
| `src/static/jaudio_NES/internal/track.c` | Sequence bytecode interpreter |
| `src/static/jaudio_NES/game/game64.c_inc` | `Na_BgmStart`, `SEQ_TABLE`, weather remap, `Sou_TrgStart`, `Na_VoiceSe` |
| `src/static/jaudio_NES/game/melody.c` | Town-tune arrangement (seq 248 + 16 notes) |
| `src/game/m_bgm.c` | BGM priority stack, hourly field, silence window |
| `src/game/m_melody.c` / `m_mscore_ovl.c` | Save 16-nibble tune; editor UI |
| `src/game/m_msg_sound.c_inc` | Char → voice code; animal vs click mode |
| `include/audio_defs.h` | `BGM_*` ids, `NA_SE_*` ids, voice modes |
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

**SFX:** One permanent sequence (**seq 242**) on `SE_GROUP` (`NA_GROUP0`). Game code calls `sAdo_SysTrgStart` / `OngenTrgStart` → `Sou_TrgStart`, which writes `se_idx_lo` / `se_idx_hi` into subtrack ports 0/1. Mono flag (`0x1000`) uses subtrack 14. Level/ambient SE (`SysLevStart`) and positional pan/reverb stay on the same group.

**Animalese:** `VOICE_GROUP` (`NA_GROUP4`) runs seq **243 / 244 / 245** (banks `0x9C` / `0x9D` / `0x9E`) from `Na_SpecChange` (looks → sound spec). Each glyph reveal calls `Na_VoiceSe` → phoneme on port 0; pitch/volume from spec + emotion. Click mode plays `NA_SE_BEBE` instead.

`m_bgm` is a **priority stack**, not a single "now playing" track: fanfare → wipe/quiet → demo → room → hourly silence → field events → **field normal**. Two sequence groups crossfade (`NA_GROUP1` / `NA_GROUP3`).

Field music is **24 separate sequences**, one per clock hour (`BGM_FIELD_00` … `BGM_FIELD_23` → `bgm_table[hour] = hour + 1`). At `:00:00` the field layer restarts. The field goes **silent XX:59:52–XX:00:16**; at `:00:00` the **town tune** plays.

Weather:

- Fine / snow / sakura: **mute subtracks** on the same hourly sequence.
- Rain: **replace** the BGM with `BGM_RAIN` (`id = 0x45` in `Sou_BgmTenkiConv`). Ambient rain SE is separate: a **level** SE (`Na_SysLevStart(7/8/9)` → `Sou_LevStart`, level id on SE subtrack 8 port 0 — its own table, *not* trigger SEs 7/8/9, which are door hinges), 0x12/0x13/0x14 under an open umbrella. Rendered as `sfx/lev_7`…`lev_14`. `Na_SysLevStart` plays 7/8/9 at **0.4** in `sou_scene_mode` 2 / 0xE / 0xF / 0x10 (rooms, exiting, museum, lighthouse). The weather actor is in every field and room scene, so rain is heard indoors; silent only in the player's basement (`basement_event`) and the title demo.

Town tune: 16 nibbles in save (`u64 melody`). Values 0–12 = pitches G(low)–E, 13 = random, 14 = rest, 15 = hold. Playback copies a pre-authored **arrangement** from sequence **248**, then feeds the 16 notes into the live sequence. Nintendo wrote the arrangements; the player only supplies the melody.

K.K. / minidisks are ordinary sequences (`BGM_MD0`–`BGM_MD54`). Gyroids are a small rhythm sequencer, not full songs.

## Important states

- Current BGM id + which of the two groups is active.
- Weather (`sou_tenki`) for mute / rain swap.
- Town melody (16 nibbles).
- Stack entries (room vs field vs fanfare).
- Talk / fishing / insect volume ducks.
- Voice mode + sound spec during dialogue.

## Behavior

- Hourly town BGM plays when a converted library is present; track switches on `Clock.hour_changed` while outdoors.
- Title BGM on the title scene; `intro_kk` on the K.K. opening; `intro_train` on the Rover train; `intro_arrive` on station arrival; shop (or house) BGM indoors.
- Rain (`Game.weather == &"rain"`) swaps to the rain track.
- SE catalog via `Audio.play_se` / `start_syslev`: footsteps, doors, tools, dig/fill, net/rod, tree shake, pickup, inventory/map UI, thunder, rain SysLev, bee sting, furniture drawer / sit.
- Animalese during dialogue typewriter (`DialogueVoice` + `Audio.play_voice`).
- Missing `assets/generated/audio/` → silence (same as missing GLBs).
- Crossfade ~1 s between tracks (the original uses long fades).
- Sequences / SE / phonemes render offline to OGG in the pipeline; Godot only plays streams. Neos, DSP ADPCM, and sequence bytecode are not ported to GDScript — the Gfx analog is convert-to-GLB, not a GBI interpreter at runtime.
- Meter-scale speeds and per-frame values aside, priority for BGM is last `play_bgm` wins, not the original's full stack.

## Pipeline (`--kind audio`)

Mirror dialogue: Python in `tools/asset_pipeline/`, wired from `tools/build_assets.py`. Nintendo output stays under `assets/generated/` (already gitignored). Never commit OGG/WAV/MIDI/SF2 pulled from the disc, and never play Nintendo music from `assets/custom/` — that folder is hand-authored recreation only.

```
files/audiorom.img
  + decomp audioheaders.c / SEQ_TABLE / BGM_* / NA_SE_*
  → slice seq / bank / wave
  → decode ADPCM samples
  → interpret sequence → mix PCM
  → OGG (+ loop start for BGM)
  → assets/generated/audio/
```

Needs a local disc (`game_files`) and `decomp_root` (same as FG / villagers) for headers and the BGM→seq map. Do not copy `audioheaders.c` into this repo; parse it at convert time.

### Output layout

```
assets/generated/audio/          # gitignored
  catalog.json                   # bgm / sfx / voice sections
  bgm/
    title.ogg
    field_00.ogg … field_23.ogg
    rain.ogg
    shop0.ogg
    …
  sfx/
    cursol.ogg
    bebe.ogg
    hanabi0.ogg
    …
  voice/
    spec_1/ph_00.ogg …           # seq 243
    spec_2/ph_00.ogg …           # seq 244
    spec_3/ph_00.ogg …           # seq 245
  waves/                         # optional debug WAVs; not loaded by the game
```

`catalog.json` keys use decomp enum names (`field_10`, `page_okuri`), not invented titles. `--kind audio` renders every `BGM_*` that `SEQ_TABLE` maps, every named `NA_SE_*`, and phonemes `0x00`–`0x77` for all three voice specs (covers `Sou_ConnectCheck` digraph ids).

Converter stages: **unpack** (slice `audiorom.img`, list 249 seq sizes, write `manifest.json`) → **waves** (N64 ADPCM → WAV) → **render BGM** (sequence interpreter + mixer → OGG + loop starts) → **render SE** (seq 242 + subtrack port inject → `sfx/*.ogg`) → **render voice** (seqs 243–245 + phoneme port 0 → `voice/spec_*/ph_*.ogg`) → **catalog** (`catalog.json` with `bgm` / `sfx` / `voice`).

## In-game systems

Keep `Audio` as the only autoload. Lookup stays in `RefCounted` catalogs so tests do not need the tree.

| Piece | Role |
| --- | --- |
| `BgmCatalog` | `stream_for(bgm_id)` |
| `SeCatalog` | `stream_for(se_id)` |
| `VoiceCatalog` | `stream_for(spec, phoneme)` |
| `Audio.play_bgm` / `stop_bgm` | Music bus crossfade |
| `Audio.play_se` / `play_voice` | SFX bus one-shots |
| `Audio.start_syslev` / `stop_syslev` / `sync_rain_syslev` | Looping level SE by level id (`lev_<hex>`): rain 7–9 / umbrella 0x12–0x14 |
| `FootstepSe` | Attr / season / gait → footstep id + volume |
| `PlayerSe` | Tool / dig / catch / sit frame schedules |
| `DialogueVoice` | Char → phoneme; looks → sound spec |
| `dialogue_overlay` | Utter on typewriter glyph advance; page / choice SE |

Do not put BGM ids on every furniture actor. Do not autoload a second music manager.

Call sites wired to original frames / triggers: footsteps (`FootstepSe`), doors `6`–`9`, dialogue page/choice/voice; tools (axe / scoop / net / rod via `PlayerSe` + hosts); dig / fill / stump / buried / rock / flower / tree shake; pickup `item_get` + `gasagoso`, bee sting, furniture drawer open, sit/bed; inventory / map UI (`menu_pause`, `cursol`, `menu_exit`, `17c`/`17d`, hand grab); thunder `424`, rain level-SE loops `lev_7`/`8`/`9` (`Audio.sync_rain_syslev`, from `WeatherFx` outdoors and `interior.gd` indoors).

## Tests

- Python: unpack offsets, VADPCM, audiomap, SE enum macros, port-gated note mix. Skip disc-backed extract when `audiorom.img` is absent.
- GdUnit: catalogs null without generated files; `play_se` / `play_voice` / `play_bgm` do not crash; `DialogueVoice` letter → phoneme. Do not assert waveform identity.

## Interacts with

- **Time** — `hour_changed` for field BGM.
- **Game** — `weather`, title vs play vs interior.
- **Dialogue** — typewriter animalese / click.
- **Pipeline** — disc + decomp headers.
- **Save** — town melody later; not required for hourly BGM.
