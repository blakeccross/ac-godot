# Fishing

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not copy fish name enums into shipped data as Nintendo species lists.

**Read before implementing:** `FishData`, rod tool, water tiles.

## Decomp sources

| File | Role |
| --- | --- |
| `include/ac_gyoei.h`, `src/actor/ac_gyoei.c` plus `ac_gyoei_*.c_inc` | Fish shadows / catchable actors |
| `include/ac_uki.h` | Bobber (uki) status: carry → ready → cast → float → vib → catch |
| `include/m_player.h` | `READY_ROD`, `CAST_ROD`, `RELAX_ROD`, `VIB_ROD`, `COLLECT_ROD`, … |
| `include/m_player_lib.h` | `mPlib_request_main_release_creature_gyoei_from_submenu` |
| `include/m_fishrecord.h` | Tourney size records |
| `include/m_common_data.h` | `gyoei_term` + transition offset |
| `include/m_name_table.h` | `ITM_FISH_START` 0x2300, `ITEM_IS_FISH` |
| `src/actor/ac_set_ovl_gyoei.c` | Spawn overlay |

Constants: `aGYO_MAX_GYOEI` **2** simultaneous shadows, `aGYO_EXIST_MAX` **4** tracked. Sizes `XXS`–`WHALE`. Trash: empty can, boot, old tire (`aGYO_IS_FISH_TRASH`). Golden vs normal rod (`aGYO_ROD_*`).

## What does the original system do?

Water units (river/pond/sea attributes) can spawn **shadows** (`GYOEI_ACTOR` controllers). At most two are active. Species depend on **fish term** (saved `gyoei_term`, aligned with calendar terms with a transition offset), location (river vs sea), and hour.

The player equips a rod → ready → cast. The **uki** (bobber) actor flies on a parabola, floats, then **vibrates** on a bite. The player must collect (hook) during the window or the fish escapes. Success yields a fish item (or trash, or rare whale demo). Catch goes to pockets or is released from the submenu.

BGM ducks (`mPlayer_BGM_VOLUME_MODE_FISHING`). Fishing tourneys (`m_event` / `m_fishrecord`) compare sizes (`mFR_fish_rndsize`) and mail results.

Museum fish rooms and “place fish as furniture” (`aFTR_INTERACTION_FISH`) are separate from the catch loop.

## Important states

- Rod player index (ready / cast / float / vib / collect / put away).
- Uki status (`aUKI_STATUS_*`).
- Shadow exist flags, species, size, swim vs escape.
- `gyoei_term` for spawn tables.
- Inventory full vs catch-and-release.

## Inputs

- Equip rod; A to cast / hook; B to put away.
- Water collision under the bobber.
- Calendar term and hour.
- Golden rod flag (higher-tier fish; can wait).

## Outputs / events

- Pocket item (fish or trash).
- Collection / museum bit.
- Escape (no item).
- Tourney record (ignore at first).
- Release back into water from inventory.

## Interacts with

- **World** — water attributes, not grass.
- **Player / interaction**.
- **Inventory**.
- **Time** — spawn tables.
- **Shops** — sell fish; Cranny unlocks rod after sales sum (`mSP_ROD_SALES_SUM` 8000).
- **Audio** — BGM duck, splash, bite.

## Reproduce

- Cast into water, wait, bite telegraph, hook timing, get an item.
- Miss / escape does nothing to pockets.
- Full pockets → cannot keep the catch (release or fail).
- At least two sizes or rarity weights so the loop is not a single guaranteed fish.
- Only on water tiles.

## Simplify

- One water type and a tiny `FishData` table (3–5 fictional fish), not 40+ species.
- One shadow at a time.
- Skip golden rod, whale, tourney, junk items until the loop feels good.
- Bobber as a simple timer + bite window, not full `ac_gyoei_move` swim AI.
- No sea vs river vs pond tables.

## Ignore

- Fishing tourney events and `mFR_record_c`.
- Island-only fish and `mISL_PLAYER_ACTION_NOTICE_FISHING_ROD`.
- Coelacanth rain-only and other famous exception rules until we want weather-gated spawns.
- Furniture-mounted fish and museum donation treadmill.
- `aGYO_TYPE_TEST` / fossil-fish (`kaseki`) debug actors.
