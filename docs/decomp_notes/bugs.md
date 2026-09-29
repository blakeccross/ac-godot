# Bugs (insects)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only.

**Read before implementing:** `BugData`, net tool, spawn on trees/flowers/ground.

## Decomp sources

| File | Role |
| --- | --- |
| `include/ac_insect.h`, `include/ac_insect_h.h` | Controller: up to **9** live insects |
| `src/actor/` insect overlays (`aINS_PROGRAM_*`: butterfly, locust, dragonfly, …) | Per-family movement |
| `include/m_player.h` | `READY_NET`, `SWING_NET`, `PULL_NET`, `STUNG_BEE`, … |
| `include/m_player_lib.h` | `mPlib_request_main_release_creature_insect_from_submenu` |
| `include/m_name_table.h` | `ITM_INSECT_START` 0x2D00, 40 insects (`ITM_INSECT_END` = start+40) |
| `include/m_common_data.h` | `insect_term` + transition offset |
| `include/m_cockroach.h` | House cockroaches (separate) |
| `include/ac_set_ovl_insect.h` | Spawn overlay |

Clip API (`aINS_Clip_c`): `make_insect_proc`, `search_near_insect_proc`, `set_pl_act_tim_proc` (player shook/dug/axed this unit). Stress: `aINS_MAX_STRESS_DIST` = 3 tiles, `aINS_PATIENCE_STEP` 0.5.

## What does the original system do?

A controller actor holds **9** `aINS_INSECT_ACTOR` slots (`aINS_ACTOR_NUM`). Field births use **8** (`aINS_MAKE_NEW`); slot 8 is for exist/release. Spawns run from `aSOI_insect_set` **once per wade into an acre** (the set manager), skipped if that acre already has a live insect (`aINS_chk_live_insect`). Placement is restricted to units in the entered acre — not a radius around the player.

The player holds a net, approaches, and swings. Catch converts the actor to an insect item in pockets. Bees can sting (`STUNG_BEE`). Mosquitoes have their own sting. Some bugs flee when the player runs, shakes a tree, or digs nearby (`aINS_PL_ACT_*`).

Wisp/spirit is an extended type (`aINS_INSECT_TYPE_SPIRIT`), not a pocket insect. Cockroaches spawn in dirty houses via `m_cockroach`. Ants on candy / spoiled turnips go through `make_ant_proc`, which queues a separate `mAc_PROFILE_ANT` actor (`aINS_check_birth_ant`) instead of taking an insect slot; `aINS_chk_live_insect` counts those ant actors too.

BGM ducks while collecting (`mPlayer_BGM_VOLUME_MODE_COLLECT_INSECTS`).

## Important states

- Occupied insect slots (type, patience, fleeing).
- Player net index (ready / walk-ready / swing / pull / notice / put away).
- `insect_term`.
- Player action timestamp on a unit (tree shake, etc.).
- Inventory full.

## Inputs

- Season/term, hour, weather.
- Habitat objects (flowers, trees).
- Player proximity, speed, net swing volume.
- Tree shake / scoop / axe on a tile.

## Outputs / events

- Pocket insect item or sting interrupt.
- Despawn / flee.
- Collection bit.
- Release from inventory back into the world.

## Interacts with

- **World / plants** — spawn points.
- **Player / interaction**.
- **Inventory**.
- **Time / weather**.
- **Audio**.
- **Furniture** — displayed bugs; house cockroaches.
- **Shops** — net unlock after `mSP_NET_SALES_SUM` 3000 at Cranny.

## Behavior

All 40 species, each on its own `BugProgram` overlay (`scripts/systems/bugs/`: butterfly, dragonfly, grasshopper, cicada, beetle, firefly, water strider, mole cricket, bagworm, pillbug, mosquito, ladybug, cockroach, wisp). `BugActor` runs the shared per-insect state machine; `BugSpawnScheduler` places up to the decomp's live-slot count per acre on entry, gated by season/term/hour/weather from `BugCatalog`; `BugHabitats` maps flowers/trees/ground to valid spawn units. The net is a hold-A / release swing whose head is tested against each insect's registered catch sphere from keyframe 6 on, and a `Check_StopNet` scare when the swing ends (see [tools.md](tools.md) § Net); a catch goes to the pockets and the catch record, and full pockets offer a swap (the exchange inventory is not built, so it is let go). Museum donation and the display case are covered in [museum.md](museum.md).

