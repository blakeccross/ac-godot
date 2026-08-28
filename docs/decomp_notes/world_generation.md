# World generation

How a playable town is produced. Behavioral reference: [world.md](world.md), `m_random_field`, `m_field_make`. Do not copy C combo tables or overlay DMA.

**Godot pipeline**

```
WorldGenerator  →  WorldData  →  WorldBuilder  →  Godot nodes
   (what exists)     (resource)     (how it looks)
```

Modes on `Game.world_mode` / `WorldData.Mode`:

| Mode | Source |
| --- | --- |
| `TEST` | Hand-authored single acre (`WorldGenerator.authored_test_town()`) |
| `GENERATED` | `TownFieldGenerator` (mRF-style 7×10 acres) → rasterize FG 5×6 → `WorldData` |
| `REFERENCE` | Reserved for a known GameCube layout later |

**New Game** on the title screen uses `GENERATED` with a live seed (decomp: `mSDI_StartInitNew` → `mRF_MakeRandomField`). **Town Seed 12345** keeps a fixed seed for debugging.

## Representation (`WorldData`)

Not `mFM_combination_c` / `mFM_fg_c`. One resource:

- `terrain` / `elevation` packed grids (cell = 2 m, 16×16 for this slice)
- `buildings[]` (`BuildingPlacement`)
- `objects[]` (`ObjectPlacement`)
- `spawn_points[]` (`SpawnPoint`)
- `acre_visual` (`grd_s_f_1` / `BG_TYPE_GRD_S_F_1`) for the single-acre test town
- `acre_types` / `acre_heights` / `acre_visuals` (70 entries, parallel `mFM_BLOCK_TYPE_*` + `grd_*` ids) for generated towns
- `mode`, `seed_value`, size metadata

Sparse cell lists (`water_cells`, `sand_cells`, …) exist so a test map can be authored without pasting 256 bytes. `bake()` writes them into the packed grids.

`WorldGrid` remains the runtime occupancy + walkability board. The builder copies terrain into it, then `place()`s buildings and objects. `FieldCollision` is a height query plus walls: catalog corners for Y (including river units), thin trapezoid segments on terrace/bank edges (plus 45° slate diagonals), and `revise_xz` (`CarryOutReverse`) so the player cannot step onto water or off a cliff.

## Generator steps (`TownFieldGenerator` ≈ `mRF_MakeRandomField_ovl`)

Seeded `RandomNumberGenerator`. Same seed → same acre grid → same `WorldData`.

1. **Step mode** — ~15% pick a canned 3-step layout; else 2-step cliff+river search
2. **Base template** — station A3, player house B3, track dumps, borders
3. **Cliff trace** left→right; **river trace** north→beach (cross column 3; mouth not F1/F5)
4. **Waterfall merges** where river meets cliff
5. **Beach** F-row; Able Sisters + dock when possible
6. **Bridges / slopes** — `mRF_SetBridgeBlock`: one `GROUP_RIVER` acre **north** of the waterfall always becomes `*_BRIDGE` (`+7`). 2-step towns also get a 50% **south** span. If that south span is missing, `mRF_SetSeaBlockWithBridgeRiver` turns the beach mouth into `BEACH_RIVER_BRIDGE` (`grd_s_m_r1_b_*`). Then one cliff acre per river side becomes a slope. Wood vs stone is **not** a second actor: `mRF_SelectBlock` picks a `data_combi` BG of that type (`grd_s_r*_b_*`). `_b_1` (and west `_b_3` / beach `_b_3`) use `bridge_1_tex` + collision attrs 32–35 (stone); `_b_2` and most `_b_3` use `bridge_2_tex` + attrs 27–31 (wood). Unused combis are preferred so two spans of the same type do not clone one mesh. The Tortimer extra actor (`BRIDGE_A0` / `obj_s_bridgeA`) is a later event, not new-game landform.
7. **Uniques** — wishing well / police / museum on flats below cliff; shop+post on A-row dumps
8. **Heights** — bump when crossing a terrace step going north (`CLIFF_HORIZONTAL` / `TOP_RIGHT` / `TOP_LEFT` bits, same as `mRF_GetBlockBase`). Vertical and bottom-corner river-cliffs stay on the current terrace.
9. **Rasterize** FG acres (bx 1–5, bz 1–6) to an 80×96 unit `WorldData`. When `grd_*.col.json` exists, water / sand / slate / holes come from that table; otherwise geometric river strips and cliff bands.
10. **Acre meshes** — `FieldCatalog.acre_for_block_type` picks a `grd_*` from the matching `data_combi` family (flat `grd_s_f_*`, river `grd_s_r1_*`, house `grd_s_f_mh_*`, bridge `grd_s_r*_b_*`, …), preferring a BG this town has not used yet (`mRF_SelectBlock` / `l_use_data`). Names are assigned even when the GLB is missing so fallback decks can still be wood vs stone. Variants whose sidecar is a HEIGHT_MAX filler (dummy TRACKS rows that reused the mesh) are skipped so they cannot box the acre in walls.
11. **FG props** — when `assets/generated/environment/fg/catalog.json` exists (from disc `fgdata.bin` + `data_combi`), each FG acre picks a matching `fg_id` and copies trees/flowers/rocks/palms from the 16×16 template (`mFM_InitFgCombiSaveData`). Then `mAGrw_ChangeTree2FruitTree` / `ChangeTree2Cedar`, `mSDI_PullTree` (left/right border columns), and `mFI_PullTanukiPathTrees` (C-3 ux 7–8, uz 0–2). Without the catalog, a sparse acre-type scatter remains as fallback.

