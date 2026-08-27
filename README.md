# AC Godot

A Godot 4 recreation inspired by the GameCube version of *Animal Crossing*.

This is **not** a 1:1 port. The goal is to rebuild the core gameplay systems, feel, visual style, and simulation philosophy using Godot-native architecture. Many of the original game's specialized systems are intentionally omitted.

This project is original work. It is **not affiliated with, endorsed by, or connected to Nintendo**. Do not add Nintendo assets, character names, music, trademarks, or source from the original game.

## Requirements

- [Godot 4.6](https://godotengine.org/download) or newer
- Forward+ capable GPU (Vulkan, Metal, or Direct3D 12)
- Desktop: macOS, Windows, or Linux

## Run

1. Open this folder in Godot 4.6+.
2. Press Play. You should see the Phase 0 boot screen (project name, engine version, scaffolding label).

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
| `assets/` | Art, audio, fonts (placeholders until a system works) |
| `scenes/` | Physical game objects and UI |
| `scripts/` | Resource classes, systems, actor/UI scripts |
| `data/` | `.tres` instances (items, villagers, tiles, dialogue) |
| `docs/` | Architecture, conventions, scope, decomp mapping |
| `tests/` | GdUnit4 suites |

## Decomp reference

Behavior may be studied from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Clone that repository **outside** this project. Do not copy C into GDScript, and do not commit the decomp, disc images, or original assets here.

See [docs/decomp-mapping.md](docs/decomp-mapping.md) and [docs/architecture.md](docs/architecture.md).

## License

MIT for the original code in this repository. See [LICENSE](LICENSE).
GdUnit4 is vendored under its own license in `addons/gdUnit4/LICENSE`.
