# Tools

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not copy player main-index tables or per-tool C actors.

**Godot:** `ToolData` (`extends ItemData`) + `ToolUse` (`RefCounted`, not an autoload). Hosts offer extra verbs when `ToolUse.has(ctx, kind)`. Empty-tile uses (`field_verb`) go through `ToolUse.field_action`. The player never switches on Shovel vs Axe. Equipped meshes parent to HAND via `HeldTool` (`visual_id` on the tool resource).

**Read before implementing:** `ItemData` / equip, interaction hosts, water tiles (`WorldGrid.Terrain.WATER`).

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_player.h` | Tool modes: `SWING_AXE`, `DIG_SCOOP`, `READY_NET` / `SWING_NET`, `READY_ROD` / `CAST_ROD`, watering |
| `include/m_player_lib.h` | `mPlib_request_main_*` scoop / net / rod / axe |
| `include/m_private.h` | Equipped item id (`equipment`), not a pocket slot |
| `include/m_name_table.h` | Tool id ranges (scoop, axe, rod, net, can; golden variants); `HOLE_START`–`HOLE_END` |
| `m_player_main_dig_scoop.c_inc` | Empty-tile / remove-item scoop writes hole FG (`dig_hole_effect_entry`) |
| `m_player_main_fill_scoop.c_inc` | Shovel on an empty hole fills it (`bury_hole_effect_entry`) |
| `m_field_info.c` (`mFI_GetDigStatus`) | Dig vs fill vs get-buried vs miss |
| `bg_item_common.c_inc` | Hole actor scale-in / scale-out; `HOLE00`–`HOLE24` from collision hole number |
| Player actor draw | `Player_actor_Item_draw` / `Player_actor_draw_After_hand`; HAND = joint 20 |

## What does the original system do?

Equipping a tool puts the player into a **tool-ready** main index. A then uses that tool on the facing unit or a volume in front (net), not a type-switch on the target actor. Empty hands still shake trees, pick items, and talk. Durability / break (axe), golden variants, and put-away (B) are separate modes.

## Reproduce

- One equippable tool at a time (`Inventory.equipment_id`).
- One interact button: host verb if the object cares about the equipped kind, otherwise the tool’s field verb.
- Axe chops a tree (three hits to a stump; fruit on the first hit or shake); shovel digs (rock / stump / empty ground → hole) and fills a hole; net swings in front; rod casts only at water; watering can waters a flower.
- Locked player anim while the verb runs.
- Drawn tool follows the right hand (`mPlayer_JOINT_HAND` / joint 20). Axe and scoop are static Gfx (`tol_axe_1`, `tol_scoop_1`). Net and rod are cKF (`tol_net_1`, `tol_sao_1`) and play their own swing clips with the player. Chop uses `ply_1_axe_swing1` (`mPlayer_ANIM_AXE_SWING1`), not `ply_1_axe1`. Net wait uses `ply_1_kamae_wait_m1`. The GameCube disc has **no watering-can mesh**.

## Simplify

- Data + `ToolUse`, not a `Tool` / `Shovel` / `Axe` class tree.
- No golden / broken / silver variants. One of each kind.
- No fishing bite loop, insect AI, flower breeding, or axe durability in this slice — those stay in [fishing.md](fishing.md), [bugs.md](bugs.md), [plants.md](plants.md).
- One hole visual (`HOLE00`). No buried items, pitfalls, shine spots, or falling-in.
- Field uses that have no world effect yet post a notice.
- No takeout / putaway clips. Watering can stays unequipped-looking (no disc model to attach).

## Ignore

- Golden axe demos, tool fairy, shop sales-sum unlocks until the shop slice wants them.
- Per-tool air / reflect / broken animation sets.
