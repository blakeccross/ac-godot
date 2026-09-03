# Intro (Rover train character creation)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not commit Nintendo message banks or train meshes.

**Read before implementing:** `IntroSequence`, `IntroTrainStage`, train intro scene, title → intro hook.

## Decomp sources

| File | Role |
| --- | --- |
| `src/actor/npc/ac_npc_guide.c` / `ac_npc_guide_move.c_inc` | New-town Rover on the train (`SP_NPC_GUIDE`) |
| `src/actor/npc/ac_npc_sleep_obaba.c` | Sleeping passenger behind Rover (`SP_NPC_SLEEP_OBABA`) |
| `src/actor/npc/ac_npc_guide_animation.c_inc` | Action → `aNPC_ANIM_*` clip table |
| `src/actor/ac_train_door.c` / `ac_train_window.c` | Door open flag + window scroll (`rom_train_out`) |
| `src/actor/ac_intro_demo*.c*` | Post-arrival station → Porter → Nook house pick |
| `src/actor/npc/ac_npc_rcn_guide*.c*` | Tom Nook guide after the train |
| `include/m_private.h` / `m_player_lib` | `gender`, `face` (`mPr_FACE_TYPE_NUM` = 8) |
| `m_ledit_ovl` / `m_timeIn_ovl` | Name and clock submenus on the train |

Key Rover actions (`aNGD_ACTION_*`): enter → approach → talk → clock check → sit → player name → sex select → town name → standup → aisle/door/deck → phone (`keitai`) to Nook → return → last talk → scene change.

Clips (`aNGD_set_animation`): `OPEN_D1`, `WALK1`, `WAIT1`, `SITDOWN_D1`, `SITDOWN_WAIT_D1`, `STANDUP_D1`, `TO_DECK_D1`, `KEITAI_ON1` / `TALK1` / `OFF1`, `OPEN_D2`. Pipeline short names: `npc_1_*`.

GX landmarks: Rover enter actor z≈130 (`open_d1` skeleton root motion starts ~48 GX on the deck); aisle/door stop z≈130; door actor z≈120; talk z≈290; sit (100, 280); camera eye ~(100,52,400), look ~(90,34,280) for seated POV (decomp literals Y=80); FOV 40°; near/far 60/800. **`rom_train_in`** = 16× acre BG DLs (`Matrix_scale(0.0625)` → `acre_uniform_scale()`). **`rom_train_out`** = raw GX (`Matrix_scale(0.05)` → `train_window_uniform_scale()`).

Face bits (`aNGD_check_talk_msg_no` / `aNGD_set_pl_face_type`): messages `0x2AC9` / `0x2ACD` / `0x2ACF` / `0x2AD3` OR bits 3..0 into `answer_flags`. If bit 0 is clear (money = “plenty”), face is random; else `face_type_table[gender][answer_flags >> 1]`.

## What does the original system do?

Starting a **new town** drops the player into a train demo. Rover walks up, confirms the system clock, sits, asks for a name, infers gender from “cool / cute” (with a confirmation), asks for a town name, then asks attitude questions that secretly pick one of eight faces. He steps into the aisle, phones Nook about a house, comes back for a farewell, then the game wipes into the outdoor intro (`ac_intro_demo`).

## Reproduce (this milestone)

