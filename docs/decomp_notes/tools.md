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
| `m_player_main_putin_scoop.c_inc` | Inventory plant/bury into a hole (`FILL_UP_I1`) |
| `m_field_info.c` (`mFI_GetDigStatus`) | Dig vs fill vs get-buried vs miss |
| `bg_item_common.c_inc` | Hole actor scale-in / scale-out; `HOLE00`–`HOLE24` from collision hole number |
| Player actor draw | `Player_actor_Item_draw` / `Player_actor_draw_After_hand`; HAND = joint 20 |

## What does the original system do?

Equipping a tool puts the player into a **tool-ready** main index. A then uses that tool on the facing unit or a volume in front (net), not a type-switch on the target actor. Empty hands still shake trees, pick items, and talk. Durability / break (axe), golden variants, and put-away (B) are separate modes.

## Behavior

- One equippable tool at a time (`Inventory.equipment_id`). Data + `ToolUse`, not a `Tool` / `Shovel` / `Axe` class tree. One of each kind (no golden / broken / silver variants).
- One interact button: host verb if the object cares about the equipped kind, otherwise the tool's field verb.
- Axe chops a tree (three hits to a stump; fruit on the first hit or shake); shovel digs (rock / stump / empty ground → hole) and fills a hole; net swings in front; rod casts only at water (see [fishing.md](fishing.md)); watering can waters a flower.
- Locked player anim while the verb runs.
- Drawn tool follows the right hand (`mPlayer_JOINT_HAND` / joint 20). Axe and scoop are static Gfx (`tol_axe_1`, `tol_scoop_1`). Net and rod are cKF (`tol_net_1`, `tol_sao_1`) and play their own swing clips with the player. Chop uses `ply_1_axe_swing1` (`mPlayer_ANIM_AXE_SWING1`), not `ply_1_axe1`. Net wait uses `ply_1_kamae_wait_m1`. Fill hole uses `ply_1_fill_up1` (effect frame 18); inventory plant into a hole uses `ply_1_fill_up_i1` (effect frame 25). The GameCube disc has **no watering-can mesh**, so it stays unequipped-looking.
- One hole visual (`HOLE00`), treated as a ground decal (`GetBgY(..., -1 GX)` plus no depth write) so it does not z-fight the acre. Buried fossils use the deposit X crack (`BURIED_CRACK` / `obj_crack0`, hole fan + `obj_crack_tex`); shine spots use golden rays (`SHINE_SPOT` / `ef_anahikari`). Diggable attrs follow `mCoBG_CheckHole_OrgAttr`; shine also requires flat ground and refuses sand-hole attrs.
- Field uses with no world effect yet post a notice. Equip snaps the held mesh on directly; there is no put-in/take-out mode.

## Umbrellas (`ac_t_umbrella.c`, `m_player_item_umbrella`, `m_player_main_rotate_umbrella`)

- **Items.** `ITM_UMBRELLA00`–`31` = tool words `ITM_TOOL_START + 4…35`; names from `itemName_tool`, catalog prices from `tool_price_table` (220–490 bells). Authored as `ToolData` (`kind = UMBRELLA`, `umbrella_index`) in `data/items/umbrellas/`. `ITM_MY_ORG_UMBRELLA0-7` (design umbrellas, `tol_umb_w` + the design on segments 8/9) are not wired to any source yet.
- **Model.** `tol_umb_NN` (`draw_dt[tool_name]`): handle `e_umbNN_model` and canopy `kasa_umbNN_model` drawn off the hand matrix × `Matrix_rotateXYZ(0, -0x4000, 0)`; the canopy after a further `translate(4500, 0, 0)`, inheriting the handle's scale. The pipeline keeps them as separate nodes (`split_by_gfx`). The umbrella rests back over the shoulder.
- **Open / close** (`aTUMB_calc_model_scale`): per-sector (x, y) scale tables for handle and canopy, 0.5 frames per tick — opening 26 frames (handle grows from nothing, canopy from a flat 3 × 0.15 disc), put-away 30. `opened_fully` at the end of opening is what the rain SE listens to. SEs: 0x139 opening, 0x10E closing (`aTUMB_OngenTrgStart`).
- **Player.** Take-out plays `UMB_OPEN1` (full body, no grow-in); put-away `UMB_CLOSE1`. While held, anim1 = `UMBRELLA1` with `mPlayer_PART_TABLE_NET`: right arm joints 17–20 hold that pose over walk / wait (`HeldUmbrella.arm_pose`, applied after the mix). A while standing or walking slowly → `ROTATE_UMBRELLA` (`UMB_ROT1`, SE 0x432, `KASAMIZU` spray — the spray is not ported). Door requests fold it first; leaving a building opens it again.
- **Shop.** `mSP_RandomUmbSelect(goods, 1)`: Nook lists one random umbrella every day, shown open on the umbrella stand (`obj_shop_umbNN`).

## Holding a tool (`Player_actor_Item_draw`, `BOY_part_data`)

- **Attachment.** Every hand item is drawn off `right_hand_mtx` (joint 20's world matrix, saved in `Player_actor_draw_After_hand`), scaled by `item_scale`, with no further rotation — the axe is literally `gSPDisplayList(tol_axe_1_model)`. The player GLB binds on `wait1` with no `ckf_basis`, so the Godot HAND bone's global pose equals that matrix (checked to 1e-6 in `ply_1_axe1`), and static tool GLBs keep GX axes. `HeldTool` therefore attaches with an identity basis. (It used to add +90° about Z to static tools, which turned the axe blade upward and twisted the umbrella canopy.) Skeletal tools (`tol_net_1`, `tol_sao_1`) bind on their own `*_wait1` clip, so they carry no basis either. Only the umbrella adds `Matrix_rotateXYZ(0, -0x4000, 0)`.
- **Carry pose.** In wait / walk / run / dash the player plays the body clip on keyframe0 and the item's basic clip on keyframe1 (`mPlib_Get_BasicPlayerAnimeIndex_fromItemKind`), mixed per joint by the part table (`mPlib_Get_BasicPartTableIndex_fromAnimeIndex`): axe `AXE1`, rod `SAO1`, shovel `SCOOP1` → AXE table (both arms, joints 14–20); net `NET1`, umbrella `UMBRELLA1` → NET table (right arm, 17–20). `KAMAE_WAIT_M1` is only the net's ready-to-swing stance. Port: `ToolData.hold_anim` + `carry_part`, `ToolCarry` applied after the mix; joints whose track the GLB writer dropped take the rest pose. Action states (swing, dig, take-out, umbrella clips) play one clip on the whole body. Audit: `scenes/dev/capture_held_tools.tscn`.
