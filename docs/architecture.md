# Architecture

This project reimplements *Animal Crossing* (GameCube) **behavior** in Godot-native systems. The decomp is a reference, not a blueprint.

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
| `AcreData` | Outdoor plot description |

### Runtime objects (scenes)

| Scene | Path |
| --- | --- |
| Player, Villager | `scenes/actors/` |
| Tree, Furniture, ItemPickup, House, Shop, Acre | `scenes/world/` |
| Clock HUD | `scenes/ui/` |

Fishing, shops, and full dialogue are **not** systems yet. The scenes and resources exist so later slices have a place to land.

## Autoloads

Add one only when the matching system is implemented and needs global access. Do **not** autoload inventory, dialogue, weather, fishing, or economy.

Autoload scripts must not reuse the autoload name as `class_name` (`Clock` hides `class_name Clock`). The clock script is `ClockService`; other scripts talk to the `Clock` singleton.

| Name | Script | Responsibility |
| --- | --- | --- |
| `Clock` | `scripts/systems/clock.gd` (`ClockService`) | Game date/time, day/night, season |
| `SaveService` | `scripts/systems/save_service.gd` | Load/save JSON to `user://` |
| `Audio` | `scripts/systems/audio.gd` | Music / SFX buses |
| `Game` | `scripts/systems/game.gd` | Composition root; owns `Inventory` |

Prefer signals on the owning system over a global event bus unless many unrelated listeners appear.

`Inventory` is a `RefCounted` owned by `Game`, not an autoload.

## Godot mapping (not C mapping)

| Concern | Godot approach |
| --- | --- |
| Game time | `Clock` autoload + unit tests, not `_process` sprinkled everywhere |
| Items | `ItemData` resources + `Inventory` on `Game` |
| Town layout | `AcreData` + `scenes/world/acre.tscn` |
| Villagers | `VillagerData` + `ScheduleData` + villager scene (AI later) |
| Dialogue | `DialogueData` + a UI scene when that slice is earned |
| Save | JSON IDs and counts to `user://`, not `.tres` with embedded scripts |

Do not port `m_common_data` as one Resource. Split player, town, inventory, and clock state.

## Vertical-slice roadmap

Each phase should be playable or testable in-engine. Later phases are not started until earlier ones are.

1. **Phase 0** — project scaffold.
2. **Phase 1** — architectural foundation + **clock, empty acre, walk** (current).
3. **One interactable** — one tree (or pickup) with correct feel, not every plant type.
4. **Inventory** — pick up, hold, drop; `Inventory` already exists for tests, wire it to the world.
5. **One villager** — schedule, greeting, one dialogue tree.
6. **One shop + economy** — buy/sell a few items.
7. **Save/load** — clock already round-trips; persist town deltas too.

Content quantity is not a milestone. One good instance of a system is.

## What "Godot-native" means here

Use nodes, scenes, resources, signals, and groups the way Godot expects. Do not emulate GameCube memory layouts, actor overlay tables, or submenu heaps in GDScript.
