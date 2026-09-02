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
| `HostCollision` | Box / cylinder hulls from occupancy for trees, rocks, and leftover shells. Houses, museum, Able Sisters, post office, Nook shop, and police disable the StaticBody; walk walls come from `StructureOffset` plus-offsets on `FieldCollision`. Door sensors stay on the host. |
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
| `house` / `shop` | Enter / Shop (door cKF + player `OPEN1` via `StructureDoor`); leave emerge uses leave cKF + `GO_OUT` | existing shells |

## New-game placement (decomp)

| Object | Rule |
| --- | --- |
| Player houses | Always **B-3**; HOUSE0–3 at (3,3) / (12,3) / (3,10) / (12,10); west +20 X, east −20 X, both +20 Z; mesh `obj_s_myhome1`; west yaw +90°. Walk collision is a 4×4 heightfield rewrite with a porch gap (see below), not an AABB. Door stand `±48` GX. FG occupancy stays 2×2. |
| Nook shop | Tracks row **A**; dump→shop; SHOP0 unit + NW (−1,0); mesh `obj_s_shop1` |
| Museum | Unique **flat** acre below cliff (`T_MUSEUM`) → `obj_s_museum` |
| Able Sisters | Beach row **bz=6** (`T_NEEDLEWORK` / `grd_s_m_ta_*`). FG `NEEDLEWORK_SHOP` is **(9, 4)** on `_1`/`_2` and **(9, 5)** on `_3`. Door verb shop, NW (−1,0), `aNW_actor_ct` −20 X +20 Z |
| Post / police / well / station | `obj_s_yubinkyoku` (−1,0) / `obj_s_kouban` (3×3 centered) / `obj_s_shrine` (0,−1) / `obj_s_station1` at TRAIN_STATION **(8, 5)** + −20 X |
| Villager homes | FG **SIGN00–SIGN20** reserves shuffled; SIGN ut must be 1..14. **6** houses (`mNpc_LOOKS_NUM`). House FG on the SIGN unit (`obj_s_house1`, no `actor_ct` shift); 3×3 RSV overwrites trees. New game also places **6** outdoor villager actors (`mNpc_DecideLivingNpcMax`: one starter per looks). Fallback synthetic plots on flats if catalog has no SIGNs |
| Dock sign | FG **`PORT_SIGN`** (`0x5852`) on `grd_s_m_wf_*` at unit **(8, 7)** on `_1`/`_2`, **(9, 7)** on `_3`. Drawn by **`ac_reserve`** (`arg0 == 0x42`) as seasonal **`obj_{s,w}_attention`** (`obj_*_attentionT_model`) — one-post bulletin with baked paper/tack. Not field `SIGNBOARD`/`obj_*_kanban` (two posts) and not plaza `obj_*_notice`. |
| Trees / rocks / flowers | FG template copy (`FgCatalog`) at **unit center** (`bg_item` `pos_table` 20+40n GX), then border pull / tanuki path, then fruit/cedar. House build clears the SIGN 3×3 |

Structure FG ids (`HOUSE0`, `SHOP0`, `MUSEUM`, `NEEDLEWORK_SHOP`, …) refine cell offsets when the disc FG catalog is present.

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

East is the mirror. The **porch is the SE (west plot) or SW (east plot) cells**, matching the door stand at actor + `(±48.29, +48.29)` GX and demo dirs `NORTH_EAST` / `NORTH_WEST`. FG occupancy stays **2×2**.

Villager homes (`aHUS_set_bgOffset`) are a **3×3** around the SIGN unit: south-center cell is all-zero (door), the other eight are offset **7**. Same mechanism, simpler footprint.

Museum (`aMsm_set_bgOffset`) raises a **7×5** (X −3..3, Z −2..2) around the FG unit to offset **10** — no porch gap; the door stand is `home.z + 120` GX (south of the block). Walk-in enter (`aMsm_check_player`) has **no A button**. Able Sisters (`aNW_set_bgOffset`) and post office (`aPOFF_set_bgOffset`) share a **4×4** around the FG unit (occupancy NW = FG+(−1,0)) with body **13** and open corners; door stand SW of the mesh. Nook shop (`aSHOP_set_bgOffset`) is the same footprint with body **12** and SW door (−50,+50 GX). Police (`aPBOX_set_bgOffset`) is a **3×3** of offset **10** with slate corners; the door stand is SE of home at `+50,+50` GX.

Godot: `StructureOffset.apply` writes those 4×4 / 3×3 / 7×5 tables into `FieldCollision` plus-offsets (`keep_h` + count, same as `SetPluss5PointOffset`). `revise_xz` builds the walls. Actor/mesh Y stays acre `keep_h` (`ground_y` ignores plus). House / museum / Able Sisters / post / shop / police scenes disable their StaticBody; ENTER stays on `InteractVolume` / `Door`.

## Ground decals

`bg_item` places **every** FG actor at `GetBgY(..., −1 GX)`. That lift is not the same as a ground decal. Only meshes authored on the acre plane (zero Y extent) z-fight the grass: `obj_hole0` / `HOLE00`. Flowers, weeds, rocks, stumps, dropped items, and signs have height — they stay `_fit_actor` at unit-center Y.

When shine spots or pitfall holes exist, they reuse the same hole fan and should go through `FieldCatalog.is_ground_decal`. Actor blob shadows (`*_shadow_v`) are skipped by convert; Godot uses the sun.

**Window panes** (`*_light_model`, museum `*_lightT_model`): opaque quads in the wall TEX_EDGE holes. The combiner ignores the wall SETTIMG and fills with prim/env — black when off, yellow (255, 255, 150) when on (`mEnv_NPC_LIGHTS_*` 18:00–05:00). Convert keeps them untextured (`unlit_fill`) so they do not merge into the MASK wall surface.

**Window ground spill** (`*_window_model`, `*_windowL/R_model`, `windowT_model`): a coplanar I4 fan drawn on the **shadow pass** as `G_RM_AA_ZB_XLU_DECAL2` (prim yellow × I4 × LOD frac 120). Draw callbacks null that joint in OPA. Convert bakes I4 into PNG alpha. `GeneratedVisual` draws it unshaded, 1 GX above the acre, so it does not z-fight the grass.

## Simplify / ignore

- Indoor room scenes live: ENTER on a mapped building loads `interior.tscn` (`InteriorCatalog` / `InteriorBook`). Shop hours still gate Nook / Able Sisters.
- Money-rock / dig loot tables. Pitfall kits, buried items, and walking into a hole (fall).
- House upgrade stages (`obj_s_myhome2`–`4`, `obj_s_house2`–`5`) until upgrades exist.
