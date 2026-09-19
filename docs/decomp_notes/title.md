# Title screen (`m_trademark` → `SCENE_TITLE_DEMO` + `ac_animal_logo`)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not commit the recordings, logo art, or the disc textures.

**Read before implementing:** `TitleLogoState`, `TitleDemoInput`, `TitleDemo`, `scenes/ui/title.tscn` / `title_logo.tscn`, `Game.begin_title_demo`.

There is **no static title image**. The title screen is a live town (`SCENE_TITLE_DEMO`, a normal `play` game state) with a scripted player, and the "Animal Crossing" logo is an *actor* (`ANIMAL_LOGO`, control actor 8) drawn over it in the font/ortho layer.

## Flow

```
trademark ──(demo scene set up)──▶ play(SCENE_TITLE_DEMO) ──START──▶ fade ──▶ player select
    ▲                                   │ 3600 ticks, no START
    └───── FADE_TYPE_SELECT_END ◀───────┘
```

1. **`m_trademark.c`.** `mTR_first_flag` is TRUE on the first boot, which sets `stage = 5` and skips straight to the demo. On every *return* from a finished demo it runs: BGM `s_titlebgm[demo]` (83–87), a 16-tick wait, the **Nintendo logo** fading in (`alpha2 += 0x880`/tick ≈ 30 ticks), a 60-tick hold, then a black fade (`alpha += 0x880`) and the next demo. START during the hold skips to the fade. **This stage is intentionally not reproduced here** (Nintendo mark).
2. **`mEv_SetTitleDemo(mTD_demono_get())`.** `S_now_demono` starts at `LOGO` (−1), then cycles START1..START5 (`TitleDemo.next_demo_index`).
3. **`trademark_goto_demo_scene`.** Clears a missing save, then for the chosen demo: `door_data` = that demo's spawn, `mTM_demotime_set` (RTC off, year `GAME_YEAR_MIN + 1`, month/day/hour/weather from `tradeday_table`), `mPr_RandomSetPlayerData_title_demo` (gender `RANDOM(4) & 1`, random cloth and face), `set_npc_4_title_demo` (14 fixed villagers), wipe `FADE_BLACK`, `scene_no = SCENE_TITLE_DEMO`.

| Demo | Date / time | Weather | Spawn GX (x, y, z) | Tool word |
| --- | --- | --- | --- | --- |
| 1 | Apr 6, 13:00 | sakura | 2180, 200, 824 | 0 (none) |
| 2 | Jun 16, 13:00 | rain | 3218, 40, 3074 | `0x2204` gelato umbrella |
| 3 | Aug 1, 06:00 | clear | 2117, 160, 1488 | `0x2203` fishing rod |
| 4 | Nov 1, 16:00 | clear | 2899, 160, 1101 | 0 (none) |
| 5 | Feb 1, 02:00 | snow | 1578, 40, 2472 | `0x2201` axe |

The head table of each `pactN.c` (`x y z angle tool scale`) matches the door data exactly. Weather is also forced in `mEnv_NowWeather` for the duration.

4. **The scene (`title_demo_info`).** Player start (2240, 0, 1600) (overridden by door data), control actors incl. `ANIMAL_LOGO`, one `UKI` actor at (340, 0, 430). FG items come from the fixed `l_title_demo_fg` table (5×6 interior blocks, 7 columns wide with a border ring), apple fruit on the trees of block (5,5) unit (14,8), BG ground texture index random (`mFM_DecideBgTexIdx`), house lights off. The acre *layout* is not overridden.
5. **Recorded input (`m_titledemo.c`).** ~1830 `u16` samples per demo at **30 Hz**, word `XXXXXXXB YYYYYYYA` (7-bit signed sticks, A/B bits). `title_demo_move` consumes one sample per 2 ticks; on odd ticks (`f1 < 1800`) the stick is the mean of the two neighbouring samples. `mCon_calc`: deadzone `STICK_MIN` 9.9, `STICK_MAX` 61, magnitude = `t / 61`. While `mEv_IsTitleDemo()` the player's controller reads this data (`m_player_controller.c_inc`), weight is 255, the axe does not break, pickups ignore pockets, and the HUD clock, events, notices and vibration are off. BGM is `mBGMPsComp_make_ps_demo(70, 0x168)`.
6. **End of demo.** At tick 3600 `mTD_game_end_init` sets `FADE_TYPE_SELECT_END` + a black wipe; after the BGM fade or `S_back_title_timer` = 120 ticks `Game_play_fbdemo_fade_out_game_end_move_end` goes back to `trademark`. START is ignored from tick 3530 (`mTD_tdemo_button_ok_check`).

