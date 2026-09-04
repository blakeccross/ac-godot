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

## Autoloads

Autoloads currently: `Clock`, `SaveService`, `Audio`, `Game`. Do not add more until a system exists and must be globally reachable. Inventory, `VillagerRoster`, `VillagerCatalog`, `VillagerAI`, `VillagerPlan`, `VillagerAction`, `VillagerWalk`, `Relationship` / `RelationshipBook`, `Interior` / `InteriorCatalog` / `InteriorBook`, `ShopBook` / `ShopUse`, `MuseumBook` / `MuseumDisplay` / `MuseumPresenter`, dialogue (`DialogueCatalog` / `DialogueRunner` / `DialogueGreeting`), `IntroSequence`, `BgmCatalog`, `Weather`, fishing, economy, `WorldGrid`, `WorldGenerator`, `WorldBuilder`, `WorldObjectRegistry`, `FieldCatalog`, `FieldCollision`, `StructureOffset`, `HostCollision`, `GeneratedVisual`, `HeldTool`, `PlayerLocomotion`, `InteractionQuery`, `ToolUse`, `FurnitureUse`, `TreeUse`, `HoleUse`, `PlantGrowth`, `VillagerSchedule`, `VillagerMotor`, and `VillagerTalk` are not autoloads. Weather, plants, fish, bugs, shops, museum, and events read `Clock` instead of tracking time themselves. Dialogue rain lines read `Game.weather`. Outdoor BGM follows `Clock.hour_changed` and `Game.weather`. See [architecture.md](architecture.md).

## Placeholders

Use primitive meshes, solid colors, and programmer UI until the underlying system is playable. Convert or author art only after that.

## Testing

Logic-heavy systems (time, inventory, economy, schedules, save) must be testable without running the full game. See [testing.md](testing.md).
