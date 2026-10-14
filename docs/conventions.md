# Conventions

Naming and layout follow the [Godot GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html).

## Naming

| Thing | Style | Example |
| --- | --- | --- |
| Files and folders | `snake_case` | `item_data.gd`, `scenes/actors/` |
| `class_name` and node names | `PascalCase` | `ItemData`, `Player` |
| Functions and variables | `snake_case` | `give_item()`, `move_speed` |
| Constants and enums | `CONSTANT_CASE` / `PascalCase` | `MAX_STACK`, `enum Season` |
| Private members | `_prefix` | `_clock: Clock` |

Use typed GDScript on every signature and member. Indent with tabs.

## Data, presentation, behavior

- **Data:** scripts that `extend Resource` live in `scripts/data/` and declare `class_name`. Instances are `.tres` files under `data/` (`items/`, `furniture/`, `villagers/`, `personalities/`, `creatures/`, `plants/`, `dialogue/`, `schedules/`, `acres/`). Indoor field templates are built by `InteriorCatalog` (same resource types: `House`, `Room`, `FurniturePlacement`).
- **Presentation:** `.tscn` scenes under `scenes/`. A scene is a physical or UI object, not a dump of game rules.
- **Behavior:** systems under `scripts/systems/`. Scene scripts stay thin: they wire nodes and call systems.
- Prefer composition (child nodes, resources, systems) over deep inheritance.

### Scene-first authorship

Author fixed presentation in the editor. Do not default to runtime construction.

- Put known hierarchy (rooms, counters, cameras, lights, spawn markers, HUD) in the `.tscn`.
- Put static (or rest-pose) transforms in the scene too: cameras, characters, and props should sit where they belong when you open the `.tscn`, not at the origin waiting for `_ready` to teleport them.
- Prefer nesting packed scenes (`instance=`) over `instantiate()` in `_ready` for layouts that never change between runs.
- Systems may *place* packed scenes from data (town generation, inventory drops). They should not *build* the visual tree with ad-hoc mesh/collider nodes when a scene would do.
- Exception: truly procedural or ephemeral objects (generated acre FG, bobber, shadows, particles, one-shot FX).

See [architecture.md](architecture.md) § Scene-first.

Do not recreate the original game's single global save blob. Split state by concern.

## Time and units

Gameplay runs on `delta`, in seconds and metres, like any Godot game. The decomp is a reference for *what* happens and roughly how fast, not a per-tick simulation to reproduce. The full migration is in [godot_native_refactor_plan.md](godot_native_refactor_plan.md).

- **Seconds, not ticks.** Countdowns are `float` seconds (`time_left -= delta`), a `Timer` node, or `await get_tree().create_timer(t).timeout`. Fades and one-off moves are `Tween`s. Repeating cadences are a looping `Timer` or an `AnimationPlayer` clip.
- **Smoothing** uses `Motion.damp` / `damp_vec3` / `damp_angle` with a half-life in seconds, not a per-tick `add_calc`. Fixed-rate approach uses `move_toward(x, target, speed * delta)`; turning uses `rotate_toward(yaw, target, turn_speed * delta)`.
- **Random events** use `Motion.happens(rate_per_second, delta, rng)`, not a roll every frame.
- **Physics** goes in `_physics_process(delta)` and visuals or effects in `_process(delta)`. Nothing may assume a 60 Hz loop.
- **Tuning is exported** with units: `@export_range(0.0, 5.0, 0.05, "suffix:s") var hide_delay := 1.0`.
- **Units are metres.** GX stays only where baked data speaks it, and is converted once in the loader.

### Converting a decomp number

Convert once, where the constant is written, and cite the source in a comment so the trail stays searchable:

```gdscript
## `aISM_wait`: 60 frames before the first cry (2 s).
const CRY_DELAY := 2.0
## `add_calc(&speed, target, 0.1, …)` per tick.
var _speed_half_life := Motion.half_life_from_fraction(0.1)
```