## Logo actor (`ac_animal_logo.c`)

All timings in 60 Hz ticks. `TitleLogoState` is a 1:1 port.

| Action | Behavior |
| --- | --- |
| `IN` | Three skeleton clips (`animal`, `cros`, `sing`), start 1 / end 121 / speed 0.5 = **240 ticks** = the 4.0 s baked clips. START or A skips to `START_KEY_CHK_START`. |
| `BACK_FADE_IN` | Backdrop `logo_us_backA–D` (prim (80,60,0)), opacity +20/tick, strict `> 220` check → 12 ticks. |
| `START_KEY_CHK_START` | Init snaps every clip to its last frame, copyright opacity 255 (the +63/draw ramp never shows — the init already set 255), `title_timer = 60`. |
| `GAME_START` | "PRESS START", pulse `127.5·sin(phase) + 127.5`, phase is an `s16` stepped by 655 while positive, 1489 otherwise (so the negative half runs ~2.3× faster, ~72-tick period). START/A accepted only if land loaded, fade-in finished, and demo tick < 3530. |
| `FADE_OUT_START` | SE `0x44D`, opacity held 255, `title_timer = 26`. |
| `OUT` | `FADE_TYPE_SELECT` + black wipe; then `title_action_data_init_start_select` → `decide_next_scene_no()`. |
| `6` | Idle once the demo has run out. |

Layout (font matrix = ortho ±160×120 px × 16, y up, 320×240 virtual): logo and backdrop `translate(0, 730)` scale 0.135; TM `translate(1530, 690)` scale 0.1621, drawn with the copyright line's prim (40,40,45); copyright = three 64×16 IA8 lines at (61/125/189, 198), prim (40,40,45) env (210,210,215) (GAFE01_00); PRESS START = two 64×16 halves at (96,159) and (160,159), one PRIM/ENV pair per demo:

| Demo | PRIM | ENV |
| --- | --- | --- |
| 1 | 70,40,40 | 255,90,30 |
| 2 | 60,50,30 | 255,135,0 |
| 3 | 60,40,60 | 255,100,255 |
| 4 | 40,50,70 | 120,205,245 |
| 5 | 40,50,60 | 165,245,0 |

`decide_next_scene_no()`: no save → `SCENE_PLAYERSELECT` (K.K.); existing save → `SCENE_PLAYERSELECT_2` (returning player / mask cat — **not modelled**, see [intro](intro.md)); bad save or RTC crash → `SCENE_PLAYERSELECT_3`. `aAL_actor_dt` also picks a random villager as the `SP_NPC_P_SEL2` event NPC when a save exists.

## Godot mapping

| Decomp | Godot |
| --- | --- |
| `trademark` + `SCENE_TITLE_DEMO` | `scenes/ui/title.tscn` (main scene) hosts an instance of `world.tscn`; `Game.begin_title_demo(index)` in `_enter_tree` fixes date (`Clock.set_datetime`), weather, random resident, tool, spawn. `Game.title_demo_active` keeps the phase `TITLE` and picks the title BGM in `world.gd`. |
| `pactN` recording | `--kind title` → `assets/generated/titledemo/demos.json`; `TitleDemoInput` (decode + 30→60 Hz blend + A edge); `Player.scripted_input` swaps the stick and A, `TitleDemo.SAFE_VERBS` limits A to tool/pickup verbs (no talking, doors, shops). |
| `ac_animal_logo` | `TitleLogoState` (pure) + `scenes/ui/title_logo.tscn` (4:3 SubViewport with an ortho camera for the three skeleton GLBs, backdrop and TM via `shaders/title_logo_mask.gdshader`, 2D `TextureRect`s for the copyright and PRESS START). |
| `decide_next_scene_no` | After the fade, a New Game / Continue menu (plus the two dev shortcuts). New → `Game.start_intro_sequence`; Continue → `Game.continue_game`. |
| `FADE_TYPE_SELECT_END` | `Title._end_demo`: `SceneTransition` fade, 1.4 s black hold, reload into the next demo. |

