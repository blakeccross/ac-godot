# Villagers (NPCs, schedules, friendship)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not copy `Animal_c` or looks tables into GDScript.

**Read before implementing:** `VillagerData`, `VillagerPersonality`, `VillagerState`, `VillagerSchedule`, `ScheduleData`, villager scene, one greeting.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_npc.h`, `src/game/m_npc.c` | Town roster, memories, mood, move-in/out |
| `include/m_npc_schedule.h`, `include/m_npc_schedule_h.h`, `src/game/m_npc_schedule.c` | Daily looks tables |
| `include/ac_npc.h` | Runtime NPC actor |
| `include/m_npc_walk.h` | Pathing / wandering |
| `include/m_quest.h` | Deliveries and errands tied to villagers |
| `include/m_event.h` | Special NPC event states |

Key functions: `mNPS_schedule_manager`, `mNPS_get_schedule_area`, `mNpc_AddFriendship`, `mNpc_GetAnimalNum`, `mNpc_CheckRemoveExp`.

Constants: `ANIMAL_NUM_MIN` **5**, `ANIMAL_NUM_MAX` **15**, `ANIMAL_MEMORY_NUM` **7** player memories per villager.

## What does the original system do?

Up to 15 villagers live in town (`animals[]` in save). Each has a species/personality id, home acre/unit, catchphrase, cloth, and **per-player memory** (last speak time, friendship `s8`, saved letter).

A global **schedule manager** ticks all animals. Looks (personality/species group) select a table of `{type, end_time}` slots. Types:

- `mNPS_SCHED_SLEEP`
- `mNPS_SCHED_IN_HOUSE`
- `mNPS_SCHED_FIELD` (home acre)
- `STAND` / `WANDER` / `WALK_WANDER`
- `SPECIAL` (unique actor scripts)

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
- Talk updates last-spoke and a simple friendship number.
- Not on the acre when sleeping or indoors (or visibly in bed later).
- Greeting differs by time of day / whether you’ve already talked (can be a flag, not full memory struct).
- Yard wander while the schedule type is field (NavigationAgent3D; stay near home).

## Simplify

- Looks tables for all six personalities as data; Pip uses the lazy (boy) table. No per-villager AI scripts.
- No wander-the-whole-town pathing; stay on one acre or teleport between house and yard.
- Friendship as an int 0–255 (or 0–100) without letter scoring.
- Skip villager–villager relation matrix.
- Skip move-out lottery and “return visitor” (`Anmret_c`) until the town has more than one animal.

## Ignore

- Islanders, mask cats, 5 event NPCs, special NPCs (resetti, kettle, etc.) until a slice needs them.
- HP password mail, Able Sisters cloth ids, umbrella ids.
- Contest quests, holiday mail (Valentine / White Day).
- `SPECIAL` schedule programs per actor overlay.
- Mechanical translation of `m_npc_walk` waypoint graphs.
