# Dialogue (message window, choices, talk lock)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not commit Nintendo message banks.

**Read before implementing:** `DialogueData`, `DialogueRunner`, `DialogueCatalog`, `DialogueGreeting`, talk UI, villager greeting.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_msg.h`, `src/game/m_msg.c` | Window state machine, buffers, free-string slots |
| `include/m_choice.h` | Up to 6 choices + determination string |
| `include/m_string.h`, `m_string_data.h` | Shared string table |
| `include/m_msg_data.h`, `m_msg_enum.h` | Message ids / banks (`MSG_MAX` 0x3F91) |
| `include/m_demo.h` | Talk demo: camera, facing, window color |
| `include/m_item_name.h` | Item name insertion |
| `include/m_font.h` | Glyph rendering (ignore) |
| `src/game/m_msg_cursol.c_inc` | Control codes: `SETNEXTMSG*`, `SETSELSTR*`, `OPENCHOICE` |
| `tools/msg_tool.py` | Disc `message_data.bin` encode/decode (char map + 0x7F commands) |
| `src/static/jsyswrap.cpp` | `message_data.bin` / `message_data_table.bin` / `select_data.bin` / `string_data.bin` |

Key functions: `mMsg_request_main_appear`, `mMsg_request_main_disappear`, `mMsg_Set_free_str`, `mMsg_Main` / `mMsg_Draw`, `mMsg_Check_main_wait`, `mMsg_Set_continue_msg_num`.

## What does the original system do?

Dialogue is a **global message window**, not a per-NPC widget. A client actor requests appear with optional nameplate and window color. The window walks:

`HIDE` → `APPEAR` → `NORMAL` (typewriter) → `CURSOL` (wait for A) → page or `DISAPPEAR`.

Strings are a **message bank** (`RESOURCE_MESSAGE` / `message_data.bin`), not a tree. Control bytes (`0x7F` + command) insert names, open a choice list, and queue the next `msg_no` (`SETNEXTMSG0` is “if the player picked choice 0”). NPC C scripts pick the starting `msg_no` from personality, friendship, weather, time, and events — those pickers stay in actor code, not in the bank.

`m_choice` is nested hide/appear/normal/disappear. Choice labels come from `select_data.bin` (`mChoice_SELECT_STR_NUM` 607).

Talk is wrapped in `m_demo`: player `mPlib_request_main_talk_type1`, camera `CAMERA2_PROCESS_TALK`, then messages.

## Important states

- Window main index (`mMsg_INDEX_*`).
- Current page / cursor.
- Status flags (fast text, no sfx, no camera zoom, …).
- Choice overlay index and `selected_choice_idx`.
- Free-string slots 0–19 filled before appear.

## Reproduce

- Modal text box, typewriter, A/E to continue, hold to speed up.
- Branching **choices** (yes/no and 2–6 options).
- Substitutions: `{player}`, `{speaker}`, `{catchphrase}`, `{town}`, `{item0}`, clock fields.
- Movement locked until the window hides (`dialogue_ui` group, same idea as pockets). The speaker holds a talk action until the overlay emits `closed`.
- Conditions on branches and choices: friendship, talk/gift counts, milestones, time of day / hour window, weekday, season, **weather** (`Game.weather` hook), inventory / held item, dialogue variables.
- Events on a line or choice: `set_var`, `add_var`, `add_friendship`, `record_gift`, `give_item`, `take_item`, `set_mood`, `notice`. Friendship and gifts go through `Relationship`.

## Simplify

- Author **JSON graphs** (`data/dialogue/*.json`), not `m_msg` bytecode. `DialogueData` / `DialogueRunner` / `DialogueCatalog` / `DialogueGreeting` are `RefCounted` helpers, not an autoload.
- One overlay scene (`scenes/ui/dialogue_overlay.tscn`). Skip appear/disappear interpolation, voice blips, article grammar, mail-string length 132.
- Named `{player}` tags instead of `mMsg_FREE_STR` 20-slot array.
- Weather is a `StringName` on `Game` (`clear` / `rain` / `snow` / `sakura`) plus intensity from `Weather.roll`.
- Camera nudge toward the speaker can wait.
- Talk start is a Godot picker (`DialogueGreeting`): looks + whether you’ve met / already talked today / weather / mood / hour → starting `msg_no`. That id `goto`s the imported bank. Personality quest/trade trees stay out until a slice needs them. If the bank is missing, `looks_greeting.json` is the placeholder.

## Import (disc → gitignored JSON)

Original banks are Nintendo IP. Do **not** commit them. Convert locally:

```sh
python3 tools/build_assets.py --kind dialogue --step convert
```

Reads `message_data.bin` + `message_data_table.bin` (and `select_data` / `string_data` when present) from the extracted disc. Writes:

```
assets/generated/dialogue/   # gitignored
  index.json
  0000.json …                # 256 conversations per file, ids `msg_0` …
  select.json
  strings.json
```

Each imported message becomes a graph: pages (`BTN`) → line nodes, `SETSELSTR`+`OPENCHOICE` → choice node, `SETNEXTMSG*` → `goto` `msg_<n>`. `DialogueCatalog` loads those files when they exist so a conversation can `goto` an imported id.

Hand-authored trees live in `data/dialogue/` (`looks_greeting` is the no-bank fallback; `filbert_greeting` is a small authored example).

## Ignore

- Debug `mMsg_debug_draw`, ARAM init, staff-roll / title demo, letter editor, board overlay, password check.
- Faithful recreation of every personality talk script in C. Import the **bank**; write Godot conditions for the lines we actually play.
