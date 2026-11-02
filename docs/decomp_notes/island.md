# Animal Island / Kapp'n (`ac_npc_sendo`, `ac_boat_demo`, `ac_boat`, `m_island`)

Behavioral reference: `src/actor/npc/ac_npc_sendo*.c*`, `src/actor/ac_boat_demo*.c*`,
`src/actor/ac_boat*.c*`, `src/game/m_island.c`, `src/actor/ac_quest_talk_island.c`.
Status: slices 1–3 landed (GBA-free). The island is built as a world of its own
(`WorldGenerator.generate_island`, `Game.island_visit`) from the town's two island acres and their
FG templates (flag, boat landing and both cottages included); Kapp'n and his dinghy wait at the
town wharf and the island landing (`IslandService`, `Boat`, `Kappn`, `KappnTalk`, `IslandRoute`).
Talk → yes → name the island (first ride) → board → he sings (`0x3091`… lyrics) as the boat sails
the route in the **town** world (`aBT_chk_point`, 0.625 GX a tick) → wipe to the island world →
"Island, ho!" → step off. The way home mirrors it. Not done: the cottage interiors, the islander,
the island climate (always summer), island fish/insects/tune, the shanties' music, the castaway
(`aBTD_setup_castaway`), and everything GBA. Dev commands: `island [home]`, `ride [fast]`.

## Shape of the system

- The island is **a block kind of the town field** (`mRF_BLOCKKIND_ISLAND`), not a separate scene:
  `BOAT_DEMO` checks the player's block and sets `at_island`. The two island grounds are already
  drawn here (`grd_s_il_*` / `grd_s_ir_*`); what is missing is their FG (`mFM_SetIslandFg`, trees,
  cottage), `mRF_IslandBgData_To_VillageData`, and a way to get the player there.
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