**Ground collision** (`aINS_BGcheck` → `mCoBG_BgCheckControll` → `mCoBG_AdjustActorY`): every frame, after the move and before the program, any insect with `bg_type != 0` has its feet (`pos.y + bg_height`) lifted onto the ground if at or under it (`on_ground`, vertical speed zeroed). A grounded insect whose ground drops by no more than this frame's XZ step follows it down. Water units floor 20 GX under the surface and set `is_in_water`. Ground height is `FieldCollision.ground_y_at` (the sloped surface, `mCoBG_GetBgY_AngleS_FromWpos`), via `BugBg.make_ground` → `Sense.ground` → `BugActor._bg_check`. Before 2026-09-25 this step was a stub, so waiting grasshoppers sank under the grass between hops. Cicadas, beetles, bees and cockroaches switch collision on once they fly off their home unit (`BugProgram.left_home_unit`).

**Grasshoppers / crickets / locusts** (`ac_ins_batta.c`): wait → change direction (probe 53 GX, 218 for migratory locusts, reject > 40 GX height change or water) → jump (4 up, 5.5 forward, gravity 0.7). The jump-or-turn choice uses the shared play clock (`game_frame % 200`: locusts jump unless in the first 20 frames, crickets only then). A scare hops them away from the player, or back toward the acre centre past 240 GX; hopping north up a slope adds `3·sin(slope)` lift. Net escapes leap off the player's facing ±60°. Debug: console `bug <id> [count]`; capture `tools/capture.sh console=bug,grasshopper,3 target=bug:grasshopper date=2001-08-20`.

**Not ported:** insect sounds (`sAdo_OngenPos` chirps 157–160, locust wings 0xA2/0xA3, beetle/cicada SEs), the drown splash (`eEC_EFFECT_TURI_MIZU` + SE 0x438), attribute walls (`bg_type 1` / `mCoBG_UniqueWallCheck`) beyond `BugBg`'s coarse blocked-cell test.

## Spawning, schedule and catching (parity pass 2026-09-28)

Checked `ac_set_ovl_insect.c`, `ac_set_manager.c`, `ac_insect_clip.c_inc`, `ac_insect_move.c_inc` and `m_player_main_{swing,notice}_net.c_inc` against `BugSpawnScheduler`, `BugHabitats`, `BugField` and `NetSwing` / `Netting`.

**When a spawn runs** (`aSetMgr_move_check_set` → `check_wait` → `move_set`): only when a wade into another acre starts (`mFI_WADE_START`), for the acre the wade lands in (`Get_WadeEndPos_proc`), after `aSetMgr_WAIT_TIME` = 5 frames. Nothing spawns on a scene load or while standing in an acre. `aSOI_ins_block_check` skips the acre if any live insect (slots 0–7, or an ant actor) was *born* there (`actor->block_x/z` = `play->block_table` at birth, which switches to the landing acre as the wade starts), and skips offing acres. The attempt is spent even with every slot full. Ours: `BugField` reads `Sense.wade_end` (`Player.wade_end_position()`).

**Spawn list** (`aSOI_ins_make_range_data`): `l_insect_month[month][term]` (terms: 23–3, 4–7, 8–15, 16, 17–18, 19–22; Jan / Feb / Dec all use `l_insect_m_other_t`), plus ANT on candy, ANT on trash, COCKROACH on trash at weight 1. The list is kept in `insect_keep` and rebuilt only when the month or term changes. Month blend (`aSOI_ins_chk_term_info`): the save holds the month the table is heading into and a 0–5 day offset; from `offset` days before that month's 1st, for 5 days, the current month weighs 5/6, 4/6 … 1/6 and the next month the rest — i.e. the *next* month fades in at the end of this one (once the calendar reaches it both halves are the same month). After the window the save moves on with a new offset. Before 2026-09-28 we blended the *previous* month in at the start of the month with a rising weight.

**Spawn areas** are the decomp enum as-is in `data/bugs/spawn_table.json`: 0 tree, 1 flower, 2 flower in rain, 3 flying, 4 ground, 5 bush, 6 near water, 7 on water, 8 candy, 9 spoiled turnip, 10 under rock, 11 underground, 12 flowers-or-flying, 13 nothing. (The table used to squeeze rock / underground into 8 / 9, which collided with the candy / trash additions: every acre with a rock read as "bait present" and only pill bugs and ants could spawn.)

