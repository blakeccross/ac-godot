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

## Reproduce

- Cast into water, wait, bite telegraph, hook timing, get an item.
- Miss / escape does nothing to pockets.
- Full pockets → cannot keep the catch (release or fail).
- At least two sizes or rarity weights so the loop is not a single guaranteed fish.
- Only on water tiles.

## Simplify

- One water type and a tiny `FishData` table (3–5 fictional fish), not 40+ species.
- Two shadows at a time, which is what the original caps at anyway.
- Skip golden rod, whale, tourney, junk items until the loop feels good.
- No sea vs river vs pond species tables.

## Shadow behaviour (`ac_gyo_test.c`)

The shadow is not a creature simulation. `aGTT_setupAction` drives seven actions:

| Action | Behaviour |
| --- | --- |
| `WAIT` | Hold station facing upstream for `(100 + rand 30) * 2` frames, drifting backwards at `-0.15` GX/frame |
| `SWIM` | One of three `swim_flag` patterns, each a sine speed envelope over a sweep advancing 5°/frame at half rate |
| `NEAR` | Turn onto the bobber and close at `aGTT_speed[size]` |
| `TOUCH` | The nibble loop: back off at `aGTT_back_speed[size]`, return, and on each approach either commit (1 in 4) or nibble again. `touch_counter` is 5, so the fifth approach is forced |
| `BITE` | Hold the bobber for `aGYO_bite_time[rod][species] * 2` frames, sitting `hosei[size]` behind it |
| `COMEBACK` | Pinned to the bobber while the rod lifts it out |
| `ESCAPE` | Bolt at `2.0` GX/frame for 100 frames, easing off by `0.02` a frame |

Detection is `aGTT_search_Uki`: inside `aGYO_search_area[rod][species]` **and** inside the `aGYO_search_angle` cone, which is 3° for a fussy species and 180° for an eager one. `aGTT_player_near` only flees a **dashing** player (110 GX) or a swung axe / net / scoop (150 GX) — walking to the bank is safe. A cast landing within 17 GX (small) or 22 GX (large) scares the fish instead of interesting it.

Shadows ride `mCoBG_GetWaterHeight - 8.0` GX under the surface. Animation is a 20-entry table stepped every two frames (`fwork0` runs 19 → 0 at 0.5/frame, wrapping by +19): `aGYO_2tile_texture_idx` picks two of four tiles and `aGYO_prim_f` cross-fades them as the *LOD fraction*, which is the tail sway. `dec_step` is `0.0` for `WHALE`, so a whale's shadow is frozen. A scared fish leaves a `GYO_KAGE_ACTOR` puff that coasts and fades over 100 frames with alpha `(timer * 0.5 - 10) * 6`.

The dwell tables are authored in 30 Hz frames and every site that loads one into a counter doubles it; speeds and the escape / puff timers are already in mover frames.

## Built

`Fishing` (session), `FishCatalog` (`data/creatures/*.tres` filtered by month, time slot and water kind, weighted by `rarity_weight`), `FishSize` (the per-size tables above), `FishShadow` (the action machine), `FishSchool` (two shadows, spawn and cull), `WaterBodies` (flood-filled water), `scenes/world/bobber.tscn` and `scenes/world/fish_shadows.gd` + `shaders/fish_shadow.gdshader`.

All forty species are on the shelf, one `.tres` each, transcribed rather than invented. `gyoei_type[]` gives size, `search_area` and `bite_time` per type. `ac_gyoei_model.c_inc`'s `aGYO_displayList` is what pairs an `aGYO_TYPE_*` index with its `act_fNN_<romaji>` art, and it is the only mapping between the two naming schemes. Availability comes out of `ac_set_ovl_gyoei.c`, which is a four-level table: `r_month` / `s_month` / `p_month` (river, sea, pond) → month → month-half → one of four time-of-day slots → a list of `FISH_SPAWN(type, area, weight)`. Walking all of it and collecting where each type appears gives its months, its slots and its weight.

