# Fishing

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not copy fish name enums into shipped data as Nintendo species lists.

**Read before implementing:** `FishData`, rod tool, water tiles.

## Decomp sources

| File | Role |
| --- | --- |
| `include/ac_gyoei.h`, `src/actor/ac_gyoei.c` plus `ac_gyoei_*.c_inc` | Fish shadows / catchable actors |
| `include/ac_uki.h` | Bobber (uki) status: carry → ready → cast → float → vib → catch |
| `include/m_player.h` | `READY_ROD`, `CAST_ROD`, `RELAX_ROD`, `VIB_ROD`, `COLLECT_ROD`, … |
| `include/m_player_lib.h` | `mPlib_request_main_release_creature_gyoei_from_submenu` |
| `include/m_fishrecord.h` | Tourney size records |
| `include/m_common_data.h` | `gyoei_term` + transition offset |
| `include/m_name_table.h` | `ITM_FISH_START` 0x2300, `ITEM_IS_FISH` |
| `src/actor/ac_set_ovl_gyoei.c` | Spawn overlay |

Constants: `aGYO_MAX_GYOEI` **2** simultaneous shadows, `aGYO_EXIST_MAX` **4** tracked. Sizes `XXS`–`WHALE`. Trash: empty can, boot, old tire (`aGYO_IS_FISH_TRASH`). Golden vs normal rod (`aGYO_ROD_*`).

## What does the original system do?

Water units (river/pond/sea attributes) can spawn **shadows** (`GYOEI_ACTOR` controllers). At most two are active. Species depend on **fish term** (saved `gyoei_term`, aligned with calendar terms with a transition offset), location (river vs sea), and hour.

The player equips a rod → ready → cast. The **uki** (bobber) actor flies on a parabola, floats, then **vibrates** on a bite. The player must collect (hook) during the window or the fish escapes. Success yields a fish item (or trash, or rare whale demo). Catch goes to pockets or is released from the submenu.

BGM ducks (`mPlayer_BGM_VOLUME_MODE_FISHING`). Fishing tourneys (`m_event` / `m_fishrecord`) compare sizes (`mFR_fish_rndsize`) and mail results.

Museum fish rooms and “place fish as furniture” (`aFTR_INTERACTION_FISH`) are separate from the catch loop.

## Important states

- Rod player index (ready / cast / float / vib / collect / put away).
- Uki status (`aUKI_STATUS_*`).
- Shadow exist flags, species, size, swim vs escape.
- `gyoei_term` for spawn tables.
- Inventory full vs catch-and-release.

## Inputs

- Equip rod; A to cast / hook; B to put away.
- Water collision under the bobber.
- Calendar term and hour.
- Golden rod flag (higher-tier fish; can wait).

## Outputs / events

- Pocket item (fish or trash).
- Collection / museum bit.
- Escape (no item).
- Tourney record (ignore at first).
- Release back into water from inventory.

## Interacts with

- **World** — water attributes, not grass.
- **Player / interaction**.
- **Inventory**.
- **Time** — spawn tables.
- **Shops** — sell fish; Cranny unlocks rod after sales sum (`mSP_ROD_SALES_SUM` 8000).
- **Audio** — BGM duck, splash, bite.

## Shadow behaviour (`ac_gyo_test.c`)

The shadow is not a creature simulation. `aGTT_setupAction` drives seven actions:

| Action | Behaviour |
| --- | --- |
| `WAIT` | Hold station facing upstream for `(100 + rand 30) * 2` ticks, drifting backwards at `-0.15 ± 0.1` GX/frame |
| `SWIM` | One of three `swim_flag` patterns, each a sine speed envelope over a sweep advancing 2.5° a tick |
| `NEAR` | Turn onto the bobber and close at `aGTT_speed[size]` |
| `TOUCH` | The nibble loop: back off at `aGTT_back_speed[size]`, return, and on each approach either commit (1 in 4) or nibble again. `touch_counter` is 5, so the fifth approach is forced |
| `BITE` | Hold the bobber for `aGYO_bite_time[rod][species] * 2` ticks, sitting `hosei[size]` behind it, then vanish in a puff |
| `COMEBACK` | Pinned to the bobber while the rod lifts it out |
| `ESCAPE` | Bolt at `2.0` GX/frame for 100 ticks, easing off by `0.02` a tick |

