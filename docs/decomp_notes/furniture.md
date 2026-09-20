# Furniture (house, rooms, placeable FTR)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not copy `FTR_ACTOR` or per-item `aFTR_PROFILE` tables.

**Read before implementing:** `FurnitureData`, `FurnitureUse`, `House`, `Room`, `FurniturePlacement`, interior scene, place/pick/rotate.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_home.h`, `include/m_home_h.h` | House size, rooms, mailbox, cottage |
| `include/ac_furniture.h` | Runtime furniture actor: push/pull/rotate, interaction bits |
| `include/m_room_type.h` | Footprint 1×1 / 1×2 / 2×2; birth (source) types |
| `include/m_collision_bg.h` | `mCoBG_FTR_TYPEA/B/C` footprints and facing |
| `include/m_ftr_def.h` | Huge FTR name enum (content catalog, not architecture) |
| `include/f_furniture.h` | Per-item profile symbols (`iam_*`) |
| `include/ac_arrange_ftr.h` | Placement helper actor |
| `include/m_scene_ftr.h` | Scene-placed furniture |
| `include/m_player.h` | `HOLD`, `PUSH`, `PULL`, `ROTATE_FURNITURE`, `SITDOWN`, `LIE_BED`, `OPEN_FURNITURE` |

Key functions: `mHm_InitHomeInfo`, `mHm_SetBasement`, `mHm_KeepHouseSize`. Interaction macros: `aFTR_IS_STORAGE`, `aFTR_CHECK_INTERACTION`.

## What does the original system do?

Each of **4 players** has a house (`homes[PLAYER_NUM]`). Rooms: **main, upper, basement** (`mHm_ROOM_*`). Size tiers: small → medium → large → upper (with basement) → statue (`mHm_HOMESIZE_*`), driven by paying Nook debts (`mPlayer_DEBT*`).

Furniture lives on the indoor **unit grid** with a footprint and facing. The furniture **actor** runs a state machine: idle, wait-push, push, pull, rotate L/R, birth (place anim), bye/death (pick up). Contact actions: chairs (one-way, multi-way, sofa), beds, storage.

Interaction bitflags on the profile: drawers, wardrobe, closet, music disk, gyroid, displayed fish/insect, mannequin, umbrella stand, fossil, Famicom, toggle (TV), radio aerobics, no-collision.

Storage furniture keeps extra item slots (`aFTR_KEEP_ITEM_COUNT`). Gyroids have their own on/off state. Wall and carpet are room properties, not FTR actors (`mTG_TYPE_ROOM_WALL` / `ROOM_CARPET` in inventory tags).

NPC houses are a different field type with a pre-arranged FTR set from villager data, not the player’s `mHm_hs_c`.

## Important states

- House size / which rooms exist.
- Per-room item grid + wall/floor ids.
- Each placed FTR: id, unit, facing, actor state (moving vs settled).
- Storage contents.
- Player mode: holding furniture vs sitting vs opening.
- Upgrade order date (Nook construction delay).

## Inputs

- Inventory “place in room” vs “pick up”.
- Player push/pull/rotate while contacting a piece.
- Sit / lie if the profile allows.
- Open storage → nested inventory.
- Shop / catalog granting FTR ids.
- Debt payoff → `mHm_SetBasement` / size flags.

## Outputs / events

- Occupied units (collision + placement rules).
- Player locked into furniture move or sit.
- Storage transfer to/from pockets.
- Save of the room grids.
- Optional toggle visuals (TV on/off).

## Interacts with

- **World** — `mFI_FIELDTYPE_PLAYER_ROOM` / NPC room.
- **Player / interaction**.
- **Inventory** — place, pick, storage, wall/carpet.
- **Shops** — furniture as goods kind `mSP_KIND_FURNITURE`.
- **Save** — `mHm_hs_c`.
- **Audio** — music players, gyroids (later).

## Behavior

- Indoor **tile grid** (`WorldGrid`); furniture occupies 1×1 / TYPEB 2×1 (`TYPEB_0` extra +X, facing rotates occupancy) / TYPEC 2×2 always SE of the stored cell (`mRmTp_size_l_data`; facing rotates the mesh only, `aMR_angle_table`). cKF storage stays closed at rest (`cKF_SkeletonInfo_R_init_standard_stop` speed 0). Draw scale follows `aFTR_PROFILE.scale` (modern chair 0.1). Mannequins use `obj_shop_manekin` plus a player shirt, not a unique `int_fmanekin` skeleton.
- Place from inventory onto an empty footprint (or onto a table for small items, or against a wall for wall pieces) with A. Contents of storage / displays return to pockets before a piece is picked up.
- **Handling** (`FurnitureGrip`, `ac_my_room_move.c_inc` / `_action.c_inc`), player's own house only: A against a piece grips it (`hold_type1`). While A stays down: stick **into** it for >16 ticks pushes it one unit, stick **away** pulls it one unit (the player backs up with it and needs the unit behind clear), stick **sideways** turns it 90° — one turn per flick, stick has to return to neutral (`allow_rotation_flag`). Full stick only (magnitude ≥ 0.8, axis component > 0.8, so diagonals do nothing). A blocked attempt "puffs" (`bubu`) and needs the stick released. A **tap** (A released within 14 ticks) is the ordinary verb: open drawers / wardrobes / music players only from the piece's front (`contact_direction`), switches from any side.
- **Turning** pivots on the end being held. A 2×1 piece swings through the two cells beside the pivot (`rotate_forbid_table`) — furniture, walls and the player block it; 1×1 and 2×2 spin in place. Items on a table ride along on every move and turn (`aMR_RequestItemToFitFurniture`). `check_rotation` pieces jam against each other (`aMR_SearchNextSituation`, implemented for 1×1 / 2×2 only).
- **Pick up** is **B** (`Player_actor_CheckController_forPickup` is `chkTrigger(BUTTON_B)`; B is also run, here `sprint`): the unit in front within 56 GX, the small piece on it first.
- **Sit / lie down** (`FurnitureSeat`, `aMR_SitDownFurniture` / `aMR_JudgeGoToBed`) are not verbs: hold the stick straight into a chair from an accepted face for >14 ticks (15° tolerance; 4-way chairs from any face, others from the front only) or across a bed's long side (35°). Any stick gets you up; a chair puts you 35 GX in front of it, a bed back where you came in. Works in every room.
- **Room limit** (`aMR_GetSceneFurnitureMax`): main floor 32 / 48 / 64 / 64 by size, upstairs 48, basement 64; table items count.
- Not ported: the `bubu` dust effect, rolling between aligned beds (`mPlayer_BED_ACTION_ROLL`), the 2×1 friction table, and the furniture birth / bye leaf effects.
- Wall and floor as room fields (`Room.wall_id` / `floor_id`); wallpaper and carpet items apply those ids from the pocket menu.
- One furniture actor script. `FurnitureData` carries model, icon, footprint/shape, rotation, placement (floor / table / small / wall), and kind; `FurnitureUse` reads those fields. Disc FTR indexes map to `int_*` visual ids; `ItemCatalog.furniture_for_visual` infers kind when no `.tres` exists. Shared `iam_hnw_common` picks `int_hnw001`–`int_hnw127` from `FTR_HNW_COMMON000` (`ac_hnw_common.c`).
- Storage: `KEEP_SLOTS` (3) on dressers / stereos. Toggle is on/off state + a notice.
- Enter/exit and every indoor field id: [interiors.md](interiors.md).

## Storage, music players, gyroids (`ac_my_room_msg_ctrl.c_inc`)

- **Profiles from the disc.** `tools/asset_pipeline/furniture_profiles.py` reads every `aFTR_PROFILE` (`src/furniture/ac_*.c`) into the gitignored `assets/generated/environment/fg/furniture_profiles.json`; `FurnitureData.apply_profile` derives footprint, sit / bed contact, storage type, music player, radio, gyroid, `starts_off` and `reacts_to_switch` from it instead of guessing from the visual's name (name guesses remain the fallback). Regenerate with `build_assets.py fg`.
- **Chests** (`FurnitureStorage`, `FurnitureTalk`): a tap from the front opens the piece (`kagu_open_{h,k,d}1` = drawers / wardrobe / closet) and the conversation follows the contents — empty: put in / close; one or two: put in / take out (two asks which); three: only "which to take out". Put-in opens the pockets (`Game.request_storage_putin`, tag "Put in"); full pockets and nothing-to-put have their own messages; the door shuts afterwards. Visitors in a villager's house only hear what is inside. Three slots (`aFTR_KEEP_ITEM_COUNT`).
- **Music players** (`FurnitureMusic`, `MinidiskCatalog`): one song per player. A disc put in joins the house's music box (`House.music_box`, 55 bits, saved as a string) and is used up; a disc the box already has stays in your pocket. The "music box" answer steps through owned songs and plays one. Only one player (or the aerobics radio, `sportsfair_aerobics`, front only) sounds at a time and replaces the room BGM (`Interior.refresh_bgm`). Song *i* is `BGM_MD0 + i` (bgm 128 + i).
- **Gyroids** hop when tapped (`aMR_HaniwaSwitchOn`); their voices need jaudio samples the pipeline does not produce.
- Not ported: song titles (discs are "K.K. Song NN" until the item-name table is extracted), where discs come from (K.K. Slider's concert — use `give minidisk_NN`), the Famicom emulator flows, Tortimer / lovely phone / tanabata palm one-liners (`HITOKOTO`), the diary calendar, lit-window state, and non-owner disc toggling in villager houses.

## House cockroaches (`m_cockroach.c`, `ac_house_goki.c`, `ac_my_room_goki.c_inc`)

- **Moving in** (`HouseGoki`): stay away more than 6 days and, when the game starts, one roach per day past the sixth moves in (a house that already has some adds the full gap), stored on `House.goki_count` (max 10) with the last-played date (`goki_year/month/day`). Playing resets the date: on every save (`Game.to_save`) and each daily renew.
- **Showing up**: entering any player floor lets up to three out (`MAX_VISIBLE`) — the first just behind the player, the rest on free floor in the first 4 / 6 / 8 cells square from unit 1 — and takes them out of the walls. The first roach of a session startles the player once (`goki_shocked_flag`, `Player.request_surprise`: a beat, then `gaaan1`, facing north). Survivors go back when you leave; the dead do not.
- **Shoving furniture** uncovers one (`aMR_MakeGokiburi`) on a cell the piece left, while some are waiting and fewer than three are out; it fades in from alpha 30 and cannot be crushed until solid. The grip events carry `vacated` cells.
- **The roach** (`house_goki.gd`, `ac_house_goki.c` action table): AWAY (runs from the player at 12 m/s, runs along walls, hops when cornered), JUMP_AWAY, WAIT, MOVE (dawdles), DEAD (blinks out). It dies when a moving player treads within 9 GX or when furniture lands on its cell. Speeds are the decomp's units at 30 Hz (1 unit = 1.5 m/s), timers 15 units/s.
- Debug: `/house goki [n]`, `/house neglect [days]`.
- Not ported: the `ef_goki01` death puff and the two-frame leg animation (the pipeline merged both poses into one mesh), the door-threshold turn (`RSV_DOOR`), roaches scuttling under a piece as it moves (`aMR_CheckFtrAndGoki`), the island cottage.

## Player heading versus grid facing

`PlayerLocomotion.facing` is `atan2(x, z)` (east +90°, west −90°) — the furniture convention. `WorldGrid.yaw_for_facing` has east/west the other way round and only agrees on north/south, so anything reading the player's heading uses `facing_from_player_yaw` / `yaw_for_furniture`. (Grip and placement were both swapped east/west until this was fixed.)