That shape is why `FishData` carries `time_slots` instead of an `hour_start` / `hour_end` pair. The original has no per-fish hour range at all — `aSOG_gyoei_time_no` buckets the clock into 9pm–4am, 4am–9am, 9am–4pm and 4pm–9pm and indexes the table with it, so a fish is in or out of a whole slot. Most species do sit in a run of adjacent slots that a window could express, but the piranha holds midday and the small hours, and the cherry salmon, char and rainbow trout hold dawn and dusk with the day between them cut out. `waters` exists for the same reason: the three tables are separate, so without it a red snapper would bite in the river. The five non-fish entries past `aGYO_TYPE_NUM` (whale, can, boot, tire, the second salmon) have no `.tres` because nothing in `Fishing` pulls junk up yet.

Three things are ours rather than transcribed. The half-month `gyoei_term` split and its transition ramp are not modelled, so each fish carries the highest weight it holds across the year instead of a per-term one. The finer `aSOG_SPAWN_AREA_*` sub-areas — pool, waterfall, river mouth, offing — collapse into the three `WaterBodies.Kind` values, so a fish that only belongs in a river pool can bite anywhere in a river. And sell prices are a formula over size class and rarity, because there is no price table anywhere in the decomp to copy; they are self-consistent but they are not the game's numbers.

The coelacanth is the one species with no table entry at all. `aSOG_add_kaseki_range_data` splices it into the sea list at weight 2 while `mEnv_NowWeather() == mEnv_WEATHER_RAIN` and the slot is not `DAY`. There is no weather system, so `needs_rain` keeps it out entirely rather than handing out a free rarity.

The bite is **not** a timer: a shadow has to find the bobber in its cone, nibble at it, and commit, so the bobber dips a few times before it goes under and the catch is whichever fish bit. `FishCatalog` is only consulted when a shadow spawns. The rod's `cast` verb opens the session; while a line is out the verb becomes `hook`, with no player animation so the bite window is not spent animating. Hooking early or late yields nothing, full pockets refuse the catch, and walking past `LEASH_METERS` drops the line because we cannot lock the player for the whole cast.

The cast's reach is fixed. `Player_actor_request_proc_index_fromReady_rod` measures out `sin_s(rot) * 100.0f` along the player's facing and casts there — you aim by turning, there is no charge-up, and no input makes the throw longer or shorter. 100 GX is 5 m, which is two and a half cells, so `ToolUse.cast_point` had to stop using the cell in front of the player: that put the bobber at the water's edge and made the whole loop a shoreline activity. The same routine decides whether the cast happens at all by probing the landing spot plus four corners at ±10 GX and requiring water under every one, which is why you cannot drop the float on a spit of land or straddle the far bank; failing the probe sends the swing out over land as `air_rod`, and since we do not model that state the verb is simply withheld. `FieldRequire.WATER` therefore means "water where the rod lands", not "water in the next cell", and it is the rod's requirement alone. The bobber also leaves the rod *during* the swing, not after it. `ready_rod` requests `cast_rod` once the swing reaches animation frame 10, and `Player_actor_Item_main_rod_cast` gives the uki command 3 on `cast_rod`'s very first frame, so the line is in the air a third of the way through the swing and the rest of the swing plays out around it. We used to await the whole clip before applying the field action, which put the animation and the bobber on visibly different beats. `Interaction.effect_frame` now carries that frame — the pipeline samples every `cKF_ba_r_*` clip at 30 fps, so a decomp frame number is that frame over 30 in clip time — and `player.gd` applies the action there, then waits out the tail. Everything other than the cast still lands when its clip ends, which is a simplification: the original frame-gates every tool's effect this way.

The flight itself is `frame_timer = 50` mover frames — not doubled the way the authored 30 Hz dwell values are — so `CAST_SECONDS` is 50/60 s, and `LEASH_METERS` is defined as an offset from `CAST_METERS` so it cannot silently fall below the throw.

Still off: `uki->cast_timer` is 40 frames of settling after the float lands during which a nibble cannot become a touch, and we have no equivalent, so fish commit slightly sooner than they should.

Shadow art is an SDF in the shader — a tapered capsule bent by the `aGYO_prim_f` curve — because the four `act_gyoei02_*_int_i4` tiles are original art and are not converted.