Detection is `aGTT_search_Uki`: inside `aGYO_search_area[rod][species]` **and** inside the `aGYO_search_angle` cone, which is 3° for a fussy species and 180° for an eager one. `aGTT_player_near` only flees a **dashing** player (110 GX) or a swung axe / net / scoop (150 GX) — walking to the bank is safe. A cast landing within 17 GX (small) or 22 GX (large) scares the fish instead of interesting it.

Shadows ride `mCoBG_GetWaterHeight - 8.0` GX under the surface. Animation is a 20-entry table stepped every two frames (`fwork0` runs 19 → 0 at 0.5/frame, wrapping by +19): `aGYO_2tile_texture_idx` picks two of four tiles and `aGYO_prim_f` cross-fades them as the *LOD fraction*, which is the tail sway. `dec_step` is `0.0` for `WHALE`, so a whale's shadow is frozen. A scared fish leaves a `GYO_KAGE_ACTOR` puff that coasts and fades over 100 frames with alpha `(timer * 0.5 - 10) * 6`.

The dwell tables are authored in 30 Hz frames and every site that loads one into a counter doubles it; the escape / puff timers are already in 60 Hz ticks. Speeds are GX per 30 fps frame: the mover runs every tick but `Actor_position_move` adds only `0.5 * speed`, so 1.0 is 30 GX a second.

## Behavior

`Fishing` (session: the bobber's clock and the reel), `FishCatalog` (`data/creatures/*.tres`) and `FishSpawnScheduler` (see Spawning), `FishSize` (the per-size tables above), `FishShadow` (the action machine), `FishSchool` (two shadows, per-tick stepping, puffs, spawn and cull), `WaterBodies` (flood-filled water), `scenes/world/bobber.tscn` and `scenes/world/fish_shadows.gd` + `shaders/fish_shadow.gdshader`.

All forty species are on the shelf, one `.tres` each, transcribed rather than invented. `gyoei_type[]` gives size, `search_area` and `bite_time` per type. `ac_gyoei_model.c_inc`'s `aGYO_displayList` pairs an `aGYO_TYPE_*` index with its `act_fNN_<romaji>` art — the only mapping between the two naming schemes. Availability comes from `ac_set_ovl_gyoei.c`, a four-level table: `r_month` / `s_month` / `p_month` (river, sea, pond) → month → month-half → one of four time-of-day slots → a list of `FISH_SPAWN(type, area, weight)`.

`FishData` carries `time_slots` rather than an hour range because the original has none either — `aSOG_gyoei_time_no` buckets the clock into 9pm–4am, 4am–9am, 9am–4pm and 4pm–9pm and indexes with it, so a fish is in or out of a whole slot (the piranha holds midday and the small hours; cherry salmon, char, and rainbow trout hold dawn and dusk with the day cut out between them). `waters` exists because the three tables are separate — without it a red snapper would bite in the river. The coelacanth spawns via `needs_rain` gating it to rain-only sea catches, matching `aSOG_add_kaseki_range_data`.

The bite is not a timer: a shadow finds the bobber in its cone, nibbles, and commits, so the bobber dips a few times before it goes under and the catch is whichever fish bit. The species is fixed when a shadow spawns. The rod's `cast` verb opens the session; once the bobber is floating the verb becomes `hook`, with no player animation so the strike lands on the press. What comes up is decided by the bobber over the next ticks (see the behaviour audit below). Full pockets refuse the catch, and walking past `LEASH_METERS` drops the line.

The cast's reach is fixed: `Player_actor_request_proc_index_fromReady_rod` measures `sin_s(rot) * 100.0f` along the player's facing (100 GX = 5 m, two and a half cells) — you aim by turning, there is no charge-up. The same routine gates whether the cast happens at all by probing the landing spot plus four corners at ±10 GX and requiring water under every one, so `FieldRequire.WATER` means "water where the rod lands," not "water in the next cell." The bobber leaves the rod during the swing, not after: `ready_rod` requests `cast_rod` at animation frame 10, and the uki gets its command on `cast_rod`'s first frame, so the line is airborne a third of the way through the swing. `Interaction.effect_frame` carries that frame (decomp frame / 30 = clip time) and `player.gd` applies the cast there, then waits out the tail; every other tool's effect still lands when its clip ends. Flight is `frame_timer = 50` mover frames, so `CAST_SECONDS` is 50/60 s, and `LEASH_METERS` is defined as an offset from `CAST_METERS`.

Shadow art is an SDF in the shader — a tapered capsule bent by the `aGYO_prim_f` curve — reproducing the four `act_gyoei02_*_int_i4` tiles without converting the original art. The bobber is the real `tol_uki1_model` from the pipeline, attached to the `Float` pivot under `bobber.tscn`; the model is authored upside down (`aUKI_actor_draw` starts from a 180° flip), so `bobber.gd`'s pitch targets are offsets from that rest pose, and `GeneratedVisual`'s ground-fit is undone after attach since the authored origin is the waterline. `bobber.gd` reproduces the tilt directly: flat (`+90°`) through the cast, easing upright (`0°`) once it settles, yanked to `-90°` on a bite, stepped on a fixed 30 Hz accumulator like the original's `add_calc_short_angle2`.

**Reel-in.** The original spends one player state per beat — `vib_rod` (`TURI_HIKI1`), `fly_rod` (`GET_T1`), `collect_rod` (`NOT_GET_T1` for reeling in nothing), `notice_rod` (`GET_T2`, holds the catch up). `vib_rod` lasts as long as the bobber's fight (`Fishing.is_reeling`), and `player.gd` loops `TURI_HIKI1` through it; `Fishing.reel_beats` maps the resolved `Outcome` onto the rest, played after the line is in rather than through `Interaction.player_anim`. `notice_rod` turns the player square-on to the camera (`add_calc_short_angle2`, now in `MLib.short_angle2`), holds 42 frames, then opens the catch report as an `mMsg` window with `LockContinue`; `dialogue_overlay.say` shows the line and `player.gd` awaits `closed` while `_update_animation` bails on `_busy`, keeping `GET_T2`'s last frame on screen for as long as the text is up. The facing carries through to `putaway_rod`, which turns the player back to the water.

The hooked fish is a real actor the whole way: `aGTT_fish_make_actor` spawns it and copies it onto the bobber's position every frame, and at catch it moves to the right hand while the rod moves to the left, through `GET_T1`/`GET_T2` — the player genuinely holds both. `act_fNN_<romaji>_{a,b,c}` are three display lists per species; only `a`/`b` are ever drawn (`aGYO_anime_frame` folds 0/1 onto `dl_a` and 2 onto `dl_b`), so the pipeline converts those two — take the Gfx symbol from `aGYO_displayList`, not the pose letter (the coelacanth's `b` is `act_f32_kasekiT_model`, no letter). `HeldFish` flips between the two poses on the species' cadence (fast 8-entry or slow 16-entry, fixed 30 Hz), billboards into the camera (the draw multiplies in `play->billboard_matrix`), and applies the per-species `aGYO_hosei_y` nudge.

