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

Do not recreate the original game's single global save blob. Split state by concern.

## Autoloads

Autoloads currently: `Clock`, `SaveService`, `Audio`, `Game`. Do not add more until a system exists and must be globally reachable. Inventory, `VillagerRoster`, `VillagerCatalog`, `VillagerAI`, `VillagerPlan`, `VillagerAction`, `VillagerWalk`, `Relationship` / `RelationshipBook`, `Interior` / `InteriorCatalog` / `InteriorBook`, dialogue (`DialogueCatalog` / `DialogueRunner` / `DialogueGreeting`), weather, fishing, economy, `WorldGrid`, `WorldGenerator`, `WorldBuilder`, `WorldObjectRegistry`, `FieldCatalog`, `FieldCollision`, `GeneratedVisual`, `HeldTool`, `PlayerLocomotion`, `InteractionQuery`, `ToolUse`, `TreeUse`, `HoleUse`, `PlantGrowth`, `VillagerSchedule`, `VillagerMotor`, and `VillagerTalk` are not autoloads. Weather, plants, fish, bugs, shops, and events read `Clock` instead of tracking time themselves. Dialogue rain lines read `Game.weather`. See [architecture.md](architecture.md).

## Placeholders

Use primitive meshes, solid colors, and programmer UI until the underlying system is playable. Convert or author art only after that.

## Testing

Logic-heavy systems (time, inventory, economy, schedules, save) must be testable without running the full game. See [testing.md](testing.md).
