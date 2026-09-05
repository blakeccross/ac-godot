# Post office & police box

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only.

## Godot

`PostBook` / `PoliceBook` on `Game`. Authored rooms `post_office.tscn` / `police_box.tscn` under `scenes/world/interiors/`. Layout tables: `PostDisplay`, `PoliceDisplay`. Play through outdoor enter → `interior.tscn` mounts the room and calls `populate()`. F6 on the room `.tscn` alone uses `public_room`’s standalone preview (camera + light + populate).

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_post_office.h`, `src/game/m_post_office.c` | Mail desk storage, delivery clock |
| `src/data/scene/post_office.c` | Player spawn, sunshine, PTerminal |
| `src/data/field/mvactor/post_office.c` | Pelly stand ut (4,2) |
| `src/bg_item/bg_post_item.c` | Day/night clerk + letter piles |
| `src/actor/npc/ac_npc_post_girl*` | Pelly / Phyllis talk (send / loan / e-Reader) |
| `include/m_police_box.h`, `src/game/m_police_box.c` | Lost-and-found 20 slots |
| `src/data/scene/police_box.c` | Player spawn facing south |
| `src/data/field/mvactor/police_box.c` | Booker stand ut (4,6) |
| `src/bg_item/bg_police_item*` | Draw RSV_POLICE_ITEM slots |
| `src/actor/npc/ac_npc_police2*` | Booker claim confirm |

## Reproduce

- **Post:** shell `grd_post_office`, spawn GX `{100,0,200}`, exit `EXIT_DOOR` (3,8)/(4,8), Pelly (`pla`) 7–19 / Phyllis (`plb`) otherwise at stand GX `{160,0,100}`, letter piles from `mPO_get_keep_mail_sum` at X 80…240 / Y60 / Z60. Always enterable (lights only).
- **Police:** shell `police_indoor`, spawn GX `{200,0,400}` south, exit `EXIT_DOOR1` (4,10)/(5,10), Booker (`plc`) at `{180,0,260}`, 20 RSV cells for `keep_items`. Init: 1 furniture + 2 shirts. Claim: face item → Booker → pockets. `force_set_keep_item` on 06:00 renew when sum ≤ 5.
- Outdoor enter: post `door_type 0` + `OPEN1`; police `door_type 1` + `INTO_S1` (already on `StructureDoor`).
- Shells use 16× acre verts (`FieldCatalog.interior_uses_acre_verts`) like shops — not classic `room01` GX scale.

## Simplify

- Full letter write / delivery / loan / bank stay out until inventory mail exists (`PostBook.receipt_mail` stub only).
- PTerminal (GBA e-Card) ignored.
- Booker zone wander deferred — stands at actable.
- Claim confirm is immediate (decomp CHOICE0 path without imported msg bank choices).

## Ignore

- Copper outdoor patrol (`SP_NPC_POLICE`).
- Pete delivery actor.
- Sunshine window actors.
