# Audio (BGM, town tune, SFX, animalese)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only.

**Do not commit Nintendo music or SFX.** Convert a disc you own into gitignored `assets/generated/audio/`, same as dialogue banks and GLBs. Hand-authored tracks live in `assets/custom/`.

**Godot:** `Audio` autoload (`play_bgm` / `stop_bgm` / `play_se` / `play_voice`). Catalogs (`BgmCatalog`, `SeCatalog`, `VoiceCatalog`) map ids → generated streams. Do **not** port Neos / `Nas_*` / JAM into GDScript. `--kind audio` unpacks `audiorom.img`, decodes bank samples, renders BGM sequences, SE one-shots (seq 242), and animalese phonemes (seqs 243–245) to OGG. Missing files are silence.

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

`m_bgm` is a **priority stack**, not a single “now playing” track: fanfare → wipe/quiet → demo → room → hourly silence → field events → **field normal**. Two sequence groups crossfade (`NA_GROUP1` / `NA_GROUP3`).

Field music is **24 separate sequences**, one per clock hour (`BGM_FIELD_00` … `BGM_FIELD_23` → `bgm_table[hour] = hour + 1`). At `:00:00` the field layer restarts. The field goes **silent XX:59:52–XX:00:16**; at `:00:00` the **town tune** plays.

Weather:

- Fine / snow / sakura: **mute subtracks** on the same hourly sequence.
- Rain: **replace** the BGM with `BGM_RAIN` (`id = 0x45` in `Sou_BgmTenkiConv`). Ambient rain SE is separate (SysLev) — catalog extract only until wired.

Town tune: 16 nibbles in save (`u64 melody`). Values 0–12 = pitches G(low)–E, 13 = random, 14 = rest, 15 = hold. Playback copies a pre-authored **arrangement** from sequence **248**, then feeds the 16 notes into the live sequence. Nintendo wrote the arrangements; the player only supplies the melody. [scope.md](../scope.md) keeps the **editor** out until earned.

K.K. / minidisks are ordinary sequences (`BGM_MD0`–`BGM_MD54`). Gyroids are a small rhythm sequencer, not full songs.

## Important states

- Current BGM id + which of the two groups is active.
- Weather (`sou_tenki`) for mute / rain swap.
- Town melody (16 nibbles).
- Stack entries (room vs field vs fanfare).
- Talk / fishing / insect volume ducks.
- Voice mode + sound spec during dialogue.

## Reproduce (first playable slice)

- **Hear original hourly town BGM** when a converted library is present.
- Switch track on `Clock.hour_changed` while outdoors.
- Play **title** BGM on the title scene; **intro_kk** on the K.K. opening; **intro_train** on the Rover train; **intro_arrive** on station arrival; **shop** (or house) BGM indoors.
- **Rain** (`Game.weather == &"rain"`) swaps to the rain track.
- **SE catalog** via `Audio.play_se` / `start_syslev`. Wired: footsteps, doors, tools, dig/fill, net/rod, tree shake, pickup, inventory/map UI, thunder, rain SysLev, bee sting, furniture drawer / sit. Fireworks / weeds / plus-bridge / floor carpet table still deferred.
- **Animalese** during dialogue typewriter (`DialogueVoice` + `Audio.play_voice`).
- Missing `assets/generated/audio/` → silence (same as missing GLBs).
- Crossfade ~1 s between tracks (original uses long fades; keep it short).

## Simplify

- **Offline render** sequences / SE / phonemes to OGG in the pipeline. Godot only plays streams.
- Do not port Neos, DSP ADPCM, or sequence bytecode into GDScript.
- Ignore fanfares, festival overrides, bee chase, train, staff roll, K.K. live mouth-sync, gyroids, furniture stereos.
- Ignore snow/sakura **subtrack mutes** until a second render pass (or accept the “fine” mix). `intro_kk` bakes `Na_TTKK_ARM` mute on subtracks 0–2.
- Ignore DSP filters / reverb and random velocity-gate (non-deterministic).
- Ignore the 24 s hourly silence and town-tune chime until a later slice (editor stays out of scope).
- Talk volume-duck can wait; pause can mute the Music bus.
- SE: no Neos polyphony / singleton / distance reverb / SysLev loops at runtime yet — one-shots only.
- Animalese: full `Sou_TanboinHenkan` / `Sou_ChouboinHenkan` / `Sou_ConnectCheck`, deferred digraph beat, `VOICE_STATUS_*` emotion pitch/volume modulators, and `0x82`/`0x83` bumps. Melody `0x80` (`Na_MelodyVoice`) still deferred (needs per-animal melody bank).

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

