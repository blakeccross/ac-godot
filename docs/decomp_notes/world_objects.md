# World objects

Reusable outdoor hosts (tree, rock, flower, ground item, building, door). Behavioral reference: FG items + structure actors in [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Do not copy C actor tables.

**Read before extending:** this note, [interaction.md](interaction.md), [world_generation.md](world_generation.md).

## Godot framework

```
WorldObjectRegistry  →  WorldBuilder  →  scene host
   (kind → scene)         (instances)      (verbs)
```

| Piece | Role |
| --- | --- |
| `WorldObjectRegistry` | One-line `register(kind, scene, place_kind, group)` |
| `ObjectPlacement` / `BuildingPlacement` | Layout entries inside `WorldData` |
| Host scene | Thin: `GeneratedVisual` + `InteractVolume` + `get_interactions` / `interact`. Solid hosts size physics from the occupancy footprint (`HostCollision`), not the GLB. |
| `HostCollision` | Box / cylinder hulls from occupancy for trees, rocks, and leftover shells. Houses, museum, Able Sisters, post office, Nook shop, and police disable the StaticBody; walk walls come from `StructureOffset` plus-offsets on `FieldCollision`. Door sensors stay on the host. Train station (`obj_s_station*`) also disables the hull **and** removes the Door — `ac_station` has no `set_bgOffset` and no indoor room; walls are baked into `grd_s_t_st1_*` acre collision, and Porter stands outdoors at unit (5, 4). |
| `Door` | Composable ENTER/SHOP sensor (child of `building`, or own placement) |

**Add a new object**

1. Create `scenes/world/my_thing.tscn` with an `InteractVolume` and the two host methods.
2. `WorldObjectRegistry.register(&"my_thing", "res://scenes/world/my_thing.tscn", …)`.
3. Emit an `ObjectPlacement` / `BuildingPlacement` with `kind = &"my_thing"` from the generator (or test town).

The player never switches on type. Verbs live on the host.

## Initial kinds

| Kind | Verb | Scene |
| --- | --- | --- |
| `tree` | Shake; chop (axe); dig stump (shovel) | `tree.tscn` |
| `rock` | Dig (stub) | `rock.tscn` |
| `flower` | Pick up | `flower.tscn` |
| `hole` | Fill (shovel) | `hole.tscn` (ground decal: 1 GX above unit, no depth write) |
| `item` | Pick up (inventory) | `item_pickup.tscn` |
| `building` | Enter via child `Door` | `building.tscn` |
| `door` | Enter / Shop | `door.tscn` |
| `prop` | Sight-map board opens the map; fences and tune board are solid only | `prop.tscn` |
| `lotus` | None (floating decoration) | `lotus.tscn` |
| `sign` (community board) | Read / first-job post notice | `sign.tscn` with `obj_*_notice` |
| `house` / `shop` | Enter / Shop (door cKF + player `OPEN1` via `StructureDoor`); leave emerge uses leave cKF + `GO_OUT` | existing shells |

## New-game placement (decomp)

| Object | Rule |
| --- | --- |
| Player houses | Always **B-3**; HOUSE0–3 at (3,3) / (12,3) / (3,10) / (12,10); west +20 X, east −20 X, both +20 Z; mesh `obj_s_myhome1`; west yaw +90°. Walk collision is a 4×4 heightfield rewrite with a porch gap (see below), not an AABB. Interact check `−20,+20` local GX (`aMHS_check_player_sub`); exit stand `±48` GX. FG occupancy stays 2×2. |
| Nook shop | Tracks row **A**; dump→shop; SHOP0 unit + NW (−1,0); mesh `obj_s_shop1` |
| Museum | Unique **flat** acre below cliff (`T_MUSEUM`) → `obj_s_museum` |
| Able Sisters | Beach row **bz=6** (`T_NEEDLEWORK` / `grd_s_m_ta_*`). FG `NEEDLEWORK_SHOP` is **(9, 4)** on `_1`/`_2` and **(9, 5)** on `_3`. Door verb shop, NW (−1,0), `aNW_actor_ct` −20 X +20 Z |
| Post / police / well / station | `obj_s_yubinkyoku` (−1,0) / `obj_s_kouban` (3×3 centered) / `obj_s_shrine` (0,−1) / `obj_s_station1` at TRAIN_STATION **(8, 5)** + −20 X. Station is **not** enterable: no `mFI_FIELD_ROOM_STATION`; walk into the open mouth via acre heightfield; talk to Porter (`SP_NPC_STATION_MASTER`) outdoors. |
| Villager homes | FG **SIGN00–SIGN20** reserves shuffled; SIGN ut must be 1..14. **6** houses (`mNpc_LOOKS_NUM`). House FG on the SIGN unit; mesh is `obj_s_house{1-5}_{a-e}` from that animal’s `npc_house_list` type/palette (`aHUS_actor_ct`); 3×3 RSV overwrites trees. Door interact / OPEN1 stand is **+40** Z GX (porch); exit rewrite **+60** Z. New game also places **6** outdoor villager actors (`mNpc_DecideLivingNpcMax`: one starter per looks). Fallback synthetic plots on flats if catalog has no SIGNs |
| Dock sign | FG **`PORT_SIGN`** (`0x5852`) on `grd_s_m_wf_*` at unit **(8, 7)** on `_1`/`_2`, **(9, 7)** on `_3`. Drawn by **`ac_reserve`** (`arg0 == 0x42`) as seasonal **`obj_{s,w}_attention`** (`obj_*_attentionT_model`) — one-post bulletin with baked paper/tack. Not field `SIGNBOARD`/`obj_*_kanban` (two posts) and not plaza `obj_*_notice`. |
| Trees / rocks / flowers | FG template copy (`FgCatalog`) at **unit center** (`bg_item` `pos_table` 20+40n GX), then border pull / tanuki path, then fruit/cedar. House build clears the SIGN 3×3 |

Structure FG ids (`HOUSE0`, `SHOP0`, `MUSEUM`, `NEEDLEWORK_SHOP`, …) refine cell offsets when the disc FG catalog is present.

## House gyroids (`ac_haniwa`)

One per house plot, from the house-acre FG template: `ACTOR_PROP_HANIWA0`–`3` at ut (3,5) / (12,5) / (3,12) / (12,12), two units south of `HOUSE0`–`3` (mailboxes sit two units toward the acre centre on the house row). West-plot house anchors are the house ut; east ones sit one cell west (`nw_off (-1, 0)`), so the east gyroid is anchor + (1, 2), the west one anchor + (0, 2). The unit is solid (`mFI_SetFG_common(DUMMY_HANIWA*)`); no shadow is drawn.

- **Owner.** Only the player's plot has one (`PlayerHouse.is_owned_node`). During the station intro, before a house is picked, all four are ownerless.
- **Animation** (`aHNW_setupAction` / `aHNW_common_process`). `hnw_move` keyframes 1 → 9 on repeat. Target speed (cKF keyframes per 60 Hz tick): owner 0.3 idle, 0.45 once the player is inside 80 GX (back to idle past 90 GX), 0.3 in any conversation; someone else's house 0.1; empty plot 0 (never started) or 0.075 after a talk, and at ≤ 0.1 it plays out and **stops** on the last frame. Speed chases up 0.05 / down 0.015 per tick. Turns with `chase_angle(..., 0x600)` to the player when owned or talking, else to the plot's front angle (±8000: west plots look east of south, east plots west of south).
- **What it says** (`aHNW_decide_msg_idx_dance`, in order): empty plot → 0x934 "This house, sadly, is empty."; another resident's house → their message (0x928); owner who has never saved, is on the first job and has no villager friends yet → 0x92E (part-time job line); bells from sales waiting → 0x935; else the menu 0x925 (Save / Store an item / Other things / Never mind). Other things = About the door (post / remove pattern) / Set message / Go back.
- **Save** (`aHNW_save_check` → `SAVE_END_WAIT` → `PL_APPROACH_DOOR`). "That's right!" sets `has_saved`, starts `BGM_ENTER_HOUSE`, and demo-walks the player (3 GX/frame) first round the gyroid, then — once they are 35 GX to the house side — to the door (`goal_pos`, as GX offsets from the gyroid: west (38, 40) then (50, −26), mirrored east). After 160 frames it gives up waiting and opens the door anyway. The door opening sends the game to `SCENE_PLAYERSELECT_SAVE`.

Port: `HaniwaTalk` (rules, ROM message ids, one merged conversation over every gyroid message with a start branch), `HaniwaStore` (the four consigned items, message, proceeds) and `scenes/world/haniwa.gd` (model, per-tick animation, talk, save walk via `player.begin_demo_walk` → `StructureDoor.play_enter` → porch exit stand → `Game.return_to_title`). Menu choices that open a submenu end the talk with a `haniwa_menu` event; the scene runs it and replays from "Request processed." (0x927), as `aHNW_menu_open_wait` / `menu_end_wait` do. **Store an item** opens the pockets with the gyroid's 4-slot table (`inventory_overlay.open_haniwa`, owner = `mSM_IV_OPEN_HANIWA_ENTRUST`): drop a held pocket item on an empty slot → Free / Set price / Display only; a held slot → Grab / Free / Set price / Display only / Quit; price entry is five digits stepped per digit, 0–99 999, 0 = free (`mTG_mv_priceSet`); status line from `mHW_make_message`. **About the door** posts a design (`door_original` = design index, SE 0x461) that `PlayerHouse.apply_door_pattern` paints over the `obj_myhome_mark` surface; Remove sets 0xFF. **Set message** edits the 4-line / 128-char visitor message in the letter writer's board mode (`mED_TYPE_HBOARD`); unset, it reads the ROM default (`mString_HANIWA_MSG0–3`, `strings.json`). Visitors (`OTHER_OWNER`) pay from wallet then bags smallest first (`mTG_present_open_proc`); the bells wait on the gyroid until the owner's next talk (`aHNW_check_proceeds`: wallet under 99 999, else 30 000-bell bags if the pockets have room, else 0x937 names how many). Model: `characters/other/hnw.glb` — its textures come from `hnw_tmem_txt` with the `hnw_face` TLUT the draw code loads (pipeline: palette compiled right before a tmem bank with no `{prefix}_pal`), and its only clip stands the +X chain up itself, so it is baked as the rest pose without `ckf_basis`. Audits: `scenes/dev/capture_haniwa.tscn`, `scenes/dev/audit_haniwa_menus.tscn`, `scenes/dev/audit_haniwa_save.tscn` (saves — back up `user://save.json`).

## Template props (fences, boards, lotus)

`FgCatalog._prop_place` maps these FG ids; `WorldGenerator._place_from_fg_templates` treats them like structures (kept in title-demo pass 1).

| FG id | Kind / visual | Notes |
| --- | --- | --- |
| `FENCE0` `0x0005` (+ `FENCE1` `0x0006`) | `prop` `obj_{s,w}_fenceL` | 2×1, mostly rail-line fences. |
| `WOOD_FENCE` `0x0010` | `prop` `obj_*_fenceS` | 1×1. |
| `MESSAGE_BOARD0/1` `0x0007` / `0x000B` | `sign` `obj_*_notice` | Community board; `notice_board` group. |
| `MAP_BOARD0/1` `0x000C` / `0x000D` | `prop` `obj_*_sightmap` | `mSM_OVL_MAP` mode 0 on A (no map item needed). |
| `MUSIC_BOARD0/1` `0x000E` / `0x000F` | `prop` `obj_*_melody` | Town-tune board; solid only until town tune exists. |
| `LOTUS` `0x5841` | `lotus` `obj_s_lotus` | No occupancy; sits on pond water. |
| `DOUZOU` `0x5843` | not placed | Statue is drawn / solid only once a player house reaches `mHm_HOMESIZE_STATUE` (loan paid off, `aDOU_set_check`); place it with that feature. |

Two-unit pieces are drawn by `bg_item` at `pos_table2` (**left edge** of the `*0` unit, unit-center Z), so the 8 m mesh is centered on the seam between the `*1`/`*0` pair. The `*0` item therefore carries a 2×1 footprint with `cell_shift (-1, 0)` and the `*1` half places nothing. `obj_hight_table_item0_nogrow` raises the whole unit (fences / notice 4 counts, map / tune 7), so the Godot hull is the full footprint box.

Lotus (`ac_lotus`): 129-frame loop at 0.5 speed; joint `0x12` (flower) draws May 26 – Aug 25 (`aLOT_actor_draw_before`); palette index per term (`aLOT_getPalNo`, 18 terms) is **not** baked, so `lotus.gd` recolors the debug palette to green / pink (placeholder). `season_role_for_label` skips `lotus` so the pad texture is not swapped for the hardwood leaf.

Not placed yet: `DUMP` (replaced by Nook's), `BRIDGE_A*`, `MIKANBOX` and other event structures, island (`FLAG` / `BOAT` / `COTTAGE_*`), `KAMAKURA`, `TENT`, `HTABLE*`. Blob shadows for notice / fence / melody / sight-map are not converted (`obj_notice_shadow` etc. absent).

Audit: `scenes/dev/capture_world_props.tscn` photographs each prop in a generated town.

## Player-house walk collision (decomp)

Not a mesh, not a 3D box. `aMHS_actor_ct` calls `aMHS_set_bgOffset`, which **rewrites the acre heightfield** on a 4×4 of units around `actor.home` (the FG unit center, **before** the +20 X / +20 Z mesh shift). Same path as cliffs: `mCoBG_SetPluss5PointOffset` adds counts to the unit’s five corners (`keep_h` + offset, cap 31) and may set `slate_flag`. `revise_xz` then builds thin walls on those height jumps. Zero offsets restore `keep_h` (the porch).

`height_tbl` uses **11 as a sentinel** meaning “house body” — replaced by size: small **11**, medium **14**, large **15**, upper **14** (`height_dt`). Count × 10 GX = raise (11 → 5.5 m). `shape` 1 is a 45° slate face.

Offsets are `s8` (`216` → **−40** GX). `addZ` `{90, 40, 0, 216}` is south→north; `90` still `Wpos2UtNum`s into the unit two south of home (center would be +80). West plots (`HOUSE0`/`HOUSE2`, `side_idx=0`) use X `{−40, 0, 40, 80}` (biased **east** toward the acre). East plots use `{−80, −40, 0, 40}`. The source labels the two `height_tbl` halves East/West **backwards** relative to `side_idx`.

West 4×4 (south row at the top; `H` = body, `.` = porch / keep_h, `4` = low skirt):

```
        x-40   x0    x+40   x+80
z+90     4     4s1    .      .
z+40     Hs1   H     Hs1    .
z0       Hs1   H      H     4s1
z-40     4     Hs1   Hs1    4
```

East is the mirror. The **porch is the SE (west plot) or SW (east plot) cells**, matching the door stand at actor + `(±48.29, +48.29)` GX and demo dirs `NORTH_EAST` / `NORTH_WEST`. Interact check is closer on the same diagonal (`−20,+20` local). FG occupancy stays **2×2**.

Villager homes (`aHUS_set_bgOffset`) are a **3×3** around the SIGN unit: south-center cell is all-zero (door), the other eight are offset **7**. Same mechanism, simpler footprint. Interact / OPEN1 stand is `home.z + 40` GX; exit rewrite is `+60`.

Museum (`aMsm_set_bgOffset`) raises a **7×5** (X −3..3, Z −2..2) around the FG unit to offset **10** — no porch gap; the door stand is `home.z + 120` GX (south of the block). Walk-in enter (`aMsm_check_player`) has **no A button**. Able Sisters (`aNW_set_bgOffset`) and post office (`aPOFF_set_bgOffset`) share a **4×4** around the FG unit (occupancy NW = FG+(−1,0)) with body **13** and open corners; door stand SW of the mesh. Nook shop (`aSHOP_set_bgOffset`) is the same footprint with body **12** and SW door (−50,+50 GX). Police (`aPBOX_set_bgOffset`) is a **3×3** of offset **10** with slate corners; the door stand is SE of home at `+50,+50` GX.

Godot: `StructureOffset.apply` writes those 4×4 / 3×3 / 7×5 tables into `FieldCollision` plus-offsets (`keep_h` + count, same as `SetPluss5PointOffset`). `revise_xz` builds the walls. Actor/mesh Y stays acre `keep_h` (`ground_y` ignores plus). House / museum / Able Sisters / post / shop / police scenes disable their StaticBody; ENTER stays on `InteractVolume` / `Door`.

## Ground decals

`bg_item` places **every** FG actor at `GetBgY(..., −1 GX)`. That lift is not the same as a ground decal. Only meshes authored on the acre plane (zero Y extent) z-fight the grass: `obj_hole0` / `HOLE00`. Flowers, weeds, rocks, stumps, dropped items, and signs have height — they stay `_fit_actor` at unit-center Y.

When shine spots or pitfall holes exist, they reuse the same hole fan and should go through `FieldCatalog.is_ground_decal`. Buried deposit X marks use `obj_crack0` (hole verts + `obj_crack_tex`); shine rays are `ef_anahikari` (also ground-decal materials). Actor blob shadows (`*_shadow_v`) convert as companion GLBs; `GeneratedVisual` attaches them under `BlobShadow`. Characters (player) use `actor_blob_shadow.tscn` — DirectionalLight shadows stay off.

**Window panes** (`*_light_model`, museum `*_lightT_model`): opaque quads in the wall TEX_EDGE holes. The combiner ignores the wall SETTIMG and fills with prim/env — black when off, yellow (255, 255, 150) when on (`mEnv_NPC_LIGHTS_*` 18:00–05:00). Convert keeps them untextured (`unlit_fill`) so they do not merge into the MASK wall surface.

**Window ground spill** (`*_window_model`, `*_windowL/R_model`, `windowT_model`): a coplanar I4 fan drawn on the **shadow pass** as `G_RM_AA_ZB_XLU_DECAL2` (prim yellow × I4 × LOD frac 120). Draw callbacks null that joint in OPA. Convert bakes I4 into PNG alpha. `GeneratedVisual` draws it unshaded, 1 GX above the acre, so it does not z-fight the grass. The spill shader composites in **8-bit sRGB** via `hint_screen_texture` (Godot’s linear `blend_mix` made the same alpha read as opaque yellow).

## Behavior notes

- ENTER on a mapped building loads `interior.tscn` (`InteriorCatalog` / `InteriorBook`); shop hours gate Nook / Able Sisters.
- Villager outdoor shapes `obj_s_house1`–`5` + palettes a–e are applied from `npc_house_list`. Player house upgrade stages (`obj_s_myhome2`–`4`) are not modelled.

## Train (`m_train_control.c`, `ac_train0/1`, `ac_npc_engineer`)

**Godot:** `TrainControl` (pure timetable + motion), `TrainCars` (couplings + door), `TrainService` (`Game.train`: ticks for the whole session, drives the world's `FieldTrain`, plays the sounds), `scenes/world/field_train.tscn` (in `world.tscn`).

- **Timetable** (`mTRC_get_depart_time`): the train is due at the east edge at hh:19 and enters the west edge 4:10 earlier (hh:14:50). `mTRC_init` runs once per session (`Game.reset_session` → `TrainService.reset`); `mTRC_move` runs every play frame, indoors too, and stops while paused (`mSM_PROCESS_WAIT`) — `TrainService` is `PROCESS_MODE_PAUSABLE`. Held while the first job runs (`mEv_CheckArbeit`). Off in the K.K. / Rover scenes and while `IntroStationStage` owns the arrival train (`train_coming_flag 3`). Title demo 1 is `mTRC_mati_init`: parked at x 2367, never leaves.
- **Motion** (GAFE01_00 constants, 60 Hz decomp frames — `x += 0.5·speed` is the "30fps -> 60fps" step): spawn x 320 at speed 6; from block 2 chase 2 at 0.01/tick; past x 2165 chase 0 at 0.005; stopped → 48-tick signal, `start_timer += 310` s dwell; then 84-tick signal, 180 ticks pulling out (0.00345 toward 2), speed up (0.00345 toward 6) until x > 4400. `x += 0.5·speed` per tick. Rail z 740; sound height y 180.
- **Actors** exist only while the loco is within one block east/west of the player's block on the rail row (`aTRC_area_check`). Mid car on a 125 GX coupling with 2 GX slack (`aTR0_ctrl_back_car`), passenger car likewise behind it (`aTR1_position_move`) — they bump when the loco starts or stops. Wheels `obj_train1_1` at `min(speed/40·10, 0.5)`. Door (`aTR1_setupAction`): stopping plays `open` at 0.5, standing holds `close` frame 1 (open), starting plays `close` at 0.5, running holds `open` frame 1 (shut); SE `0x2B` on open/close unless the car just spawned (`arg0_f == 1`) or in the title demo, which snap to the end pose. Engineer (`mnk_1`) at loco + (−40, 47, 20), facing +X (`0x4000`).
- **Sound** (`Na_KishaStatusTrg` / `Na_KishaStatusLevel`): approach whistle `0x70` (rooms `0x6E`), stop `0x73`, departure whistle `0x71` (rooms `0x6F`) — whistles audible to 6400 GX, linear `distance2vol4KITEKI`. While running: level SE `0x10` loop at the loco, steam chuff `0x3B` every `20 − 2.5·speed` ticks and wheel clack `0x3F` every `90 − 11.5·speed` ticks (at the passenger car), only above speed 0.4; these use `distance2vol` and cut off past 540 GX (`SOU_ONGEN_AREA1`). Mic = player + (0, 240, 77) outdoors, the exit door indoors (`mTRC_SetMicPos`). Title demo is `sou_scene_mode 0`: silent. `0x3F` / `0x73` are enum gaps (`EXTRA_SE_NUMS`); `lev_10` is rendered on SE subtrack 8 via port 0 (`render_lev_se`) and crossfaded into a loop.
- **Not modelled:** steam / smoke effects (`ef_kisha_kemuri`, `ef_steam` — no effect system or converted effect models yet); `train_coming_flag` 2/4 (friend visits, leaving town); the station doorway attribute swap (`aTR1_chg_station_attr`); `pan_kochou`; one shared panner (the clack pans with the loco).
