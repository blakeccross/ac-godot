# AC Godot

A Godot 4 recreation of the GameCube version of *Animal Crossing*.

The goal is a **1:1 recreation** of every system and content set from the original
(`GAFE01`, USA rev 0), the only intended deviation being **HD / re-authored art** in
place of the original textures. Behaviour, numbers, schedules, and content should
match the GameCube game. Systems are still built with Godot-native architecture
rather than translated from C.

**[→ Full feature checklist](docs/feature-checklist.md)** — every feature, big and
small, tracked to completion.

This project is original work. It is **not affiliated with, endorsed by, or connected to Nintendo**. Do not add Nintendo assets, music, trademarks, or source from the original game. Villager names in data (Filbert, Rosie, …) are fine.

## Requirements

- [Godot 4.6](https://godotengine.org/download) or newer
- Forward+ capable GPU (Vulkan, Metal, or Direct3D 12)
- Desktop: macOS, Windows, or Linux

## Run

1. Open this folder in Godot 4.6+.
2. Press Play. Title → **New Game** runs the full opening (K.K. player select → Rover's train → station arrival with Porter and Nook → house pick → first job), like the original. Dev shortcuts: **Town Seed 12345** drops straight into a deterministic town, **Intro Sequence** re-enters the K.K.→train chain, **Station Arrival** runs just the station demo. WASD to walk, Shift to run, **E** to interact (pick up, talk, shake, sit, read, …), **Esc** to save and return to title. **Continue** reloads that save. Debug: **T** +1 hour, **Y** +1 day (crosses the 06:00 daily renew), **U** save. Shop is open 9:00–22:00. Filbert is off the acre while asleep or indoors.

From a terminal, if the Godot binary is on your `PATH`:

```sh
godot --path .
```

On macOS with the official app bundle:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

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

| Path | Purpose |
| --- | --- |
| `assets/generated/` | Pipeline output from a local disc (gitignored) |
| `assets/custom/` | Hand-authored Godot assets |
| `scenes/` | Physical game objects and UI |
| `scripts/` | Resource classes, systems, actor/UI scripts |
| `data/` | `.tres` instances (items, villagers, tiles, dialogue) |
| `docs/` | Architecture, conventions, scope, decomp mapping, asset pipeline |
| `tools/` | Disc extract / convert scripts |
| `tests/` | GdUnit4 suites |

## Decomp reference

Behavior may be studied from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Clone that repository **outside** this project. Do not copy C into GDScript, and do not commit the decomp, disc images, or original assets here.

Asset extraction from a disc you already own is documented in [docs/asset_pipeline.md](docs/asset_pipeline.md). Converted files land in `assets/generated/` and are gitignored.

See [docs/decomp-mapping.md](docs/decomp-mapping.md) and [docs/architecture.md](docs/architecture.md).

## License

MIT for the original code in this repository. See [LICENSE](LICENSE).
GdUnit4 is vendored under its own license in `addons/gdUnit4/LICENSE`.
