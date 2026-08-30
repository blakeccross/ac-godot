# Architecture

This project reimplements *Animal Crossing* (GameCube) **behavior** in Godot-native systems. The decomp is a reference, not a blueprint. Per-system research (states, I/O, reproduce / simplify / ignore) lives in [docs/decomp_notes/](decomp_notes/) (including [audio](decomp_notes/audio.md)). Read the relevant note before writing implementation code.

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
| `ToolData` | Equippable tool (`extends ItemData`; shovel, rod, net, axe, can) |
| `FurnitureData` | Placeable item (`extends ItemData`) |
| `FishData` / `BugData` | Catchables (`extends ItemData`) |
| `PlantData` | Growing plants (not pocket items) |
| `VillagerData` | Villager definition (species, personality, dialogue) |
| `VillagerPersonality` | Looks group; selects the daily table |
| `ActivityKind` | Reusable action ids (walk, sit, fish, shop, sleep, …) |
| `DialogueData` | Conversation graph (JSON or legacy greeting fields) |
| `ScheduleData` / `ScheduleSlot` | Daily `{activity, end_hour}` table (`mNPS` looks tables) |
| `AcreData` | Legacy plot grid used by `WorldGrid` tests |
| `WorldData` | Town layout: terrain, elevation, buildings, objects, spawns |
| `BuildingPlacement` / `ObjectPlacement` / `SpawnPoint` | Entries inside `WorldData` |

### Runtime objects (scenes)

| Scene | Path |
| --- | --- |
| Player, Villager | `scenes/actors/` |
| World, Tree, Rock, Flower, Hole, Furniture, ItemPickup, House, Shop, ShopCounter, ShopStock, Building, Door, Sign | `scenes/world/` |
| InteractVolume | `scenes/world/interact_volume.gd` (sensor only; host implements verbs) |
| Title, Clock HUD, Dialogue overlay, Shop overlay | `scenes/ui/` |

Fishing and full fishing / bug loops are **not** systems yet. Shops are `ShopBook` (owned by `Game`) plus indoor counters in Nook's Cranny and Able Sisters. Dialogue is `DialogueData` + `DialogueRunner` + `DialogueCatalog` + `DialogueGreeting` (not an autoload) and `scenes/ui/dialogue_overlay.tscn`. Tools exist as `ToolData` + `ToolUse` (shovel, rod, net, axe, watering can) wired through interaction verbs; rod/net notices are not the fishing or bug loops. Trees use `TreeUse` (shake, multi-hit chop, stump, fruit drop). Plant growth is `PlantGrowth`: stored `planted_renew` (and water/fruit overlays) on `Game.plant_states`, visual stage derived at 06:00. Shovel empty-ground dig writes a hole (`HoleUse`); shovel on a hole fills it. Shop, door, and sign scenes exist as verb stubs. Furniture is `FurnitureData` + `FurnitureUse` (place, pick, rotate, sit/lie, storage, toggle, display, wall/floor). Shop hours and villager sleep / in-house come from `Clock`. Town layout is `WorldData` produced by `WorldGenerator` and instanced by `WorldBuilder`. `FieldCatalog` maps original FG/BG ids to generated GLBs when present, and loads each acre's paired `mCoBG` table from a gitignored `.col.json` sidecar. `FieldCollision` uses that heightfield (and geometric bands only when the sidecar is missing). Acre XLU water (river dual-scroll, ocean waves, wet sand) is converted into those GLBs and shaded by `GeneratedVisual`. The world scene is a shell that owns a `WorldGrid`. The player scene owns a `PlayerLocomotion` (`RefCounted`, not an autoload) and instances `boy_1.glb` from `assets/generated/` when that file exists. Villagers instance a species GLB the same way (`GeneratedVisual.attach_villager`) and roam goal acres through `VillagerWalk`. Equipped tools parent to HAND through `HeldTool`. Field interact uses `InteractionQuery` (`RefCounted`, not an autoload); objects expose verbs instead of the player switching on type.

## Autoloads

Add one only when the matching system is implemented and needs global access. Do **not** autoload inventory, dialogue, weather, fishing, or economy. `Game.weather` is a session value for rain lines, not a weather autoload.

Autoload scripts must not reuse the autoload name as `class_name` (`Clock` hides `class_name Clock`). The clock script is `ClockService`; other scripts talk to the `Clock` singleton.

| Name | Script | Responsibility |
| --- | --- | --- |
| `Clock` | `scripts/systems/clock.gd` (`ClockService`) | Time system: calendar, day/night, 06:00 renew |
| `SaveService` | `scripts/systems/save_service.gd` | Load/save JSON to `user://` |
| `Audio` | `scripts/systems/audio.gd` | Music / SFX buses; `play_bgm` from generated OGG via `BgmCatalog` ([audio](decomp_notes/audio.md)) |
| `Game` | `scripts/systems/game.gd` | Session phase, scene changes; owns `Inventory`, `VillagerRoster`, `RelationshipBook`, `InteriorBook`, and `ShopBook` |

Prefer signals on the owning system over a global event bus unless many unrelated listeners appear.

