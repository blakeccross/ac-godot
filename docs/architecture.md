# Architecture

This project reimplements *Animal Crossing* (GameCube) **behavior** in Godot-native systems. The decomp is a reference, not a blueprint.

## Layers

```
Resource data  -->  systems (behavior)  -->  scenes (presentation)
```

- **Resources** describe what something is (an item, a villager definition, a tile type).
- **Systems** implement game-wide rules (clock, inventory, schedules, economy, save).
- **Scenes** are what the player sees and touches (player, tree, shop counter, HUD).

Keep those layers separate. A tree scene should not own growth formulas. An item `.tres` should not run shop logic.

## Planned autoloads

None exist in Phase 0. Add one only when the matching system is implemented and needs global access.

| Name | Responsibility | First needed |
| --- | --- | --- |
| `Clock` | Game date/time, day/night, season | First playable acre |
| `SaveService` | Load/save split resources to `user://` | After inventory or town state exists |
| `Audio` | Music and SFX buses | When audio is more than one player |

Prefer signals on the owning system over a global event bus unless many unrelated listeners appear.

## Godot mapping (not C mapping)

| Concern | Godot approach |
| --- | --- |
| Game time | Autoload or node system + tests, not `_process` sprinkled everywhere |
| Items | `ItemData` resources + inventory system |
| Town layout | Data describing acres/tiles + a world scene that instances them |
| Villagers | Villager resources + schedule system + actor scene |
| Dialogue | Data files + a UI scene |
| Save | Serialized IDs and counts to `user://` (JSON or binary), not `.tres` with embedded scripts |

Do not port `m_common_data` as one Resource. Split player, town, inventory, and clock state.

## Vertical-slice roadmap

Each phase should be playable or testable in-engine. Later phases are not started until earlier ones are.

1. **Phase 0** — this scaffold (current).
2. **Clock + empty acre + walk** — move a placeholder player on a small 3D plot with day/night tint.
3. **One interactable** — one tree (or pickup) with correct feel, not every plant type.
4. **Inventory** — pick up, hold, drop; testable without the world scene.
5. **One villager** — schedule, greeting, one dialogue tree.
6. **One shop + economy** — buy/sell a few items.
7. **Save/load** — clock, inventory, and town deltas survive a restart.

Content quantity is not a milestone. One good instance of a system is.

## What "Godot-native" means here

Use nodes, scenes, resources, signals, and groups the way Godot expects. Do not emulate GameCube memory layouts, actor overlay tables, or submenu heaps in GDScript.
