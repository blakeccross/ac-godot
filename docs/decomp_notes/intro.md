# Intro (Rover train character creation)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not commit Nintendo message banks or train meshes.

**Read before implementing:** `IntroSequence`, train intro scene, title → intro hook.

## Decomp sources

| File | Role |
| --- | --- |
| `src/actor/npc/ac_npc_guide.c` / `ac_npc_guide_move.c_inc` | New-town Rover on the train (`SP_NPC_GUIDE`) |
| `src/actor/npc/ac_npc_mask_cat2*.c*` | Returning / visitor Rover path (not this slice) |
| `src/actor/ac_intro_demo*.c*` | Post-arrival station → Porter → Nook house pick |
| `src/actor/npc/ac_npc_rcn_guide*.c*` | Tom Nook guide after the train |
| `include/m_private.h` / `m_player_lib` | `gender`, `face` (`mPr_FACE_TYPE_NUM` = 8) |
| `m_ledit_ovl` / `m_timeIn_ovl` | Name and clock submenus on the train |

Key Rover actions (`aNGD_ACTION_*`): enter → approach → talk → clock check → sit → player name → sex select → town name → standup → aisle/door/deck → phone (`keitai`) to Nook → return → last talk → scene change.

Face bits (`aNGD_check_talk_msg_no` / `aNGD_set_pl_face_type`): messages `0x2AC9` / `0x2ACD` / `0x2ACF` / `0x2AD3` OR bits 3..0 into `answer_flags`. If bit 0 is clear (money = “plenty”), face is random; else `face_type_table[gender][answer_flags >> 1]`.

## What does the original system do?

Starting a **new town** drops the player into a train demo. Rover walks up, confirms the system clock, sits, asks for a name, infers gender from “cool / cute” (with a confirmation), asks for a town name, then asks four attitude questions that secretly pick one of eight faces. He steps into the aisle, phones Nook about a house, comes back for a farewell, then the game wipes into the outdoor intro (`ac_intro_demo`).

## Reproduce (this milestone)

- Title menu entry that runs the **train act only**.
- Clock confirm / edit → name → gender → town → four face questions → phone call (text) → farewell.
- Face selection matching the decomp bit table (and random when the money answer clears bit 0).
- Persist `player_name`, `town_name`, `player_gender`, `player_face` into the session and start a generated new game.
- Placeholder train car + Rover; paraphrased dialogue JSON (no bank text).

## Simplify

- No train door / walk / sit animations; no echo SFX; no faithful camera morph.
- Name and clock are small intro modals, not `m_ledit` / `m_timeIn` ports.
- Phone call is dialogue only (no keitai prop).
- Skip returning-player / mask-cat Blanca path.

## Ignore (later slices)

- Station arrival, Porter (`SP_NPC_STATION_MASTER`), Raccoon guide house pick, first-job quests (`mQst_SetFirstJobStart`).
- Title demos (`m_titledemo`), staff roll, multi-player slot select.
