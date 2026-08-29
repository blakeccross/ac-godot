# Plants (trees, flowers, FG growth)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only.

**Godot:** `PlantData` + one tree scene. Chop / shake / stump rules are `TreeUse` (`RefCounted`, not an autoload). Daily grow is not this slice.

**Read before implementing:** `PlantData`, one tree scene, daily grow at 06:00.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_all_grow.h`, `src/game/m_all_grow.c` | Daily FG renewal `mAGrw_RenewalFgItem` |
| `include/m_all_grow_ovl.h` | Overlay that actually walks the town grid |
| `include/m_name_table.h` | Tree/flower/sapling id ranges; `IS_ITEM_ALIVE_TREE`, `IS_ITEM_GROWN_FLOWER` |
| `include/m_collision_bg.h` | Per-unit grow cap `mCoBG_PLANT0`–`PLANT4`, `KILL_PLANT` |
| `include/m_bg_item.h` | FG item actors |
| `include/m_mushroom.h` | 5 mushrooms, active from hour 8 |
| `include/m_player.h` | `SHAKE_TREE`, `SWING_AXE`, `DIG_SCOOP`, `REMOVE_GRASS` |
| `include/m_field_info.h` | Unit queries; `mFI_SET_SHELL_NUM` (beach, ignore) |

Fruit enum in grow: apple, cherry, pear, peach, orange (`mAGrw_FRUIT_*`). Tree types: normal, palm, cedar, gold (`mNT_TREE_TYPE_*`). Sizes: sapling stages S0–S2 then full (`mNT_TREE_SIZE_*`).

## What does the original system do?

Almost every outdoor plant is an **FG item id on a unit**, not a free-placed mesh. Daily at the time renew (`mAGrw_RenewalFgItem`), the overlay advances growth: sapling → small trees → full, flowers through leaf/bud/bloom, fruit appears on fruit trees, dead saplings, money trees, etc.

Collision **plant level** caps how far something can grow on that tile (including “nothing grows here”). Axe chops (with durability / break), shovel plants a sapling or digs, shake knocks fruit / items / bees / furniture. Grass can be removed. Cedar vs hardwood swaps with season (`mAGrw_ChangeTree2Cedar` / reverse). Christmas lights can be hung on cedars in season.

Mushrooms: `mMsr_SetMushroom` places up to **5** near the player after **08:00** (`mMsr_ACTIVE_HOUR`) on eligible days.

Buried items share the FG slot (hole vs item). Flowers breed in the original; that is a large neighbor-rule system.

## Important states

- Per-unit item id (sapling, tree-no-fruit, tree-fruit, flower stage, hole, …).
- Plant-growth cap on the collision cell.
- Last renew timestamp (`all_grow_renew_time` in save).
- Fruit type of the town (native fruit) vs foreign fruit.
- Mushroom active flag / last date.

## Inputs

- Daily renew at 06:00 (clock).
- Player: plant, water (if we add it), shake, chop, dig.
- Season (cedar, snow, fruit).
- Collision plant cap.

## Outputs / events

- Updated FG ids (visible tree/flower stage).
- Dropped fruit / wood / furniture / bee nest on shake.
- Stump or empty tile after chop. Digging the stump writes a hole FG item.
- New sapling occupying a unit.
- Insect spawn opportunities on flowers/trees.

## Interacts with

- **Time** — renew + season.
- **World** — FG grid and collision.
- **Player / interaction**.
- **Inventory** — fruit, saplings, shovel, axe.
- **Bugs** — habitat.
- **Shops** — saplings, watering can, foreign fruit price `mSP_FOREIGN_FRUIT_PRICE` 2000.
- **Save** — `fg[][]`.

## Reproduce

- **One tree**: shake for fruit → chop down to a stump → shovel the stump.
- Full trees take **3** axe hits (`tree_cut_tbl` S2/full). Fruit drops on the **first** shake or chop that still has fruit (3 apples, 2 coconuts), then the tree is bare.
- The last hit leaves a **stump**, not an empty tile. Cut progress is session-only; the stump itself is saved (`Game.stump_interactables`).
- Occupies a tile; cannot plant on occupied/blocked tiles.
- Shake is a locked player anim that may emit an item. Chop plays `ply_1_axe_swing1` (`mPlayer_ANIM_AXE_SWING1`); the tree wobbles, then falls away from the player.

## Simplify

- One species, 3–4 growth stages, one fruit item. Growth across days still waits for the plant-growth slice.
- No flower breeding, gold trees, palm, cedar swap, 10k/30k bell trees.
- No watering can until plants exist without it.
- Mushrooms, bees, dumped furniture-from-trees, and axe durability wait.
- Shake / fall are Godot tweens on the live mesh, not converted `ef_s_tree5_*` EffectBG clips.
- Digging a stump leaves a hole on that tile (`DIG_SCOOP` after the stump flies). Fill with the shovel (`FILL_SCOOP`).

## Ignore

- `mAGrw_SetXmasTree`, fossil/haniwa dump debug.
- Perfect-town flower coverage assessments (`m_field_assessment`).
- Beach shells (`mFI_MAX_SHELLS_PER_BLOCK`).
- Weed-overrun and fully automated town-wide grow overlay performance tricks.
- Every `FLOWER_*` id (9 flower kinds × stages).
