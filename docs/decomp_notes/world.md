# World (acres, terrain, rooms)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not copy C structs, `Common_Get` blobs, or overlay tables into Godot.

**Read before implementing:** `AcreData`, outdoor acre scene, collision, indoor rooms.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_field_make.h`, `src/game/m_field_make.c` | Town grid, acre types, FG item arrays, `mFM_FieldInit` |
| `include/m_field_info.h`, `src/game/m_field_info.c` | World-size constants, field-id types, position → acre/unit queries |
| `include/m_collision_bg.h` | Per-unit height, plant-growth caps, surface attributes, furniture footprints |
| `include/m_bg_item.h` | Runtime FG (foreground) item actors on the field |
| `include/m_bg_type.h` | Terrain type ids |
| `include/m_scene.h` | Outdoor vs room scene kinds; door direction |
| `include/m_camera2.h` | Follow camera (`CAMERA2_PROCESS_NORMAL`, talk/door/wade variants) |
| `include/m_random_field.h` | Town generation / acre combination |
| `include/m_land.h` | Town name and land id |

Key functions: `mFM_FieldInit`, `mFM_InitFgCombiSaveData`, `mFI_Wpos2BkandUtNuminBlock`, `mFI_Wpos2UtNum`, `mFI_GetFieldId`, `mFI_CheckShop`, `mBI_change_bg_item`.

## What does the original system do?

The town is a **7×10 block** grid (`BLOCK_X_NUM` × `BLOCK_Z_NUM`). The playable outdoor field is the inner **5×6** foreground acres (`FG_BLOCK_X_NUM` × `FG_BLOCK_Z_NUM`); the rest are cliffs, tracks, and borders.

Each acre is a **16×16 unit** grid (`UT_X_NUM`). One unit is **40 world units** (`mFI_UNIT_BASE_SIZE`). An acre is therefore 640×640 in original space.

Every unit can hold a **foreground item** (tree, flower, buried item, dropped furniture, etc.) stored in save as `mFM_fg_c fg[6][5]`. Acre *shape* (river, cliff, house plot) is stored separately as a **combination table** `combi_table[10][7]`.

Field ids encode type + index (`mFI_TO_FIELD_ID`): outdoor FG, public rooms (shop, post office, museum wings), NPC houses, demos, and four player houses.

Only **four acres** nearest the player are considered visible (`mFM_VISIBLE_BLOCK_NUM`). Collision is a heightfield plus attributes (grass, soil, water, river direction, sand, hole, bush).

## Important states

- Current **field id** (outdoor vs which room).
- Player **block (bx, bz)** and **unit (ut_x, ut_z)**.
- Per-acre combination / terrain kind (flat, river, cliff, player house, station, … — large `mFM_BLOCK_TYPE_*` enum).
- Per-unit FG item id and collision attribute / plant-growth cap (`mCoBG_PLANT0`–`PLANT4`, `KILL_PLANT`).
- Scene kind: outdoors, my room, NPC room (`mSc_ROOM_TYPE_*`).
- Camera process: normal, wade, talk, door, demo (`CAMERA2_PROCESS_*`).

## Inputs

- Saved combination table + FG item grid.
- Player world position (for acre streaming, unit queries, camera).
- Season / climate (`mFM_toSummer` / `mFM_returnSeason`; island climate forces a fixed term).
- Door / scene change (enter house, shop, acre edge).

## Outputs / events

- Loaded terrain and FG actors for nearby acres.
- Collision height and walkability.
- “You are in shop / player room / NPC room” checks used by inventory tags and NPC AI.
- Camera target and FOV (outdoor follow is ~20° FOV, 3/4 view; see `Init_Camera2`).
- Daily FG renewal is *not* this module; plants call `mAGrw_RenewalFgItem` from time.

## Interacts with

- **Time** — seasonal acre palettes / cedar vs deciduous swaps.
- **Player** — walk, wade, door enter/exit.
- **Plants / items** — FG slots.
- **Furniture** — indoor field type + unit footprints.
- **Villagers** — home acre coordinates; “in field vs in house”.
- **Shops** — shop room field ids (`mFI_FIELD_ROOM_SHOP0` … `SHOP3_2`).
- **Save** — `fg`, `combi_table`, `land_info` inside `Save_s`.

## Reproduce

- Discrete **acres** made of a unit grid, not a free-form open world.
- One acre on screen at first; later, load neighbors.
- Outdoor **3/4 camera**, ~20° FOV, follow the player.
- Collision that distinguishes **walkable grass**, **water** (wade / fish), and **blocked**.
- Indoor vs outdoor as separate scenes, not one giant mesh.
- Dropped / grown items occupy **tiles**, not arbitrary floats.

## Simplify

- One authored acre instead of generating a 5×6 town from combination tables.
- No 4-acre visibility window or GameCube overlay streaming.
- No full river/cliff/bridge combination solver (`m_random_field`).
- Scale 40-unit tiles to Godot meters; keep *relative* acre size, not the integer 40.
- One indoor room type to start (player house), not museum wings / lighthouse / tent.

## Ignore

- Island BG restore (`mFM_RestoreIslandBG`), police-box special FG, dump/station acre variants until needed.
- All 293 BG mesh ids and 12 field palettes as a content treadmill.
- Demo fields (`mFI_FIELD_DEMO_*`), title-screen towns.
- Copy-protect land id behavior beyond “town has a name”.
- Perfect acre-edge wade camera (`CAMERA2_PROCESS_WADE`).
