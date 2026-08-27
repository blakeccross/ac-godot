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
│   │   ├── acres/          # grd_* outdoor ground tiles
│   │   ├── trees/
│   │   ├── flowers/
│   │   └── rocks/
│   ├── furniture/          # int_*
│   ├── items/              # tol_*
│   ├── textures/
│   │   ├── player/faces|shirts/
│   │   ├── rooms/floor|wall/
│   │   └── rel/            # named REL CI dumps
│   └── ui/                 # BTI → PNG
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
  → copy into assets/generated/
  → validate
```

Full library (every cKF skeleton, static Gfx, BTI, player face/shirt bins, room floor/wall, REL `*_tex*`):

```sh
python3 tools/build_assets.py --step convert --full
```

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
| Acre/room meshes have no textures | DLs use runtime segment banks (`0x80` field BG, `0x08–0x0C` house floor/wall). Convert binds those before walking the Gfx |
| Boy cheek/skin is shirt-yellow | Pending tris were flushed after the next shirt `G_LOADTLUT`; flush before TLUT |
| Leaves/cutouts show a black/gray box | Texture has alpha but GLB material was `OPAQUE`; use `MASK`/`BLEND` from PNG alpha |
| Player is ~3.5–4.8 m tall | `scale` 0.001 is a first guess; tune in `config.local.json` once we match in-game units |
| Magenta PNG | Unsupported BTI format (CI14X2 still incomplete) |
| Godot missing `assets/generated/...` | Run convert; those files are gitignored |

## 10. Godot import settings

- **2D:** project default canvas texture filter is **Nearest**.
- **3D textures:** generated GLBs use `gltf/embedded_image_handling = Embed as Uncompressed` so Godot does not extract them and VRAM-compress (S3TC) 16×16 CI art. PNG imports use lossless, no mipmaps. Materials use nearest filtering. Do not upscale, sharpen, or AI-enhance.
- **GLB meshes:** import with LODs off and vertex compression off. Tiny N64 meshes look destroyed if Godot generates LODs. cKF models bake **identity-rotation bind pose** (joint translations only) then rotate +90° about Z so the rest chain along +X stands on +Y. That matches an assembled Blender `BOY.dae` skeleton. Do not use wait-pose or Cuyler `(-x,z,y)` on the assembled mesh. Static (non-cKF) meshes still use a Z flip at vertex parse.
- **GLB:** N64 Vtx `cn[]` values are lighting normals, not albedo, so they are omitted. Embedded textures use nearest filtering; do not upscale.
- **Scale:** vertices are multiplied by `0.001`. Display-list `G_VTX` loads from addresses in `{prefix}_v` (same as [Cuyler36's model editor](https://github.com/Cuyler36/Animal-Crossing-Model-Editor)). UVs are `s/width`, `t/height` (no V flip — a flip put the player nose above the eyes).
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
- `scale` 0.001 currently makes the standing player about 3.5 m tall; we have not matched original world units yet.
- Audio (`audiorom.img`) is not converted.
- Terrain grass is textures + generated collision in the original game, not one mesh. Water should be a Godot shader/particles, not a GX port.
- Effects: document appearance, then recreate with `GPUParticles3D`. Do not port JPA.
- REL `.data` offset is hardcoded for `GAFE01_00`.
- BTI: CI14X2 incomplete; IA4 added but less common on this disc.
- Shadow blobs (`*_shadow_v`) often have no triangles in the listed DLs; they are recorded as errors and skipped.
- Famicom `*.bti.szs` on this dump are already uncompressed BTI (not Yaz0); the converter reads them directly.
- Standalone REL texture PNGs under `textures/rel/` infer CI4 dimensions from symbol size; a nearby `_pal` is used when one exists. Garbage palettes are possible for textures never referenced by a display list.

See [asset_pipeline_research.md](asset_pipeline_research.md) for format and tool decisions.
