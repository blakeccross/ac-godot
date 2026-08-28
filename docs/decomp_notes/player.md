# Player

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not copy the player actor struct or `mPlayer_INDEX_*` table into GDScript.

**Read before implementing:** player scene movement, tool use, talk lock, indoor furniture contact.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_player.h` | Main-index enum (~100 modes), joints, addressable flags, debt constants |
| `include/m_player_lib.h`, `src/game/m_player_lib.c` | `mPlib_request_main_*` — other systems ask the player to change mode |
| `src/game/m_player_main_walk.c_inc` | Analog walk vs run: **4.875** vs **7.5** |
| `include/m_controller.h` | Stick `move_pR` / `move_angle` |
| `include/m_private.h` | Persistent player: pockets, cloth, birthday, equipment |
| `include/m_camera2.h` | Follow / talk / door cameras |

Key functions: `mPlib_request_main_talk_type1`, `mPlib_request_main_wait_*`, `mPlib_request_main_hold_type1`, `mPlib_request_main_give_type1`, `mPlib_get_player_actor_main_index`, `mPlib_Check_able_force_speak_label`.

## What does the original system do?

The player is a single actor with a **main index** state machine. Movement, tools, doors, furniture, demos, and talk are mutually exclusive modes (`mPlayer_INDEX_WAIT`, `WALK`, `RUN`, `DASH`, `PICKUP`, `SWING_AXE`, `READY_ROD` … `TALK`, `SHAKE_TREE`, …). Other systems never poke bones directly; they **request** a mode via `mPlib_request_main_*`.

Stick magnitude picks walk vs run (normalized against 7.5 run, 4.875 walk). Sprint/dash is a further index. Wade, snow, and furniture push have their own modes.

`mPlayer_ADDRESSABLE_*` gates whether NPCs may start dialogue: false while moving, talking, or holding a ready net.

Appearance (cloth, face) and inventory live in `Private_c`, not the actor. Equipped item is `Private_c.equipment`. House debt tiers are named constants (`mPlayer_DEBT0` … `DEBT4`) used by Tom Nook, not by locomotion.

## Important states

- **Main index** (current action).
- Requested next index (pending `request_main_*`).
- World position / facing; forced position flags for cutscenes.
- **Addressable** (can be talked to).
- Held / equipped item; tool-specific substates (rod ready/cast/vib, net ready/swing).
- Indoor furniture contact (push, pull, rotate, sit, lie on bed).
- Demo lock (`DEMO_WAIT`, train, boat).
- Tired / stung / pitfall (interrupt locomotion).

## Inputs

- Controller stick + face buttons (A interact, B cancel/put away, Y/Start inventory).
- Collision heightfield and water attributes.
- Requests from NPC, submenu, shop, fishing bobber, insect catch.
- Scene transitions (door, outdoor, invade other house).

## Outputs / events

- Position updates for camera and acre streaming.
- Animation / tool traces (net swing volume, axe on tree, scoop dig).
- Mode changes that spawn FG items (drop), consume durability, or start `m_msg`.
- BGM volume ducking while fishing or catching bugs (`mPlayer_BGM_VOLUME_MODE_*`).
- “Player acted on this unit” timestamps for insects (`aINS_PL_ACT_SHAKE_TREE`, scoop, axe).

## Interacts with

- **World** — collision, doors, wade.
- **Interaction / inventory** — pickup, present, give, tag menus.
- **Dialogue / villagers** — talk request + camera.
- **Furniture** — hold, push/pull/rotate, sit/lie, open storage.
- **Fishing / bugs / plants** — rod, net, axe, scoop, shake.
- **Shops** — receive/give at counter.
- **Save** — `Private_c` (not the live actor pose).

## Reproduce

- **Walk vs run** from analog magnitude; a sprint modifier.
- One **locked action** at a time (cannot walk-and-fish; talk freezes locomotion).
- Interact from a facing tile, not a 360° magnet.
- Put-away / cancel for tools.
- Door enter/exit as a short locked anim, then scene change.
- Outdoor camera follow; tighter camera when talking.

## Simplify

- Collapse the 100+ indices into a small Godot state machine: idle, move, interact, tool, talk, menu, scene-transition.
- One tool animation set per tool, not air/reflect/broken variants for every item.
- Ignore dash-turn, tumble, umbrella, fan, snowball as first-slice locomotion.
- Meter-scale speeds from the 4.875 / 7.5 per-frame values: one 40-unit tile is one 2 m cell, so walk is 7.31 m/s and run 11.25 m/s relative to the acre.

## Ignore

- Train, boat, island wade demos.
- Radio calisthenics, golden axe/item demos, shrine throw-money / pray.
- Pitfall, bee/mosquito sting sequences, groundhog, wash-car.
- Sunburn ranks, reset count, e-Card letters.
- Multi-player house invade (`INVADE`) and four-save-slot character switching until multiplayer is in scope.
- Joint-level face/mouth texture swapping (`mPlib_Get_PlayerEyeTexAnimation_p`).
