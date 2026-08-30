# Asset pipeline research

Investigation of formats and tools for converting a legally obtained Animal Crossing (GameCube, `GAFE01`) disc into Godot-native assets.

This is **not** a J3D (BMD/BDL) game. Animal Crossing GC is an N64 port. Almost all 3D data lives inside `foresta.rel` as cKF skeletons, F3DEX2-style `Vtx` arrays, and Dolphin-GBI display lists. SuperBMD / GCFT J3D conversion is the wrong primary path.

Do not download or search for pre-extracted Nintendo assets. The only legal input is a disc image (or Dolphin `files/` dump) you already own.

## Disc layout

After extraction (Dolphin dump or `dtk disc extract`):

| Path | Role |
| --- | --- |
| `sys/` | DOL, BI2, boot |
| `files/forest_1st.arc` | RARC: string/mail tables, `face_boy.bin`, `tex_boy.bin`, `pallet_boy.bin` |
| `files/forest_2nd.arc` | RARC: standalone **BTI** textures (player faces, seasonal UI, station icons, title), room floor/wall bins, message tables |
| `files/famicom.arc` | RARC: NES/Famicom extras (out of scope) |
| `files/foresta.rel.szs` | Yaz0-compressed REL. After decompress: `foresta.rel` (~15 MB). **Models, skeletons, animations, embedded textures** |
| `files/foresta.map` | CodeWarrior map: symbol names, `.data` addresses, sizes |
| `files/audiorom.img` | Packed audio (sequences + waveforms). Not a standard JaiSeq/MusyX dump |
| `files/opening.bnr` | Banner |
| `files/static.str` / maps | Other tables |

`forest_*.arc` magic is `RARC`. Unpack with `dtk vfs cp archive.arc: dest/`.

REL `.data` for `GAFE01_00` starts at file offset `0x2DD340` (`dtk rel info`). A map symbol address is an offset into `.data`. Slice: `rel[0x2DD340 + address : + size]`.

## Formats discovered

| Format | Where | What it is | Godot target |
| --- | --- | --- | --- |
| RARC | `*.arc` | JKR archive | Extracted files only (not imported) |
| Yaz0 | `*.szs`, nested | Compression | Decompress, then handle inner format |
| BTI | `forest_2nd.arc` | GX texture (I4/I8/IA4/IA8/RGB565/RGB5A3/RGBA8/CI4/CI8/CMPR) | PNG |
| cKF skeleton `cKF_bs_r_*` | `foresta.rel` | 8-byte header + joint table `cKF_je_r_*_tbl` | GLB mesh now; skeleton later |
| cKF animation `cKF_ba_r_*` | `foresta.rel` | 20-byte header; pointers need REL reloc | AnimationPlayer later (not baked yet) |
| `Vtx` / `*_v` | `foresta.rel` | F3DEX2 16-byte vertices | GLB positions, UVs, vertex colors |
| Gfx DLs `*_model` | `foresta.rel` | Dolphin-GBI (`G_VTX=0x01`, `G_TRIN_INDEPEND=0x0A`, `G_SETTILE_DOLPHIN=0xD2`) | GLB triangles |
| N64 CI textures `*_tex_txt` | `foresta.rel` | Embedded paletted textures on models | PNG (custom work remaining) |
| Room floor/wall `.bin` | `forest_2nd.arc` | CI4 tiles (`ac-decomp` `texture_tool.py`) | PNG later |
| `audiorom.img` | disc `files/` | N64 sequences + banks + ADPCM (`Audioseq` `0x0` size `0xCF700`, `Audiobank` `0xCF700` size `0x67C80`, `Audiowave` `0x137380` size `0x6B33E0`) | Gitignored OGG via `--kind audio` ([decomp_notes/audio.md](decomp_notes/audio.md)) |
| JPA/JPC | **not** the primary effect path here | Effects are Gfx/cKF (`ef_*`) plus game code | Recreate in GPUParticles3D; do not port the particle engine |
| BMD/BDL/BCK/BTK/BRK/BTP | Essentially unused on this disc | J3D | Do not use |

