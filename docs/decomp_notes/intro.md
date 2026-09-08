# Intro (K.K. opening → Rover train character creation)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not commit Nintendo message banks or train meshes.

**Read before implementing:** `IntroKkStage`, `IntroSequence`, `IntroTrainStage`, KK + train intro scenes, title → intro hook.

## Flow

1. **Player select / K.K.** (`SCENE_PLAYERSELECT`, `ac_npc_p_sel`, `SP_NPC_P_SEL`) — Totakeke strums under `grd_player_select`, BGM `BGM_INTRO_KK`.
2. **Train** (`SCENE_START_DEMO`, `ac_npc_guide`) — Rover character creation, BGM `BGM_INTRO_TRAIN`.
3. **Station arrival** (`ac_intro_demo`) — outdoor train (`TRAIN0`/`TRAIN1`), Porter (`SP_NPC_STATION_MASTER`), walk off platform, Tom Nook (`SP_NPC_RCN_GUIDE`) greets; BGM `BGM_INTRO_ARRIVE`.

**Godot wiring (one unbroken chain).** Title **New Game** → `Game.start_intro_sequence()` → `intro_kk.tscn` → (fade) `advance_intro_to_train` → `intro_train.tscn` → `Game.finish_intro_sequence(identity)` → `_begin_station_arrival` (new town, keeps the train-set clock, `intro_station_active = true`) → generated `world.tscn` + `IntroStationDirector` → `Game.complete_intro_station` → `FirstJob.begin_after_house`. Dev entries: **Town Seed 12345** skips the intro into a deterministic town; **Station Arrival** (`start_intro_station`) runs step 3 only in a fresh town; the standalone `intro_station.tscn` scene exits via `Game.debug_finish_station_arrival`.

**Scene transitions** use the persistent `SceneTransition` overlay (autoload, layer 100 — the whole-game port of `m_fbdemo_wipe` / `Game_play_fbdemo_wipe_*`, not just doors). Two axes: `play_wipe_out(style)` that the caller awaits (fade direction `fb_fade_type`) and a `Style` visual (`fb_wipe_type` — `FADE` = `WIPE_TYPE_FADE_BLACK`, `IRIS` = `WIPE_TYPE_TRIFORCE`/`CIRCLE_*`, iris shader deferred so it renders as a fade). `wipe_in_pending` + `pending_style`/`pending_color` are the `transition.wipe_type` hand-off carried across the load; `queue_wipe_in(style)` overrides just the incoming half. Title → K.K.: `Game.start_intro_sequence()` awaits `play_wipe_out(FADE)` → `play_wipe_in_if_pending()` in `intro_kk._ready`. K.K. → train: the `aNPS` 70-frame fade-to-black runs on the K.K. `%FadeRect` (strum/BGM-synced, scene-owned), then `advance_intro_to_train` calls `SceneTransition.hold_black()` to hold opaque across the swap (`WIPE_TYPE_FADE_BLACK`), `intro_train._ready` fades in. Train → station: `intro_train._finish_deferred` awaits `play_wipe_out(FADE)` then `queue_wipe_in(IRIS)` before `finish_intro_sequence` (`aNGD_scene_change_wait_init` `fb_wipe_type = FADE_BLACK`, `transition.wipe_type = CIRCLE_LEFT`), `world.gd._spawn_player` runs the wipe-in. `abort_intro_sequence` calls `cancel_wipe()` so Esc never leaves the title black.

