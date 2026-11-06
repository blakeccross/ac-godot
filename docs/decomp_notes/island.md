# Animal Island / Kapp'n (`ac_npc_sendo`, `ac_boat_demo`, `ac_boat`, `m_island`)

Behavioral reference: `src/actor/npc/ac_npc_sendo*.c*`, `src/actor/ac_boat_demo*.c*`,
`src/actor/ac_boat*.c*`, `src/game/m_island.c`, `src/actor/ac_quest_talk_island.c`.
Status: slices 1–3 landed (GBA-free). The island is built as a world of its own
(`WorldGenerator.generate_island`, `Game.island_visit`) from the town's two island acres and their
FG templates (flag, boat landing and both cottages included); Kapp'n and his dinghy wait at the
town wharf and the island landing (`IslandService`, `Boat`, `Kappn`, `KappnTalk`, `IslandRoute`).
Talk → yes → name the island (first ride) → board → he sings (`0x3091`… lyrics) as the boat sails
the route in the **town** world (`aBT_chk_point`, 0.625 GX a tick) → wipe to the island world →
"Island, ho!" → step off. The way home mirrors it. The player's cottage (`COTTAGE_MY`, model `obj_s_myhome_i`) opens into room `cottage`: `aMR_GetSceneRoomKind` gives it the large house's room, entered at (200, 0, 380), with its own wall / floor / furniture and no stairs (`InteriorCatalogPublic._cottage_room`); the door flow is the player house's (`HostCollision.is_player_house` matches `myhome`) and has not been walked through in-game yet. What is in and what is left is under Status at the bottom. Dev commands: `island [home]`, `ride [fast]`.

## Shape of the system

- The island is **a block kind of the town field** (`mRF_BLOCKKIND_ISLAND`), not a separate scene:
  `BOAT_DEMO` checks the player's block and sets `at_island`. The two island grounds are already
  drawn here (`grd_s_il_*` / `grd_s_ir_*`); what is missing is their FG (`mFM_SetIslandFg`, trees,
  cottage) and `mRF_IslandBgData_To_VillageData`; the way there is built (`Boat`, `Kappn`, `IslandRoute`).
- `BOAT_DEMO` (control actor) drives the trip; Kapp'n (`NPC_SENDO`) reacts to its `action`
  (`aBTD_ACTION_*`) and the demo reacts to his `demo_act`. The boat (`ac_boat`) sails between the
  town wharf and the island wharf; the player rides on it.
- Kapp'n's talk (`aSEN_TALK_*`, ~30 states) is mostly **GBA transfer** (`mGcgba_*`): connect-enabled
  check, program/data send, island data read back. The GBA-free path is: `PL_RIDE_ON_CHECK` →
  `CHK_EXIST_ISLAND_DATA_IN_RAM` → (no island yet) `GET_ISLAND_NAME_MENU` (`mLE_TYPE_ISLAND_NAME`)
  → ride; on the island, `arrive_call` (think acts 12/13), ride-off, and the out-of-service talks
  (think acts 15/16, `mISL_RestoreIsland`).
- Think acts (`aSEN_setup_think_proc` table): 0/1/2 wait (fine / rain / at island), 3 ride-on end,
  4/5/6 start call (no island data / island data in RAM / at island), 7 sing, 8/9 force talk while
  sailing, 10/11 touch wharf, 12/13 arrive call, 14 ride-off end, 15/16 out of service.
- `mISL_SetNowPlayerAction` records the rider's destiny and gender for the islander's talk.
- Islander villager, cottage (`SCENE_COTTAGE_MY`, `ac_cottage`), island fish/bugs, island flag
  (`ac_flag`, `island.flag_design`) and the island tune are separate slices.

## Proposed slices (each leaves something playable)

1. **Island FG + access** — place the island FG (`mFM_SetIslandFg`), fruit/palms, cottage building;
   a debug `island` console command that puts the player on the island wharf.
2. **Boat demo** — `BoatDemo` presenter: boat and Kapp'n at the town wharf, ride out and back with
   the sing/arrive talks; no GBA (skip the transfer states).
