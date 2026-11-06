# Game Boy Advance features: not implemented

The GameCube game links to a Game Boy Advance (and an e-Reader). None of that is built here, by
decision: this project has no GBA, and the island lives in the town's own data. Everything below
is **skipped on purpose**, not forgotten. Each entry names the decomp code that would be ported if
the link ever came back as something else (a second device, a file exchange, a web service).

## Animal Island on the GBA (`m_island`, `m_gba_ovl`, `mGcgba_*`, `m_eappli`)

- **Kapp'n's transfer states** (`aSEN_TALK_*` in `ac_npc_sendo_move.c_inc`, about a third of the
  file): "is a GBA connected", sending the island program, sending / reading back island data, the
  "check the cable" and "transfer finished" talks. Kapp'n's GBA-free talks are in (`KappnTalk`).
- **A GBA-made island**: the GBA game can carry its own island and islander. `mISL_gc_to_agb` /
  `mISL_agb_to_gc` (the whole island packed for the cartridge and unpacked from it, with checksums:
  the FG, the cottage, the islander's memories, quests and mail) are not ported.
- **Playing the island on the GBA** and the changes that **sync back** to the town (what you left
  in the cottage, the islander's friendship, the trade state).
- **The islander moving into your town** once befriended there (`mNpc_...` moves driven by the GBA
  data). Here the islander is a fixed resident of the island who never moves.
- **Island-only items sent to the GBA** (`mSP_SelectRandomItemToAGB`) and the **island tune** that
  comes back with them.

## e-Reader (`m_card`, `ac_broker_design`, password systems)

- Design cards, villager and character cards, item cards, NES-game cards, town-tune cards and
  special-character cards; villagers scanned in moving to town.
- Able Sisters' "Other things" → GBA design tool / upload / e-Reader (`ac_npc_needlework_gba.c_inc`,
  `aNNW_TALK_GBA_*`, `CARD_E_*`): the menu is there and answers "no Game Boy Advance connected".

## NES / Famicom

- The built-in NES games on the Famicom furniture (`famicom_emu.c`, `jaudio_NES`, `ks_nes_core`),
  their save states and their GBA download. The console exists as furniture only.

## Not GBA, and not done yet

The island's furniture trade with the islander (`mNpc_SetIslandRoomFtr`, `mNpc_SetIslandGetFtr`,
`mNpc_SetIslandPresentFtr`, `aQMgr_check_trade_0..8`, the 18 island rooms in `l_island_npc_room_data`
and their "best furniture"), the islander's lines about what you did on the way over
(`mISL_SetNowPlayerAction`), about other players and about letters, and the islander's letters and
presents. They need no GBA; see [island](decomp_notes/island.md) for what is in and what is left.
