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

- **Post:** shell `grd_post_office`, spawn GX `{100,0,200}`, exit `EXIT_DOOR` (3,8)/(4,8), Pelly (`pga_1` / `SP_NPC_POST_GIRL`) 7–19 / Phyllis (`pgb_1` / `SP_NPC_POST_GIRL2`) otherwise at stand GX `{160,0,100}`, letter piles from `mPO_get_keep_mail_sum` at X 80…240 / Y60 / Z60. Desk hull + Talk at GX `{160,0,140}` (shell mesh has no physics). eTM `PTerminal` at GX `{60,0,240}` (`msg_15854` → GBA missing → `msg_15859`). Clerk talk uses imported bank `msg_*` from `aPG_set_talk_info` (fallback `post_girl_greeting.json`). Desk choices: Mail / Deposit-or-Repay / Save → follow-up menus (`PostUse`). Always enterable (lights only). Do not use `pla`/`plb` — those are Booker / Pete.
- **Police:** shell `police_indoor`, spawn GX `{200,0,400}` south, exit `EXIT_DOOR1` (4,10)/(5,10), Booker (`pla_1` / `SP_NPC_POLICE2`) at `{180,0,260}`, 20 RSV cells for `keep_items`. Init: 1 furniture + 2 shirts. Claim: face item → Booker → pockets. `force_set_keep_item` on 06:00 renew when sum ≤ 5. `plc_1` is outdoor Copper.
- Outdoor enter: post `door_type 0` + `OPEN1`; police `door_type 1` + `INTO_S1` (already on `StructureDoor`).
- Shells use 16× acre verts (`FieldCatalog.interior_uses_acre_verts`) like shops — not classic `room01` GX scale.

## Simplify

- Letter write uses preset bodies + recipient picker (no full stationery editor). Delivery scheduling / Pete wait until a delivery slice.
- Bank amount entry is choice presets (All / 1,000), not the money keypad overlay.
- House **loan** lives on `Inventory.loan`; when `loan > 0`, Pelly's Deposit choice is repay. Bank savings unlock when loan is 0.
- PTerminal plays exact eTM welcome / choices; GBA link is stubbed to the “not properly connected” bank lines (`msg_15859`).
- Booker zone wander deferred — stands at actable.
- Claim confirm is immediate (decomp CHOICE0 path without imported msg bank choices).

## Ignore

- Copper outdoor patrol (`SP_NPC_POLICE`).
- Pete delivery actor.
- Sunshine window actors.