- Title menu entry that runs the **train act only**.
- 3D stage with pipeline GLBs: `rom_train_in`, `rom_train_out`, `obj_romtrain_door`, Rover=`xct_1`, sleep passenger=`kab_1`, phone=`tol_keitai_1`.
- Vestibule door actor origin z≈120; `place_train_door_at_gateway` fits against `rom_train_in` jambs then recesses `DOOR_PANEL_Z_BIAS_GX` (−20 GX) toward the deck.
- `IntroTrainStage` plays decomp clips and GX camera / walk path; dialogue cues `rover_sit` / `rover_phone` / `rover_phone_done` / `rover_return`. Phone-done waits for `KEITAI_TALK` then chains `KEITAI_OFF` → `OPEN_D2` → return walk → standing talk (decomp `LAST_TALK`), not an immediate `OPEN_DOOR` skip mid-walk.
- Clock confirm → snap to seat + `npc_1_sitdown_d1` (no pre-walk; anim carries motion). Daylight when sitdown finishes.
- Background sleep NPC at FG ut (4,4), birth offset x−6/z−24 → (174, 156). `aNPC_COND_DEMO_SKIP_ENTRANCE_CHECK` only skips the house-entrance probe (`aNPC_entranceCheck`); it does **not** skip the `think_in_block` walk. On the visible train frame the sleeper is still at the birth offset. Body yaw is `aNPC_act_search_turn` toward the player (`aNSO_set_request_act`), not raw appear-0 π — pipeline `kab_1` + `kokkuri` frame 0 reads correctly with `yaw_toward_player`. Bench align uses posed world min-Y on the floor datum (rest AABB snap to ~40 GX cushion floated Kab).
- Dialogue overlay draws `con_kaiwa2` / `con_kaiwaname` as an SDF cloud at the `mMsg_init` rect (center 160/185.4, 245×96) with the decomp tints; the turn mark follows `mMsg_Set_display_button_turn_color`'s 60-frame alpha triangle wave. See `MessageWindowChrome`.
- Rover blinks and flaps his mouth by eye/mouth **texture swap**, not geometry (`aNPC_tex_anm_ctrl`). Villager model DLs use `GX_MIRROR` on S for `anime_1_txt` / `anime_2_txt`; `NpcFace` expands 32×16 REL frames to match the GLB quad (64×16 mirror bake or ACHD 256×128). Frames come from `--kind faces`: `face_{species}.bin` when present plus all REL villager prefixes discovered under `converted/textures/rel/` (`discover_villager_prefixes` in `faces.py`). Without PNGs, `NpcFace` synthesizes blink/talk frames from the villager GLB's baked `seg_08` / `seg_09` quads.
- Intro dialogue `manpu` events (`aNPC_check_manpu_demoCode` / `DEMONPC0` slot 0) play reaction clips (`npc_1_smile1` standing, `smile_d1` seated, …), set a matching face hold (laugh eyes + open mouth for smile), and spawn floating feel glyphs (`eEC_EFFECT_WARAU` HA-HA cards, `SHOCK`, `HA`) via `NpcFeelGlyphs` + pipeline `effects/ef_warau01_*.glb`. Entrance `open_d1` parks on angry/stern eyes (`eye3`) until approach/talk. Face frame swaps mirror-expand 32×16 halves onto ACHD 512×128 `seg_08`/`seg_09` quads (`GX_MIRROR`).
- Interior light is `mEnv_GetNowRoomPointLightInfo`'s single point light for `FIELD_DRAW_TYPE_TRAIN` — GX (80, 120, 510), colour (255, 255, 160), power 1200 — with `sun_percent` pinned to 0. `mEnv_CalcSetLight_train` lifts ambient by (35, 30, 40) until `sunlight_flag`. No ceiling array, no sun, and OPA surfaces get no albedo lift, emission or specular.
- Rover head tracks camera `(100, eye_y, 400)` during approach/return (`camera_eyes_flag`) on `joint_21` via decomp Euler override; not during `open_d1`.
- Clock confirm / edit → name → gender → town → face questions → phone → farewell.
- Face selection matching the decomp bit table (and random when the money answer clears bit 0).
- Persist `player_name`, `town_name`, `player_gender`, `player_face` into the session and start a generated new game.
- Paraphrased dialogue JSON (no bank text).

## Assets

Generated meshes are gitignored. Locally:

```bash
python3 tools/build_assets.py --step convert
```

Without GLBs the scene shows a banner and still runs dialogue so the title entry stays testable.

## Simplify

- Name and clock are small intro modals, not `m_ledit` / `m_timeIn` ports.
- Keitai is offset-parented to Rover (not true hand-joint bind).
- Window UV scroll (`ac_train_window`): tree strip always scrolls; cloud UVs ramp on daylight (`GoingOutTunnel`).
- Skip returning-player / mask-cat Blanca path.

## Ignore (later slices)

- Station arrival, Porter (`SP_NPC_STATION_MASTER`), Raccoon guide house pick, first-job quests (`mQst_SetFirstJobStart`).
- Title demos (`m_titledemo`), staff roll, multi-player slot select.
