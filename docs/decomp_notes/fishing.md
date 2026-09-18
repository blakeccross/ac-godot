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

## Behavior

`Fishing` (session), `FishCatalog` (`data/creatures/*.tres` filtered by month, time slot and water kind, weighted by `rarity_weight`), `FishSize` (the per-size tables above), `FishShadow` (the action machine), `FishSchool` (two shadows, spawn and cull), `WaterBodies` (flood-filled water), `scenes/world/bobber.tscn` and `scenes/world/fish_shadows.gd` + `shaders/fish_shadow.gdshader`.

All forty species are on the shelf, one `.tres` each, transcribed rather than invented. `gyoei_type[]` gives size, `search_area` and `bite_time` per type. `ac_gyoei_model.c_inc`'s `aGYO_displayList` pairs an `aGYO_TYPE_*` index with its `act_fNN_<romaji>` art — the only mapping between the two naming schemes. Availability comes from `ac_set_ovl_gyoei.c`, a four-level table: `r_month` / `s_month` / `p_month` (river, sea, pond) → month → month-half → one of four time-of-day slots → a list of `FISH_SPAWN(type, area, weight)`.

`FishData` carries `time_slots` rather than an hour range because the original has none either — `aSOG_gyoei_time_no` buckets the clock into 9pm–4am, 4am–9am, 9am–4pm and 4pm–9pm and indexes with it, so a fish is in or out of a whole slot (the piranha holds midday and the small hours; cherry salmon, char, and rainbow trout hold dawn and dusk with the day cut out between them). `waters` exists because the three tables are separate — without it a red snapper would bite in the river. The coelacanth spawns via `needs_rain` gating it to rain-only sea catches, matching `aSOG_add_kaseki_range_data`.

The bite is not a timer: a shadow finds the bobber in its cone, nibbles, and commits, so the bobber dips a few times before it goes under and the catch is whichever fish bit. `FishCatalog` is only consulted when a shadow spawns. The rod's `cast` verb opens the session; while a line is out the verb becomes `hook`, with no player animation so the bite window is not spent animating. Hooking early or late yields nothing, full pockets refuse the catch, and walking past `LEASH_METERS` drops the line.

The cast's reach is fixed: `Player_actor_request_proc_index_fromReady_rod` measures `sin_s(rot) * 100.0f` along the player's facing (100 GX = 5 m, two and a half cells) — you aim by turning, there is no charge-up. The same routine gates whether the cast happens at all by probing the landing spot plus four corners at ±10 GX and requiring water under every one, so `FieldRequire.WATER` means "water where the rod lands," not "water in the next cell." The bobber leaves the rod during the swing, not after: `ready_rod` requests `cast_rod` at animation frame 10, and the uki gets its command on `cast_rod`'s first frame, so the line is airborne a third of the way through the swing. `Interaction.effect_frame` carries that frame (decomp frame / 30 = clip time) and `player.gd` applies the cast there, then waits out the tail; every other tool's effect still lands when its clip ends. Flight is `frame_timer = 50` mover frames, so `CAST_SECONDS` is 50/60 s, and `LEASH_METERS` is defined as an offset from `CAST_METERS`.

Shadow art is an SDF in the shader — a tapered capsule bent by the `aGYO_prim_f` curve — reproducing the four `act_gyoei02_*_int_i4` tiles without converting the original art. The bobber is the real `tol_uki1_model` from the pipeline, attached to the `Float` pivot under `bobber.tscn`; the model is authored upside down (`aUKI_actor_draw` starts from a 180° flip), so `bobber.gd`'s pitch targets are offsets from that rest pose, and `GeneratedVisual`'s ground-fit is undone after attach since the authored origin is the waterline. `bobber.gd` reproduces the tilt directly: flat (`+90°`) through the cast, easing upright (`0°`) once it settles, yanked to `-90°` on a bite, stepped on a fixed 30 Hz accumulator like the original's `add_calc_short_angle2`.

