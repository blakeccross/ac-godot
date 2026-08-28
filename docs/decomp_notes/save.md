# Save (persistence, slots, what is stored)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — **do not** port `Save_s` or `Common_Get` as one Resource.

**Read before implementing:** `SaveService`, JSON under `user://`, what to persist per slice.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_common_data.h` | `Save_s` — almost the entire game |
| `include/m_private.h` | Per-player `Private_c` (4 slots, `PLAYER_NUM`) |
| `include/m_card.h`, `src/game/m_card.c` | Memory card files, copy protect, travel |
| `include/m_flashrom.h` | Checksum, version (`mFRm_VERSION` 6), error enum |
| `include/m_start_data_init.h` | Boot: new town, new player, load, error |
| `include/m_land.h` | Town name / land id |
| `include/m_home_h.h` | Houses inside save |
| `include/m_npc.h` | `animals[]` |

Init modes: `mSDI_INIT_MODE_NEW`, `NEW_PLAYER`, `FROM` (load), `PAK`, `ERR`. Card files include main, backup, mail, original designs, diary, present, player (`mCD_FILE_*`). Land save size is huge (`mCD_LAND_SAVE_SIZE` 0x72000). Copy protect is a land id in `[1, 65520]`.

## What does the original system do?

One **town save** holds everything: four player privates, land name, noticeboard, four houses, the 5×6 FG grid, acre combination table, 15 villagers, shop, turnips, post office, police box, snowmen, island, needlework, museum, events, fish records, insect/fish terms, grow renew time, etc.

A **checksum + version + land id + timestamp** header (`mFRm_chk_t`) detects corruption. Memory card code handles Slot A/B, not enough space, travel data conflict, foreigner arriving with a player file.

Runtime `Common_Get` is the live copy of that blob plus clips (actor function tables) that are **not** saved.

New game (`mSDI_StartDataInit` / `mFM_InitFgCombiSaveData`) generates the town. Adding a player initializes one `Private_c` without wiping the town.

## Important states

- File exists vs new.
- Header valid vs corrupt vs outdated.
- Which of 4 player slots is active (`exists` byte on `Private_c`).
- Scene id to resume (`scene_no`).
- Copy-protect / travel flags (multi-pak).
- Backup file vs main.

## Inputs

- Explicit save (house, exit, periodic — original saves at many transitions).
- New town / new player flow.
- Memory card status (Godot: filesystem).

## Outputs / events

- Loaded `Save_s` into common data **or**, in this project, split documents into systems.
- Error screens (`mFRm_ERROR_*`).
- Backup written.
- Player-select if multiple `exists`.

## Interacts with

Every system that has durable state: **time, world FG, inventory, villagers, shop, house, calendar, museum, island**. Clips and actors are rebuilt on load.

## Reproduce

- **Save/load** of: clock, player position/scene, pockets + wallet, town name, FG deltas (trees/items), villager friendship/schedule pointers, shop stock if present.
- New game initializes defaults; load restores them.
- Fail gracefully if JSON is missing or invalid (do not crash).
- Single player slot is enough for now.

## Simplify

- JSON (or Godot `ConfigFile`) keyed by system, **not** one packed blob.
- One player, one house, one acre’s FG.
- Save on a explicit action and/or leaving the session (Phase 1 already has U/I debug save).
- No checksum theater beyond “parse failed”.
- No Slot A/B, travel briefcase, or backup file pair.

## Ignore

- Memory card UI, banners, icons, `mCD_SAVE_DATA_OFS`.
- Copy protection and foreigner start conditions (`mCD_START_COND_*`).
- Diary, original design, present, and standalone player-pak files.
- Island save, GBA, e-Reader.
- `m_flashrom` error codes except as product inspiration for “save failed”.
- Noticeboard, police lost-and-found, snowmen, museum bitfields until those systems exist.
- Emulating `scene_no` integer tables; store a Godot scene path or acre id.

## Godot mapping reminder

`SaveService` should keep writing **ids and counts**, not packed C layouts. When a new system earns persistence, add a keyed section and cite the decomp field it corresponds to in that system’s note — do not grow a `CommonData` singleton.
