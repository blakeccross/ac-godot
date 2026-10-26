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

A class that something else steps over time (it is not a node with its own `_process`) does it in `advance(delta: float)`, `delta` in seconds; never `tick`.

## Data, presentation, behavior

- **Data:** scripts that `extend Resource` live in `scripts/data/` and declare `class_name`. Instances are `.tres` files under `data/` (`items/`, `furniture/`, `villagers/`, `personalities/`, `creatures/`, `plants/`, `dialogue/`, `schedules/`, `acres/`). Indoor field templates are built by `InteriorCatalog` (same resource types: `House`, `Room`, `FurniturePlacement`).
- **Presentation:** `.tscn` scenes under `scenes/`. A scene is a physical or UI object, not a dump of game rules.
- **Behavior:** systems under `scripts/systems/<area>/`; a new one goes in the folder of the area it serves. A feature moved to `features/<name>/` (`fishing`, `bugs`, `villagers`, `museum`, `shops/<shop>`, `house`, `lighthouse`, `intro`, `events`, `player`) holds its scenes and scripts together, and new work on it goes there. Scene scripts stay thin: they wire nodes and call systems.
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
- **Units are metres.** A decomp distance is converted where the constant is written (`const STAND := 24.0 * FieldCatalog.GX_TO_METERS`), so names carry no `_GX` suffix and nothing passes GX between classes.
  - A decomp data table converts each row as it is written (`Vector3(220.0, 40.0, 220.0) * FieldCatalog.GX_TO_METERS`) or, for tables read from data files, in its accessor (`FishSize.touch_distance`, `TitleDemo.spawn_point`).
  - Decomp field coordinates are `TownSpace` field positions: metres from the decomp field's north-west corner, turned into world positions by `TownSpace.field_to_world` (and back by `world_to_field`). Block maths (`block_of`, `block_base`) works on them.
  - Rooms place decomp room coordinates with `WorldGrid.room_point(grid, local)`.
  - A formula the decomp writes in GX a frame (the ball's kick sums, a balloon's sway) may keep those units inside one function and convert at its edges; say so in a comment.
  - The insect simulation and the train / station intro stages still compute in GX inside; their interfaces take and return metres.

### Converting a decomp number

Convert once, where the constant is written, and cite the source in a comment so the trail stays searchable:

```gdscript
## `aISM_wait`: 60 frames before the first cry (2 s).
const CRY_DELAY := 2.0
## `add_calc(&speed, target, 0.1, …)` per tick.
var _speed_half_life := Motion.half_life_from_fraction(0.1)
## `aNPS_schedule_init_proc`: 440 ticks of strumming before the first talk.
const TALK_DELAY := 440.0 * DecompTime.TICK_SEC
```

When the seconds aren't round, multiply by the clock the count is in (`DecompTime.TICK_SEC` for the 60 Hz play loop's counters, `FRAME_SEC` for 30 fps animation frames) rather than dividing by a bare `60.0`, so the source and its rate stay visible.

A timing that a `Timer` or an `AnimationPlayer` clip runs belongs on that node in the `.tscn`, with the decomp count in its `editor_description`. Don't mirror it in a script constant; a test checks the node against the decomp count instead (`test_intro_kk.gd`, `test_title_logo.gd`).

`DecompTime` (frame and tick rates, `frames_to_sec`) and `Motion.half_life_from_fraction` / `rate_from_chance` are **authoring helpers** for writing those constants. Animation GLBs are baked in seconds already (`tools/asset_pipeline/ckf.py` `FPS`), so clips play at the right speed with no conversion. A clip event that names a decomp frame becomes a method-call track or a time in seconds.

Angles in the decomp are s16 (`0x10000` = a full turn). Convert them to radians when writing the constant (`MathUtil.s16_to_rad`); don't carry s16 values through gameplay code.

### No fixed-tick loops

Nothing in gameplay steps a fixed 60 Hz tick any more (`FrameStepper` was removed when the player converted). Some systems still keep a countdown in decomp ticks because every table that sets it is written in ticks (bugs, NPC moods); they drop it by the ticks a step covers (`delta * DecompTime.TICK_HZ`). Don't add new fixed-tick loops or frame counters.

## Naming

Names are plain English. Decomp symbols and romaji appear **only in comments**, as citations (`## ac_insect_semi.c`, `` `aISM_wait` ``):

