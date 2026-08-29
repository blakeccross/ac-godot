# Interaction (talk, pick up, tools, context tags)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only.

**Godot:** Field A is `InteractionQuery` against `InteractVolume` sensors. Hosts expose `get_interactions` / `interact`. Do not add `if target is Tree` in the player.

**Read before implementing:** A-button targeting, pickup/drop, tool use on a tile, talk start.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_player.h` | `PICKUP`, `TALK`, `SHAKE_TREE`, tool indices |
| `include/m_player_lib.h` | `mPlib_request_main_talk_type1`, `give`, `hold`, `sitdown`, scoop/net/rod requests |
| `include/m_tag_ovl.h` | Inventory **context menu** types (`mTG_TYPE_FIELD_DEFAULT`, plant, sell, give, …) |
| `include/m_submenu.h` | Pause/inventory overlay; Start/Y open pockets, X map |
| `include/m_hand_ovl.h` | Cursor-hand grabbing a slot (`mHD_ACTION_*`) |
| `include/m_demo.h` | Talk/cutscene lock; camera + message priority |
| `include/m_msg.h` | Message window appear/disappear |
| `include/ac_insect_h.h` | Player-action notices to bugs (`aINS_PL_ACT_*`) |
| `include/ac_furniture.h` | Contact actions: sit, push, storage |

A-button in the field is **not** one function. The player actor, collision unit, equipped item, and nearby NPC together pick a mode. Inventory uses a second path: highlight a slot, then a **tag** list (bury, plant, drop, present, sell).

## What does the original system do?

**Field interact (A):**

- Empty hands + item on tile → pickup (or pickup-jump, furniture pickup).
- Empty hands + NPC in range and addressable → `request_main_talk` + demo/camera + `m_msg`.
- Empty hands + tree → shake (`SHAKE_TREE`). Fruit may fall; later shakes only rustle.
- Axe + tree → chop (`SWING_AXE`). Three hits fell a full tree to a stump; the first hit also drops fruit if any.
- Axe / net / rod / scoop equipped → tool mode for that item.
- Furniture contact while indoors → push/pull/rotate or sit depending on profile flags.

**Inventory interact:**

- 15 pockets shown 5×3 (`mIV_ITEM_COLUMNS` × `ROWS`).
- Hand overlay picks a slot; tag overlay shows verbs that depend on **where** you opened the menu (field, own room, shop sell, letter, gyroid).
- Dropping writes an FG item onto the facing unit (`mTG_TYPE_FIELD_DEFAULT` vs `FIELD_DEFAULT_BURY`).

**Talk** is a demo: player faces the NPC, camera switches to `CAMERA2_PROCESS_TALK`, message window appears, player is non-addressable.

## Important states

- Player main index (idle vs already busy).
- Equipped item kind.
- Facing unit’s FG item / actor.
- Nearby NPC label (`mPlib_Set_able_force_speak_label`).
- Submenu open vs closed (`mSM_PROCESS_*`).
- Tag type + selected verb.
- Demo state (`mDemo_STATE_WAIT/READY/RUN/STOP`).

## Inputs

- A / B / Start / Y / X.
- Stick (move only when not in talk/tool lock).
- Equipped item and pocket contents.
- Tile contents, water attribute, indoor vs outdoor field id.
- Shop/NPC “I want to receive/give” requests.

## Outputs / events

- Mode request on the player.
- FG item add/remove; pocket slot change; wallet change.
- Message window + choice result (`mChoice` selected index).
- Insect stress (shake/dig/axe on a unit).
- Furniture state change (open drawer, rotate 90°).
- Submenu close → player `wait` or `give`/`putin_scoop` if the hand is holding something.

## Interacts with

- **Player** — exclusive modes.
- **Inventory** — pockets, presents, quest-flagged items.
- **World** — unit occupancy and collision.
- **Dialogue / villagers**.
- **Furniture / plants / fishing / bugs / shops**.

## Reproduce

- **One interact button** that does talk, pick up, or use-tool based on target + equipment.
- Cannot interact while already in a locked action.
- Pick up goes to the first free pocket; refuse if full (`REFUSE_PICKUP`).
- Drop / place onto the facing tile if empty.
- Talk turns the player, locks movement, opens dialogue.
- Tool use is tile- or volume-based (axe/shake on tree; shovel digs a hole or fills one; net in front; rod at water).

## Simplify

- One interaction ray / facing-tile query instead of actor overlay clipping.
- A small verb set: talk, pick up, drop, use tool, sit. Do not port 70+ `mTG_TYPE_*` tags.
- No separate “pickup jump” / “pickup exchange” unless a slice needs it.
- Inventory context: field vs shop vs house is enough; skip letters, gyroids, e-Reader, Able Sisters patterns.
- No GameCube submenu prerender heap (`mSM_MODE_PRERENDER_*`).

## Ignore

- Password items, tickets, balloons, wisps as tag types.
- Haniwa (gyroid) buy/sell tags.
- Catalog order / collector hand-over to Blathers tags until museum is in scope.
- Needlework / custom design stickers.
- `mDemo_ORDER_*` scripted cutscene sequencer beyond “talk camera + UI”.