**Reel-in.** The original spends one player state per beat — `vib_rod` (`TURI_HIKI1`), `fly_rod` (`GET_T1`), `collect_rod` (`NOT_GET_T1` for reeling in nothing), `notice_rod` (`GET_T2`, holds the catch up). `Fishing.reel_beats` maps an `Outcome` onto those beats and `player.gd` plays them, after the hook resolves rather than through `Interaction.player_anim` — animating first would spend the whole bite window. `notice_rod` turns the player square-on to the camera (`add_calc_short_angle2`, now in `MLib.short_angle2`), holds 42 frames, then opens the catch report as an `mMsg` window with `LockContinue`; `dialogue_overlay.say` shows the line and `player.gd` awaits `closed` while `_update_animation` bails on `_busy`, keeping `GET_T2`'s last frame on screen for as long as the text is up. The facing carries through to `putaway_rod`, which turns the player back to the water.

The hooked fish is a real actor the whole way: `aGTT_fish_make_actor` spawns it and copies it onto the bobber's position every frame, and at catch it moves to the right hand while the rod moves to the left, through `GET_T1`/`GET_T2` — the player genuinely holds both. `act_fNN_<romaji>_{a,b,c}` are three display lists per species; only `a`/`b` are ever drawn (`aGYO_anime_frame` folds 0/1 onto `dl_a` and 2 onto `dl_b`), so the pipeline converts those two — take the Gfx symbol from `aGYO_displayList`, not the pose letter (the coelacanth's `b` is `act_f32_kasekiT_model`, no letter). `HeldFish` flips between the two poses on the species' cadence (fast 8-entry or slow 16-entry, fixed 30 Hz), billboards into the camera (the draw multiplies in `play->billboard_matrix`), and applies the per-species `aGYO_hosei_y` nudge.

`HeldCatch`'s hand point is derived from the rig rather than the original's `left_hand_pos` constant (`Matrix_Position_VecX(1100.0f, …)` off the Larm2 matrix, since the left arm chain stops at the elbow in-engine): the right arm does have a full chain (`Larm1`/`Larm2` against `Rarm1`/`Rarm2`/`joint_20`), and `joint_20` sits exactly one hand segment past `Rarm2`, so `HeldCatch` measures that same segment length off the rig. Scale is `FieldCatalog.actor_uniform_scale()` (`ACTOR_DRAW_SCALE / PIPELINE_SCALE * GX_TO_METERS` = 0.5) applied in world space (the parent bone attachment's own 0.5 rig scale is divided back out in `_ready`), matching `aFTR_PROFILE.scale` — the catch is scaled like everything else held in the player's hand. `_billboard` rebuilds the basis each frame rather than assigning `global_rotation`, so the hold survives the parent's rotation. Converted meshes need `GeneratedVisual`'s material pass or they keep backface culling from the wrong side, since the fish is billboarded rather than oriented by the hand; `scenes/dev/held_fish_check.tscn` freezes with `Engine.time_scale` (not `get_tree().paused`) so billboarding keeps running while the pose holds.

`Player_actor_request_proc_index_fromNotice_rod`'s exit code 0x39 hands off to `putaway_rod`, which plays `ply_1_putaway_t1` before requesting the wait; the catch is banked into the pocket before the report opens (`Player_actor_putin_item`), and a full pocket takes the other exit (0x53, `release_creature`) and throws the fish back. The model releases at the end of the putaway rather than the start, so the fish rides the hand down. That handoff is timed off the putaway clip's own length rather than `animation_finished`, since anything else driving the player in the meantime would mean the signal never arrives.

The catch report uses the game's own words: `Player_actor_Get_sakana_msg_num` maps a species to a message number (`0x1327 + type` up to type `0x20`, `0x2FA9 + type` past it), and `FishData.catch_msg` plays that conversation through `DialogueCatalog` and the existing overlay — multi-page, since the stringfish, coelacanth, and arapaima open on a reaction page before naming the fish. `mSM_CHECK_LAST_FISH_GET`'s `0x1349` swap (species already in `MuseumBook`) happens at hook time. An empty or escaped line uses `Game.post_notice` since there is no pose to hang it on.
