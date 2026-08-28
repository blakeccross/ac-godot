# Architecture

This project reimplements *Animal Crossing* (GameCube) **behavior** in Godot-native systems. The decomp is a reference, not a blueprint. Per-system research (states, I/O, reproduce / simplify / ignore) lives in [docs/decomp_notes/](decomp_notes/). Read the relevant note before writing implementation code.

## Layers

```
Resource data  -->  systems (behavior)  -->  scenes (presentation)
```

- **Resources** describe what something is (an item, a villager definition, a tile type). Scripts live in `scripts/data/` with `class_name`. Instances are `.tres` files under `data/`.
- **Systems** implement game-wide rules (clock, inventory, schedules, economy, save). Scripts live in `scripts/systems/`. They must be testable without the world scene.
- **Scenes** are what the player sees and touches (player, tree, shop counter, HUD). Scripts stay thin: they wire nodes and call systems.

Keep those layers separate. A tree scene should not own growth formulas. An item `.tres` should not run shop logic.

### Data (examples)

| Class | Role |
| --- | --- |
| `ItemData` | Pocket catalog (tools, fruit, …) |
| `FurnitureData` | Placeable item (`extends ItemData`) |
| `FishData` / `BugData` | Catchables (`extends ItemData`) |
| `PlantData` | Growing plants (not pocket items) |
| `VillagerData` | Villager definition |
| `DialogueData` | Conversation lines |
| `ScheduleData` / `ScheduleSlot` | Daily routine |
| `AcreData` | Outdoor plot + cell grid (size, water/soil/blocked) |

### Runtime objects (scenes)

| Scene | Path |
| --- | --- |
| Player, Villager | `scenes/actors/` |
| World, Tree, Furniture, ItemPickup, House, Shop | `scenes/world/` |
| Title, Clock HUD | `scenes/ui/` |

Fishing, shops, and full dialogue are **not** systems yet. The world scene owns a `WorldGrid`. The player scene owns a `PlayerLocomotion` (`RefCounted`, not an autoload) and instances `boy_1.glb` from `assets/generated/` when that file exists.

## Autoloads

Add one only when the matching system is implemented and needs global access. Do **not** autoload inventory, dialogue, weather, fishing, or economy.

Autoload scripts must not reuse the autoload name as `class_name` (`Clock` hides `class_name Clock`). The clock script is `ClockService`; other scripts talk to the `Clock` singleton.

| Name | Script | Responsibility |
| --- | --- | --- |
| `Clock` | `scripts/systems/clock.gd` (`ClockService`) | Game date/time, day/night, season |
| `SaveService` | `scripts/systems/save_service.gd` | Load/save JSON to `user://` |
| `Audio` | `scripts/systems/audio.gd` | Music / SFX buses |
| `Game` | `scripts/systems/game.gd` | Session phase, scene changes; owns `Inventory` |

Prefer signals on the owning system over a global event bus unless many unrelated listeners appear.

`Inventory` is a `RefCounted` owned by `Game`, not an autoload. `WorldGrid` is a `RefCounted` owned by the world scene, not an autoload. `PlayerLocomotion` is a `RefCounted` owned by the player scene, not an autoload.

## World scene

`scenes/world/world.tscn` is one outdoor plot (16×16 cells, 2 m each). Hierarchy:

```
World
├── Terrain
├── Objects
├── Characters
├── Buildings
├── Effects
├── Navigation
└── WorldEnvironment
```

## Godot mapping (not C mapping)

| Concern | Godot approach |
| --- | --- |
| Game time | `Clock` autoload + unit tests, not `_process` sprinkled everywhere |
| Player | `scenes/actors/player.tscn` + `PlayerLocomotion`; generated `boy_1.glb` if present |
| Items | `ItemData` resources + `Inventory` on `Game` |
| Town layout | `AcreData` + `WorldGrid` + `scenes/world/world.tscn` |
| Villagers | `VillagerData` + `ScheduleData` + villager scene (AI later) |
| Dialogue | `DialogueData` + a UI scene when that slice is earned |
| Save | JSON IDs and counts to `user://`, not `.tres` with embedded scripts |

Do not port `m_common_data` as one Resource. Split player, town, inventory, and clock state.

## Vertical-slice roadmap

Each phase should be playable or testable in-engine. Later phases are not started until earlier ones are.

1. **Phase 0** — project scaffold.
2. **Phase 1** — architectural foundation + clock, empty acre, walk.
3. **Phase 2** — decomp research notes (`docs/decomp_notes/`).
4. **Phase 3** — title → world → spawn → walk → pick up → save on return to title.
5. **Phase 4** — world hierarchy + logical cell grid.
6. **Phase 5** — player controller (current): `CharacterBody3D`, GC walk feel, generated `boy_1` visual when present.
7. **One interactable** — one tree (grow, shake, fruit) with correct feel, not every plant type.
8. **Inventory** — pick up, hold, drop; `Inventory` already exists for tests, wire drop/equip next.
9. **One villager** — schedule, greeting, one dialogue tree.
10. **One shop + economy** — buy/sell a few items.
11. **Town deltas** — persist more than one pickup and the current acre FG.

Content quantity is not a milestone. One good instance of a system is.

## What "Godot-native" means here

Use nodes, scenes, resources, signals, and groups the way Godot expects. Do not emulate GameCube memory layouts, actor overlay tables, or submenu heaps in GDScript.