The bobber is the real `tol_uki1_model` from the pipeline (`items/tol_uki_1.glb`), attached to the `Float` pivot under `bobber.tscn`, with the placeholder sphere hidden behind it and the ripple ring left alone. Two details are worth knowing. The model is authored upside down — every case in `aUKI_actor_draw` starts from `DEG2SHORT_ANGLE2(180.0f)` — so the flip is the rest pose and `bobber.gd`'s pitch targets are offsets from it. And the authored origin is the actor position, which for a floating bobber is the waterline, so `GeneratedVisual`'s ground-fit is undone after the attach; otherwise the whole float sinks below the surface.

The reel-in is its own small chain. The original spends a whole player state per beat — `vib_rod` pulls the rod over on `TURI_HIKI1` while the rod flexes (`sao_sinari1`), `fly_rod` swings the catch up on `GET_T1` (`sao_get_t1`), `collect_rod` gives you a single empty `NOT_GET_T1` beat (`not_sao_swing1`) for reeling in nothing, and `notice_rod` holds the catch up on `GET_T2`. `Fishing.reel_beats` maps an `Outcome` onto those beats and `player.gd` plays them.

`notice_rod` is the show-off, and it is not just a clip. `Player_actor_Movement_Notice_rod` turns the player to `shape_info.rotation.y == 0`, which in a fixed 3/4 acre means square-on to the screen; our follow camera sits on +Z and yaw 0 faces +Z, so the original's target angle already means "look at the camera" and needed no reinterpreting. It turns on `add_calc_short_angle2(..., 1 - sqrt(0.5), 2500, 50)`, and that `minStep` of 50 is the first place we have needed the floor branch of that function, so it now lives in `MLib.short_angle2` with the bobber's tilt sharing it. `main_notice->timer` counts 42 frames independently of the animation and then `Player_actor_MessageControl_Notice_rod` opens the catch report, so the text appears while `GET_T2` (1.1 s) is still playing underneath it. The report is an `mMsg` window with `LockContinue` held until the player advances it, and `notice_rod` does not hand off to `putaway_rod` until that happens — so the pose stays up for exactly as long as the text does. `dialogue_overlay.say` shows a single line with no conversation behind it and `player.gd` awaits its `closed`; `_update_animation` bails while `_busy`, which is what keeps the last frame of `GET_T2` on screen instead of falling back to the idle. The facing is put back afterwards because `notice_rod` carries the pre-catch angle through to `putaway_rod`, which turns you back to the water — without that you would finish every catch pointing away from the river.

The player holds the catch, and that **is** what the original does. This note twice said otherwise and was wrong both times, so the chain is worth writing down. The hooked fish is a real actor: `aGTT_fish_make_actor` spawns it as `mAc_PROFILE_GYO_RELEASE` and `aGTT_comeback` copies it onto `uki->uki_pos` every frame, so it goes wherever the bobber goes. `aUKI_catch` and `aUKI_get` then put the bobber actor at `uki->right_hand_pos` and set `uki->uki_pos = uki->left_hand_pos` — rod in one hand, fish in the other, through `GET_T1` and `GET_T2`. At the same moment `uki->gyo_status` reaches 5, `gyo_flags` picks up bit 8, `aGYO_change_data_area` flips `draw_type` to `aGYO_DRAW_TYPE_FISH`, and `aGYO_actor_draw_fish` replaces the shadow quad with the species model.

The models were always reachable; the earlier claim that they sat outside `dataobject.obj` was simply false. `act_fNN_<romaji>_{a,b,c}` are in the same REL as everything else, three display lists per species with their own `_tex` and `_pal`. Only two of the three are ever drawn: `aGYO_anime_frame` returns 0, 1 or 2 and the draw indexes with `(int)(frame * 0.5)`, which folds 0 and 1 onto `dl_a` and 2 onto `dl_b`, leaving `dl_c` unreachable dead art. So the pipeline converts `a` and `b` only. Take the Gfx symbol from `aGYO_displayList` rather than from the pose letter — the coelacanth's `b` is `act_f32_kasekiT_model`, with no letter at all.