**Feasibility** (`aSOI_chk_live_area_data`, every area in enum order, on the acre's inner 12×12 units — the 2-unit rim never hosts a birth): tree = `aSOI_tree_check` FG list (no palms, saplings, bee trees, fruit trees only while bearing); flower = any bloom, not in rain; rain flower = only in rain; flying = any unit with no FG item; ground = attribute GRASS0–SOIL1 or BUSH; bush = BUSH; near water = `mCoBG_CheckWaterAttribute`; on water = WATER…RIVER_NE and only in a pool acre or one without river / waterfall / marine bits; candy / trash = that item on a unit, not in rain or snow; under rock = ROCK_A–E; underground = hole-diggable attribute with no FG item. An area the acre cannot host has its entries' weight zeroed. Area 12 entries become ON_FLOWER (flowers present) or FLYING (none) and keep their weight; in rain they are zeroed. Candy or a spoiled turnip present zeroes every non-bait entry.

**Pick** (`aSOI_ins_get_idx`): total > 100 → roll over the total, else over 100 (the rest is no insect); weights × `env_rate` by town rank (0.5 / 0.75 / 0.875 / 1, rank fixed at 3 until town assessment exists). On bait: roll over the total at rate 1. A picked NOTHING (island only) spawns nothing. One species per acre entry; `l_insect_birth_sum` births 1, except red dragonflies and fireflies 6 + [0,3). Each birth takes a random still-unused live unit, at the unit's centre. A cockroach on a tree / spoiled turnip starts in its tree / item pose.

**Cull** (`aINS_cull_check`): only while off screen (`Sense.on_screen`, the camera frustum). A released insect (`actor_specific == 1`) is destructed at once; any other when > 600 GX from the player and born in another block than `play->block_table`. Life time 216000 frames, then the alpha fade.

**Notice / stress** (`aINS_get_stress`): patience rises from the most stressful moving actor in the PLAYER, NPC, BG and unused lists within `aINS_MAX_STRESS_DIST` + `catch_ME_data[type]` (3D distance, frame move × `calc_table`). Villagers now count (`Sense.npc_positions` / `npc_moves_gx`, filled by `bug_actors.gd`); before 2026-09-28 only the player stressed insects. BG actors other than villagers (ants, bees, the train) are not fed in.

**Net** (`Player_actor_CatchSomethingCheck_common`): from keyframe > 6 every tick tests each registered insect (`aINS_set_catch_range`: 24 GX butterflies 0/1, 24 GX facing-gated cicadas / bee / beetles and a stopped cockroach, else 8 GX) against the net head + 15 GX; first hit in registration order wins; the swing plays out. Pull → report 0xA2C+type (<0x20) / 0x2FA1+type, 0xA4E/0xA4F for the last missing insect; pockets full → 0xA4D and the insect is let go (`release_creature` on the caught actor). Already matched; no change.

**Not ported / left:** ants as a separate non-slot actor (ours are ordinary insects in a slot); island (`l_insect_island`, NOTHING weights) and Wisp (`aSOI_SPAWN_TYPE_SPIRIT`) spawn types; the town-rank `env_rate` (no assessment); the buried-item (`mFI_GetLineDeposit`) exclusion in the per-area "any unit?" pre-check; the gold net's 21 GX reach.

## Movement programs (`ac_ins_*.c` → `scripts/systems/bugs/bug_*.gd`)

Audited 2026-09-28 against the decomp, program by program. Units: 1 unit = `mFI_UNIT_BASE_SIZE_F` = **40 GX** (one 2 m `WorldGrid` cell); an acre is 16 units = 640 GX and its centre is the block corner + 320. Speeds are GX per 30 Hz frame, applied at half per 60 Hz tick (`Actor_position_move`); `chase_angle` steps are frame-scaled (halved per tick), `add_calc` is not.

**Shared rules** (`BugProgram` helpers):

- **Acre centre, not home.** Every range the decomp measures from `mFI_BkNum2WposXZ + 320` (dragonfly 240 / 480, firefly 240, hopper 240, pill bug and mole cricket 400, wisp 160) uses `acre_center`. Most programs used to measure from the spawn point.
- **Escape heading = the player's facing.** Released, caught and most scared insects leave along `player->shape_info.rotation.y + RANDOM_CENTER_F(120°)` (±60°), or 21845·(rand − 0.5) for the ground crawlers. That is not away from the player's position. The exceptions are that cicadas and cockroaches that are scared on a tree pick a heading within ±67.5° of south, and fleeing hoppers jump away from the player. Released inits rerun on the first frame that knows the player (`BugActor._init_waits_for_player`).
- **Tool scares** use the real events. They are not any tool swing near the player.
  - `mPlib_Check_StopNet` (the net's position on the tick a swing stops) → `net_stop_pos`.
  - `Check_DigScoop` (the dug or struck unit's centre) → `scoop_pos`.
  - `Check_HitAxe` (the unit in front of a swing that is not a scoop) → `axe_hit_pos`.
  - `VibUnit` (an axe hit anywhere in the acre) → `vib_unit`.
- **Tree insects** keep `world.angle.y` = 0, the catch-range facing; only the shape (`rot.y`) turns or sways. They climb 35 GX up a broadleaf and 30 GX up a cedar, with Z −2 / +8. Cedar is `BugBg.is_cedar`, settled on the first frame.
- **Crawlers** turn along a front wall to `wall.angleY + 90°` (`wall_normal` estimates the wall facing from the unit grid). They dive when the point `bg_range + speed` ahead is water (`water_ahead`), and drown at the surface.
- **Stress** radius is 120 GX + `catch_ME`. The index is `(int)(min_dist − 40 − max(d − 40, 0)) / 20`. It is driven by the player's per-tick move.

| Program | Height | Key rules now matched |
| --- | --- | --- |
| chou (butterflies) | born ground − 30, lands on pansy0 | The outer ring of units (in-block 0 / 15) is the edge. Flower search is unit based (`npc_on`, height < 20, retry ±2). AVOID heads for the acre centre on the ring, otherwise away ±0x1000. Scared by a net or dig within 60 GX. |
| tonbo (dragonflies) | cruise over ground | 240 / 480 GX from the acre centre (banded leaves past 480). Wall / ground deflection escapes on the 4th. Touches water when `game_frame % 100 < 20`. Red dragonflies perch on reserve signs at `center_y + 20`. |
| semi / kabuto / goki (trunk) | 35 / 30 GX up | Scare order: shaken tree → axe in the acre within 150 → stopped net 70 (not the one holding it) → dig 30. Beetle sway table ±4.2°. Cockroach flower y = home + 25, item y = home + 7. |
| hotaru (fireflies) | home + 70 | Acre-centre leash 240. Patience > 90 heads off `player_angle + 180°`. Wall target shift by quadrant. |
| ka (mosquito) | ground + 14 (born −30, lifted by `bg_height`) | Homes in only on a player in its acre and within 60 GX of its height; turns 0x100 within a unit. Hovers inside 20 GX (half a unit) for 180 frames, then bites. |
| tentou (ladybugs, mantis, snail) | ground + 25, re-read every move frame | Move timer `(90 + game_frame % 60)·2`. Scared by a net (70) or dig (60). US build: leaving the flower does not scare (AUS only). The snail leaves only when its unit loses its flower, then slides along walls. |
| amenbo (pond skater) | bed + 14 (gravity to −2) | Stops and turns about when the unit a unit ahead is not water (the pond bank is its wall). Rest 0–59 frames. |
| dango (pill bug, ant) | ground | Appears when the struck unit is its own. Scares (net / dig / axe 70) only once off the rock's unit (`bg_type` 4 → 2). Retires 400 GX from the acre centre. |
| kera (mole cricket) | ground | Wakes on a dig of the unit it is in. Speed re-rolls ±10% every 10 frames. Past 400 GX it burrows on a hole, otherwise runs. |
| mino (bagworm, spider) | ground + 65 | Wakes on a shake of its own tree's unit. Drops away from the player: east +30 / −18 z, or west −30 / −25 z, 6 lower. A second shake swings it as a damped 50 GX s16 pendulum. A felled tree (`BugBg.tree_cut`) drops it. The spider checks the wall behind it. |
| batta (hoppers) | ground; released at player + 40 | Wait `2·(120 + game_frame % 240)`. Scared by a net or dig within 70. Hop turns ±90° off front walls, on release too. |
| hitodama (wisp) | ground or water surface + 40 | Turn rate and timer from the play clock. Past 160 GX from the acre centre, heading within 22.5° of straight away flips the turn. |

**Wiring fixed outside the programs:**

- `rock.gd` now latches `REFLECT_SCOOP` on its unit; before this, pill bugs could never appear.
- `tree.gd` and `hole_use.gd` no longer call `BugField.notify_player_action`. That call released every insect on the cell, so hidden bagworms and mole crickets escaped instead of appearing.
- The probe keys `water_ahead`, `water_below` and `tree_cut` never existed, and programs now use `BugProgram` / `BugBg` queries in their place. Before this, no insect ever dived, dragonflies never touched water and bagworms never fell.

**Deliberate deviations / not ported:**

- The US build sends a netted snail down the flying LET_ESCAPE, which AUS fixed; the port keeps the fix.
- Out of range, `aIBT_chk_active_range` never writes its angle out-parameter (the heading is stack garbage); the port hops back toward the acre centre.
- An ant is its own actor (`ac_ant.c`) that only becomes a dango insect once netted; here it spawns crawling.
- The mosquito sting has no player state (`mPlib_request_main_stung_mosquito_type1`): the bite flags `BIT` and the mosquito leaves at once.
- The ball scare is not ported (there is no ball).
- `mCoBG_CheckHole_OrgAttr` is always false (`BugBg` has no dig-hole tracking), so mole crickets never burrow.
- Batta's `check_live_condition` (rain, height gap and FG-type despawn in the first two frames) is left to the spawner.
- Squash-and-stretch scales, ripples, dirt and light effects are presentation.
- Wall facing is estimated from the unit grid, not from `wall_info[].angleY`.