**Full `fb_wipe_type` catalogue** (`include/m_play.h`): `NORMAL` (`fbdemo_wipe1` HW dither — doors left at `NORMAL` are remapped to `FADE_BLACK` in `m_scene.c`, so effectively unused); `TRIFORCE` (`fbdemo_triforce` iris — every building door: house / my house / villager house / museum / shops / Able's / needlework / post / police / depart); `FADE_WHITE` (dead — enum only); `FADE_BLACK` (title / trademark / `ac_animal_logo` / title-demo, RTC + restart → title, K.K. → train); `CIRCLE_LEFT` / `CIRCLE_RIGHT` (`fbdemo_triforce` + direction — intro train → town arrival, returning-player `p_sel2` / `mask_cat2`); `EVENT` (`fbdemo_fade`, `ac_event_manager` fireworks etc., weather-gated). Rates `transition.wipe_rate` 28 / `fade_rate` 30. The separate always-on grey `color_fade` (`0xA0A0A0`, `FADE_TYPE_LOCK`) is pause/menu dimming, not a scene wipe — not modelled here.

**Dialogue.** Every intro line prefers the disc-extracted bank message (`--kind dialogue`) and falls back to a paraphrased authored JSON: K.K. `msg_2503` (`0x09C7`, first game) → `kk_opening.json`; Porter `msg_2013`; Nook `msg_2014/2015/2017/2020/2022/2027` → `nook_station_*` / `nook_house_debt*`. The authored fallbacks are deliberately not the original wording — exact text needs the extraction step.

**Nook down payment** (`aNRG_demand_payment`, was missing). `m_start_data_init.c` gives a new resident one QUEST-flagged **1,000-bell bag** in pocket slot 0 (`Game._grant_intro_start_items`). Authored beat order: `nook_house_debt.json` ends on "let's have a look in those pockets" → `IntroStationDirector._begin_demand_payment` sets `Game.intro_payment_pending` and opens `inventory_ui`, which shows a **Hand over** tag only on `money_1000` (`Inventory.tags_for_slot`) — the pockets open *at* the ask, not after Nook's whole speech. Pick it → `HandOver.player_gives_to_npc` + `inventory.remove` → `nook_house_settled.json` (loan / settle-in tail, `aNRG_demo_end_wait`) → job talk. Close the pockets empty → `nook_house_debt_nag.json` / `0x07EB` → reopen (`aNRG_menu_close_wait_talk_proc` empty branch). Bank `msg_2022` chains the settle-in tail itself, so the authored follow-up is fallback-path only. `Game.complete_intro_station` books `loan = Inventory.INTRO_HOUSE_DEBT` (`mPlayer_DEBT0` = 17,400) after Nook leaves.

**Animation / lighting.** Rover's aisle move (`aNGD_move_to_aisle`) chase-turns the body toward the aisle point at 11.25°/frame while WALK1 carries him forward — no pivot-in-place. K.K. lighting matches `l_mEnv_kcolor_data_p_sel` (ambient 30/30/80, sun dir 0/89/79 colour 255/255/200, fog 100/100/120 kept disabled) with an authored ambient-energy lift for the white fur and a black clear instead of the unused `22/27/94`. **Train interior lighting**: `mEnv_SetBaseLight` `FIELD_DRAW_TYPE_TRAIN` lights the car with **ambient + a directional sun** (`mEnv_ChangeDiffuseLight`). The `l_mEnv_kcolor_fine_data` ambient is cool/blue by design; `IntroTrainPresentation` takes it from `Clock.outdoor_light()` (blended toward a dim fill in the tunnel + the `(35,30,40)×(1−sun_percent)` lift), and a `Sun` DirectionalLight3D in `intro_train.tscn` supplies the warm/bright half — colour + energy from `Clock.outdoor_light()` `sun` / `sun_energy`, scaled by `sun_percent`. Without the sun the car read dark and blue. `sun_percent` ramp `1−√0.5 / 0.1 / 0.005`; `ef_lamp_light` overhead lamp off once `sun_percent ≥ 1`. Still open: Rover `keitai_talk1`↔`talk2` alternation (we loop `talk1`), Porter mouth-flap during the announce (no `mnk_1` face binding), K.K. blob-shadow tint (`shadow_color 0/30/70`).

## Decomp sources — K.K. opening

| File | Role |
| --- | --- |
| `src/actor/npc/ac_npc_p_sel.c` | Camera lock, strum anim sync, `sAdos_TTKK_ARM` |
| `src/actor/npc/ac_npc_p_sel_schedule.c_inc` | `strum_timer` 440 → talk; post-talk fade 150 / BGM wipe at 80 → `SCENE_START_DEMO` |
| `src/actor/npc/ac_npc_p_sel_talk.c_inc` | First-game msg `0x09C7` / returning `0x09CA`; sound / voice / vibration setup |
| `src/data/field/mvactor/player_select.c` | Spawns `SP_NPC_P_SEL` at FG ut (2, 1) |
| `src/data/scene/player_select.c` | Demo field `FIELD_DRAW_TYPE_PLAYER_SELECT` |
| `src/game/m_bgm.c` `mBGMDemo_make_scene_bgm` | `mFI_FIELD_DEMO_PLAYERSELECT` → BGM 43 (`BGM_INTRO_KK`); STARTDEMO → 42 (`BGM_INTRO_TRAIN`) |
| `include/audio_defs.h` | `BGM_INTRO_TRAIN`, `BGM_INTRO_KK` |
| Model | `end_1` (`npc_draw_data` for `SP_NPC_P_SEL` / `SP_NPC_TOTAKEKE`); clip `npc_1_4haku_e1` @ speed 0.5 after staffroll. **Not** `mka_1` (`SP_NPC_MASK_CAT`). |

Camera (`aNPS_actor_ct`): look (100, 60, 60), eye (100, 130, 210), FOV 40°, near/far 100/400. Godot uses a short near (~0.1 m) — literal 100 GX → 5 m clips the seated mesh. Player actor is invisible. `Na_TTKK_ARM` mutes intro_kk subtracks 0–2 while the arm flag is set. Decomp post-staffroll keeps the flag set; we skip staffroll, so the bed OGG bakes those tracks muted and a synced `intro_kk_arm` stem is unmuted while pose is strum / muted on look-up. During talk, `aNPS_talk_end_chk` `silent_counter`: leave `4haku` → `wait_e1` (look up / stop strum, morph −5); after **600** frames unanswered, order 255 `TALK1` remaps via `default_animation` back to **`4haku`** (morph −3) — not standing `wait1`. Face: `NpcFace` on `end_*` blinks / mouth-flaps while uttering.

Lighting (`l_mEnv_kcolor_data_p_sel`): ambient `(30,30,80)`, sun dir `(0,89,79)` / color `(255,255,200)`, fog color `(100,100,120)` (cleared — `fog_disabled` for this draw type), clear authored `(22,27,94)` but captures read as black void. Acre `grd_player_select_model` = OPA wood floor; `modelT` = XLU spot `(PRIM−ENV)×I+ENV` env `(255,255,130)` lod 150 (GC also scrolls `rom_open_spot2` via EVW — we bake the cone only) + black shade curtain `RGB=PRIM A=I`. Guitar is furniture `int_sum_guitar01` parented to `chest_end_model` (not a hand TOOL — Totakeke’s prop is not in the NPC draw table). Face: `end_1` has normal eye/mouth/tmem banks (`end_1_eye*_TA_tex_txt`, `end_1_mouth*_TA_tex_txt`, `end_1_tmem_txt`) bound to anime segments like other special NPCs.

## Decomp sources — train

| File | Role |
| --- | --- |
| `src/actor/npc/ac_npc_guide.c` / `ac_npc_guide_move.c_inc` | New-town Rover on the train (`SP_NPC_GUIDE`) |
| `src/actor/npc/ac_npc_sleep_obaba.c` | Sleeping passenger behind Rover (`SP_NPC_SLEEP_OBABA`) |
| `src/actor/npc/ac_npc_guide_animation.c_inc` | Action → `aNPC_ANIM_*` clip table |
| `src/actor/ac_train_door.c` / `ac_train_window.c` | Door open flag + window scroll (`rom_train_out`) |
| `src/game/m_kankyo.c` `mEnv_CalcSetLight_train` | Tunnel ambient lift `(35,30,40)×(1−sun_percent)` |
| `src/effect/ef_lamp_light.c` | Overhead lamp off while `sunlight_flag` |
| `src/actor/ac_intro_demo*.c*` | Post-arrival station → Porter → Nook house pick |
| `src/actor/npc/ac_npc_rcn_guide*.c*` | Tom Nook guide after the train |
| `include/m_private.h` / `m_player_lib` | `gender`, `face` (`mPr_FACE_TYPE_NUM` = 8) |
| `m_ledit_ovl` / `m_timeIn_ovl` | Name and clock submenus on the train |

Key Rover actions (`aNGD_ACTION_*`): enter → approach → talk → clock check → sit → player name → sex select → town name → standup → aisle/door/deck → phone (`keitai`) to Nook → return → last talk → scene change.

Clips (`aNGD_set_animation`): `OPEN_D1`, `WALK1`, `WAIT1`, `SITDOWN_D1`, `SITDOWN_WAIT_D1`, `STANDUP_D1`, `TO_DECK_D1`, `KEITAI_ON1` / `TALK1` / `OFF1`, `OPEN_D2`. Pipeline short names: `npc_1_*`.

GX landmarks: Rover enter actor z≈130 (`open_d1` skeleton root motion starts ~48 GX on the deck); aisle/door stop z≈130; door actor z≈120; talk z≈290; sit (100, 280); camera eye ~(100,52,400), look ~(90,34,280) for seated POV (decomp literals Y=80); FOV 40°; near/far 60/800. **`rom_train_in`** = 16× acre BG DLs (`Matrix_scale(0.0625)` → `acre_uniform_scale()`). **`rom_train_out`** = raw GX (`Matrix_scale(0.05)` → `train_window_uniform_scale()`).

Camera (`aNGD_set_camera`): after first talk morph completes, `lock_camera_flag` stays true for the rest of the demo — look follows Rover’s shadow through standup → aisle → door → phone → return (never remorphs to the default aisle center). When Rover’s shadow `z < 140` during `MOVE_TO_DOOR`, `camera_tilt_goal = 90°` / add `2.8125°` shifts the eye (`sin*20` X, `sin*-5` Y) toward the vestibule; `OPEN_DOOR` frame 22 clears tilt (`add = 0x600` ≈ 8.4375°) if still near the door.

Face bits (`aNGD_check_talk_msg_no` / `aNGD_set_pl_face_type`): messages `0x2AC9` / `0x2ACD` / `0x2ACF` / `0x2AD3` OR bits 3..0 into `answer_flags`. If bit 0 is clear (money = “plenty”), face is random; else `face_type_table[gender][answer_flags >> 1]`.

## What does the original system do?

Boot / first-game path lands on **player select**: K.K. strums for ~440 frames, then talks (welcome + optional sound/voice/rumble setup). After talk he strums again while the screen fades (~150 frames; BGM wipe at 80) into the **train demo**. Rover walks up, confirms the system clock, sits, asks for a name, infers gender from “cool / cute” (with a confirmation), asks for a town name, then asks attitude questions that secretly pick one of eight faces. He steps into the aisle, phones Nook about a house, comes back for a farewell, then the game wipes into the outdoor intro (`ac_intro_demo`).

## Reproduce (this milestone)

- Title **Intro Sequence** → `intro_kk.tscn` → `intro_train.tscn`.
- K.K. acre `grd_player_select` + `end_1` playing `npc_1_4haku_e1` @ 0.5; camera lock as above; BGM `intro_kk`.
- Void lighting: black clear (captures; decomp bg unused with fog off); fog stays off (`fog_disabled`). XLU baked spot cone / shade; acoustic guitar on chest; dialogue speaker `K.K.`.
- Acre textures stay native `rom_open_*` (ACHD is a near-identical upscale of the tiny tiles).
- Face/body from `end_1_*` banks (+ ACHD when enabled). `mka_1` is Mask Cat — do not use it for this scene.
- Strum wait → talk (`wait_e1` look-up; resume `4haku` after ~10 s idle) → paraphrased dialogue (`kk_opening.json`, decomp msg `0x09C7` flow) → fade + BGM stop → train.
- Skip full sound/voice/vibration menus (decomp `aNPS_setup_*`); welcome + proceed is enough.
- Train act: 3D stage with pipeline GLBs: `rom_train_in`, `rom_train_out`, `obj_romtrain_door`, Rover=`xct_1`, sleep passenger=`kab_1`, phone=`tol_keitai_1`; BGM `intro_train`.
- Dialogue `manpu` cues (`gaaan` / `hirameki` / `smile` / …) play shared `npc_1_*` clips baked into `xct_1` (`INTRO_ROVER_NPC_ANIMS`) plus feel glyphs (`ef_shock01_00` burst, `ef_hirameki01_den`/`_hikari` lightbulb).
- Vestibule door actor origin z≈120; `place_train_door_at_gateway` fits against `rom_train_in` jambs then recesses `DOOR_PANEL_Z_BIAS_GX` (−20 GX) toward the deck.
- `IntroTrainStage` plays decomp clips and GX camera / walk path; dialogue cues `rover_sit` / `rover_phone` / `rover_phone_done` / `rover_return`. Phone-done waits for `KEITAI_TALK` then chains `KEITAI_OFF` → `OPEN_D2` → return walk → standing “I’m back” → `sitdown2` (`rover_return` / `return_seated`) → farewell seated (decomp `LAST_TALK` / `SITDOWN2`), not an immediate `OPEN_DOOR` skip mid-walk.
- **Window scenery** (`ac_train_window` / `rom_train_out`, `scenes/ui/intro_train_car.gd`): tree strip (`bgtree_modelT`, 128×32) always scrolls +5 texels/frame from `TreeScrollx = 500`; cloud tile (`bgcloud_modelT`, 64×64) always drifts +2 texels/frame in V (`aTrainWindow_out_cloud {0,-2}` EVW). In the tunnel the **tunnel wall** (`tunnel_model`) is opaque and occludes the panes; on `sunlight_flag` (Rover seated) it becomes an alpha layer (`DEPTH_DRAW_DISABLED`, `render_priority = -1`) whose alpha fades 1→0 as the exit scroll runs — an opaque mesh can never reveal the scenery no matter how far its texture scrolls. The tunnel/sky (seg 11) + cloud U scroll +15 texels/frame (`OperateScrollLimit` halves the +30) to `xend = 1000` then freeze (`DrawGoingOutTunnel` → `DrawGoneOutTunnel`); the sky stays an opaque backdrop. Every window surface is prim-tinted each frame by `clamp(ambient + sun_color)` from `Clock.outdoor_light()` (`aTrainWindow_SetLightPrimColorDetail`); the tree adds the `(-80,-70,-160)` offset. XLU elements (cloud, tree) also take `xlu_alpha`, eased from 254 toward the `aTW_GetNowAlpha()` day curve (0 at 04:00 / 20:00, 255 at noon, ~100 at midnight) at `add_calc` rate 0.07. Door cKF plays once at 0.5× on `open_flag` (`ac_train_door`); SE at frames 2 / 27 not modelled. Still approximate: the 15 date-indexed `aTrainWindow_tree_pal_table` CI palettes (seasonal foliage) — we tint rather than palette-swap; `lod_factor` shineglass curve is a daylight snap.

**Voices.** The intro NPCs speak **animalese** at `sound_spec 2` (`l_sp_actor_name` in `m_npc.c`: `SP_NPC_GUIDE` / `SP_NPC_RCN_GUIDE` / `SP_NPC_STATION_MASTER` / `SP_NPC_P_SEL` all id 2). `DialogueContext.from_game()` defaults `voice_mode` to CLICK when there is no `VillagerData`, so each intro scene calls `ctx.speak_as_special(&"rover" | &"tom_nook" | &"porter" | &"kk_slider")` — animalese + spec 2 + nameplate sex (`mPr_SEX_MALE` for Rover/Nook/Porter, `mPr_SEX_OTHER` for K.K.). Needs the `--kind audio` voice OGGs; without them the utter is silent.
- Entrance face: `npc_1_open_d1` eye_seq is normal blinks (`eye0..2`); mouth_seq holds `mouth3` for most of the clip — not angry `eye3`.
- Clock confirm → snap to seat + `npc_1_sitdown_d1` (no pre-walk; anim carries motion). When sitdown finishes (`aNGD_sitdown`), set `sunlight_flag`: window draw → GoingOutTunnel, `ef_lamp_light` off, `sun_percent` lerps 0→1 (`add_calc` 1−√0.5 / 0.1 / 0.005) and clears the tunnel ambient lift.
- Car glass is `rom_train_in_modelT` XLU with ENV `(100,230,255)`; I4 → texture alpha (`I×PRIM`). Do not force a mid color-alpha body. `rom_train_out` shares the car's Y snap (decomp translate 0). Shineglass α is `T0×T1×PRIM_LOD_FRAC` — convert clears PNG alpha when the combiner scales A by `PRIM_LOD_FRAC` (invisible until a future lod restore).
- Background sleep NPC at FG ut (4,4), birth offset x−6/z−24 → (174, 156).
- Persist `player_name`, `town_name`, `player_gender`, `player_face` into the session and start a generated new game.
- Paraphrased dialogue JSON (no bank text).

## Assets

Generated meshes are gitignored. Locally:

```bash
python3 tools/build_assets.py --step convert
python3 tools/build_assets.py --kind audio --step convert
```

Needs `end_1.glb`, `grd_player_select.glb`, and BGM `intro_kk` / `intro_train` in the audio test set. Test-set convert bakes `wait1` (bind) + `npc_1_4haku_e1` + `npc_1_wait_e1` into `end_1` via `INTRO_KK_NPC_ANIMS` (same pattern as Rover’s `INTRO_ROVER_NPC_ANIMS`). Omitting `wait1` makes seated clips bake with `ckf_basis` and lie sideways. Without GLBs the KK scene shows a banner and still advances. Without audio files, BGM is silence.

## Simplify

- Name and clock are small intro modals, not `m_ledit` / `m_timeIn` ports.
- Window UV scroll (`ac_train_window`): tree strip always scrolls (+5). On sitdown `sunlight_flag`, `DrawGoingOutTunnel` scrolls tunnel+sky (seg 11) and clouds toward xend 1000 (+30, `OperateScrollLimit` → 15 texels/frame); then `DrawGoneOutTunnel` freezes exit scroll while trees keep moving.
- Skip returning-player / mask-cat Blanca path.
- Skip K.K. sound/voice/rumble setup menus and staffroll frame sync (strum at constant 0.5×). Guitar uses bed + `intro_kk_arm` stem; mute arm on look-up (`Audio.set_ttkk_arm`).
- Skip `SCENE_PLAYERSELECT_2` / `SP_NPC_P_SEL2` load path.

## Ignore (later slices)

- Full acre-to-acre house tour / wade lock after Nook’s greeting (`aNRG` STOP_WADE, restart plots). Station slice covers explain → enter → debt → job on the station acre.
- Ongoing villager deliveries / “can I help” errands / contest letters after first job ends (`m_quest` non–first-job types).
- Title demos (`m_titledemo`), staff roll, multi-player slot select.
- Animal Crossing logo actor (`ac_animal_logo`) / trademark Nintendo splash.
- Returning-player / mask-cat Blanca path; `SCENE_PLAYERSELECT_2`.

## Station arrival (this milestone)

**Read:** `ac_intro_demo` / `ac_intro_demo_move`, `m_train_control` (`train_coming_flag = 3` → `mTRC_demo_init`), `ac_train0` / `ac_train1`, `ac_npc_station_master`, `ac_npc_rcn_guide`, engineer spawn `SP_NPC_ENGINEER`.

### Flow

1. Field BGM wipe → `BGM_INTRO_ARRIVE`; player forced on caboose (`TRAIN1.arg0`).
2. Locomotive `obj_train1_1` + caboose `obj_train1_3` roll in from the west (demo start x≈2037, z=740); monkey engineer parented to the loco (`mnk_1`).
3. Slow to a stop past x≈2165; caboose door opens (`obj_train1_3_open`); Porter (`mnk_1` at station unit 5,4) force-talks msg `0x07DD` (`msg_2013`, fallback `porter_arrive`) with **`CAMERA2_PROCESS_NORMAL`** (no talk-angle nudge).
4. Player gets free control (`wait_type3` / `Camera2_request_main_normal`) and walks south past the station mouth (`aID_OUT_OF_STATION_Z_POS`).
5. Spawn Tom Nook (`rcn_1`) at unit (8,15); force-talk `0x07DE` (**NORMAL**) then `0x07DF` (**TALK** / `GetAngleY`) (`msg_2014` / `msg_2015`, laugh → `msg_2016`).
6. Nook leads to vacant plots (`aNRG` TAKE_WITH → EXPLAIN, `0x07E1` / `msg_2017`, **TALK**); player picks a house → Nook `0x07E4` / `msg_2020` (**NORMAL**, turn off) → enter. Outdoor Nook is deleted with the field while indoors (`aNRG` THINK_WAIT).
7. On outdoor return, intro demo `aID_birth_rcn_guide` respawns Nook at the claimed house unit (`restart_ux/uz` + ofsX ±10 / ofsZ +8) before/while the player emerges; `aNRG_restart_wait` holds until GO_OUT ends, then force-talk debt/job `0x07E6` (`msg_2022` → … → `msg_2028`, **TALK**). Authored `nook_*` JSON is the no-bank fallback only.
8. After talk: `aNRG` EXIT_TURN → EXIT (run to east leave points) → `Actor_delete`. Intro waits in `aID_retire_rcn_guide_wait` until `rcn_guide_actor_p == NULL`, then unlocks play / first job (`Game.complete_intro_station` → `FirstJob.begin_after_house`).

### First job (shop / uniform) — this milestone

**Read:** `ac_npc_rcn_guide2*` (`SP_NPC_RCN_GUIDE2` replaces shop-master talk during chores), `mQst_SetFirstJob*`, `aQMgr_move_own_errand_cloth` / `_seed`, `mEv_CheckFirstJob`.

#### Flow

1. After Nook EXIT, errand = `FIRSTJOB_START`; free walk. Shop is force-open (`mSP_ShopOpen` + `CheckFirstJob`).
2. Enter Cranny → force-talk `0x07EE` / `msg_2030` (“finally you arrive”) then `0x07F1` / `msg_2033` (hand uniform `ITM_CLOTH016`) → quest `CHANGE_CLOTH` progress 2. Authored fallbacks: `nook_job_*`.
3. Player opens pockets → **Wear** uniform (swap with worn cloth). Quest manager sets progress 0 when `cloth.item == ITM_CLOTH016`.
4. Talk again → `0x07F4` / `msg_2036` → assign plant job (`PLANT_FLOWER`), give 7 flower bags + 3 saplings (`msg_2038`).
5. After plants are gone from pockets, talk → plant done → introductions (meet all + Tortimer) if needed → furniture delivery (QUEST item + town map) → letter → OPEN (talk to a villager) → carpet → axe → notice board → all-job end.

#### Godot

- `FirstJob` on `Game` (not an autoload). `cloth_id` is the worn shirt; `GeneratedVisual.apply_cloth` on the player. `has_map` gates the map overlay until furniture delivery.
- `TomNook` branches on `FirstJob` (force-greet on enter, no Buy/Sell while active); advances the full chore chain.
- **Named recipients:** furniture / letter / carpet / axe assign + hint graphs (`FirstJob.recipient_dialogue_ids`) must include `{recipient}`. `DialogueContext.from_game` fills the slot from the active first job; `substitute` errors on empty/leftover slots for every conversation. Unit tests cover the id list and all authored `{slot}` expansions.
- Item gifts use `HandOver` (`npc_1_transfer1` / player `ply_1_get_pull1`) plus the floating `obj_item_*` card (`HandOverItem` / `ac_handOverItem` trans+scale tables); villager deliveries reverse it (`ply_1_transfer1` / `npc_1_get_pull1`).
- Inventory tag **Wear** for `Category.CLOTH`; delivery goods use `Condition.QUEST`.
- Villager talk accepts QUEST deliveries / OPEN; post office mailing finishes letter chores; field signs post the notice; Tortimer at the wishing well (`fd_npc_land` ut 10,10 / `SP_NPC_SONCHO`).
- Bank ids preferred (`msg_2030`…); authored `nook_job_*.json` when banks are missing.

### Godot (station)

- Title **Station Arrival** → `Game.start_intro_station()` → generated `world.tscn` + `IntroStationDirector` + `IntroStationStage`.
- Train: loco `obj_train1_1` + mid `obj_train1_2` + passenger `obj_train1_3`, all yaw 0 (anim-bind + `ckf_basis` → long on +X). Mid at loco−125, passenger at loco−250. `prepare_outdoor_train` keeps skinning, stops autoplay, strips `joint_0` tracks so door/wheel clips cannot move the root, and snaps caboose doors closed (`obj_train1_3_open` @ frame 1 — `*_close` frame 1 is open; the 32-frame close clip ends closed). Stage plays loco `obj_train1_1` (wheel/rod loop) during approach with speed `(train_speed/40)*10` capped at 0.5 (`aTR0_actor_move`); on stop plays `obj_train1_3_open` @ 0.5 (`mTRC_ACTION_SIGNAL_STOPPED`). Player rides/exits the passenger car facing yaw 0. Porter/engineer use `mnk_1` GLBs directly (not `mesh_paths`).
- Station / house landmarks come from the town layout (`Buildings/station`, `player_house*`). Stage GX is relative to the station acre block origin; `set_landmarks` runs **after** `bind` so vacant-plot GX is not wiped.
- Platform actors sit at count-8 height (40 GX); tracks at count-6 (20 GX). Arrive camera: doorway look, dist 620, FOV 20°.
- **Get off** (`mPlayer_INDEX_DEMO_GETOFF_TRAIN`): the stage hands the real player actor `begin_demo_getoff_train`, which runs `OUTTRAIN1` at **0.5×** (`Player_actor_InitAnimation_Base2 … 0.5f`) with its own AnimationMove / captured `joint_0` root motion — the old scripted smoothstep lerp slid the body along a path that ignored the clip's step-down. The debug acre keeps the lerp (no player actor).
- After Porter, free walk until past the station; then Nook → **guided** walk to the vacant house **porches** (`StructureDoor.approach_position`). The player follow (`aID_walk_after_rcn_guide`) runs **per render frame** through `PlayerLocomotion` (eases walk↔run, no per-30 Hz-tick hop / anim flap); when Nook stops (`rcn_guide->action.idx == 0` → `mPlib_request_main_wait_type3`) the player stops **immediately** wherever it is and drops to `wait1`. Then house pick → `msg_2020` → interior → outdoor return places Nook at the door **before** emerge, restarts `intro_rcn_guide`, debt/job talk after GO_OUT, then Nook turns and runs off before the director tears down.
- Force-talk cameras follow `aSTM` / `aNRG` tables: Porter + first Nook call stay on follow/`NORMAL`; Rover-call, show-houses, and debt/job request `TalkCamera` (`CAMERA2_PROCESS_TALK` / `GetAngleY`). House-look (`0x07E4`) stays NORMAL with turn off.
- Debug acre scene `scenes/ui/intro_station.tscn` remains for isolated checks; play path is the generated world.
- BGM chain (`IntroStationDirector._play_bgm_chain`, each step falls back to the prior track when its OGG is missing):
  `intro_arrive` on the train pull-in → **fades** on `nook_birth` / `nook_call` (decomp `aSTM_talk_wait` drops `BGM_INTRO_ARRIVE` at player z ≥ 970) → `intro_select_house2` for the walk to the plots + the pick → `intro_rcn_guide` on the outdoor return for the loan / part-time-job talk (`ac_intro_demo` `_1A4` path) → `intro_find_shop` when Nook leaves (`aID_set_first_field_bgm`). Pipeline test set now renders `intro_select_house2` / `intro_rcn_guide` / `intro_find_shop`.

```bash
python3 tools/build_assets.py --kind audio --step convert   # intro_arrive
python3 tools/build_assets.py --kind dialogue --step convert  # msg_* + select.json
python3 tools/build_assets.py --step convert                 # outtrain clip on boy_1 when listed
# Rebake outdoor trains (structure pal):
PYTHONPATH=tools python3 -c "from pathlib import Path; from asset_pipeline.config import load_config; from asset_pipeline.convert import convert_ckf_prefixes; c=load_config(Path('.')); convert_ckf_prefixes(c,['obj_train1_1','obj_train1_3'])"
```