`HeldCatch`'s hand point is derived from the rig rather than the original's `left_hand_pos` constant (`Matrix_Position_VecX(1100.0f, …)` off the Larm2 matrix, since the left arm chain stops at the elbow in-engine): the right arm does have a full chain (`Larm1`/`Larm2` against `Rarm1`/`Rarm2`/`joint_20`), and `joint_20` sits exactly one hand segment past `Rarm2`, so `HeldCatch` measures that same segment length off the rig. Scale is `FieldCatalog.actor_uniform_scale()` (`ACTOR_DRAW_SCALE / PIPELINE_SCALE * GX_TO_METERS` = 0.5) applied in world space (the parent bone attachment's own 0.5 rig scale is divided back out in `_ready`), matching `aFTR_PROFILE.scale` — the catch is scaled like everything else held in the player's hand. `_billboard` rebuilds the basis each frame rather than assigning `global_rotation`, so the hold survives the parent's rotation. Converted meshes need `GeneratedVisual`'s material pass or they keep backface culling from the wrong side, since the fish is billboarded rather than oriented by the hand; `scenes/dev/held_fish_check.tscn` freezes with `Engine.time_scale` (not `get_tree().paused`) so billboarding keeps running while the pose holds.

`Player_actor_request_proc_index_fromNotice_rod`'s exit code 0x39 hands off to `putaway_rod`, which plays `ply_1_putaway_t1` before requesting the wait; the catch is banked into the pocket before the report opens (`Player_actor_putin_item`), and a full pocket takes the other exit (0x53, `release_creature`) and throws the fish back. The model releases at the end of the putaway rather than the start, so the fish rides the hand down. That handoff is timed off the putaway clip's own length rather than `animation_finished`, since anything else driving the player in the meantime would mean the signal never arrives.

The catch report uses the game's own words: `Player_actor_Get_sakana_msg_num` maps a species to a message number (`0x1327 + type` up to type `0x20`, `0x2FA9 + type` past it), and `FishData.catch_msg` plays that conversation through `DialogueCatalog` and the existing overlay — multi-page, since the stringfish, coelacanth, and arapaima open on a reaction page before naming the fish. `mSM_CHECK_LAST_FISH_GET` is true only when every other fish is on the catch record and this one is not; that single catch gets `0x1349` (naming the fish), then `0x134A` over `YATTA2`. `mSM_COLLECT_FISH_SET` runs whether or not the fish fit, so a fish thrown back from full pockets still reaches `SpeciesLog`. An empty reel and an escaped fish say nothing, as in the original.

## Behaviour audit: shadows, bobber, rod (`ac_gyo_test.c`, `ac_uki_move.c_inc`, `m_player_main_*_rod`)

Everything below runs on the 60 Hz mover tick. `fish_shadows.gd` steps a `FrameStepper` and, each tick, builds the sense, ticks `FishSchool` (every shadow in turn, like `aGYO_actor_move`'s controller loop) and then `Fishing`.

**Shadow movement.**

- `aGYO_position_move` moves before the action proc, `0.5 * speed` GX a tick along `world.angle.y`. `FishShadow.heading` is `world.angle.y` and `yaw` is `shape_info.rotation.y`; swim patterns 1 and 2 split them.
- Upstream is `atans_table(flow) + 180°` from the unit's `mCoBG_GetWaterFlow` (`FishSchool.water_flow`, `flow_for_attr`). Still water has zero flow and `atans_table(0, 0)` is +Z, so pond fish hold station facing -Z. `aGTT_flow_direction` turns 0x100 a tick, 0x400 when more than 90° off.
- Swim 0: sweep 50°→360°, speed `0.5·sin`, so it swims forward then backs up. Swim 1: heading jumps `RANDOM2_F(180°)` (±90°), body keeps facing, sweep 0→180°, body and heading re-join at the end. Swim 2: turn at 0x400 a tick onto heading `± 45°` with no speed, then sweep 0→180° at `1.0·sin` while the body swings by `(upstream − heading) / 36` a tick from 7.5° on.
- A wall during `SWIM` turns the fish a quarter turn and sends it into `ESCAPE`; `ESCAPE` turns off one wall only (`gyo_flags & 0x40`, cleared when the escape times out).
- `aGTT_player_near` is checked in `WAIT` / `SWIM` / `ESCAPE` only: dash within 110 GX or a tool within 150 GX and the fish is gone in a `GYO_KAGE` puff. `NEAR` / `TOUCH` / `BITE` ignore the player.
- `aGTT_search_Uki` (same three actions): a splash within 17 / 22 GX sends it into `ESCAPE`; otherwise it needs `cast_timer == 0`, no shadow already engaged (`bite_check` → `gyo_flags & 1`), within `aGYO_search_area` and strictly inside the cone.
- `NEAR` closes at `aGTT_speed`; out of range → `WAIT`; inside `aGTT_touch_distance` it takes the bobber only if `gyo_status == 1`, else `WAIT`.
- `TOUCH`: each time `work0` runs out it darts at `aGTT_speed`; in range it rolls `RANDOM_F(4) < 1` (a hit skips the counter) or `DECREMENT_TIMER(touch_counter) == 0` (the fifth miss). A commit only lands once the bobber is in its touch proc (`gyo_status == 2`) and re-rolls every tick until then. A nibble sets `work0 = (int)((touch_count + RANDOM2_F(30)) * 2)` and backs off at `back_speed + RANDOM2_F(0.2)`. The 1-in-20 trash swap changes only the type; the shadow keeps its size.
- `BITE` without a strike counts `bite_time * 2` ticks and vanishes in a puff. The puff (`GYO_KAGE`) is spawned with a zero rotation, so it always darts +Z at 2.0 GX/frame, easing by 0.02 a tick, turning off one bank, for 100 ticks.

**Bobber.**

- Flight is 50 ticks; `hit_water_flag` is up for the landing tick only. `cast_timer = 40` is set at the cast and counted only once floating, so for 40 ticks after the splash no fish can see it or start nibbling.
- `aUKI_movement`: within 130 GX of the player it drifts along the unit flow, `chase_f(speed, 0.45, 0.1)` (0.225 while a fish nibbles); pond water drifts +Z. Past 130 GX it is towed back toward the player at 0.8. `range` eases from 12 to 40 GX at 0.05 a tick, and the bobber stops that far from the bank.
- `gyo_status`: 1 floating, 2 once a nibbling fish has moved the bobber into its touch proc (only then can that fish commit, and no other fish can start), 3 bitten. If the bite runs out the bobber drops back to its wait proc with the line still out — the next fish can have it.
- A (`command = 6`) is ignored until `relax_rod`, i.e. while the bobber is in the air. Pressed with nothing on: the bobber stops and comes up after its 12-tick `frame_timer` (reset to 12 if a fish starts nibbling), so a fish that commits inside those ticks is still struck and caught; a nibbling fish that does not is frightened off (`uki->status == 6`). Pressed during a bite: the fish is held (`gyo_status 4`, its bite clock stops) and fought for `timer[size] * 2` ticks (26 for trash), then lifted (`gyo_status 5`). A strike during a bite always lands.
- `NA_SE_10B` on landing, `NA_SE_10C` when the bobber comes up; `ROD_STROKE` is `cast_rod`'s frame-20 sound, `ROD_STROKE_small` `air_rod`'s.

**Rod.**

- `ready_rod` swings regardless. At frame 10 it probes 100 GX ahead plus four ±10 GX corners; all water → `cast_rod`, otherwise `air_rod`: `NOT_SAO_SWING1` continues from that frame and the bobber comes straight back. `Interaction.AIR_ROD` is that swing, offered at priority 0 so any other host keeps A. `cast_rod` posts no message.
- A strike on trash also leaves a fish's shadow puffing away (`aGTT_kage_make_actor(gyo, 1)`).

**Not reproduced, and why.**

- The player is not locked into `relax_rod` (it can walk; `LEASH_METERS` drops the line) and is not turned toward the bobber (`SetPlayerAngle_forUki`) — that would fight the stick.
- Walls are the body's cells, not `mCoBG` wall segments, so the wall-angle choice of which way to turn is replaced by "the side that is still water"; waterfalls (`aGYO_check_fall`), bridges (`aGYO_check_bridge`) and the 10 GX height check are not modelled.
- The hooked fish's thrash position (`aGTT_pos_calc` off the player's facing), the bobber's circling during the fight (`angl` / `spd`), the vibration tables and `NA_SE_24` / `NA_SE_11A` are presentation not yet built.
- The full-pocket `0x1348` choice has no exchange inventory yet, so either answer throws the fish back (same gap as the net).
- The bobber's flight back to the hand after an empty or air cast is not drawn.

## Spawning (`ac_set_ovl_gyoei.c`, `ac_gyoei_clip.c_inc`)

`FishSpawnScheduler` is the decision, `FishSchool._tick_spawn` / `try_spawn_in_acre` the loop, `data/creatures/fish_spawn_table.json` (`tools/generate_fish.py`) the weights. This section supersedes the spawn remarks above.

**When.** The set manager runs `aSOG_gyoei_set` once per acre transition (`aSetMgr_move_check_set` on wade start, for the acre being entered), never on a timer. It is skipped when a live shadow is already in that acre (`aGYO_chk_live_gyoei`) and when the acre is neither `MARINE` nor `RIVER` and holds no fresh water (`aSOG_gyoei_check_water_unit_in_block`; its loop runs 40×40 over a 16×16 table and reads into later acres, which has no visible effect because an acre with no water still has no unit to spawn on). A spawn fails silently when both `aGYO_MAX_GYOEI` controllers are taken. So an acre holds at most one fish per visit, and two at once across the town. We count the acre the player starts in as entered (like `BugField`); the original spawns nothing until the first crossing.

**Despawn.** `aGYO_cull_check`: a shadow off screen, more than 600 GX from the player and in another acre is destroyed. That is the only restock path: walk away, come back, roll again. We skip the off-screen test (as insects do) and never cull a hooked fish.

**Which list.** From the acre's `mRF_BLOCKKIND_*` (`mRF_block_info` in `m_random_field.c`, `FishSpawnScheduler.BLOCK_INFO`), not the water body:

| Block kind | List |
| --- | --- |
| `MARINE` + `OFFING` | sea list ×10, plus whale weight 1 (current term only) |
| `MARINE` + `ISLAND` | `f_island` (sea bass 20, red snapper 10, knifejaw 3), no ramp |
| `MARINE` (beach, river-mouth beach, dock, tailors) | `s_month` |
| `RIVER` during a fishing tourney, acre has `POOL`, `BRIDGE` or `WATERFALL` | 75%: `f_event` (small / normal / large bass), no ramp |
| `RIVER` | `r_month` |
| anything else with water | `p_month` (empty Oct–Mar and from Sep 16) |

A river-mouth beach fishes the sea list; its river water only hosts salmon (`SALMON2`, area `RIVER_MOUTH`). A pond inside a river acre fishes the river list.

**Term ramp** (`aSOG_gyoei_chk_term_info`). The save holds the *next* half-month and a 0–5 day lead (`renew_term_info`). From midnight `lead` days before the next term starts (the 1st, or the 15th for a second half) for five days, the current term's weights are scaled 5/6, 4/6 … 1/6 and the next term's list is added at the remainder. Past that window the saved term moves on and a new lead is rolled; a saved term more than one away (except term 0 / now 23) resets without a ramp. The previous implementation blended the *previous* term in after the boundary, the wrong way round. Terms are persisted in the save.

**Additions.** Coelacanth `FISH_SPAWN(COELACANTH, SEA, 2.0f)` is appended to sea and island lists when `mEnv_NowWeather() == RAIN` (snow does not count) and the slot is not 9am–3:59pm, current term only and unscaled, so it thins during a ramp. It was weighted 5 here before. The whale needs an offing acre, which the player cannot enter, so it never spawns in practice; it has no `FishData` and rolls to nothing.

**Roll** (`aSOG_gyoei_get_idx`). `selected = total * rand`, then walk the list subtracting `weight * env_rate`; the first entry whose remainder is ≤ `selected` wins, and if the remainder goes negative there is no fish. `env_rate` is 0.5 / 0.75 / 0.875 / 1.0 by field rank, so a poor town leaves up to half the rolls empty (rank is the calendar's constant 3 until town assessment exists). If the winner's sub-area fails `aSOG_gyoei_place_check` — `WATERFALL` needs a waterfall acre, `POOL` (brook trout, giant catfish, giant snakehead) a river-pool acre, `RIVER_MOUTH` a `RIVER` bit (GAFE01; the AUS build also wants `MARINE`) — it is struck and the roll repeats over the rest. All struck: no fish. The old code let every sub-area spawn anywhere and added an invented per-body size ceiling; both are gone.

**Where in the acre** (`aSOG_gyoei_set_gyoei_data`, `aSOG_gyoei_make`). Units 2–13 of the 16×16 acre only, filtered per species: large char on `WATERFALL` units; coelacanth, jellyfish, sea bass, red snapper, knifejaw on `SEA` units at least 20 GX deep (sea surface is a flat 20 GX, so bed height ≤ 0 GX, i.e. count 0 at beach level); salmon on any water, sea units only where deep; whale units 5–10; everything else any water unit (sea included). One qualifying unit is chosen uniformly. The shadow appears on that unit's north-west corner (`aSOG_get_water_attribute_position` returns the first water point it scans); the large char goes half a unit across and one unit down to the foot of the fall when that is water, else the unit centre. No qualifying unit: no fish.

**Shadow size and opacity.** `aGYO_shadow_scale` {0.3, 0.4, 0.5, 0.5, 0.6, 0.8, 1.2, 10} × 0.02 scales a ±1000 GX quad (`act_gyoei02_00_v`), X further ×0.4. The I4 tiles fill 14 of 16 rows and 28 of 32 columns, so the visible fish is 7/8 of the quad: 35 × scale GX long (17.5 GX for size S). We had it at 1000 GX, about two thirds of the original size. Prim alpha is 120 (whale 50) multiplied into the tile lerp; the escape puff starts at `(100·0.5 − 10)·6 = 240`, so it reads darker than the fish it left.

**Species rows.** `FishData.months / time_slots / waters / rarity_weight` are the union of the table (checked by `test_species_rows_agree_with_the_spawn_table`); the salmon row covers the river mouth. The spawn table generator copied the first half of September into `p_month`'s NULL second half; fixed.
