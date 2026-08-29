# Testing

Systems must be testable without booting the whole game. Time, inventory, economy, schedules, and save data should have unit tests that construct resources and call system APIs directly.

## Framework

[GdUnit4](https://github.com/godot-gdunit-labs/gdUnit4) **v6.2.1** is vendored at `addons/gdUnit4` and enabled in `project.godot`. It supports Godot 4.6.

Put suites under `tests/unit/` (and later `tests/scene/` if a scene runner is needed). Name files `test_*.gd`. Suites `extend GdUnitTestSuite`.

```gdscript
class_name TestExample
extends GdUnitTestSuite


func test_example() -> void:
	assert_int(2 + 2).is_equal(4)
```

## Run in the editor

1. Open the project in Godot 4.6+.
2. Confirm **Project → Project Settings → Plugins** has gdUnit4 enabled.
3. Use the GdUnit inspector, or right-click a test script → Run Test(s).

## Run from the CLI

```sh
export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
./addons/gdUnit4/runtest.sh --add res://tests
```

On Windows, use `addons/gdUnit4/runtest.cmd` with `--godot_binary` pointing at the Godot executable.

`--add` selects the suite path. See `addons/gdUnit4/runtest.sh` for the Godot binary requirement (`GODOT_BIN` or `--godot_binary`).

## What to test

- **Do:** Resource defaults, clock advancement, 06:00 renew, shop hours, catchable windows, inventory stacking, shop prices, schedule lookups, villager looks tables / talk friendship / greeting pick / full catalog (236 animals), **dialogue graphs** (conditions, choices, events, variables, weather/item/time gates, looks greeting offset), activity plans (wake / leave / walk-to-acre / looping wander / go home / sleep), talk interrupt (hold current step until `end_talk`), starter roster pick (one per looks), field roam goal tables, standable cells, wait/walk/run weights, shared 1.5 / 4.5 m/s walk/run (`VillagerMotor`), avoid-vs-rim dest resume, and wander arrive (`VillagerWalk`), save round-trips, grid cell math, locomotion accel/turn, interaction verb priority and host duck-typing, equipped-tool field verbs (`ToolUse`), held-tool `visual_id` / clips, tree chop/shake/stump (`TreeUse`), plant growth stages / water / fruit (`PlantGrowth`), shovel dig/fill holes (`HoleUse`), generator determinism (`seed` → same `WorldData.fingerprint()`), unit heightfield (`FieldCollision`) and catalog water units when `grd_*.col.json` is present, world-object registry kinds and decomp acre placement (house B-3, shop row A, museum unique, Able Sisters beach).
- **Don't:** Screenshot-test placeholder art, or require the boot scene for logic tests.

Suites live in `tests/unit/`: `test_clock.gd`, `test_inventory.gd`, `test_save_service.gd`, `test_game.gd`, `test_world_grid.gd`, `test_world_generation.gd`, `test_field_catalog.gd`, `test_field_collision.gd`, `test_player_locomotion.gd`, `test_interaction.gd`, `test_tool_use.gd`, `test_tree_use.gd`, `test_plant_growth.gd`, `test_hole_use.gd`, `test_resources.gd`, `test_villager.gd`, `test_dialogue.gd`.