Still deferred vs decomp: bit-exact `data_combi_table` row pick for BG+FG together (we pick BG by type family, then an FG that matches that BG), acre streaming. The FG catalog stays gitignored like other disc output.

**Structure spawn.** FG items sit on a unit. `mFI_BkandUtNum2CenterWpos` puts the actor at the **unit center**, then `actor_ct` adds a half-unit offset. Occupancy NW is that unit plus `nw_off`. Offsets that are not a 2×2 center (station: −20 X only) stay on the FG unit with `actor_shift`.

| Actor | FG unit | `actor_ct` from unit center | Occupancy NW | Mesh yaw |
| --- | --- | --- | --- | --- |
| `HOUSE0`–`HOUSE3` (`ac_my_house.c`) | `(3,3)` `(12,3)` `(3,10)` `(12,10)` on `FG_TYPE_0069` / `GRD_S_F_MH_*` | west `+20` X, east `−20` X; both `+20` Z | 2×2 NW = FG (west) or FG+(−1,0) (east). Mesh yaw: west `WEST` (AC `angle_table` **+90°**), east 0. All four are `obj_s_myhome1` on new game (`mHm_HOMESIZE_SMALL`). |
| `SHOP0` (`ac_shop.c`) | `(10, 9)` on `grd_s_t_sh_1`; `(10, 10)` on `_2`/`_3` | `−20` X, `+20` Z | SHOP0 + `(−1, 0)` |
| Post / Able Sisters | FG item | `−20` X, `+20` Z | FG + `(−1, 0)` |
| Station (`ac_station.c`) | `(8, 5)` on `FG_TYPE_GRD_S_T_ST1_*` | `−20` X only | FG unit + `actor_shift (−0.5, 0)` |
| Shrine | FG `WISHING_WELL` | `+20` X, `−19` Z | FG + `(0, −1)` |
| Museum / police | FG item | none | Police 3×3 centered; museum 2×2 on the FG unit |
| Villager house | SIGN reserve (`mNpc_SetNpcHome`) | none | 3×3 RSV around SIGN; villager at `uz + 1` |

The house acre always has HOUSE0–3 (top-left, top-right, bottom-left, bottom-right). New game inits all four to tent size; only player 0’s private data is filled. Mailboxes (`ACTOR_PROP_MAILBOX0`–`3`) sit two units toward the acre center on the house row; haniwa two units south of each house. Those props are not spawned yet. Door of the west pair uses AC **+90°** Y (`WorldGrid.Facing.WEST` here — `EAST` is −90°). `mFI_PullTanukiPathTrees` then clears trees on **C-3** (`Save_Get(fg[2][2])`), not B-3: ut indices `0x07, 0x08, 0x17, 0x18, 0x27, 0x28`.

## Builder

Maps `kind` → packed scene via **`WorldObjectRegistry`** (register once; do not grow a match ladder in the builder). Instantiates under `Terrain` / `Objects` / `Buildings` / `Characters`. The world `.tscn` is a shell, not a catalog of every tree. See [world_objects.md](world_objects.md).

