# Villagers (NPCs, schedules, friendship)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not copy `Animal_c` or looks tables into GDScript.

**Read before implementing:** `VillagerData`, `VillagerPersonality`, `VillagerState`, `VillagerSchedule`, `ScheduleData`, `ActivityKind`, `VillagerAI`, villager scene, one greeting.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_npc.h`, `src/game/m_npc.c` | Town roster, memories, mood, move-in/out, **new-town pick** |
| `include/m_npc_schedule.h`, `include/m_npc_schedule_h.h`, `src/game/m_npc_schedule.c` | Daily looks tables |
| `include/ac_npc.h`, `src/actor/npc/ac_npc_schedule*.c_inc` | Runtime NPC actor + field / in-house / sleep steps |
| `include/m_npc_walk.h`, `src/game/m_npc_walk.c` | Goal acres while in the field (shrine / home / alone) |
| `include/m_quest.h` | Deliveries and errands tied to villagers |
| `include/m_event.h` | Special NPC event states |

Key functions: `mNPS_schedule_manager`, `mNPS_get_schedule_area`, `mNpc_AddFriendship`, `mNpc_GetAnimalNum`, `mNpc_CheckRemoveExp`, `mNpc_InitNpcAllInfo`, `mNpc_DecideLivingNpcMax`, `mNpc_MakeRandTable`, `mNpc_SetNpcHome`.

Constants: `ANIMAL_NUM_MIN` **5**, `ANIMAL_NUM_MAX` **15**, `ANIMAL_MEMORY_NUM` **7** player memories per villager.

## What does the original system do?

Up to 15 villagers live in town (`animals[]` in save). Each has a species/personality id, home acre/unit, catchphrase, cloth, and **per-player memory** (last speak time, friendship `s8`, saved letter).

**New town** (`mNpc_InitNpcAllInfo`): `now_npc_max = mNpc_LOOKS_NUM` (**6**). `mNpc_DecideLivingNpcMax` shuffles the full NPC id table (`mNpc_MakeRandTable`), then walks it and keeps animals whose grow permission is `mNpc_GROW_STARTER` until **one of each looks** is filled. Homes are a second shuffle of SIGN reserves (`mNpc_SetNpcHome`).

A global **schedule manager** ticks all animals. Looks (personality/species group) select a table of `{type, end_time}` slots. Types:

- `mNPS_SCHED_SLEEP`
- `mNPS_SCHED_IN_HOUSE`
- `mNPS_SCHED_FIELD` (home acre)
- `STAND` / `WANDER` / `WALK_WANDER`
- `SPECIAL` (unique actor scripts)

The field type is a **step machine**, not a single wander loop: leave house (hidden) → wander. If they are already outside (`is_home == FALSE`), skip leave and wander immediately. Wander think **does not end** until the schedule type changes (or a pitfall interrupt). Each wander step rolls wait / walk / run from looks weights and walks to a dest on a circle around the **acre center** (`range_radius` 280 GX), snapped off HOUSE/TREE. That dest is kept until arrival. Arrival compares dist² to **72 GX** (~0.42 m); a dest more than 90° behind is a turn in place. Hitting a wall is avoid / turn / wait, then a new point — they do not grind a collider. In-house is go home → into house → hide. Sleep hides when `is_home`. While in the field, `m_npc_walk` picks a goal acre from looks-based `{shrine, home, alone, my_home}` tables. Assigned walkers (cap `n/3`) walk toward that acre; everyone else keeps wandering their current acre.

The table can be **forced** for a timer (events, talking). `is_home` on `Animal_c` tracks whether they are inside.

Friendship changes on talk, mail, quests, and annoyances (patience: mildly annoyed / annoyed / normal). Mood (`mNpc_FEEL_*`: normal, happy, angry, sad, sleepy, pitfall) lasts for a `mood_time`. Inter-villager relations are a 15-byte matrix starting at 128 (neutral).

Move-out: `removing`, `remove_animal_idx` on save, minimum days before force removal (`mNpc_MINIMUM_DAYS_BEFORE_FORCE_REMOVAL` 10). Special NPCs use id type `0xD000`.

## Important states

- Roster occupancy vs empty slots.
- Schedule type + forced override.
- Position: in house, home acre, wandering town.
- Friendship per player; last speak time.
- Mood and patience.
- `removing` / last removed id.
- Contest quest slot on the animal.

## Inputs

- Clock (seconds, weekday, season).
- Player talk / mail / gift / hit with net (patience).
- Town events (holidays, tours).
- Save load of `Animal_c` array.

## Outputs / events

- Desired location for the NPC actor (house interior vs field).
- Dialogue personality and available quests.
- Friendship delta.
- Move-in/move-out flags for loading houses and plots.
- “In house” for knocking vs entering.

## Interacts with

- **Time** — schedule tables.
- **World** — home coordinates, field vs room.
- **Player / interaction** — addressable talk.
- **Dialogue** — message ids, catchphrase substitution.
- **Inventory / quests** — deliveries.
- **Furniture** — NPC rooms are a field type with placed FTR.
- **Save** — `animals[]`, `now_npc_max`, `remove_animal_idx`.

## Reproduce

- **One villager** with a daily table: sleep, indoors, outdoors, with hour boundaries. Looks (personality) selects the table; the actor is shared.
- New game fills **six** outdoor villagers: shuffle the starter pool, keep one of each looks, assign to the six NPC houses.
- Field day is a reusable action queue: wake / leave home / walk to goal acre / wander / go home / sleep. Wander **loops** for the whole FIELD window (wait / walk / run around the acre). Sit / fish / shop are not the FIELD default.
- While in the field, pick a goal acre from looks+time (`shrine` / other `home` / `alone` / `my_home`). Walkers go there, linger in-acre, then pick a new goal. Concurrent town-walkers cap at `n/3` (max 5). Empty goal-table windows stay on the home acre. Non-walkers still wander their home acre; they do not stand at the door.
- Species GLB (`squ_1`, `cat_1`, …) + shared `npc_1` wait/walk when `assets/generated/characters/villagers/` exists. Display names use the original villager names.
- Talk updates last-spoke and a simple friendship number.
- Not on the acre when sleeping or indoors (or visibly in bed later). Walking home/out is still visible.
- Greeting differs by time of day / whether you’ve already talked (can be a flag, not full memory struct).

## Simplify

- Looks tables for all six personalities as data. Filbert uses the lazy (boy) table (`data/schedules/pip_weekday.tres`).
- Shared activity runner (`VillagerAI` + reusable `ActivityKind` steps). Not per-villager AI scripts and not `aNPC_think_*` overlays. Wander wait/walk/run weights and acre-center radius come from that think, encoded as data on `VillagerWalk`.
- Field goals use `mNpcW_GOAL_*` kinds and acre picks. Full-town walks the route; no acre-edge appear/streaming and no gate waypoint graphs. Stay-in-acre then new goal is ~28s, not the original 30-minute arrive counter. Wander dests sit on the 280 GX acre circle (snapped off house/tree). Arrive uses √72 GX so a walk covers the rim, not one cell. Display names use the original villager names; meshes are disc species GLBs (`squ_1`, `cat_1`, …) when converted.
- Friendship as an int 0–255 (or 0–100) without letter scoring.
- Skip villager–villager relation matrix.
- Skip move-out lottery and “return visitor” (`Anmret_c`). New towns stay at six starters (one looks each).

## Ignore

- Islanders, mask cats, 5 event NPCs, special NPCs (resetti, kettle, etc.) until a slice needs them.
- HP password mail, Able Sisters cloth ids, umbrella ids.
- Contest quests, holiday mail (Valentine / White Day).
- `SPECIAL` schedule programs per actor overlay.
- Mechanical translation of `m_npc_walk` waypoint graphs.