`catalog.json` keys use decomp enum names (`field_10`, `page_okuri`), not invented titles.

### Coverage

`--kind audio` renders every `BGM_*` that `SEQ_TABLE` maps, every named `NA_SE_*`, and phonemes `0x00`–`0x77` for all three voice specs (covers `Sou_ConnectCheck` digraph ids).

### Converter stages

1. **Unpack** — slice `audiorom.img`; list 249 seq sizes; write `work_root/converted/audio/manifest.json`.
2. **Waves** — N64 ADPCM → WAV (debug).
3. **Render BGM** — sequence interpreter + mixer → OGG + loop starts.
4. **Render SE** — seq 242 + subtrack port inject (`Sou_TrgStart`) → `sfx/*.ogg`.
5. **Render voice** — seqs 243–245 + phoneme port 0 → `voice/spec_*/ph_*.ogg`.
6. **Catalog** — `catalog.json` with `bgm` / `sfx` / `voice`.

## In-game systems

Keep `Audio` as the only autoload. Lookup stays in `RefCounted` catalogs so tests do not need the tree.

| Piece | Role |
| --- | --- |
| `BgmCatalog` | `stream_for(bgm_id)` |
| `SeCatalog` | `stream_for(se_id)` |
| `VoiceCatalog` | `stream_for(spec, phoneme)` |
| `Audio.play_bgm` / `stop_bgm` | Music bus crossfade |
| `Audio.play_se` / `play_voice` | SFX bus one-shots |
| `Audio.start_syslev` / `stop_syslev` | Looping rain ambient (ids 7–9) |
| `FootstepSe` | Attr / season / gait → footstep id + volume |
| `PlayerSe` | Tool / dig / catch / sit frame schedules |
| `DialogueVoice` | Char → phoneme; looks → sound spec |
| `dialogue_overlay` | Utter on typewriter glyph advance; page / choice SE |

Do not put BGM ids on every furniture actor. Do not autoload a second music manager.

Priority for v1 BGM: last `play_bgm` wins. The original stack can wait.

## Deferred call-site wiring

Still out until gameplay exists:

- Fireworks (`hanabi*`) — no event FX yet
- Weed pull (`zassou_nuku`) — no weed hosts
- Umbrella rain SysLev variants / umbrella rotate
- Positional SE pan/distance
- Town-tune note pips
- Plus-bridge footstep override (`sAdo_CheckOnPlussBridge`) — needs Tortimer bridge actor
- Indoor floor-index table (`SE_FLOOR_DATA`) — rooms use wood (`Na_PlyWalkSeRoom(0xFF)`)

Wired to original frames / triggers:

- Footsteps (`FootstepSe`), doors `6`–`9`, dialogue page/choice/voice
- Tools: axe / scoop / net / rod (`PlayerSe` + hosts)
- Dig / fill / stump / buried / rock / flower / tree shake
- Pickup `item_get` + `gasagoso`, bee sting, furniture drawer open, sit/bed
- Inventory / map UI (`menu_pause`, `cursol`, `menu_exit`, `17c`/`17d`, hand grab)
- Thunder `424`, rain SysLev loops 7/8/9 (`Audio.start_syslev`)

## Tests

- Python: unpack offsets, VADPCM, audiomap, SE enum macros, port-gated note mix. Skip disc-backed extract when `audiorom.img` is absent.
- GdUnit: catalogs null without generated files; `play_se` / `play_voice` / `play_bgm` do not crash; `DialogueVoice` letter → phoneme. Do not assert waveform identity.

## Phased work

1. **Unpack + catalog stub** — done.
2. **Wave decode** — done.
3. **Sequence render** — done (BGM).
4. **Playback** — done (BGM + rain + interiors).
5. **SE + animalese + world SE call sites** — done for existing gameplay (tools, dig, fish/net, UI, rain SysLev, thunder). Fireworks / weeds / floor carpet table wait on systems.
6. **Later** — remaining BGM polish, talk duck, hourly silence, town-tune arranger, positional SE, SysLev umbrella variants.

## Interacts with

- **Time** — `hour_changed` for field BGM.
- **Game** — `weather`, title vs play vs interior.
- **Dialogue** — typewriter animalese / click.
- **Pipeline** — disc + decomp headers.
- **Save** — town melody later; not required for hourly BGM.
