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

## Behavior

- **Save/load** of: clock, player position/scene, pockets + wallet, town name, FG deltas (trees/items, including stumps), villager friendship / relationships, interior furniture/wall/floor, shop stock if present.
- New game initializes defaults; load restores them. Fail gracefully if JSON is missing or invalid.
- JSON (or Godot `ConfigFile`) keyed by system, not one packed blob. One player, one house, one acre's FG, one save slot.
- Save on an explicit action and/or leaving the session. No checksum beyond "parse failed". No Slot A/B, travel briefcase, or backup file pair.
- `scene_no` is a Godot scene path or acre id, not an integer table.

## Importing an original save

The title screen's **Import GameCube Save** brings a USA (`GAFE`) town over from the user's own Memory Card dump: a Dolphin `.gci` export of `DobutsunomoriP_MURA`, or a whole `.raw` card image. It writes a normal JSON save into slot A or B, asking before it replaces a town.

- `GameCubeCard` finds the town file: a GCI is a 0x40-byte directory entry then the blocks. A card image keeps two directory copies (blocks 1–2, update counter at 0x1FFA) and two allocation tables (blocks 3–4, counter at 0x04, next-block map at 0x0A indexed by block − 5). The newer copy wins.
- `GameCubeTown` reads the file's three 0x26000-byte areas (letters/designs, `mCD_FILE_SAVE_MAIN`, its backup). It takes the first copy that passes `mCD_LoadLand`'s check (code `GAFE`, version 5 or 6, every big-endian u16 summing to 0) and decodes only what is carried over. Names use the game's own font table (`ac_msg_codec.json`).
- `TownImport` maps that onto this game's save:
  - Town name, id, tune, fruit, grass, statues.
  - The acre map (`combi_table` words → `FieldObjectCatalog.combi`, from `data_combi.c` via the FG pipeline) and every unit's item, kept as `TownState.imported_field`. `WorldGenerator` copies those in place of the random FG picks and skips the new-town steps that already happened (border-tree pull, fruit/cedar swap, starter beds and villagers).
  - Weeds, items lying out and buried things (`deposit` bits) go into `TownState`'s own records.
  - Villagers keep their homes: `home_info` is one unit south of the SIGN unit, with 1-based blocks.
  - Each resident's name, gender, face, shirt, pockets, wallet, savings, loan and house (plot from `house_arrangement`, size, basement, statue, roof).
  - House rooms: wallpaper, carpet and placed furniture (main / upper / basement), facing kept; layers 1–3 at a furniture cell become storage (`st`), and `ftr_switch` bits become `on`.
  - Villager friendships: each animal's `Anmmem_c` for that resident (friendship, last-spoke day, letter flags).
  - Letters (pocket + house mailbox + post office desk), player and Able Sisters designs, catalog bitfields and mail orders, fish/insect species log, museum display nibbles, Nook's goods/level/sales and the stalk market, police lost-and-found, notice board posts, lighthouse quest, rainbow reservation, second bridge, snowmen, fish tourney records, house gyroid stock/message, music box and cockroach count.
- Not carried: the island FG, event schedule blobs, and anything this game has no system for. Items or villagers this game does not have are left behind and counted in the notice.

## Godot mapping reminder

`SaveService` should keep writing **ids and counts**, not packed C layouts. When a new system earns persistence, add a keyed section and cite the decomp field it corresponds to in that system’s note — do not grow a `CommonData` singleton.
