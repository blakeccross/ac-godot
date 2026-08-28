# Bugs (insects)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not ship original insect names as content.

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

A controller actor holds **9** `aINS_INSECT_ACTOR` slots. Each has type, patience, life timer, tile (ut_x, ut_z), and a **program** (flight vs hop vs tree-sit vs water skater, etc.). Spawns depend on **insect term**, hour, weather, and habitat (flower, tree, rock, light, trash, water).

The player holds a net, approaches, and swings. Catch converts the actor to an insect item in pockets. Bees can sting (`STUNG_BEE`). Mosquitoes have their own sting. Some bugs flee when the player runs, shakes a tree, or digs nearby (`aINS_PL_ACT_*`).

Wisp/spirit is an extended type (`aINS_INSECT_TYPE_SPIRIT`), not a pocket insect. Cockroaches spawn in dirty houses via `m_cockroach`. Ants can spawn from leftover items (`make_ant_proc` exists but is unused in AC).

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

## Reproduce

- Spawn a visible bug on a valid habitat.
- Net swing has a catch volume in front of the player.
- Miss → bug flees; patience so it is not trivial.
- Success → item in pocket.
- Full pockets → cannot keep.

## Simplify

- One family (e.g. flying) and 2–3 fictional bugs.
- 1–2 concurrent spawns, not 9.
- Skip bees, mosquitoes, cockroaches, wisps, water striders.
- Patience as a single flee-on-approach radius.
- No overlay DMA programs (`aINS_PROGRAM_*`).

## Ignore

- All 40 species and island exclusives.
- Museum insect room treadmill.
- Firefly point lights (`Lights point_light` on the actor).
- Ant leftover-food spawns.
- GBA transfer of insects.