Extraction gotcha: `log_win_logo3/4_tex` and `log_win_nintendo1–3_tex` are **linear** `IIIIAAAA` 64×16 (drawn through `gDPLoadTextureTile` + `gSPTextureRectangle`, the N64 path), *not* GX IA4 (8×4-tiled `AAAAIIII`). The generic REL pass decodes them as 64×32 noise; `title_screen.py` decodes them correctly and bakes the tints. The backdrop and TM are I4 whose **alpha is the intensity** (`G_CC_BACK` / `G_CC_TM`); the converted GLB keeps intensity in RGB and a 0/255 cutout in alpha, so the shader takes alpha from `.r`.

```bash
python3 tools/build_assets.py --kind title --step convert   # logo textures + demos.json
```

The logo skeletons/clips (`ui/logo_us_animal|cros|sing.glb`) and backdrop/TM (`environment/logo_us_back|tm.glb`) come from the normal full convert.

## Done since first pass

- **Fixed FG + villagers** (`WorldGenerator.generate(seed, true)`). `l_title_demo_fg` overrides the template pick per block (grass cells only — the templates assume flat ground, and the acre layout here is the generated town's). Each named villager's house is a distinct `0x50xx` item in those templates, one unit **north** of its `mNpc_SetAnimalTitleDemo` home unit; `_place_title_demo_villagers` matches each villager to the nearest marker within 2 units and centres the 3×3 house on it. Lobo has no marker in the fixed FG (the decomp lists 14 villagers but loops over 15), and homes on non-grass plots are dropped, so seed 12345 lands 10 of 14.
- **Apple tree** (`mFM_SetFruit_title_demo`): one `TREE_APPLE_FRUIT` at acre (5,5) unit (14,8) when that unit is grass.
- **Start chime**: SE `0x44D` is not named in `audio_sound_effects`, so `audio.py` carries an `EXTRA_SE_NUMS` table (`"44d": 0x44D`). Rendered: 0.84 s, 6 notes (`sfx/44d.ogg`). The full audio step also refreshed the whole catalog (it had been left at the old 53-SE test set).
- **BGM**: id 70 = `title` (rendered, used by the demo scene). Ids 83–87 are `nintendo0..4`, the Nintendo-logo jingles played in the `trademark` stage that is intentionally skipped, so they are not needed.

## Not done / open

- **Gelato umbrella** (`0x2204`, demo 2). A whole subsystem, not an item: `tol_umb_*` models are not converted, and the decomp drives it through a tools actor with open / close / rotate states (`mPlayer_INDEX_ROTATE_UMBRELLA`, clips `ply_1_umb_open1/close1/rot1` are baked) plus the `KASAMIZU` spray effect. Demo 2 walks empty-handed.
- **Scripted A presses now act.** The decomp's axe always swings on A (`CheckAndRequest_main_axe_all`: tree → chop, rock → reflect, otherwise `AIR_AXE` / `ply_1_axe_suka1`), so the axe got that open-air whiff as its field verb (`Interaction.AIR_AXE`, `axe.tres`; chop priority 18 still wins near a tree). Soak of the axe demo: 19 whiffs + 1 chop. The rod demo casts once. This also fixed a lost-press bug: the A edge is latched until the player consumes it, because the title steps the recording from an accumulator that can run two steps in one physics tick.
- **The route is a replay, not a guarantee.** Only the first and last recorded presses fall near a tree even in the original FG layout, and the acre layout differs; the player's path is the recorded stick input replayed through this game's locomotion.
- **Acre layout source.** Only the FG is overridden by `SCENE_TITLE_DEMO`; the BG comes from the land data, which is probably the zeroed default before `mCD_LoadLand` runs. Not confirmed; the demo uses seed 12345.
- **Logic rate.** Input is consumed at 60 ticks/s (3600 ticks = 60 s); `SetGameFrame(3)` is set elsewhere. Playback is driven from elapsed time.
- **Nintendo logo stage** (skipped on purpose), returning-player `PLAYERSELECT_2`, `aAL_title_decide_p_sel_npc`, `UKI` at (340, 0, 430).