`Inventory` is a `RefCounted` owned by `Game`, not an autoload. `VillagerRoster` is a `RefCounted` owned by `Game` (id → `VillagerState`). `RelationshipBook` is a `RefCounted` owned by `Game` (id → `Relationship`). `InteriorBook` and `ShopBook` are `RefCounted` owned by `Game`. `WorldGrid` is a `RefCounted` owned by the world scene, not an autoload. `TownFieldGenerator`, `WorldGenerator`, `WorldBuilder`, `WorldObjectRegistry`, `FieldCatalog`, `FieldCollision`, `StructureOffset`, `HostCollision`, `GeneratedVisual`, and `HeldTool` are `RefCounted` helpers, not autoloads. `PlayerLocomotion` is a `RefCounted` owned by the player scene, not an autoload. `Interaction`, `InteractionContext`, `InteractionQuery`, `ToolUse`, `FurnitureUse`, `ShopUse`, `TreeUse`, `HoleUse`, and `PlantGrowth` are `RefCounted` helpers, not autoloads. `VillagerCatalog`, `VillagerAI`, `VillagerPlan`, `VillagerAction`, and `VillagerWalk` are `RefCounted` helpers, not autoloads. `DialogueCatalog`, `DialogueRunner`, `DialogueContext`, and `DialogueGreeting` are `RefCounted` helpers, not autoloads. `BgmCatalog` is a `RefCounted` helper, not an autoload. Do not autoload fishing or events; those systems subscribe to `Clock` when they exist. `Game.weather` is a `StringName` hook (`clear`, `rain`, `snow`, `sakura`, `leaves`) for dialogue until weather is a system.

### Time system

`Clock` is the only calendar. Fields: year, month, day, weekday, hour, minute, season (plus term and time-of-day). Other systems **subscribe** (`time_changed`, `hour_changed`, `day_changed`, `season_changed`, `term_changed`, `time_of_day_changed`, `field_renewed`) or **query** (`calendar()`, `now_sec()`, `in_hour_window()`, `is_listed_now()`). They must not call `Time.get_datetime_dict_from_system()` or recompute season/weekday.

| Subscriber (now or next slice) | Signal / query |
| --- | --- |
| Day/night lighting | `time_changed` → `outdoor_light()` |
| Villager schedules | `time_changed` + `VillagerSchedule.tick` / `activity_now()` |
| Shops | `in_hour_window(9, 22)`; restock on `field_renewed` |
| Weather | `field_renewed` (not implemented yet) |
| Plant growth | `field_renewed` → `PlantGrowth.refresh_world`; stage from `Clock.renew_index()` |
| Outdoor BGM | `hour_changed` + `Game.weather` → `BgmCatalog.outdoor_id` |
| Fish / bugs | `is_listed_now(months, hour_start, hour_end)` |
| Events | `weekday()` + date (not implemented yet) |

Daily simulation ticks at **06:00**, not midnight (`field_renewed`). Save/load restores the clock without replaying missed renews.

### Interaction

Hosts duck-type two methods. There is no shared `Interactable` base: a tree is a `StaticBody3D`, a villager is a `CharacterBody3D`.

| Piece | Role |
| --- | --- |
| `Interaction` | Verb payload (`id`, `prompt`, `priority`, `locks_player`, `player_anim`) |
| `InteractionContext` | `actor`, `inventory`, `world`; `release_occupant()` |
| `InteractionQuery` | Walk ancestors for a host; pick the closest overlapping `InteractVolume` |
| `ToolUse` | Equipped `ToolData` → kind, field verb, apply empty-tile use |
| `FurnitureUse` | `FurnitureData` → sit / lie / open / toggle / display / pick / rotate |
| `ShopUse` | Counter → buy overlay; Nook also sells |
| `TreeUse` | Shake / multi-hit chop / stump / fruit-drop counts |
| `PlantGrowth` | Seed → Growing → Mature → Harvestable from `planted_renew`; persist ids `plant_x_y` |
| `HoleUse` | Dig / fill hole FG; persist ids `hole_x_y` |
| Host scene | `get_interactions(ctx) -> Array[Interaction]` and `interact(action, ctx)` |

The player facing probe (physics layer `interact`) never does `if target is Tree`. It plays `action.player_anim` if set, then calls `host.interact` (or `ToolUse.apply_field` when the equipped tool has an empty-tile verb). Hosts add tool verbs via `ToolUse.has(ctx, kind)`: axe chops a tree (three hits to a stump; first hit or shake drops fruit), shovel digs a rock or a stump (stump leaves a hole), watering can waters a flower, shovel on a hole fills it. Empty-ground shovel writes a hole FG item. Net and rod are field verbs (swing anywhere; cast only at water). Stub verbs: talk, sit, enter, shop, read. Item pickup (ground items and flowers) is the one path with real pocket logic. Outdoor hosts register through `WorldObjectRegistry` so `WorldBuilder` does not switch on type.

## World scene