There is no BMD/BDL player model. Player is `cKF_bs_r_boy_1` + `boy_1_v` + `*_boy_model` display lists.

## Tools

### decomp-toolkit (`dtk`)

| | |
| --- | --- |
| **Purpose** | Disc extract, Yaz0, RARC/VFS, REL inspection |
| **Supported** | GCM/ISO, Yaz0/Yay0, RARC, REL, DOL |
| **Input** | Disc image or archive |
| **Output** | `files/` tree, decompressed REL, unpacked archives |
| **Limitations** | Does not convert models or BTI to PNG |
| **License** | MIT OR Apache-2.0 |
| **Repo** | https://github.com/encounter/decomp-toolkit |
| **Use it?** | **Yes.** Primary extractor. Pipeline auto-downloads v1.8.3 to `tools/.cache/dtk`. |

### ACreTeam/ac-decomp

| | |
| --- | --- |
| **Purpose** | Matching decompilation; format reference (`c_keyframe.h`, Gfx macros, `tools/converters/gfxdis.py`, `tools/arc_tool.py`, `tools/texture_tool.py`) |
| **Supported** | Source-level understanding of cKF, GBI, room CI4 |
| **Input** | Your disc (decomp repo contains **no** game assets) |
| **Output** | C that matches the DOL/REL |
| **Limitations** | Not a Godot converter. Do not copy C architecture into this project. |
| **License** | CC0-1.0 |
| **Repo** | https://github.com/ACreTeam/ac-decomp |
| **Use it?** | **Yes, as documentation only.** Clone outside this repo. |

### GCFT (GameCube File Tools)

| | |
| --- | --- |
| **Purpose** | GUI for GCM, RARC, BTI, J3D, JPC |
| **Supported** | BTI↔PNG, RARC, Yaz0, BMD/BDL (J3D), JPC 1.00/2.10 |
| **Input** | Disc/archives/BTI |
| **Output** | PNG, extracted trees |
| **Limitations** | J3D-centric. **This game’s models are not J3D.** BTI path is valid but we already decode BTI in-pipeline. |
| **License** | MIT |
| **Repo** | https://github.com/LagoLunatic/GCFT |
| **Use it?** | Optional for inspecting BTI by hand. **Not** the model converter. |

### SuperBMD / J3D tools

| | |
| --- | --- |
| **Purpose** | BMD/BDL → glTF |
| **Use it?** | **No** for this title. Wrong format family. |

### ac-decomp `gfxdis.py` / `arc_tool.py` / `texture_tool.py`

| | |
| --- | --- |
| **Purpose** | Disassemble Gfx; unpack RARC via pyjkernel; decode room CI4 |
| **Use it?** | Reference for GBI and CI4. Pipeline uses `dtk` instead of pyjkernel, and a Python GBI walker instead of shipping gfxdis. Room CI4 conversion is still TODO. |

### Pillow

| | |
| --- | --- |
| **Purpose** | Write PNG from decoded BTI |
| **License** | HPND-style (Pillow) |
| **Use it?** | **Yes.** `tools/requirements.txt`. |

### Custom converters in this repo

Required because no mature open-source tool consumes **Dolphin-GBI + cKF in a GameCube REL**:

- `tools/asset_pipeline/gfx.py` — G_VTX / G_TRIN_INDEPEND (5-bit indices)
- `tools/asset_pipeline/ckf.py` — skeleton + static Gfx → mesh parts
- `tools/asset_pipeline/bti.py` — BTI → PNG
- `tools/asset_pipeline/glb.py` — mesh parts → GLB

## What we are not copying

- GX hardware TEV / the original particle engine / the GameCube audio driver
- Cryptic disc folder layout into `res://`
- Bulk extraction of all 596 cKF skeletons until the player path is visually signed off
