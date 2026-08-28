# Furniture (house, rooms, placeable FTR)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not copy `FTR_ACTOR` or per-item `aFTR_PROFILE` tables.

**Read before implementing:** `FurnitureData`, interior scene, place/pick/rotate.

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

## Reproduce

- Indoor **tile grid**; furniture occupies 1×1 first (then 1×2 / 2×2 if needed).
- Place from inventory onto an empty footprint; pick up back to a free pocket.
- **Rotate** in 90° steps.
- Push/pull along the grid (or skip pull and only rotate+place for a first slice).
- One **sittable** object.
- Wall and floor as room fields, even if only one wallpaper/flooring item exists.

## Simplify

- One room, one house size; no basement/upper/statue progression until Nook loans exist.
- One furniture actor script with data-driven size and “can_sit / can_store”.
- No per-item overlay profiles (`iam_*`).
- Storage: a few slots on one dresser, not every drawer type.
- No place-birth / pick-death tweens required for v1.

## Ignore

- Famicom / NES furniture, e-Reader, radio aerobics.
- Gyroid trading and Haniwa messages (`HANIWA_MESSAGE_LEN`).
- Museum displays, snowman furniture, island cottage (`mHm_InitCottage`).
- Four-player houses and mailbox (10 letters) until mail exists.
- `mRmTp_BIRTH_TYPE_*` rarity groups except as optional shop tags.
- Outlook palette (house exterior colors) as a system.