`HeldFish` reproduces three things from that draw. It flips between the two poses on `aGYO_anime_ptn`'s per-species cadence, fast (an 8-entry cycle) or slow (16), stepped on a fixed 30 Hz tick rather than the monitor's refresh. It billboards into the camera, because the draw multiplies in `play->billboard_matrix` and the fish faces the viewer, not the hand. And it applies the per-species `aGYO_hosei_y` nudge, which lowers the model.

`left_hand_pos` is not a joint, which is the whole trick. `Player_actor_draw_After_Larm2` runs `Matrix_Position_VecX(1100.0f, &player->left_hand_pos)` off the Larm2 matrix: the left arm chain stops at the elbow, so the game computes the hand it does not have. The right arm does have one — `Larm1`/`Larm2` against `Rarm1`/`Rarm2`/`joint_20` — and `joint_20` sits exactly one hand segment past `Rarm2`. So `HeldCatch` puts a `HandPoint` that far along the arm from the elbow, taking the length off the rig rather than transcribing 1100, whose units are the original's model space and do not survive conversion. Binding to the joint itself is what put the forearm and fist through the fish.

The scale is transcribed after all, and the detour is worth recording because it shipped a fish half the right size. `aGTT_comeback` sets the actor scale to a flat `0.01` when the draw type is FISH, and the first pass read that as living in a unit space the pipeline does not preserve, so it calibrated each model to the length `FishSize.shadow_size` gives its size class. But `0.01` is just `aFTR_PROFILE.scale`, the same number nearly every field actor carries, and `FieldCatalog.actor_uniform_scale()` already converts it — `ACTOR_DRAW_SCALE / PIPELINE_SCALE * GX_TO_METERS`, which is 0.5. The calibration had landed on 0.25, exactly half, and a held fish came out the length of its own shadow rather than twice it. The check that settles it: a tool bound to the hand takes local scale 1 under a rig scaled 0.5, so it draws at world 0.5 — the same figure. The catch is scaled like every other thing in the player's hand.

That scale is applied in world terms rather than as a local one, because the parent is a bone attachment and the rig's 0.5 would otherwise multiply in on top. `_ready` divides the rig's scale back out so the first drawn frame is already right, and `_billboard` rebuilds the basis each frame instead of assigning `global_rotation`, so the hold survives the parent's rotation.

Two footguns found by rendering it rather than asserting about it. The converted meshes need `GeneratedVisual`'s material pass like everything else, or they keep the imported material's backface culling — and because the fish is billboarded into the camera rather than oriented by the hand holding it, the side that culls can be the side facing you. And a fish frozen with `get_tree().paused` stops billboarding, so it sits edge-on and reads as a 12-pixel sliver; `scenes/dev/held_fish_check.tscn` freezes with `Engine.time_scale` instead, which holds the pose while `_process` keeps running.

Not reproduced from that draw: the ±13° yaw wiggle (`move_angle`, gated on `gyo_flags & 0x200`, which is a later `gyo_status`) and `mAc_UnagiActorShadow`.

The rod has no `sao_get_t2`, so it keeps the pose it finished the lift in.

Dismissing the report does not return the player straight to the idle. `Player_actor_request_proc_index_fromNotice_rod` reads the message control's exit code: 0x39 hands off to `putaway_rod`, which plays `mPlayer_ANIM_PUTAWAY_T1` with a `GASAGOSO` rustle and only then requests the wait. `_play_putaway` is that step, on `ply_1_putaway_t1` — a clip the pipeline had to be told to convert, since `PLAYER_CORE_ANIMS` names each one. The rod holds its wait pose through it, because `tol_sao_1` carries six clips and none of them is a putaway.

The catch is in the pocket long before that animation: `setup_main_Notice_rod` banks it with `Player_actor_putin_item` before the text ever opens, which is also why the full-pocket case takes the other exit (0x53, `release_creature`) and throws the fish back rather than failing to store it. Ours releases the model at the end of the putaway rather than the start, so the fish rides the hand down instead of blinking out of a raised one — a reading of "when does it stop being drawn", which the decomp answers through actor lifetimes we do not model. The `GASAGOSO` rustle is not played; nothing in the project plays SFX yet.

