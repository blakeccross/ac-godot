# Interiors (houses, public rooms, enter/exit)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not copy `mHm_hs_c` or field-id enums as architecture.

**Read before implementing:** `House`, `Room`, `FurniturePlacement`, `Interior`, `InteriorCatalog`, `InteriorBook`.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_field_info.h` | Indoor field ids (`mFI_FIELD_ROOM_*`, NPC rooms, player rooms) |
| `include/m_home.h`, `src/game/m_home.c` | Player house size, main/upper/basement templates (`l_proom_*_tmp`) |
| `include/m_scene.h` | `SCENE_MY_ROOM_*` size variants |
| `include/m_collision_bg.h` | Unit grid + furniture footprints (same as outdoor) |
| `include/m_room_type.h` | FTR size 1×1 / 1×2 / 2×2; facing |
| `src/data/npc/house_list.c` | Per-animal wall, carpet, house type (`npc_house_list`) |

Indoor fields are still a **16×16 unit grid** (`UT_X_NUM`). Walls occupy units (`RSV_WALL_NO`); the walkable rectangle grows with house size. Public interiors (shop, museum wings, post, police, Able Sisters, …) are separate field ids, not player `mHm_hs_c`. NPC houses are pre-arranged FTR on `mFI_FIELD_NPCROOM*` with wall/floor from `npc_house_list`.

## Reproduce

- Same `WorldGrid` as outdoor (2 m cells, occupancy, 90° facing, footprints).
- Enter / exit swaps the playable field (Godot scene), remembering outdoor pose.
- Outdoor enter plays the structure door cKF and player `OPEN1` together (`StructureDoor` + `begin_door_enter`), then changes scene. Door camera / triforce wipe wait.
- Indoor leave is a walk-on warp: stepping onto `Room.door_cell` (`EXIT_DOOR`) plays player `INTO_S1` walking south through the exit, then `Game.exit_interior` — no A press. Outdoor spawn then plays structure leave + player `GO_OUT` (`StructureDoor.play_emerge` / `mPlayer_INDEX_OUTDOOR`).
- Every GC indoor field id exists as a `Room` template (shops, museum wings, NPC 0–14, player main/upper/basement, tent, lighthouse, cottage, …).
- Each animal also has a named room (`npc_filbert`, …) using `npc_house_list` wall/carpet indexes. Outdoor `npc_house_*` plots bind `resident_id` so entering loads that villager’s room.
- Indoor shells use pipeline GLBs. NPC homes match Arrange_Room: `rom_myhome2_floor` + `rom_myhome2_wall` with carpet/wallpaper from `player_room_*.bin` (64×64 pages). Do not paint those banks onto `room01`’s embedded 64×32 `room_floor` — UVs and repeat count will be wrong. Player main uses `rom_myhome1_*`; shops/museum/tailor/tent have their own `rom_*`. Museum wings use `rom_museum1`–`rom_museum5` (+ `rom_museum4_wall` / `rom_museum4_ue` / `rom_museum5_wall`); leave wall/floor ids empty so baked TEX_EDGE materials stay. Only `player_room_wall` / `player_room_floor` / carpet surfaces take bank styles — generic `*floor*` / `*wall*` names on museum/tailor shells must not. Window/exit trim (`rom_myhome_window_tex`, `rom_myhome_enter*_tex`) keep baked TEX_EDGE textures — do not classify them as wallpaper just because the parent mesh is `*_wall`. Placeholder boxes remain when the local pipeline has not been run. Collision is one floor slab plus four wall boxes — not a body per cell. `rom_*` stay at acre scale (do not AABB-stretch). Translate the **floor** min-corner onto the walkable rect — walls/door alcoves are larger and must not shrink the carpet off the FG grid. Combined shells (`rom_museum1`) resolve floor AABB from materials named `*floor*`, not only child nodes named `*_floor`. `rom_myhome1_floor` at acre scale is the small-house 4×4 (`l_proom_s_tmp`); `rom_myhome2_floor` is the 6×6 NPC / medium size. Player main inner size must match that 4×4 so wall boxes sit on the visible walls, not a 6×6 pocket past them. Style ids must be bank indexes (`wall_03`, `floor_38`); named tints like `wall_cream` do not resolve to PNGs and would overwrite the shell with a solid color.
- Player small main starts with the crate and cassette from `mHm_SetDefaultPlayerRoomData` (orange box at the NW inner cell, tape deck three units east). Wallpaper/carpet follow `l_mHm_player_room_default_data[0]` (stone wall 3, old flooring 38). Saves that still have cream/wood tints, the old placeholder chair at (6, 7), furniture from the old centered 6×6, or an empty default-styled main room are upgraded on load.
- Named villager rooms (`npc_filbert`, …) are created on first lookup, not at catalog load.
- NPC furniture comes from disc `fgnpcdata.bin` via `npc_house_list.main_layer_id` (`assets/generated/environment/fg/npc_rooms.json`). Inner walkable grid is the NW 6×6 (`1,1`). Facing uses `aMR_angle_table` (EAST +90°), not outdoor house yaw. TYPEB rest is 2×1 east (`aFTR_SHAPE_TYPEB_0`); TYPEC sits a half-unit past the stored cell and always occupies the SE 2×2 (`mRmTp_size_l_data`) — facing rotates the mesh only. Actor Y stays authored (piano pedals dip below the floor; do not AABB-lift to that min). cKF cabinets bake clip frame 1 (closed, rest yaw in the constants) and do not autoplay. `aFTR_PROFILE.scale` is 0.01 except `int_ari_isu01` (0.1). Mannequins (`iam_fmanekin`) share `obj_shop_manekin`; the shirt is `tex_boy.bin` index `(item - FTR_CLOTH_START) >> 2` on `anime_1_txt` / seg 8. Shirt UVs repeat in S (U up to 2); runtime tiles the PNG and keeps clamp. Saves that predate `cloth_index` refill from the NPC layout.
- Player and villager homes pin the 3/4 camera to the room center (small indoor fields lock look-at when the follow border inverts). Distance is at least Camera2 620 (31 m) so the near wall stays on screen; larger shells zoom out further. Shops and other public interiors still follow the player.
- Nook and Able Sisters interiors spawn a counter plus that day's goods (mannequins at Able). Those nodes are not `Room.placements`, so they are not decorate-able.
- Wall/floor style swaps re-tile into the shell’s wrap-baked atlas so UVs stay correct. Floors use `GX_MIRROR` (odd atlas cells flipped); walls use REPEAT.
- Wall and floor are room fields. Player house can decorate.

## Simplify

- One playable player room (small main). Upper/basement exist as data until loans.
- Shop upgrades are alternate rooms; the town shop enters `shop0`.
- Museum wings are enterable rooms with donation displays (`MuseumBook` + `MuseumPresenter`). Completion treadmill / mail-in fossils wait until earned.
- Island cottage is catalog-only until island is in scope.
- No indoor villager actors yet (outdoor `IN_HOUSE` already hides them).

## Ignore

- Four-player houses, Famicom rooms, e-Reader, `NPCROOM_FIELD_TOOL_INSIDE`.
- Secondary FG2 layers (usually empty).
- Outlook palette / house exterior color as a system.
