# Asset pipeline

How to turn a legally obtained Animal Crossing (GameCube) disc into Godot-ready files for **AC Godot**.

Generated Nintendo assets stay **outside git**. The Godot repo only contains conversion scripts, docs, and assets you choose to keep (hand-authored work under `assets/custom/`).

## 1. Required tools

- Python 3.9+
- Pillow (`pip3 install -r tools/requirements.txt`)
- [decomp-toolkit](https://github.com/encounter/decomp-toolkit) `dtk` — downloaded automatically to `tools/.cache/dtk` on first run
- Optional: Godot 4.6+ on `PATH` or at `/Applications/Godot.app` (import validation)
- A disc image or Dolphin-extracted folder you already own (`GAFE01`)

## 2. Installation

```sh
cd /path/to/ac-godot
pip3 install -r tools/requirements.txt
cp tools/config.example.json tools/config.local.json
```

Edit `tools/config.local.json` (gitignored):

```json
{
  "game_files": "/absolute/path/to/Animal Crossing (USA)",
  "work_root": "/absolute/path/to/ac-assets-work",
  "godot_generated": "assets/generated",
  "dtk_path": "tools/.cache/dtk",
  "scale": 0.001,
  "test_set_only": true
}
```

`game_files` may be:

- A Dolphin dump directory that contains `files/` and `sys/`
- The `files/` directory itself
- A `.iso` / `.gcm` / `.rvz` path (`dtk disc extract`)

Do **not** put the disc image inside this repository.

## 3. Required input files

From the US disc (`GAFE01_00`):

- `files/forest_1st.arc`, `files/forest_2nd.arc`
- `files/foresta.rel.szs` (or already-decompressed `foresta.rel`)
- `files/foresta.map`

## 4. Directory structure

Work root (outside the Godot repo, configured as `work_root`):

```
ac-assets-work/
├── extracted/
│   ├── disc/          # copy of files/ + sys/
│   └── archives/      # unpacked RARC
├── converted/         # Godot-ready GLB/PNG (staging)
└── manifests/
	├── assets.json
	├── conversion_report.json
	├── id_map.json
	└── validation_report.json
```

Godot project:

```
assets/
├── generated/              # copies of converted/  (gitignored)
│   ├── characters/
│   │   ├── player/         # boy_1 (US disc has no separate girl_1 skeleton)
│   │   ├── villagers/      # species skeletons + full npc_1 anim bank
│   │   └── other/          # non-species cKF leftovers
│   ├── effects/            # ef_*
│   ├── environment/
│   │   ├── interiors/      # rom_* room shells (floors/walls/shops)
│   │   ├── acres/          # grd_* outdoor ground tiles + grd_*.col.json collision
│   │   ├── fg/             # catalog.json from fgdata.bin + data_combi
│   │   ├── trees/
│   │   ├── flowers/
│   │   └── rocks/
│   ├── furniture/          # int_*
│   ├── items/              # tol_*
│   ├── textures/
│   │   ├── player/faces|shirts/
│   │   ├── rooms/floor|wall/
│   │   └── rel/            # named REL CI dumps
│   └── ui/                 # BTI → PNG; inventory/ chrome from REL
└── custom/                 # hand-authored; never overwritten by the pipeline

tools/
├── build_assets.py
├── config.example.json
├── config.local.json  # gitignored
└── asset_pipeline/    # extract / scan / convert / validate
```

## 5. Extraction

```sh
python3 tools/build_assets.py --step extract
```

Copies/extracts the disc into `work_root/extracted/disc`, decompresses `foresta.rel.szs`, unpacks `*.arc` with `dtk vfs cp`.

## 6. Conversion

Test set only (default):

```sh
python3 tools/build_assets.py --step convert
```

Pipeline:

```
disc image
  → files/ + unpacked RARC
  → scan manifest
  → REL symbol slice (cKF / Vtx / Gfx) or BTI
  → GLB / PNG
  → `data_bgd` → `grd_*.col.json` (16×16 heightfield paired with each acre mesh)
  → copy into assets/generated/
  → validate
```

Full library (every cKF skeleton, static Gfx, BTI, player face/shirt bins, room floor/wall, REL `*_tex*`):

```sh
python3 tools/build_assets.py --step convert --full
```

Acre collision only (no mesh reconvert):

```sh
python3 tools/build_assets.py --step convert --kind collision
```

Writes `assets/generated/environment/acres/grd_*.col.json` from `data_bgd` in `foresta.rel` (paired with each acre mesh). Do not copy `bg_data.c` into this repo.

FG acre templates (trees/flowers from `fgdata.bin`; needs decomp headers for `data_combi`):

```sh
python3 tools/build_assets.py --step convert --kind fg
```

Inventory window chrome (`inv_mwin_*` from `foresta.rel` → gitignored PNGs, Nintendo IP, reference only):

```sh
python3 tools/build_assets.py --step convert --kind inventory-ui
```

Writes `assets/generated/ui/inventory/`.

Or set `"test_set_only": false` in `config.local.json`. `--step all` still extract + scan + convert + validate; add `--full` to convert everything.

Per-asset failures are recorded and skipped; the run does not stop.

## 7. Building the asset manifest

```sh
python3 tools/build_assets.py --step scan
```

Writes deterministic JSON to `work_root/manifests/assets.json` (`sort_keys`, sorted paths). Each entry includes original path/name, format, category, size, suggested converter, optional `output_path`, conversion status.

`manifests/id_map.json` maps original IDs (`cKF_bs_r_boy_1`, `forest_2nd/data/boy1.bti`, …) to Godot asset IDs and output paths. Uncertain identities keep the original identifier and `confident_name: false`.

## 8. Adding new asset types

1. Identify the symbol or file in `assets.json` / `foresta.map`. Do not invent a villager personal name.
2. Add a row to `tools/asset_pipeline/test_set.py`:
   - cKF: `TEST_SKELETONS` with `cKF_bs_r_*` and `{prefix}_v`
   - Static Gfx: `TEST_STATIC` with `*_v` + `*_gfx_model`
   - BTI: `TEST_BTI`
3. Re-run `--step convert`.
4. If a new type is unreliable, **stop** and fix the decoder before expanding the test set. `--full` already converts every cKF / static Gfx / BTI the scanner knows.

## 9. Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `game_files must be a disc image or ... files/` | Wrong `game_files` path |
| `REL slice out of range` | Not `GAFE01_00`, or REL not decompressed |
| `KeyError: ..._v` | Prefix does not match `{skeleton without cKF_bs_r_}_v` |
| `No mesh parts decoded` | GBI walker missed triangles, or listed DLs are material-only |
| Player looks like stacked parts along +X | Bind bake missing the +90° Z stand-up (`ckf_bind_to_godot`) |
| Player is exploded shards / rainbow | Old GPU-skin export mixed joints and used lighting normals as vertex colors |
| Limbs attached to the wrong bones | G_VTX w1 is an address into `{prefix}_v`, not sequential consumption in DL file order |
| Body seams look flipped / folded, head OK | `G_MTX` 0x0D slots were ignored; seam verts must skin to the parent joint |
| Holes in meshes / one side of a symmetric tip folded inward | Vertex dedupe used `id(src)`; after `G_VTX` reloads the cache, CPython reuses object ids so later verts map to earlier ones. Key on `src_index` instead |
| Left side of shirt (or other tiled body art) looks stuck/wrong | Shirt UVs go past 1.0 with `wrapS=REPEAT` but `wrapT=CLAMP`; Godot’s one `texture_repeat` flag often clamps both. Bake REPEAT/MIRROR into the PNG and normalize UVs to 0–1 |
| Villager/body textures are grayscale | CI4 missing `{prefix}_pal` (NPC DLs skip LOADTLUT) or I4/IA without `G_SETPRIMCOLOR` tint |
| House/shop is grayscale | CI4 loads `anime_1_txt` (segment 0x08). Bind `obj_s_house1_a_pal` / `obj_shop1_pal` from `structure_pal`, not `{prefix}_pal` |
| Player house / post office is grayscale | Same `anime_1_txt` bank. `obj_s_myhome1` maps to `obj_s_myhome_a_pal` (strip the stage digit); `obj_s_yubinkyoku` aliases to `obj_s_post_office_pal` (winter: `obj_s_post_office_winter_pal`) |
| Palm/cedar is black-and-white | CI4 leaf/trunk (`obj_s_palm_*_tex`, `obj_s_cedar_*_tex`) never LOADTLUT. Runtime uses `mFM_obj_palm_01_pal` / `mFM_obj_tree_01_pal_dol` (`mFM_SetFGPal`). Fallback used to require `"tree"` in the symbol name. Reconvert with `--step convert --kind plants` |
| Fruit overlay (`obj_s_tree5_apple`, `obj_*_palm5_coco`) is solid white | Overlay Gfx is triangles only. `bg_item` draws `apple_DL_mode` / `obj_item_cocoT_mat_model` first (`tree4_ap_list` / `palm5_coco_list`). Converter used to look for a missing `*_mat_model` and export an untextured white PBR. Reconvert with `--kind plants` |
| Tree leaves are pastel pink/teal | Hardwood fallback used map symbol `mFM_obj_tree_01_pal`, whose REL blob does not CI-decode leaf art. Use `mFM_obj_tree_01_pal_dol` / `obj_tree_pal`. Reconvert trees |
| Summer `obj_s_tree3` leaf is untextured | Disc has only `obj_s_gold_tree3_leafT_mat_model` (no non-gold leaf mat). Converter falls back to the gold mat for SETTIMG |
| Boy torso is a hollow flame X / see-through chest | `G_SETTILESIZE` 128×32 overwrote the shirt’s 32×32 `SETTIMG` size; decode zero-padded with transparent CI0 → MASK holes. Keep tile size separate from image size; UVs still divide by the 32×32 image so REPEAT can bake. Reconvert `boy_1` |
| House/shop lies on its back | GX verts already sit on +Y; do not apply `ckf_basis` (+90° Z). Bake door-clip frame 1 (joint-0 yaw: house −90°, shop/myhome −135°) |
| Player tent is on its side | Weather-vane verts fail the Y-up heuristic. Treat `obj_*_myhome*` as a Y-up structure and bake `cKF_ba_r_obj_s_myhome1` (not `_out`, not `ckf_basis`) |
| Station lies on its side | Same heuristic miss (clock-hand verts). Treat `obj_*_station*` as Y-up and bake `cKF_ba_r_obj_s_station1` (joint-0 identity; skip `ckf_basis`) |
| Shop looks face-on / door due south | Missing anim bind — shop joint-0 Y is **−135°**, not −90° |
| Acre/room meshes have no textures | DLs use runtime segment banks (`0x80` field BG, `0x08–0x0C` house floor/wall). Convert binds those before walking the Gfx |
| Boy cheek/skin is shirt-yellow | Pending tris were flushed after the next shirt `G_LOADTLUT`; flush before TLUT |
| Leaves/cutouts show a black/gray box | Texture has alpha but GLB material was `OPAQUE`; use `MASK`/`BLEND` from PNG alpha |
| Player GLB is ~3.5–4.8 m before Godot scale | Pipeline `scale` 0.001 is not the draw matrix. Actors are `0.01`; acres are `0.0625`. `FieldCatalog.actor_uniform_scale()` (0.5) maps the player into the 2 m cell grid |
| Magenta PNG | Unsupported BTI format (CI14X2 still incomplete) |
| Invisible walls in grass / falling into rivers | Collision was a guessed strip or a gravity hole. Need `grd_*.col.json`; water is a heightfield plus bank walls, not `NO_FLOOR` |
| One acre boxed in by a tall wall | Dummy TRACKS `data_bgd` rows reuse a field mesh (`grd_s_c1_3_1`, …) with HEIGHT_MAX floors. Sidecars must keep the first outdoor table for that mesh; `FieldCatalog` skips filler variants. Reconvert with `--kind collision` |

## 10. Godot import settings

- **2D:** project default canvas texture filter is **Nearest**.
- **3D textures:** generated GLBs use `gltf/embedded_image_handling = Embed as Uncompressed` so Godot does not extract them and VRAM-compress (S3TC) 16×16 CI art. PNG imports use lossless, no mipmaps. Materials use nearest filtering. Do not upscale, sharpen, or AI-enhance.
- **GLB meshes:** import with LODs off and vertex compression off. Tiny N64 meshes look destroyed if Godot generates LODs. cKF models bake **identity-rotation bind pose** (joint translations only) then rotate +90° about Z so the rest chain along +X stands on +Y — except meshes that already sit on +Y (houses, shops): those skip the stand-up and bake **door-clip frame 1**, whose joint-0 Y constant is the rest yaw (house **−90°**, shop **−135°**, degrees×10 in the cKF tables). Actors still spawn at yaw 0; the angle is in the skeleton pose, not `WorldBuilder`. That matches an assembled Blender `BOY.dae` skeleton for characters. Do not use Cuyler `(-x,z,y)` on the assembled mesh. Static (non-cKF) meshes keep GX Z. Reconvert static Gfx after a Z-axis change with `--step convert --kind static` (does not wipe cKF). Reconvert house/shop with `--step convert --kind buildings`. Reconvert palms/cedars/fruit overlays with `--step convert --kind plants`.
- **GLB:** N64 Vtx `cn[]` values are **lighting normals** (signed bytes under `G_LIGHTING`), not albedo. Export them as glTF `NORMAL` so Godot’s sun/moon/ambient match the original LightsN path. Do not treat them as vertex colors. Embedded textures use nearest filtering; do not upscale.
- **Scale:** vertices are multiplied by `0.001` so s16 GX values fit in a glTF. That is **not** the in-game draw scale. Actors use `Matrix_scale(0.01)` (`m_actor.c`); acre DLs store verts 16× and undo with `Matrix_scale(0.0625)` (`ac_field_draw.c`). `FieldCatalog` applies `draw_scale / 0.001 * 0.05` so 40 GX = one 2 m cell. Display-list `G_VTX` loads from addresses in `{prefix}_v` (same as [Cuyler36's model editor](https://github.com/Cuyler36/Animal-Crossing-Model-Editor)). UVs are `s/width`, `t/height` (no V flip — a flip put the player nose above the eyes).
- **Acre collision:** each `mFM_bg_data_c` holds gfx plus `collision[16][16]`. Sidecars use our JSON (`c,nw,sw,se,ne,s,a`), not a dump of the C struct. Heights are ×10 GX; land datum is count 4. Some later rows reuse an outdoor mesh with a HEIGHT_MAX / FLOOR table (`GRD_S_C1_3_1` on TRACKS8). Key by mesh name but **keep the field table**, not the dummy.
- **Generated vs custom:** never overwrite `assets/custom/`. Pipeline writes only `assets/generated/`.

Preview (after convert):

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/dev/asset_preview.tscn
```

## 11. Known limitations

- Player `boy_1.glb` is a **skinned** GLB: wait-frame-1 bind (already stands on +Y), IBMs, and every `cKF_ba_r_ply_1_*` clip. The US disc has **no** `cKF_bs_r_girl_1` / `girl_1_v` — only `boy_1` plus UI portraits (`girl1.bti`…). Girl clothing/face selection is runtime data on that shared player mesh, not a second skeleton. Models without wait use identity bind + +90° Z. Materials are `doubleSided`. Shirt and hat both sample segment `0x0A` (same 32×32 CI4); wrap/UVs differ, so they stay separate materials. Out-of-range REPEAT/MIRROR UVs are baked into a tiled PNG with UVs remapped to 0–1 (Godot cannot express per-axis wrap). Limb/chest DLs switch `G_MTX` mid-list (segment `0x0D`); seam vertices are weighted to the parent joint, not the DL owner.
- Villager species (`cat_1`, `bev_1`, …) bake the full shared `cKF_ba_r_npc_1_*` bank (~244 clips), matching the game.
- Static meshes include `*_gfx_model` and plain `*_model` DLs. Room shells (`rom_*` → `environment/interiors/`) and outdoor acre tiles (`grd_*` → `environment/acres/`) come from that path. Acre DLs sample dummy segment `0x80` (grass/earth/cliff/bush); convert materializes the summer bank from `l_bg_tex_segment_rom_start_s_0` + palettes. Player-house floor/wall DLs sample segments `0x08–0x0C` from `player_room_floor.bin` / `player_room_wall.bin` (style 0). A few interiors (`rom_uranai`, `room01`) use classic N64 `G_SETTILE` / `G_SETTILESIZE` instead of `G_SETTILE_DOLPHIN`.
- Model textures are GX CI4/CI8 with RGB5A3 palettes. Pending tris flush before `G_LOADTLUT` / prim / tile changes so the palette active at draw time is the one baked into the PNG. Segment banks use one path for every cKF prefix: REL `{prefix}_pal` / `eye1` / `mouth1` / `tmem_txt` when present, else archive `face_{species}.bin` + `tex_{species}.bin` + `pallet_{species}.bin` (shirt index 0). I4/IA are modulated by `G_SETPRIMCOLOR`.
- `scale` 0.001 is a shared Vtx multiplier. Godot then applies actor `0.01` vs acre `0.0625` so meshes share 40 GX = 2 m. Do not AABB-fit pipeline meshes to invented meters.
- Audio (`audiorom.img`) is not converted.
- Terrain grass is textures + generated collision in the original game, not one mesh. Water should be a Godot shader/particles, not a GX port.
- Effects: document appearance, then recreate with `GPUParticles3D`. Do not port JPA.
- REL `.data` offset is hardcoded for `GAFE01_00`.
- BTI: CI14X2 incomplete; IA4 added but less common on this disc.
- Shadow blobs (`*_shadow_v`) often have no triangles in the listed DLs; they are recorded as errors and skipped.
- Famicom `*.bti.szs` on this dump are already uncompressed BTI (not Yaz0); the converter reads them directly.
- Standalone REL texture PNGs under `textures/rel/` infer CI4 dimensions from symbol size; a nearby `_pal` is used when one exists. Garbage palettes are possible for textures never referenced by a display list.

See [asset_pipeline_research.md](asset_pipeline_research.md) for format and tool decisions.