Timing that step off `animation_finished` does not work. Anything else that drives the player in the meantime means the signal never arrives, and the catch is then never released — so it waits out the clip's own length instead.

The ordering matters: the reel plays **after** the hook resolves, not through `Interaction.player_anim`. `_play_action` awaits the clip before applying the action, so animating first would spend the whole bite window and the hook would always land late. A fish that reached the hook gets all three beats even when pockets are full, because you watch the catch come up and get held up before it is refused. The catch report is carried on that beat as `ReelBeat.catch_msg` rather than posted when the button goes down, which is what lets the pose and the text line up.

The report is the game's own words. `Player_actor_Get_sakana_msg_num` maps a species to a message number — `0x1327 + type` up to type `0x20`, `0x2FA9 + type` past it — and the message bank the dialogue step already extracts has the line, pun included ("I caught a crucian carp! / Carpe diem!", "Daces wild!", "Whew! And I thought the POND smelt bad!"). So `FishData.catch_msg` stores the number and `player.gd` plays the real conversation through `DialogueCatalog` and the existing overlay rather than formatting a string. That matters for more than flavour: the stringfish, coelacanth and arapaima open on a reaction page and name the fish on a second one, so the report has to be able to run multiple pages, which a single `say()` could not.

Two branches of that message flow are not modelled. `mSM_CHECK_LAST_FISH_GET` swaps in `0x1349` ("I caught {item0}! / Wait a second. That means...") once you have already collected a species, which needs museum bits we do not keep, so every catch reads as a first catch. And when pockets are full `mMsg_Set_continue_msg_num(win, 0x1348)` chains "But my pockets are full! / Should I swap it for something else?" onto the report with a two-option choice; we show that line after the species report and drop the choice. `Fishing` still puts the fish in your pockets at hook time, though — the original does it in `notice_rod`'s setup, which is why a full pocket there gets a swap-or-discard choice we do not offer. An empty or escaped line keeps its plain `Game.post_notice`: there is no pose to hang it on, and the original shows no message at all for reeling in nothing.

`bobber.gd` reproduces the tilt directly: lying flat (`+90°`) through the cast, easing upright (`0°`) on the fast `1 - sqrt(0.8)` curve once it settles, and yanked to `-90°` on a bite. Because `add_calc_short_angle2` steps once per drawn frame, the tilt runs on a fixed 30 Hz accumulator rather than scaling by `delta`.

Not built, deliberately: the rest of the rod player chain (`ready_rod` exists only as the cast-target measurement above, not as a state you stand in; `air_rod` for casting onto land, `putaway_rod` beyond restoring the facing, and `notice_rod`'s message flow — the `mDemo` item camera, the `YATTA2` celebration, the fanfare pair, the new-species check against the museum bits, and the swap-an-item choice when pockets are full), the `gyoei_term` half-month split and its transition ramp, the `aSOG_SPAWN_AREA_*` sub-areas, weather and therefore the coelacanth, trash, golden rod (only the normal-rod rows of `aGYO_search_area` / `_angle` / `aGYO_bite_time` are transcribed, and `tol_uki2_model` is not converted), the whale, BGM duck, splash and bite SFX (there is no SFX catalog yet), and the `eEC_EFFECT_TURI_HAMON` / `_SIBUKI` ripple and spray effects.

Known gap: the water **surface** height is a single flat value per field (`WorldBuilder.water_surface_y`). The original reads `mCoBG_GetWaterHeight` per unit, and catalog water is a heightfield whose surface we do not extract, so shadows on a sloped or multi-elevation acre will sit at the wrong height. `WaterBodies.Kind` is classified from body shape rather than the unit attribute for the same reason.

## Ignore

- Fishing tourney events and `mFR_record_c`.
- Island-only fish and `mISL_PLAYER_ACTION_NOTICE_FISHING_ROD`.
- Coelacanth rain-only and other famous exception rules until we want weather-gated spawns.
- Furniture-mounted fish and museum donation treadmill.
- `aGYO_TYPE_TEST` / fossil-fish (`kaseki`) debug actors.
