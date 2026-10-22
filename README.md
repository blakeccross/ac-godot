# AC Godot

A Godot 4 recreation of the GameCube version of _Animal Crossing_.

The goal is a **1:1 recreation** of every system and content set from the original
(`GAFE01`, USA rev 0), the only intended deviation being **HD / re-authored art** in
place of the original textures. Behaviour, numbers, schedules, and content should
match the GameCube game. Systems are still built with Godot-native architecture
rather than translated from C.

**[→ Roadmap](docs/feature-checklist.md)** — the feature checklist of every system,
tracked to completion.

This project is original work. It is **not affiliated with, endorsed by, or connected to Nintendo**. Do not add Nintendo assets, music, trademarks, or source from the original game. Villager names in data (Filbert, Rosie, …) are fine.

## Requirements

- [Godot 4.6](https://godotengine.org/download) or newer
- Python 3.9+
- Forward+ capable GPU (Vulkan, Metal, or Direct3D 12)
- Desktop: macOS, Windows, or Linux
- A GameCube disc image you already own (`GAFE01`, USA). Do not put it inside this repository

## Run

The town's acres are built by the asset pipeline. Run it once before the first play. Full options are in [docs/asset_pipeline.md](docs/asset_pipeline.md).

1. Install the pipeline's Python packages:

   ```sh
   pip3 install -r tools/requirements.txt
   ```

2. Build every asset from your disc image (`.iso`, `.gcm`, `.rvz`, or a Dolphin dump that contains `files/`):

   ```sh
   python3 tools/build_assets.py --disc /path/to/GAFE01.iso
   ```

   This extracts the disc, converts models, textures, UI, dialogue and music, and bakes the acre scenes. The first run asks whether to use the [Animal Crossing HD](https://docs.google.com/document/d/1ofFuIgV9AfQcx3DmGXvDKl-fdoTk-ZQ3AxBX5QLA7vI/) texture pack (about 160 MB, downloaded for you; pass `--hd` or `--no-hd` to skip the question), writes `tools/config.local.json` (gitignored), puts extracted files in `~/ac-assets-work`, downloads `dtk` into `tools/.cache/dtk`, and shallow-clones [ac-decomp](https://github.com/ACreTeam/ac-decomp) into the work folder unless it finds a checkout already. Godot is found in its usual install locations; set `GODOT_BIN` if yours is elsewhere. Later rebuilds are just `python3 tools/build_assets.py`.

   To change the defaults, edit `tools/config.local.json` (see `tools/config.example.json`):
   - `godot_bin` — the Godot executable, if it is not in a usual place
   - `achd_enabled` / `achd_root` — the HD texture pack. `--hd` / `--no-hd` switch it later and reconvert
   - `decomp_root` — an existing ac-decomp checkout

3. Start the game. Open this folder in Godot 4.6+ and press Play, or from a terminal:

   ```sh
   godot --path .
   ```

   On macOS with the official app bundle:

   ```sh
   /Applications/Godot.app/Contents/MacOS/Godot --path .
   ```

### Desktop builds

After assets are baked, package a local Windows or macOS build (needs the matching **export templates** installed in Godot: Editor → Manage Export Templates):

```sh
python3 tools/build_assets.py --step export --export macos
python3 tools/build_assets.py --step export --export windows
python3 tools/build_assets.py --step export --export all
```

Output lands in `out/` (gitignored). Builds include whatever is already in `assets/generated/`; they never upload or distribute a disc image. See [docs/asset_pipeline.md](docs/asset_pipeline.md) § Desktop export.

## Tests

Unit tests use [GdUnit4](https://github.com/godot-gdunit-labs/gdUnit4) v6.2.1.

In the editor: enable the gdUnit4 plugin (already listed in `project.godot`), then run suites from the GdUnit inspector or by right-clicking a test script.

From the command line:

```sh
export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
./addons/gdUnit4/runtest.sh --add res://tests
```

See [docs/testing.md](docs/testing.md).

## Project layout

| Path                | Purpose                                                          |
| ------------------- | ---------------------------------------------------------------- |
| `assets/generated/` | Pipeline output from a local disc (gitignored)                   |
| `assets/custom/`    | Hand-authored Godot assets                                       |
| `scenes/`           | Physical game objects and UI                                     |
| `scripts/`          | Resource classes, systems, actor/UI scripts                      |
| `data/`             | `.tres` instances (items, villagers, tiles, dialogue)            |
| `docs/`             | Architecture, conventions, scope, decomp mapping, asset pipeline |
| `tools/`            | Disc extract / convert scripts                                   |
| `tests/`            | GdUnit4 suites                                                   |

## Decomp reference

Behavior may be studied from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp).

Asset extraction from a disc you already own is documented in [docs/asset_pipeline.md](docs/asset_pipeline.md). Converted files land in `assets/generated/` and are gitignored. The steps to build them and start the game are in [Run](#run).

See [docs/decomp-mapping.md](docs/decomp-mapping.md) and [docs/architecture.md](docs/architecture.md).

## License

MIT for the original code in this repository. See [LICENSE](LICENSE).
GdUnit4 is vendored under its own license in `addons/gdUnit4/LICENSE`.
