# World objects

Reusable outdoor hosts (tree, rock, flower, ground item, building, door). Behavioral reference: FG items + structure actors in [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Do not copy C actor tables.

**Read before extending:** this note, [interaction.md](interaction.md), [world_generation.md](world_generation.md).

## Godot framework

```
WorldObjectRegistry  →  WorldBuilder  →  scene host
   (kind → scene)         (instances)      (verbs)
```

| Piece | Role |
| --- | --- |
| `WorldObjectRegistry` | One-line `register(kind, scene, place_kind, group)` |
| `ObjectPlacement` / `BuildingPlacement` | Layout entries inside `WorldData` |
| Host scene | Thin: `GeneratedVisual` + `InteractVolume` + `get_interactions` / `interact` |
| `Door` | Composable ENTER/SHOP sensor (child of `building`, or own placement) |

**Add a new object**

1. Create `scenes/world/my_thing.tscn` with an `InteractVolume` and the two host methods.
2. `WorldObjectRegistry.register(&"my_thing", "res://scenes/world/my_thing.tscn", …)`.
3. Emit an `ObjectPlacement` / `BuildingPlacement` with `kind = &"my_thing"` from the generator (or test town).

The player never switches on type. Verbs live on the host.

## Initial kinds

| Kind | Verb | Scene |
| --- | --- | --- |
| `tree` | Shake; chop (axe); dig stump (shovel) | `tree.tscn` |
| `rock` | Dig (stub) | `rock.tscn` |
| `flower` | Pick up | `flower.tscn` |
| `hole` | Fill (shovel) | `hole.tscn` |
| `item` | Pick up (inventory) | `item_pickup.tscn` |
| `building` | Enter via child `Door` | `building.tscn` |
| `door` | Enter / Shop | `door.tscn` |
| `house` / `shop` | Enter / Shop | existing shells |

## New-game placement (decomp)

| Object | Rule |
| --- | --- |
| Player houses | Always **B-3**; HOUSE0–3 at (3,3) / (12,3) / (3,10) / (12,10); west +20 X, east −20 X, both +20 Z; mesh `obj_s_myhome1`; west yaw +90° |
| Nook shop | Tracks row **A**; dump→shop; SHOP0 unit + NW (−1,0); mesh `obj_s_shop1` |
| Museum | Unique **flat** acre below cliff (`T_MUSEUM`) → `obj_s_museum` |
| Able Sisters | Beach row **bz=6** (`T_NEEDLEWORK` / `grd_s_m_ta_*`). FG `NEEDLEWORK_SHOP` is **(9, 4)** on `_1`/`_2` and **(9, 5)** on `_3`. Door verb shop, NW (−1,0), `aNW_actor_ct` −20 X +20 Z |
| Post / police / well / station | `obj_s_yubinkyoku` (−1,0) / `obj_s_kouban` (3×3 centered) / `obj_s_shrine` (0,−1) / `obj_s_station1` at TRAIN_STATION **(8, 5)** + −20 X |
| Villager homes | FG **SIGN00–SIGN20** reserves shuffled; SIGN ut must be 1..14. **6** houses (`mNpc_LOOKS_NUM`). House FG on the SIGN unit (`obj_s_house1`, no `actor_ct` shift); 3×3 RSV overwrites trees. No outdoor villager actor on generated towns. Fallback synthetic plots on flats if catalog has no SIGNs |
| Trees / rocks / flowers | FG template copy (`FgCatalog`) at **unit center** (`bg_item` `pos_table` 20+40n GX), then border pull / tanuki path, then fruit/cedar. House build clears the SIGN 3×3 |

Structure FG ids (`HOUSE0`, `SHOP0`, `MUSEUM`, `NEEDLEWORK_SHOP`, …) refine cell offsets when the disc FG catalog is present.

## Simplify / ignore

- Indoor room scenes (ENTER stays “locked” / shop hours stub).
- Outdoor NPC actors and schedules on generated towns (test town still has Pip). House shells spawn; villagers do not.
- Money-rock / dig loot tables. Pitfall kits, buried items, and walking into a hole (fall).
- House upgrade stages (`obj_s_myhome2`–`4`, `obj_s_house2`–`5`) until upgrades exist.
