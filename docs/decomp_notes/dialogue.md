# Dialogue (message window, choices, talk lock)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not import message binaries or `m_msg` control codes.

**Read before implementing:** `DialogueData`, talk UI, villager greeting.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_msg.h`, `src/game/m_msg.c` | Window state machine, buffers, free-string slots |
| `include/m_choice.h` | Up to 6 choices + determination string |
| `include/m_string.h`, `m_string_data.h` | Shared string table |
| `include/m_msg_data.h`, `m_msg_enum.h` | Message ids / banks |
| `include/m_demo.h` | Talk demo: camera, facing, window color |
| `include/m_item_name.h` | Item name insertion |
| `include/m_font.h` | Glyph rendering (ignore) |

Key functions: `mMsg_request_main_appear`, `mMsg_request_main_disappear`, `mMsg_Set_free_str`, `mMsg_Main` / `mMsg_Draw`, `mMsg_Check_main_wait`.

## What does the original system do?

Dialogue is a **global message window**, not a per-NPC widget. A client actor (usually the NPC) requests appear with optional nameplate and window color. The window walks:

`HIDE` → `APPEAR` → `NORMAL` (typewriter) → `CURSOL` (wait for A) → page or `DISAPPEAR`.

There are wait variants (`APPEAR_WAIT`, `DISAPPEAR_WAIT`) so the player/NPC anim can finish. Buffer size is large (`mMsg_MSG_BUF_MAX` 1536) with **4 visible lines**. Typewriter speed can fast-forward (`mMsg_STATUS_FLAG_FAST_TEXT`). Voice blips and zoom-in sfx are flag-gated.

Strings support **free slots** (player name, town, catchphrase, numbers) and **item name** slots. Articles can be stripped (`CUT_ARTICLE`). Results are a small enum: void / false / true — often from a yes/no choice.

`m_choice` is a nested list (hide/appear/normal/disappear) with automove between options. Choice strings are short (16 chars in the struct; select table has hundreds of canned lines).

Talk is wrapped in `m_demo`: player `mPlib_request_main_talk_type1`, camera `CAMERA2_PROCESS_TALK`, then messages. Ending talk is `mPlib_request_main_talk_end_type1`.

The original script is thousands of banks selected by personality, friendship, event, weather, and random. That content is Nintendo IP and out of scope.

## Important states

- Window main index (`mMsg_INDEX_*`).
- Current page / cursor.
- Status flags (fast text, no sfx, no camera zoom, …).
- Choice overlay index and `selected_choice_idx`.
- Demo state and speak-actor pointer.
- Free-string slots 0–19 filled before appear.

## Inputs

- Appear request + message id / buffer.
- A (advance), B (fast-forward / skip in some modes).
- Pre-filled template strings (names, item, numbers).
- Choice count and labels.

## Outputs / events

- Window closed (`main_hide`).
- Choice index or boolean result.
- Player returns to wait.
- Friendship / shop / quest scripts read the result (not the message system itself).

## Interacts with

- **Player** — talk lock.
- **Villagers** — client actor, personality, catchphrase.
- **Camera** — talk process.
- **Inventory / shops** — “sell this?” choices.
- **Audio** — voice and page-turn (optional).

## Reproduce

- Modal text box, typewriter, A to continue.
- Hold-to-speed-up.
- **Branching choices** (at least yes/no, later 2–3 options).
- Substitutions: player name, villager name, item name.
- Movement locked until the window hides.
- Camera nudge toward the speaker.

## Simplify

- Author `DialogueData` trees in `.tres`; do not emulate message banks or control-code bytecode.
- One window UI scene; skip appear/disappear interpolation fidelity.
- Skip voice blips, article grammar engines, mail-string length 132.
- Skip `mMsg_FREE_STR` 20-slot array; named dictionary is enough.
- No determination-string extra button on choices unless a shop needs “confirm”.

## Ignore

- Debug `mMsg_debug_draw`.
- ARAM message init (`mMsg_aram_init`).
- Staff-roll and title demo messages.
- Letter editor, board overlay, password check text.
- Faithful recreation of every personality script.