- **Classes, files and nodes:** `Cicada` not `Cicada`, `Gyroid` not `Haniwa`, `StalkMarket` not `StalkMarket`.
- **Members:** say what they hold. `wing_time` not `anime1`, `catchable` not `f_no_catch`; no `s32_work[n]` scratch slots.
- **Signals:** past-tense events, such as `caught`, `talk_finished` and `item_picked`.
- **Dispatch:** state machines are an `enum State` with `_enter_state` / `_exit_state` (or child state nodes for large actors), not `action_proc` callables keyed by integer action codes.

Existing decomp-style names are renamed in plan § Phase 1, with the old names recorded in [decomp-mapping.md](decomp-mapping.md). Renames that touch a save key ship with a `SaveService` migration.

## Typed scene references

`Player`, `DialogueOverlay`, `World`, `Interior` and the one-per-scene overlays and props (`InventoryOverlay`, `LetterWriterOverlay`, `MapOverlay`, `WishingWell`, `FollowCamera`, …) have class names and a static `find(tree)`. Reach them with `Player.find(tree)`, `DialogueOverlay.find(tree)` (plus `uttering_in` / `open_in`), `Interior.find(tree)` and so on, and call their methods and signals directly — no `get_first_node_in_group("player")`, `.call("method")`, `has_method` guards or `connect("closed", …)` strings. Duck typing stays where a slot really takes different nodes: an `InteractVolume` binding its host's `get_interactions` / `interact` (the player only talks to the volume), `InteractionContext.actor` / `.world` (tests pass grid stubs), talk-camera speakers, the follow-camera target, NPC hand-over actors, and villager player checks (tests use stand-ins).

## Components

A large actor splits by responsibility into child `Node`s declared in its `.tscn` (`player.tscn`: `Doors`, `Furniture`, `Tools`, `Net`, `Fishing`, `Snowball`, `Reports`; `features/villagers/villager.tscn`: `Mover`, `Conversation`, `Greeter`, `Brain`, under `components/`). The actor holds them as node exports assigned in the scene (`@export var doors: PlayerDoors`, `node_paths` in the `.tscn`), so they are set before any child's `_ready`. A component finds its actor on first use (`_player` / `_villager`, a getter on `get_parent()`), so scenes built in tests without a tree work. Components are parts of one actor: they may read its private state (`_motor`, `_anim`, `_busy`) and each other's through it. Code outside the actor goes through the component (`player.doors.begin_door_enter(…)`).

## Saved state

`Game.resident` (`PlayerState`) holds the playing resident's own saved fields and `Game.town` (`TownState`) the town's; the per-system `*Book` classes hold the rest. Each writes and reads its part of `Game.to_save()` under its own keys. A new saved field goes on one of them, with its `write_save` / `read_save` / `reset` lines; session-only flags stay on `Game`.

## Autoloads

Autoloads currently: `Clock`, `SaveService`, `Audio`, `Game`. Do not add more until a system exists and must be globally reachable. Inventory, `VillagerRoster`, `VillagerCatalog`, `VillagerAI`, `VillagerPlan`, `VillagerAction`, `VillagerWalk`, `Relationship` / `RelationshipBook`, `Interior` / `InteriorCatalog` / `InteriorBook`, `ShopBook` / `CatalogPages`, `MuseumBook` / `MuseumDisplay` / `MuseumPresenter`, dialogue (`DialogueCatalog` / `DialogueRunner` / `DialogueGreeting`), `IntroSequence`, `BgmCatalog`, `Weather`, fishing, economy, `WorldGrid`, `WorldGenerator`, `WorldBuilder`, `WorldObjectRegistry`, `FieldCatalog`, `FieldCollision`, `StructureOffset`, `HostCollision`, `GeneratedVisual`, `HeldTool`, `PlayerLocomotion`, `InteractionQuery`, `ToolUse`, `FurnitureUse`, `TreeUse`, `HoleUse`, `PlantGrowth`, `VillagerSchedule`, `VillagerMotor`, and `VillagerTalk` are not autoloads. Weather, plants, fish, bugs, shops, museum, and events read `Clock` instead of tracking time themselves. Dialogue rain lines read `Game.weather`. Outdoor BGM follows `Clock.hour_changed` and `Game.weather`. See [architecture.md](architecture.md).

## Testing

Logic-heavy systems (time, inventory, economy, schedules, save) must be testable without running the full game. See [testing.md](testing.md).

Code that only tests call (a probe, getter or helper with no in-game caller) carries a `## Test-only: no in-game callers; kept for tests.` line in its doc comment. That keeps it out of dead-code sweeps; delete it together with the last test that uses it.