Generated towns instance one `grd_*` GLB per FG acre under `Terrain/Acres` (5×6). Placement matches `ac_field_draw`: min-corner (`mFI_BkNum2WposXZ`), Y = `mFI_BkNum2BaseHeight` (height × 3 cells = 6 m). Draw-list verts are 16×; the original undoes that with `Matrix_scale(0.0625)` while actors use `Matrix_scale(0.01)`. The pipeline writes both at `0.001`; `FieldCatalog` applies the two draw scales into the same 40 GX = 2 m grid so acres, trees, and the player share one GX factor. The player does **not** stand on those triangles. Each `grd_*` combo ships gfx **and** a 16×16 `mCoBG` table (`data_bgd`); the pipeline writes that as `grd_*.col.json` next to the GLB. `FieldCollision` bilinear-samples those corners (`GetBgY_AngleS_FromWpos`) — **including water** — and puts **trapezoid segments** on unit edges where neighbor heights differ (`mCoBG_SearchWallFlag`), plus 45° walls on slate units (`GetUnitVecInf_SlatingWall`). Thickness sits on the low side of each segment so the high terrace has no lip. Those are oriented boxes (uniform height) or explicit prism triangles (trapezoid ends) — not convex hulls. Mixed slate/grass cardinals are shortened to the half-edge that had a real height jump before `UtInf2NormalSlateWallVector` flatten, so a full N–S box does not sit in the SE notch in front of the 45° face. Not AABB cell boxes and not the `grd_*` triangles. `revise_xz` pushes the actor back (`CarryOutReverse`) so thin physics walls cannot drop them into a river or off a terrace. Authored ponds and geometric cliff faces (no sidecar) stay holes. Snapping to the unit *center* buried the capsule in the ramp mesh and blocked downhill travel. Off-map is impassable (`MapBound`). Test town places a single `grd_s_f_1` the same way and keeps its authored pond. Colored paint tiles are only used when those meshes are missing.

`visual_id` on each placement is an original identifier (`TREE_APPLE_FRUIT`, `obj_s_house1`, `ROCK_A`, …). `FieldCatalog` resolves that to a gitignored GLB from `assets/generated/` when the local disc pipeline has been run; otherwise the scene keeps its placeholder mesh.

Static Gfx keep GX +Z. cKF characters stand up with wait bind or +90° about Z. Houses and shops already sit on +Y in GX, so they skip that stand-up (it laid them on their backs) and bake the door-clip rest pose: joint-0 Y is **−90°** (house) or **−135°** (shop/myhome). Station clock-hand verts fail the same Y-up heuristic; treat it as Y-up and bake identity joint-0 (no `ckf_basis`). Structure actors spawn at yaw 0 except **west player houses** (`HOUSE0`/`HOUSE2`): AC `angle_table` +90° Y maps to Godot `+PI/2` (`Facing.WEST`). `obj_s_myhome1` already bakes joint-0 **−135°** (same as the shop). The diagonal shop door is skeleton yaw, matching the 135° enter angle in `ac_shop_move`. Structure CI palettes come from `anime_1_txt` (`obj_s_house1_a_pal`, `obj_shop1_pal`, `obj_s_myhome_a_pal`, `obj_s_post_office_pal`).

## Original object → mesh

From `m_name_table.h` / `m_bg_type.h` / `ac_sign`. Summer prefix `obj_s_`; winter `obj_w_`; autumn hardwood `obj_f_`.

| Decomp id | Role | Generated mesh |
| --- | --- | --- |
| `BG_TYPE_GRD_S_F_1` | Flat acre terrain | `grd_s_f_1.glb` |
| `TREE` | Full hardwood | `obj_s_tree5.glb` |
| `TREE_APPLE_FRUIT` | Apple tree + fruit overlay | `obj_s_tree5` + `obj_s_tree5_apple` |
| `CEDAR_TREE` | Full cedar | `obj_s_cedar5.glb` |
| `TREE_PALM_FRUIT` | Palm + coconut | `obj_s_palm5` + `obj_s_palm5_coco` |
| `FLOWER_PANSIES0/1/2` | Pansies | `obj_flower_a/b/c.glb` |
| `ROCK_A`–`ROCK_E` | Rocks | `obj_s_stoneA`–`E.glb` |
| Player house stage 1 | `obj_s_myhome1` (`ac_my_house`) | `obj_s_myhome1.glb` |
| Villager house | `obj_s_house1` (`ac_house`) | `obj_s_house1.glb` |
| Nook shop stage 1 | `obj_s_shop1` | `obj_s_shop1.glb` |
| Museum | `obj_s_museum` | `obj_s_museum.glb` |
| Able Sisters | `obj_s_tailor` | `obj_s_tailor.glb` |
| Post office | `obj_s_yubinkyoku` | `obj_s_yubinkyoku.glb` |
| Police box | `obj_s_kouban` | `obj_s_kouban.glb` |
| Wishing well | `obj_s_shrine` | `obj_s_shrine.glb` |
| Train station | `obj_s_station1` | `obj_s_station1.glb` |
| `SIGNBOARD` / `ac_sign` | Field sign (`obj_s_kanban`) | `obj_shop_kanban.glb` until `obj_s_kanban` is converted |
| `ITM_FOOD_APPLE` | Dropped apple | `obj_item_apple_tex.png` on the pickup |
| `int_sum_chair01` | Wood chair | `int_sum_chair01.glb` |
| Squirrel villager | Species skeleton | `squ_1.glb` |