`scenes/world/world.tscn` is a **shell**: empty group nodes, ground, camera, HUD. Trees, buildings, and pickups are not stored in the `.tscn`. On `_ready`, `Game.resolve_world_data()` picks a layout and `WorldBuilder` instances scenes into the groups. `HoleUse.restore` and `PlantGrowth.restore` then re-instance saved holes and player-planted hosts.

```
WorldGenerator  →  WorldData  →  WorldBuilder  →  Godot nodes
 (what exists)      (resource)     (how it looks)
```

| Mode (`Game.world_mode`) | Source |
| --- | --- |
| `TEST` | Hand-authored single acre (`WorldGenerator.authored_test_town()`) |
| `GENERATED` | `TownFieldGenerator` (mRF acres) → rasterize 5×6 FG → `WorldData` (New Game; live seed. Title “Town Seed 12345” uses fixed seed) |
| `REFERENCE` | Reserved for a known GameCube layout later |

Generated towns are the playable **5×6 FG acres** (80×96 cells, 2 m each). Test town stays one 16×16 acre. Hierarchy:

```
World
├── Terrain
│   └── Acres          # generated: one grd_* host per FG acre
├── Objects
├── Characters
├── Buildings
├── Effects
├── Navigation
└── WorldEnvironment
```

Pipeline details: [decomp_notes/world_generation.md](decomp_notes/world_generation.md).

## Godot mapping (not C mapping)

| Concern | Godot approach |
| --- | --- |
| Game time | `Clock` autoload; subscribers, not OS `Time` in each system |
| Player | `scenes/actors/player.tscn` + `PlayerLocomotion`; generated `boy_1.glb` if present; `HeldTool` on HAND |
| Field A-button | `InteractionQuery` + host `get_interactions` / `interact`; `InteractVolume` sensors; `ToolUse` field verbs |
| Items | `ItemData` / `ToolData` resources + `Inventory` on `Game` |
| Town layout | `WorldData` + `WorldGenerator` / `WorldBuilder` / `WorldObjectRegistry` + `WorldGrid` + `FieldCollision`; world `.tscn` is a shell |
| Villagers | `VillagerData` + `VillagerPersonality` + `ScheduleData` + `Villager` scene; runtime `VillagerSchedule` / `VillagerState` / `VillagerMotor` / `VillagerAI` / `VillagerWalk`; species GLB via `GeneratedVisual.attach_villager` when present. Catalog is all 236 GC animals; towns still pick six starters. Talk interrupts the current AI step until the overlay closes. Player ↔ villager memory is `Relationship` (`Game.relationships`). |
| Dialogue | `DialogueData` JSON graphs + `DialogueRunner` + overlay; `DialogueGreeting` picks a starting imported `msg_no`; disc banks via `--kind dialogue` |
| Save | JSON IDs and counts to `user://`, not `.tres` with embedded scripts |

Do not port `m_common_data` as one Resource. Split player, town, inventory, and clock state.

## Vertical-slice roadmap

Each phase should be playable or testable in-engine. Later phases are not started until earlier ones are.

1. **Phase 0** — project scaffold.
2. **Phase 1** — architectural foundation + clock, empty acre, walk.
3. **Phase 2** — decomp research notes (`docs/decomp_notes/`).
4. **Phase 3** — title → world → spawn → walk → pick up → save on return to title.
5. **Phase 4** — world hierarchy + logical cell grid.
6. **Phase 5** — player controller: `CharacterBody3D`, GC walk feel, generated `boy_1` visual when present.
7. **Phase 6** — interaction framework: objects expose verbs; player uses `InteractionQuery`.
8. **Phase 7** — time and calendar: `Clock` is the source of truth; other systems subscribe.
9. **Phase 8** — world from data: `WorldData` + deterministic generator + hand-authored test town; world `.tscn` is a shell.
10. **Phase 9** — world-object framework (`WorldObjectRegistry`): tree, rock, flower, ground item, building, door; all use interaction verbs. New-game placement for house / shop / museum / Able Sisters / villager plots follows decomp acre rules ([world_objects.md](decomp_notes/world_objects.md)).
11. **Phase 10** — tools: `ToolData` + `ToolUse`; shovel, fishing rod, net, axe, watering can as interaction verbs (not full fishing / bug / plant systems).
12. **One deep interactable** — one tree (grow, shake, fruit, plant) with correct feel. Growth derived from planting date on `field_renewed`.
13. **Inventory** — `ItemData` / `InventoryItem` / `InventorySlot` / `Inventory`; 5×3 pocket UI; pick up, drop, stack, use, equip, save.
14. **Villagers** — shared `Villager` actor + looks data; full GC catalog; six starters in town. Talk opens the overlay via `DialogueGreeting`.
15. **Town shops + economy** — Nook buy/sell and Able Sisters buy; daily stock at 06:00.
16. **Town deltas** — persist more than one pickup and the current acre FG.

Content quantity is not a milestone. One good instance of a system is.

## What "Godot-native" means here

Use nodes, scenes, resources, signals, and groups the way Godot expects. Do not emulate GameCube memory layouts, actor overlay tables, or submenu heaps in GDScript.
