# Asset pipeline

How to turn a legally obtained Animal Crossing (GameCube) disc into Godot-ready files for **AC Godot**.

Generated Nintendo assets stay **outside git**. The Godot repo only contains conversion scripts, docs, and assets you choose to keep (hand-authored work under `assets/custom/`).

## 1. Required tools

- Python 3.9+
- Pillow (`pip3 install -r tools/requirements.txt`)
- [decomp-toolkit](https://github.com/encounter/decomp-toolkit) `dtk` — downloaded automatically to `tools/.cache/dtk` on first run
- Optional: Godot 4.6+ on `PATH` or at `/Applications/Godot.app` (import validation)
- Optional: `ffmpeg` on `PATH` (OGG encode for `--kind audio`; WAV is the fallback)
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
│   ├── ui/                 # BTI → PNG; inventory/ chrome from REL
│   └── dialogue/           # message_data.bin → JSON graphs (gitignored Nintendo text)
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

Copies/extracts the disc into `work_root/extracted/disc`, decompresses `foresta.rel.szs`, unpacks `*.arc` with `dtk vfs cp`. Re-running extract skips the copy/unpack when the disc inputs and stamp match.

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

River/ocean water surfaces (acre XLU `*_modelT` plus dual water/wave textures):

```sh
python3 tools/build_assets.py --step convert --kind water
```

Reconverts river, marine, open-ocean (`grd_*_o_*`), cliff-edge ocean/marine (`grd_s_e2_o_*` / `e3_m_*`), and cliff-river acres so `grd_*_modelT` is in the GLB and OPA beachB under open ocean is tagged for the wet-sand shader (decomp dark-blue underdraw). Every acre **keeps** its XLU ocean waves alongside OPA shore wet sand (`beachA`) and the dark-blue ocean-floor underdraw (`beachB`). Marine acres draw two wave bands (shore `wave2` 32×64 CLAMP T, open `wave3` 32×32 REPEAT); open-ocean border acres draw the open band only. Grass still wrap-bakes; water keeps REPEAT for UV scroll. Waterfalls (`obj_fallS`) are FG actors, not this step.

The player's clips are named one by one in `PLAYER_CORE_ANIMS`, so a new pose needs adding there and a reconvert (`--step convert`) before the game can play it — `ply_1_putaway_t1`, the catch-report exit, arrived that way.

Held-up catches (one model per fish species):

```sh
python3 tools/build_assets.py --step convert --kind fish
```

Writes `assets/generated/creatures/fish/act_fNN_<romaji>_{a,b}.glb`, two per `aGYO_TYPE_*` up to `aGYO_TYPE_NUM`. Each species has three display lists in `dataobject.obj`, but only two are reachable: `aGYO_anime_frame` returns 0, 1 or 2 and `aGYO_actor_draw_fish` indexes with `(int)(frame * 0.5)`, folding 0 and 1 onto `dl_a` and 2 onto `dl_b`, so `dl_c` is dead art. The needles are the exact `act_fNN_<romaji>_{a,b}` asset ids, which keeps the `_c` jobs out since `"..._a"` is not a substring of `"..._c"`.

Two gotchas. `aGYO_displayList` in `ac_gyoei_model.c_inc` is the only mapping from an `aGYO_TYPE_*` index to a romaji symbol, so add species through it rather than guessing names. And take the Gfx symbol from that table rather than appending the pose letter to the prefix — the names are not always regular, and the coelacanth's `b` pose is `act_f32_kasekiT_model` with no letter (its vertices are still `act_f32_kaseki_b_v`).

Seasonal field/tree albedo packs (runtime material swaps; press **U** in-game to advance season):

```sh
python3 tools/build_assets.py --step convert --kind seasons
```

Writes `assets/generated/environment/seasons/{s,f,w}/` PNGs (`grass`, `grass_0`–`grass_2` for triangle/square/circle town motifs, `earth`, `cliff`, `bush_a`, `bush_b`, `rail`, `stone`, `sand`, `beach_wet`, `river_edge`, `tree_leaf`, `tree_trunk`). Summer and autumn acres share the summer CI bank with different monthly palettes; winter uses the winter bank. Trees use summer CI + season FG palettes, or winter tree art (`obj_w_tree*`) for snow. Field BG bank export covers textures flat acres never draw; river (`grd_s_r*`), beach (`grd_s_m*`), cliff, and shrine (`grd_s_f_ko*`) acre jobs fill earth/sand/wet-shore gaps. `GeneratedVisual.apply_season_textures` swaps albedo on attach (re-tiling wrap-baked acre atlases) including `beach_wet` shore bands. Runtime picks `grass_{bg_tex_idx}.png` from `WorldData.grass_pattern` / `Game.grass_pattern`. Mesh remap (`grd_w_*` / `obj_f_*` / `obj_w_*`) still runs when those GLBs exist. Rebuild this pack after disc extract so grass and snow update even if only summer meshes are present.

FG acre templates (trees/flowers from `fgdata.bin`; needs decomp headers for `data_combi`):

```sh
python3 tools/build_assets.py --step convert --kind fg
```

Inventory window chrome (`inv_mwin_*` from `foresta.rel` → gitignored PNGs, Nintendo IP, reference only):

```sh
python3 tools/build_assets.py --step convert --kind inventory-ui
```

Writes `assets/generated/ui/inventory/`.

Message / talk window chrome (`con_kaiwa2_*`, `con_namefuti_TXT` from `foresta.rel` → gitignored PNGs):

```sh
python3 tools/build_assets.py --step convert --kind message-ui
```

Writes `assets/generated/ui/message/` (`msg_window_body.png`, `msg_nameplate.png`, tile sources). Used by `scenes/ui/dialogue_overlay.tscn`.

Dialogue banks (`message_data.bin` → JSON graphs, Nintendo IP, gitignored):

```sh
python3 tools/build_assets.py --step convert --kind dialogue
```

Writes `assets/generated/dialogue/`. Hand-authored trees stay in `data/dialogue/`. See [decomp_notes/dialogue.md](decomp_notes/dialogue.md).

Villager roster (names / looks / species / starter flag from decomp tables, not disc art):

```sh
python3 tools/build_assets.py --kind villagers --step convert
```

Writes `data/villagers/*.tres` (236 animals). Needs a local `ac-decomp` checkout (`decomp_root` or the usual Documents path).

BGM catalog (`audiorom.img` → gitignored `catalog.json`; Nintendo music, do not commit):

```sh
python3 tools/build_assets.py --kind audio --step convert
```

Writes `assets/generated/audio/catalog.json` and looping `bgm/*.ogg` (gitignored). Needs `audiorom.img`, decomp headers for `BGM_*` → sequence mapping, and `ffmpeg` (vorbis encode; `libvorbis` or native `-strict -2`). Falls back to WAV if encode fails. See [decomp_notes/audio.md](decomp_notes/audio.md).

Or set `"test_set_only": false` in `config.local.json`. Optional `"decomp_root"` points at an `ac-decomp` checkout for FG combis. `--step all` still extract + scan + convert + validate; add `--full` to convert everything.

Test-set convert **overwrites** the files it writes and does not delete `assets/generated/` (so a later test run will not wipe a `--full` library, FG catalog, or inventory UI). `--full` clears work-root `converted/` staging only.

Per-asset failures are recorded and skipped; the run does not stop. The process exits **1** if any convert error occurred or validate is not ok.

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
   A `TEST_STATIC` row wins over the prefix inference, so it is the way in for a display
   list whose name no rule will ever pair with its vertex array (the bobber's
   `tol_uki_1_v` is drawn by `tol_uki1_model`, with no underscore).
3. Re-run `--step convert`.
4. If a new type is unreliable, **stop** and fix the decoder before expanding the test set. `--full` already converts every cKF / static Gfx / BTI the scanner knows.

## 9. Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `game_files must be a disc image or ... files/` | Wrong `game_files` path |
| `REL slice out of range` | Not `GAFE01_00`, or REL not decompressed |
| `KeyError: ..._v` | Prefix does not match `{skeleton without cKF_bs_r_}_v` |
| `No mesh parts decoded` | GBI walker missed triangles, listed DLs are material-only, or the `*_v` name is duplicated in `foresta.map` and the by-name lookup picked the copy the display list does not point at (`_vtx_sym_for_gfx` now follows `G_VTX`) |
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
| Hardwood stump missing / cylinder placeholder | Gfx is `obj_stump5T_*` while verts are `obj_s_stump5_v`. Converter used to skip the job. Reconvert with `--kind plants` |
| ROCK_B–E (`obj_s_stoneB` …) is solid white | Geometry-only Gfx. `bg_item` draws `obj_s_stoneA_mat_model` once (`stone_DL_table[0]`), then `obj_s_stoneB_gfx_model` as `table[1 + sub_idx]`. Converter used to look for a missing `obj_s_stoneB_mat_model`. Reconvert with `--kind plants` |
| Hole (`obj_hole0`) is solid white | Geometry-only Gfx. `hole00_g_list` draws `obj_hole0T_g_mat_model` then `obj_hole0T_gfx_model`. Palette is `obj_g_hole_pal` (no LOADTLUT). Reconvert with `--kind plants` |
| Hole flickers / z-fights the acre | The fan is coplanar with grass. `GeneratedVisual` treats `HOLE*` as a ground decal (no AABB snap, no depth write); `HoleUse` places at `GetBgY(..., -1 GX)` |
| House/shop window blob z-fights the grass | `*_window_model` is an XLU ground decal (`G_RM_AA_ZB_XLU_DECAL2`). Convert keeps it as a BLEND I4-alpha surface. `GeneratedVisual` draws it 1 GX above the acre (not coplanar). Facade glow is a separate opaque `*_light_model` pane |
| Tree leaves are pastel pink/teal | Hardwood fallback used map symbol `mFM_obj_tree_01_pal`, whose REL blob does not CI-decode leaf art. Use `mFM_obj_tree_01_pal_dol` / `obj_tree_pal`. Reconvert trees |
| Summer `obj_s_tree3` leaf is untextured | Disc has only `obj_s_gold_tree3_leafT_mat_model` (no non-gold leaf mat). Converter falls back to the gold mat for SETTIMG |
| Boy torso is a hollow flame X / see-through chest | `G_SETTILESIZE` 128×32 overwrote the shirt’s 32×32 `SETTIMG` size; decode zero-padded with transparent CI0 → MASK holes. Keep tile size separate from image size; UVs still divide by the 32×32 image so REPEAT can bake. Reconvert `boy_1` |
| House/shop lies on its back | GX verts already sit on +Y; do not apply `ckf_basis` (+90° Z). Bake door-clip frame 1 (joint-0 yaw: house −90°, shop/myhome −135°) |
| Player tent is on its side | Weather-vane verts fail the Y-up heuristic. Treat `obj_*_myhome*` as a Y-up structure and bake `cKF_ba_r_obj_s_myhome1` (not `_out`, not `ckf_basis`) |
| Station lies on its side | Same heuristic miss (clock-hand verts). Treat `obj_*_station*` as Y-up and bake `cKF_ba_r_obj_s_station1` (joint-0 identity; skip `ckf_basis`) |
| Shop looks face-on / door due south | Missing anim bind — shop joint-0 Y is **−135°**, not −90° |
| Acre/room meshes have no textures | DLs use runtime segment banks (`0x80` field BG, `0x08–0x0C` house floor/wall). Convert binds those before walking the Gfx |
| Acre grass/earth is a stretched edge colour | REPEAT UVs span the 16×16 cell grid. Wrap must be baked into the PNG (`GeneratedVisual` clamps). Reconvert `--step convert --kind static` |
| Grass colour / tree snow ignore season (U key) | GLBs bake one season into albedo. Build the seasons pack (`--kind seasons`) then press **U**. Runtime swaps grass/earth/cliff/bush/sand/wet-shore/leaf/trunk albedos from `environment/seasons/{s,f,w}/`. Town grass motifs need `grass_0.png`–`grass_2.png` (triangle/square/circle) exported from the three `mFM_grd_*_grass*_tex` CI tiles — not just `grass.png`. River earth strips and beach sand/wet bands need the expanded export (river/beach/shrine acre jobs + field BG bank). Cliff fringe (`bush_a`/`bush_b`) comes from the field BG bank — rebuild seasons after pipeline changes. Autumn recolors summer CI; winter needs the winter field bank + `obj_w_tree*` leaf art in that pack. Mesh remap alone is not enough when only summer GLBs exist. |
| Rivers/ocean look like missing holes or still water | Acre XLU (`grd_*_modelT`) used to be skipped. Convert keeps dual `mFM_grd_water*` / `wave*` tiles (layer1 as glTF occlusionTexture). River acres use `shaders/river_water.gdshader`; ocean acres use `shaders/ocean_water.gdshader`. Reconvert `--kind water`. Still water after that means the GLB was not reimported. |
| Open-ocean bed is solid white / shore wet sand is black | `beach_wet` I4 must be baked as `(PRIM−ENV)×I+ENV` in RGB with I in alpha (not `baseColorFactor×I4`). Skip wrap-bake for `beach_wet`. Runtime `beach_wet.gdshader` mixes ENV/PRIM from alpha I (do not add env onto baked RGB). Reconvert `--kind water` if the GLB bake is wrong. |
| Ocean is near-invisible white cracks over a dark bed | GX `IA4` packs **AAAAIIII** (alpha high nibble, intensity low). Decoding it as `IIIIAAAA` leaves wave maps bright with ~18% peak alpha, so `PRIM×SHADE` never tints the `beachB` underdraw and only the cell outlines show. Correct decode gives dark I / ~50% A and deep-water ≈ `(41,74,174)`. Affects every `G_IM_FMT_IA, G_IM_SIZ_8b` texture, not just waves — reconvert broadly, not just `--kind water` |
| Water cells look like a hard pixel grid | The XLU water shaders must sample `filter_linear` (`m_rcp` sets `G_TF_BILERP` globally); the project-wide `filter_nearest` shreds 32px cell maps stretched over an acre. On a `repeat_enable` sampler, any non-REPEAT hardware wrap then needs a half-texel inset — ocean `wave2` CLAMP T, splash `GX_MIRROR` S — or the linear tap wraps to the far edge and leaves a seam |
| Shore crash is a rigid line (not curvy) | Ocean layer1 (wave2) must keep tile1 **CLAMP T** in the GLB occlusion sampler + `extras.wave2_clamp_t`. Convert used to force REPEAT/REPEAT. Also check the acre `.glb.import`: LODs off, `force_disable_compression=true`, `gltf/embedded_image_handling=3` (Embed as Uncompressed). A bad reimport (LODs/compression/Extract) flattens the shore mesh/UVs and drops wave2 CLAMP — `python3 -c "from asset_pipeline.godot_import import apply_import_settings; print(apply_import_settings(__import__('pathlib').Path('assets/generated/environment/acres')))"` then reimport. Reconvert `--kind water` if the GLB itself is stale. |
| Object part is solid white (`seg_08` / `seg_09` / `seg_0A`) | Gfx samples `anime_N_txt` (dummy `gSPSegment` slots). Actor draw binds the real pal/tex at runtime (shrine leaf → tree leaf + FG pal; house mark → `obj_myhome_mark_*`). Convert resolves unbound anime SETTIMG from REL textures of the same byte size whose name shares the Gfx part (`leaf`, `mark`). Dummy LOADTLUT pals must also share the object family (`myhome`+`mark`) — a generic `front`/`door`/`leaf` hit must not replace the structure TLUT (that recolored shops/houses). Reconvert with `--kind buildings`. Save-data slots (statue faces, some flags) stay white if the REL has no stand-in |
| Boy cheek/skin is shirt-yellow | Pending tris were flushed after the next shirt `G_LOADTLUT`; flush before TLUT |
| Leaves/cutouts show a black/gray box | Texture has alpha but GLB material was `OPAQUE`; use `MASK`/`BLEND` from PNG alpha |
| Player GLB is ~3.5–4.8 m before Godot scale | Pipeline `scale` 0.001 is not the draw matrix. Actors are `0.01`; acres are `0.0625`. `FieldCatalog.actor_uniform_scale()` (0.5) maps the player into the 2 m cell grid |
| Magenta PNG | Unsupported BTI format (CI14X2 still incomplete) |
| Invisible walls in grass / falling into rivers | Collision was a guessed strip or a gravity hole. Need `grd_*.col.json`; water is a heightfield plus bank walls, not `NO_FLOOR` |
| One acre boxed in by a tall wall | Dummy TRACKS `data_bgd` rows reuse a field mesh (`grd_s_c1_3_1`, …) with HEIGHT_MAX floors. Sidecars must keep the first outdoor table for that mesh; `FieldCatalog` skips filler variants. Reconvert with `--kind collision` |

## 10. Godot import settings

- **2D:** project default canvas texture filter is **Nearest**.
- **3D textures:** generated GLBs use `gltf/embedded_image_handling = Embed as Uncompressed` so Godot does not extract them and VRAM-compress (S3TC) 16×16 CI art. PNG imports use lossless, no mipmaps. Materials use nearest filtering. Do not upscale, sharpen, or AI-enhance.
- **GLB meshes:** import with LODs off and vertex compression off. Tiny N64 meshes look destroyed if Godot generates LODs. cKF models bake **identity-rotation bind pose** (joint translations only) then rotate +90° about Z so the rest chain along +X stands on +Y — except meshes that already sit on +Y (houses, shops): those skip the stand-up and bake **door-clip frame 1**, whose joint-0 Y constant is the rest yaw (house **−90°**, shop **−135°**, degrees×10 in the cKF tables). Actors still spawn at yaw 0; the angle is in the skeleton pose, not `WorldBuilder`. That matches an assembled Blender `BOY.dae` skeleton for characters. Do not use Cuyler `(-x,z,y)` on the assembled mesh. Static (non-cKF) meshes keep GX Z. Reconvert static Gfx after a Z-axis change with `--step convert --kind static` (does not wipe cKF). Reconvert house/shop with `--step convert --kind buildings`. Reconvert palms/cedars/fruit overlays, ROCK_B–E, hardwood stumps, and holes with `--step convert --kind plants`. Reconvert river/ocean acres (`grd_*_modelT`) with `--step convert --kind water`.
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
- Villager species (`cat_1`, `bev_1`, …) embed the shared `cKF_ba_r_npc_1_*` bank. Pose evaluation is cached across species (same clip tables); rest translations still differ so each GLB has its own tracks. Test-set convert bakes wait/walk/run only.
- Static meshes include `*_gfx_model` and plain `*_model` DLs. Room shells (`rom_*` → `environment/interiors/`) and outdoor acre tiles (`grd_*` → `environment/acres/`) come from that path. Acre DLs sample dummy segment `0x80` (grass/earth/cliff/bush); convert materializes the summer bank from `l_bg_tex_segment_rom_start_s_0` + palettes. Player-house floor/wall DLs sample segments `0x08–0x0C` from `player_room_floor.bin` / `player_room_wall.bin` (style 0). A few interiors (`rom_uranai`, `room01`) use classic N64 `G_SETTILE` / `G_SETTILESIZE` instead of `G_SETTILE_DOLPHIN`.
- Model textures are GX CI4/CI8 with RGB5A3 palettes. Pending tris flush before `G_LOADTLUT` / prim / tile changes so the palette active at draw time is the one baked into the PNG. Segment banks use one path for every cKF prefix: REL `{prefix}_pal` / `eye1` / `mouth1` / `tmem_txt` when present, else archive `face_{species}.bin` + `tex_{species}.bin` + `pallet_{species}.bin` (shirt index 0). Unbound `anime_N_txt` SETTIMG/LOADTLUT (segments `0x08–0x0F`) resolve from same-size REL textures whose name shares the Gfx part (`leaf` → hardwood leaf tex + FG pal; `mark` → `obj_myhome_mark_*`). I4/IA are modulated by `G_SETPRIMCOLOR`.
- `scale` 0.001 is a shared Vtx multiplier. Godot then applies actor `0.01` vs acre `0.0625` so meshes share 40 GX = 2 m. Do not AABB-fit pipeline meshes to invented meters.
- Audio (`audiorom.img`) converts via `--kind audio` to gitignored `catalog.json` + looping OGG. The mixer follows original envelopes, vibrato, and portamento; it still skips DSP filters/reverb and weather subtrack mutes. Do not commit Nintendo music.
- Terrain grass is textures + generated collision in the original game, not one mesh. Water should be a Godot shader/particles, not a GX port.
- Effects: document appearance, then recreate with `GPUParticles3D`. Do not port JPA.
- REL `.data` offset is hardcoded for `GAFE01_00`.
- BTI: CI14X2 incomplete; IA4 added but less common on this disc.
- Shadow blobs (`*_shadow_v`) are skipped; Godot uses the sun.
- Famicom `*.bti.szs` on this dump are already uncompressed BTI (not Yaz0); the converter reads them directly.
- Standalone REL texture PNGs under `textures/rel/` infer CI4 dimensions from symbol size; a nearby `_pal` is required (skipped otherwise). Garbage palettes are still possible for textures never referenced by a display list.

See [asset_pipeline_research.md](asset_pipeline_research.md) for format and tool decisions.