`DecompTime` (frame and tick rates, `frames_to_sec`) and `Motion.half_life_from_fraction` / `rate_from_chance` are **authoring helpers** for writing those constants. Animation GLBs are baked in seconds already (`tools/asset_pipeline/ckf.py` `FPS`), so clips play at the right speed with no conversion. A clip event that names a decomp frame becomes a method-call track or a time in seconds.

Angles in the decomp are s16 (`0x10000` = a full turn). Convert them to radians when writing the constant (`MLib.s16_to_rad`); don't carry s16 values through gameplay code.

### Legacy tick code

`FrameStepper` loops (`while steps.next(): _tick()`) and integer frame counters still drive much of the game. They are being replaced system by system (plan § Phase 2). Don't add new ones. When you touch a tick-driven system for other reasons, leave it as it is unless the change is that system's conversion; a half-converted system is worse than either.

## Naming

Names are plain English. Decomp symbols and romaji appear **only in comments**, as citations (`## ac_insect_semi.c`, `` `aISM_wait` ``):

- **Classes, files and nodes:** `Cicada` not `BugSemi`, `Gyroid` not `Haniwa`, `StalkMarket` not `KabuMarket`.
- **Members:** say what they hold. `wing_time` not `anime1`, `catchable` not `f_no_catch`; no `s32_work[n]` scratch slots.
- **Signals:** past-tense events, such as `caught`, `talk_finished` and `item_picked`.
- **Dispatch:** state machines are an `enum State` with `_enter_state` / `_exit_state` (or child state nodes for large actors), not `action_proc` callables keyed by integer action codes.

Existing decomp-style names are renamed in plan § Phase 1, with the old names recorded in [decomp-mapping.md](decomp-mapping.md). Renames that touch a save key ship with a `SaveService` migration.

## Typed scene references

`Player`, `DialogueOverlay` and `World` have class names. Reach them with `Player.find(tree)`, `DialogueOverlay.find(tree)` (plus `uttering_in` / `open_in`) and `World.find(tree)`, and call their methods directly — no `get_first_node_in_group("player")`, `.call("method")`, `has_method` guards or `connect("closed", …)` strings. Duck typing stays where a slot really takes different nodes: `InteractionContext.actor` / `.world` (tests pass grid stubs), talk-camera speakers, the follow-camera target, NPC hand-over actors, and villager player checks (tests use stand-ins).

## Autoloads

Autoloads currently: `Clock`, `SaveService`, `Audio`, `Game`. Do not add more until a system exists and must be globally reachable. Inventory, `VillagerRoster`, `VillagerCatalog`, `VillagerAI`, `VillagerPlan`, `VillagerAction`, `VillagerWalk`, `Relationship` / `RelationshipBook`, `Interior` / `InteriorCatalog` / `InteriorBook`, `ShopBook` / `CatalogPages`, `MuseumBook` / `MuseumDisplay` / `MuseumPresenter`, dialogue (`DialogueCatalog` / `DialogueRunner` / `DialogueGreeting`), `IntroSequence`, `BgmCatalog`, `Weather`, fishing, economy, `WorldGrid`, `WorldGenerator`, `WorldBuilder`, `WorldObjectRegistry`, `FieldCatalog`, `FieldCollision`, `StructureOffset`, `HostCollision`, `GeneratedVisual`, `HeldTool`, `PlayerLocomotion`, `InteractionQuery`, `ToolUse`, `FurnitureUse`, `TreeUse`, `HoleUse`, `PlantGrowth`, `VillagerSchedule`, `VillagerMotor`, and `VillagerTalk` are not autoloads. Weather, plants, fish, bugs, shops, museum, and events read `Clock` instead of tracking time themselves. Dialogue rain lines read `Game.weather`. Outdoor BGM follows `Clock.hour_changed` and `Game.weather`. See [architecture.md](architecture.md).

## Testing

Logic-heavy systems (time, inventory, economy, schedules, save) must be testable without running the full game. See [testing.md](testing.md).
