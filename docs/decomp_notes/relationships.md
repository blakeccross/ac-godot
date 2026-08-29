# Relationships (player ↔ villager memory)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not copy `Anmmem_c`.

**Read before implementing:** `Relationship`, `RelationshipBook`, `VillagerState.relationship`. Dialogue snapshots this; it must not store friendship itself.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_npc.h` (`Anmmem_c`) | Per-player memory on each animal: last speak, friendship `s8`, saved letter |
| `src/game/m_npc.c` | `mNpc_AddFriendship`, `mNpc_GetAnimalMemoryBestFriend`, letter + present deltas |
| `include/m_private.h` | Player-side animal memory slot (foreigner mail), not the NPC’s 7 memories |

Key functions: `mNpc_AddFriendship`, `mNpc_GetAnimalMemoryIdx`, `mNpc_GetAnimalMemoryBestFriend`, `mNpc_SetAnimalMemory`.

Constants: `ANIMAL_MEMORY_NUM` **7** (one slot per player who has spoken). Friendship clamp **0–127**. Best-friend mail requires friendship **≥ 80**.

## What does the original system do?

Each villager stores **up to 7 player memories**. A memory is created the first time that player talks to them. It holds:

- Player id
- Last speak time
- Friendship (`s8`, `mNpc_AddFriendship` clamps 0–127)
- Saved letter flags / body (rank, reply, present cloth)

Friendship moves on **talk**, **mail**, **quests**, and **annoyances**. A received letter is **+3**, **−5** extra if the letter ranks bad, **+3** extra if it included a present. Talk amounts live in actor/quest code (this project uses +3 first talk of the day, +1 again).

“Best friend” is not a separate flag. `mNpc_GetAnimalMemoryBestFriend` picks the highest friendship memory and **rejects it below 80**. Event present mail uses that gate. Inter-villager relations are a 15-byte matrix at 128 (neutral) — a different system.

There is **no conversation log** and **no named milestone list**. History is last-speak time plus the letter. Gifts are presents on mail (and later hand-overs), not a gift journal.

## Important states

- Friendship 0–127 (original) / unlocked “best friend” at 80.
- Last speak timestamp.
- Letter exists / rank / present-cloth bits.
- Which of 7 slots this player occupies.

## Inputs

- Talk (creates memory if needed).
- Mail with optional present.
- Quest success/fail friendship deltas.
- Player leave / memory eviction when all 7 slots are full.

## Outputs / events

- Friendship value for greetings and quests.
- Best-friend index for event mail.
- Last-speak for “already talked today” / long-time-no-see.

## Interacts with

- **Villagers** — memories hang off the animal, not the message window.
- **Dialogue** — pickers **read** friendship / last speak; they do not own the number.
- **Inventory** — wrapped presents (`mPr_ITEM_COND_PRESENT`) and mail attachments.
- **Save** — `Animal_c.memories[]`.

## Reproduce

- One **player ↔ villager** bond per town animal (single-player; skip 7-slot eviction).
- Friendship int, last-spoke day, talk count, a short talk history, gift log, named milestones.
- Talk: +3 first of the day, +1 again that day (`VillagerState` / `Relationship.record_talk`).
- Gift: +3 (`mNpc` present-on-letter analog) via `Relationship.record_gift` / `RelationshipBook.give_gift`.
- Milestones: `met` (first talk), `best_friend` (80), `kindred` (127, original cap), `first_gift`.
- Dialogue **queries** friendship / milestones / gift count. `add_friendship` / `record_gift` events call into `Relationship`.

## Simplify

- One memory per villager, not 7 players. Friendship range stays **0–255** (already in save) with original **80 / 127** gates.
- No letter body, letter rank, or present-cloth bits.
- Talk history stores `{day, kind}` not spoken lines (lines belong to dialogue).
- Gift log stores `{day, item}` (cap 12). No wrapping / mail overlay.
- Skip villager–villager matrix and memory eviction.

## Ignore

- Multiplayer memory slots and foreigner `mPr_animal_memory`.
- HP password mail, Able Sisters cloth presents.
- Contest letter quests.