3. **Kapp'n's talk** — name-the-island menu, ride-on check, out-of-service talks.
4. **Islander + cottage** — the resident, `aEv`/quest talk (`ac_quest_talk_island`), cottage room.
5. **Island ecology** — island fish list (`f_island`), insects (`l_insect_island`), tune.

Slice 2 is the largest (`ac_boat_demo_move` 387 lines, `ac_boat_move` 558, plus the sendo move
file at 1290 lines of which about a third is GBA).

## Status (2026-11-06)

In: the player's cottage and its room (own wallpaper / floor / furniture / music box / cockroaches);
the islander (`Islander`: picked once per town from the 18 `islander` villagers by the town seed,
saved in `TownState.islander_id`), standing in their cottage's yard by their schedule, the cottage a
villager-style home (`obj_s_house_i`, the room `npc_<id>`; a knock while they sleep is answered with
`MSG_ISLANDER_NOENTRY_SLEEPING1` + looks), their greeting (the island hello table) and island chat
(`aQMgr_decide_normal_msg_no_island`, `VillagerTalkManager.as_islander`); the island's summer
(`Clock.summer_only`, `mFM_toSummer`) and weather (80% clear / 20% heavy rain, `IslandClimate`),
restored on the way home; `BGM_ISLAND` on the island and Kapp'n's shanty music (`BGM` 92–111 first
part, 112–121 second) over the voyage; Gulliver floating out at sea (`ac_ev_castaway`) while his
wash-up is on and unmet; island fish (`f_island`) and insects (`l_insect_island`); and Kapp'n drawn
with the right skeleton (`wip_1`: `npc_draw_data_tbl[ALL_NPC_NUM + 114]`, not `kab_1`).

Not in, and not GBA: the furniture trade with the islander and the rest of `aQMgr_talk_island_select_talk`
(its first branch, the player-action / other-player / mail lines), the islander's room as the island's
own furniture list (`l_island_npc_room_data`, `RSV_ISLAND_FTR*`) instead of the villager default, the
islander's presents and letters, the hourly-chime instrument (`sAdo_Inst(0xFE)`) and the boat's volume
duck (`mBGMPsComp_volume_boat`). GBA: [gba_not_implemented.md](../gba_not_implemented.md).

## The furniture trade (not built; what it takes)

Researched 2026-11-06 and left, because it is a multi-player furniture exchange rather than a chat:

- **Room data**: the islander's room is not their villager room. `l_island_npc_best_fg_id[islander]`
  names an `fgnpcdata` template whose 16 furniture slots (`mNpc_ISLAND_FTR_NUM`) hold either their
  "best" pieces or reserved `RSV_ISLAND_FTR0..15` markers (0xFEB3…, by size and direction).
  `tools/asset_pipeline/npc_rooms.py` only decodes each villager's `npc_house_list` template, so the
  island rooms need a second pass there (the best ids come from `m_npc.c`), with the markers kept as
  slots.
- **State** (`Save_Get(island).animal`): per player memory `have_bitfield` (which of the 16 slots they
  filled), the four-entry `anmuni.island_ftr` trade list (the generic pieces, by size), and the
  present piece with the player who left it (`mNpc_SetIslandPresentFtr`). A slot shows in the room
  only once some player has it (`mNpc_ChangeIslandRoom`).
- **Rules**: `mNpc_CheckFtrIsIslandBestFtr` / `_NormalFtr`, `mNpc_CheckIslandNpcRoomFtrItemNo_keep`,
  `mNpc_SetIslandGetFtr`, `mNpc_EraseIslandFtr(_keep)`, `mNpc_GetRandomBestFtr`,
  `mNpc_GetOtherBestFtr`, `mNpc_GetPlayerBestFtr`.
- **Talk**: `aQMgr_check_trade_0..8` pick the line (most look at another player's memory), then
  decide-trade orders 18–21 fill the item strings and the trade orders swap items with the pockets.
  Orders 1–17 and 22–24 are the town's, already in `VillagerTalkManager`.

A single-player port would only need check 0 / 1 / 5 / 7 / 8 and orders 18–20, but the dialogue banks
(`0x35E0…`) are written against the full set, so it is worth doing together with a second player.
