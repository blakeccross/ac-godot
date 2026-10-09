# Animal Crossing (GameCube) — 1:1 Feature Checklist

Goal: recreate **every** system and content set from *Animal Crossing* for the
Nintendo GameCube (`GAFE01`, USA rev 0 — the [ac-decomp](https://github.com/ACreTeam/ac-decomp)
target) in Godot 4. The only intended deviation is **HD textures / re-authored art**;
behaviour, numbers, schedules, and content should match the original.

> This checklist is the authoritative status tracker; see [scope.md](scope.md) for
> content policy. Items are listed whether or not they are currently in progress so
> nothing is forgotten. `docs/decomp_notes/` holds the behavioural detail for systems
> already studied.

## Legend

- `[ ]` — not started
- `[~]` — partial / scaffolding exists (see notes)
- `[x]` — complete and verified faithful to the original

Numbers marked _(verify)_ are from memory and should be pinned against the decomp
data tables before a category is called done.

---

## 1. Boot, save, and session

- [~] Title screen: New Game / Continue (`m_scene`, `m_start_data_init`) — `scenes/ui/title.tscn` (attract-mode town + animated logo; see [title](decomp_notes/title.md))
- [~] New town vs. load-existing branch (`mSDI_StartInitNew`)
- [x] Up to **4 human residents** per town, picked at K.K.'s player select (`ac_npc_p_sel2`): the disc's talk from `MSG_5106` — "Shall we get started?", the residents' names plus "I'm new" (four names, no newcomer, in a full town), then "That's right!" and the town loads for them, or a newcomer rides Rover's train in and gets a vacant house from Nook ("That house has already been taken, by…" on the others) — `PlayerRoster`, `PlayerSelectTalk`, `Game.start_player_select` / `start_new_resident`. The save is the town plus four private parts (`SaveService` version 2; older saves are resident 1). Missing: K.K.'s own word ending, the sound / rumble options do nothing
- [~] Character creation flow driven by Rover Q&A (`ac_npc_guide` / intro train) — `intro_train_stage.gd`
- [x] Delete a resident ("Demolish a house", two names a page with "Someone else." in a full town; never the last house) or the whole town ("Build a new town") from K.K.'s "Other things" (`aNPS2_chk_clr_pl_data*`, `aNPS2_chk_clr_village_data_cartridge`)
- [~] Save + return to title on quit (`save_menu.c`, `m_save`) — `save_service.gd`
- [x] **House gyroid** outside each house plot is the save point (`ac_haniwa`, `ACTOR_PROP_HANIWA0`–`3`) — `scenes/world/haniwa.tscn` + `HaniwaTalk` + `HaniwaStore`: FG placement two units south of every house, `hnw_move` bob / dance speeds and turn-to-player, empty-plot freeze facing front, first-job "need a friend" line; owner menu: **Save** (walk to the door → door opens → save → title), **Store an item** (4-slot consignment table in the pockets: free / display only / for sale with a 5-digit price, take back), **Other things** → **About the door** (post one of your designs on the front door / remove it) and **Set message** (4-line visitor message, ROM default text); sale **proceeds** collected on the next talk (wallet, then 30 000-bell bags); **visitor** flow (read the message, pay and take) is in place but can't trigger in a one-resident town. `BGM_ENTER_HOUSE` is a plain BGM swap rather than a pushed demo track
- [x] ~~Memory Card management, copy, "not saved correctly" recovery~~ — no Memory Card here; saves are files (`SaveService`), and quitting without saving is Mr. Resetti's job (below)
- [x] **Mr. Resetti** appears if you quit without saving; escalating lectures by reset count; **Don** on the fifth (`mCD_SetResetInfo`, `ac_reset_demo`, `ac_npc_majin*`) — the save carries a `reset_code` set at load and cleared by a proper save; `ResettiVisit` picks the visitor and opening message (9+ cycle 6–8), `scenes/world/resetti.tscn` pops up (`APPEAR1`), lectures, waits to be spoken to on the fourth, digs back down (`GO_UG1`), with his helmet light at night. The typing test of the sixth follows the messages' own default branch
- [x] ~~`zurumode`~~ — the developer debug mode (`zurumode.c`), not a player feature; the player-facing anti-cheat is the clock check below and the codes' checksum (`SecretCode.tampered`)
- [~] RTC read, clock-was-changed detection (`lb_rtc.c`, `aNPS2_game_start_wait`) — the save stamps the wall clock and loading moves the game clock on by the real time away (`Clock.resume_after`, renewals catch up); a clock set behind the last save sets `cheated_flag` (GCN's only penalty: no birthday surprise, returning card visitors sent home). The time-set prompt at player select isn't built; the game follows the system clock
- [x] Continue: the game starts with you walking out of your own house (`mSDI_StartInitFrom` → `SCENE_FG`); a save made indoors reopens in that room

## 2. Time, calendar, seasons

- [~] Real-time clock drives the whole simulation (`m_time`, `lb_rtc`) — `clock.gd`
- [~] Day / night with 8 lighting windows, per-term colour tables (`m_kankyo` `klight_chg_tim`) — `Clock.outdoor_light()`
- [~] Daily renewal at **06:00** (weeds spread, stock rotates, plants grow, villager moves resolve) — `field_renewed`
- [~] 18 calendar terms, years 2001–2030 (`lb_rtc`)
- [x] The calendar screen (`m_calendar_ovl`, `m_calendar`): month pages eleven months either side, each day boxed by type (Sunday, holiday, today), footprints on the days played and red ones where Tortimer was met in the last twelve months, the day's holidays named on the plate with a badge for those taken part in; picking a day opens the diary on that month — `CalendarOverlay`, `CalendarBook`
- [x] Seasons: snow cover Dec–Feb, cherry-blossom trees early April, coloured foliage in autumn, bare trees in winter — `VisualSeasons`, `Acre.apply_season`
- [x] Season affects grass colour / acre visuals, tree models (no river ice; snow ground) — `Clock.season`, seasonal textures from the pipeline's `seasons` kind
- [~] Weekday tracking; shop closed days; K.K. on Saturday night — K.K. on Saturday night and Joan on Sunday morning come through the event manager (§30); Nook closes for renovations
- [x] Played days and long absences: the calendar marks every day played over the last twelve months (`CalendarBook`); villagers greet a player they haven't spoken to in two weeks or two months with the "long time" lines (`aQMgr_get_meet_time`, `DialogueGreeting.meet_type`)
- [x] The player's birthday: a villager asks for it (the cake date picker, `m_birthday_ovl`) and uses it for star-sign lines; on the day, when continuing from the house, the villager who likes you most waits outside with a wrapped Famicom (`ac_present_demo`, `ac_present_npc`); every other villager who remembers you mails a card with a present once the date has passed (`mNpc_SendEventBirthdayCard2`) — `BirthdayOverlay`, `PresentVisit`. In the rain the visitor comes under their umbrella (`aPST_make_umbrella`). GameCube villagers have no birthdays of their own (a later-games feature)

## 3. Weather & environment

- [~] Rain / snow / clear by term probability tables (`m_kankyo_weather.c_inc`) — `weather.gd`
- [x] Rain intensity: drizzle vs. downpour; snow: flurry vs. heavy — `Weather.Intensity` from `mEnv_RandomWeather`, stepped levels in `WeatherFx` (`aWeather_RenewWeatherLevel`)
- [~] Weather particles + puddles / wet sand shader — `WeatherFx`, `beach_wet.gdshader`
- [x] Snow flakes and cherry petals drawn with the disc's `ef_yuki01` / `ef_hanabira01` cards, with the decomp's spawn box, fall speed, wobble, wind drift, floor reset and petal tumble (`ac_weather_snow`, `ac_weather_sakura`) — `WeatherFx`, `weather_sprites.py`
- [x] Falling leaves: not ambient on the GameCube; `mEnv_WEATHER_LEAVES` is only used by the K.K. show (no work needed)
- [x] Rainbow after rain: a clear/sakura day after rain/snow reserves it; it fades in 9:00–15:00 in summer and fades out slowly, drawn at the waterfall as `obj_fallS_rainbowT_model` billboarded about the fall with its two-texture combiner (`mEnv_PreRainNowFine_Init`, `mEnv_rainbow_power_calc`, `ac_fallS`) — `Rainbow`, `waterfall.gd`, `fall_rainbow.gdshader`; `rainbow` console command
- [x] Fog: distance fog follows the per-time `kcolor` tables (`mEnv_SetFog`) — `Clock.outdoor_light()`; the GameCube has no separate foggy-morning weather
- [~] Rain: the field plays the rain BGM (`BgmCatalog`), the coelacanth joins the sea list while it rains (`FishSpawnScheduler`), rain-only bugs (snail) come out. The indoor rain arrangement is chosen inside the sound driver (`sAdo_Tenki`), which the decomp doesn't cover
- [~] Lightning flashes in storms — `WeatherFx._tick_lightning` (approximate). No aurora on the GameCube
- [x] Shooting stars (`eEC_EFFECT_SHOOTING_SET`): only at the Meteor Shower, as streaks reflected on the pond while the player is there, quickening towards 19:30, each led by a sparkle (`ef_shooting`, `ef_shooting_kira`) — `MeteorShower`
- [x] Harvest Moon reflection on the pond: glides east to west 18:00–21:00, sways and ripples, with its disc/ripple combiner (`ef_night13_moon`, `ef_moon01_01_modelT`) — `PondMoon`, `pond_moon.gdshader`
- [~] Wind: balloons drift with it, the house's fish weathervane points into it and its propeller spins with its power (`aMHS_actor_draw_before`) — `Wind`, `HouseWeathervane`. The GameCube grass does not sway; `ac_windmill` / `ac_koinobori` only loop their animation; `ac_flag` (speed from wind power) is not placed yet

## 4. Town generation & geography

- [~] Procedural town: 5×6 acre grid, cliffs/terraces (3 elevations), river, waterfalls, ponds, sea + beach (`m_random_field`, `m_field_make`) — `town_field_generator.gd`
- [ ] Fixed known-seed towns (A–D style) selectable — `REFERENCE` world mode reserved
- [~] River mouth, river forks, round pond, waterfall placement rules — `TownFieldGenerator` picks the disc's acre templates by block kind (river, bridge, pond, waterfall, mouth); `WaterBodies` splits sea from river
- [x] Beach along the south edge with the sea and its horizon (beach / ocean acres from the disc, wave units, surf sound, shells) — the GameCube has no tide
- [x] ~~Acre-edge scroll~~ — the GameCube camera follows continuously across acres (`AcreCamera`)
- [x] Town map from the held map item (blue) or the sight-map boards (yellow), drawn like `mMP_set_dl` from the disc's `kan_win` / `kan_tizu` art: acre tiles, the selected acre's letter and number, the label frame sized to its labels, building names or residents (the player plus "free" plots; villagers by name with their house marks tinted by ground height), you-are-here mark, the easing, pulsing cursor (`m_map_ovl`) — `map_overlay.gd`, layers from `menu_ui.py` (`ui/map_screen/`); `map` console command
- [x] Bridge(s) across the river (`ac_bridge_a`) — the river's bridge acre comes from the generator. Once fifteen villagers live in town, Tortimer stands by the river Monday–Saturday (not on Gulliver's day), an acre further upstream each day among those with a bridge spot (`RSV_BRIDGE0/1`); "Here is good!" orders the bridge there and it stands from 6:00 the next day: `obj_s/w_bridgeA` with its deck raised over the water (`aBridgeA_set_BgOffset`) — `SecondBridge`, `TortimerBridgeTalk`. The river acres are ordered north to south rather than traced (`river_stream`), and the deck does not sway underfoot
- [x] Building slots: player houses, Nook's, Able Sisters, Museum, Post Office, Police Station, Wishing Well, Train Station, Dump, Lighthouse — block kinds placed by `TownFieldGenerator` (no Town Hall on the GameCube)
- [x] Villager house plots (up to 15) with reserved lots (`ac_reserve`) — `TownResidents` moves villagers onto free SIGN plots
- [x] The station and train tracks along the top row (`ac_station`, `ac_train_door`) — `TrainControl`, `TrainCars`, `VisualTrain`
- [x] Cliffs block movement; only ramps / slopes connect elevations — `FieldCollision`
- [~] "Perfect town" / environment assessment: trees, weeds, litter, flowers → rating per acre and town rank, daily perfect streak; the wishing well names the worst acre and, after 15 perfect days, its spirit hands over the golden axe (`m_field_assessment`, `ac_shrine`, `ac_npc_hem`) — `TownAssessment`, `WishingWellTalk`, `WellSpirit`. The rank sets bug / fish rarity and the gap between special visitors. Missing: special music (GCN has no Jacob's ladder)

## 5. Player character

- [~] Body model, head model, face texture set (from Rover Q&A), skin/tan state (`m_player`, `m_player_draw`) — `scenes/actors/player.tscn`
- [x] Suntan: fifteen minutes in the midday sun (10:00–16:59, Jul 16 – Sep 15, clear sky, no umbrella) earns a rank up to 8, shown on the next scene change or acre crossing by swapping the face palette (face and skin); it holds two days, then fades a rank a day (`Player_actor_Check_player_sunburn_*`, `mPlib_Get_UseFacePalletRom_p`) — `Sunburn`, `PlayerFace`. The island's five-minute rate waits on the island
- [x] ~~Hair style / colour~~ — the GCN player has no separate hair; the face set comes from Rover's questions (see the line above)
- [~] Clothing: the equipped shirt shows on the model (`VisualCloth`), umbrella held in rain (see Umbrella). Missing: hats and accessories (not in the GCN player either — the cap is part of the head model)
- [x] Change clothes anywhere from pockets — "Wear" swaps inside the menu (`Game.wear_cloth_from_slot`). `m_player_main_change_cloth` / `ef_kigae` is the shop try-on and the Halloween prank, not the pockets
- [x] Pockets = **15 item slots** + separate wallet (`m_private` `mPr_POCKETS_SLOT_COUNT`) — `inventory.gd` (duplicate of the line below, kept in sync)
- [~] Carrying a held item in hand while walking (`ToolCarry`, part tables per tool). The GCN player never carries furniture: it is pushed and pulled (`FurnitureGrip`)
- [x] Trip / stumble when running into things or on ants (`m_player_main_tumble`, `stung`) — `player.gd` `TUMBLE` gaits + `_tumble_events`
- [x] Fall in a pitfall; struggle out (`m_player_main_fall_pitfall`, `struggle_pitfall`, `climbup_pitfall`) — `Player.run_pitfall`; seeds are buried with the pockets' "Bury" (shovel + hole, `mTG_TYPE_FIELD_DEFAULT_BURY`) into `BuriedUse` `KIND_PITFALL`; villagers fall in too and climb out when talked to (`aNPC_act_pitfall` / `revive`)
- [x] Get stung by bees → swollen face; villagers react (`m_player_main_stung_bee`, `notice_bee`, `mNpc_SetTalkBee`) — `Player.run_stung_bee`, `PlayerFace`, `Game.bee_*`, `DialogueGreeting` `BEE_STUNG` / `BEE_CHASE`. The swell lasts until the game is reset (common data); GCN has no medicine
- [x] Mosquito bites in summer (`ac_ins_ka`, `stung_mosquito`, `notice_mosquito`) — `BugKa` bite → `BugField.take_bite` → `Player.run_stung_mosquito` (`MSG_12387`)
- [x] ~~Tired / sleepy animations late at night~~ — GCN `m_player_main_tired` only follows `wash_car`; there is no late-night tiredness
- [x] Push / pull furniture and snowballs (`m_player_main_push`, `push_snowball`) — furniture (`FurnitureGrip`); snowballs (`ply_1_push_yuki1`, the ball leads and the player keeps behind it, `Player.begin_snowball_push`). Missing: carrying a pushed ball across an acre border (`wade_snowball`)
- [x] Sit on benches/chairs (`m_player_main_sitdown`) — `FurnitureSeat`
- [x] Lie in bed / roll in bed / stand up from bed (`m_player_main_lie_bed`, `roll_bed`, `aMR_GetBedAction`) — sideways stick rolls across a double bed or aligned beds, or gets out on that side (`FurnitureSeat.bed_action`). GCN beds do not save
- [x] Wade across acre borders (`m_player_main_wade`) — `AcreWade`, `Player._begin_wade`
- [x] Radio-exercise / morning aerobics participation (`m_player_main_radio_exercise`) — `RadioExercise` C-stick patterns (right stick or I/J/K/L) → `Player.run_radio_exercise`, on the shrine acre during aerobics or by the aerobics radio
- [x] ~~Emotions menu~~ — GCN has no player emotion menu (later games); `ef_warau` / `ef_naku` / `ef_pun` are villager manpu, done with dialogue

## 6. Camera

- [~] 3/4 fixed-angle follow camera, ~20° FOV, ~45°, focus distance 620 (`m_camera2`) — `follow_camera` / `FollowCamera`
- [x] ~~Camera rotates 90° per acre~~ — the GCN camera keeps one heading; acre crossings only re-aim the follow (`AcreCamera`)
- [~] Special cameras: door enter/exit, talking, sitting, fishing show-off, demos — `door_camera.gd`, `talk_camera.gd`
- [x] ~~C-stick / look controls~~ — `m_camera2` reads no input; there is no look or pause zoom
- [~] Cutscene direction for events (`m_demo.c`) — each event drives its own camera and actors (door, talk, intro train, K.K., Resetti, present visit); there is no shared demo director

## 7. Movement & locomotion

- [~] Analog walk (~4.875 u/frame) and run (~7.5 u/frame); B / L / R to dash (`m_player_main_walk`, `run`, `dash`) — `player_locomotion.gd`
- [~] Turn-in-place, dash turn, skid (`turn_dash`) — partial
- [x] Trample flowers when dashing through them; walking is safe — `PlantGrowth.trample_flower`, `StepFx` petal burst (`eHanatiri_ct`)
- [~] Grass wears into dirt paths where you walk repeatedly; regrows slowly (`ac_field_draw` wear) — _(check)_
- [~] Per-foot footprints on sand/snow, slope-fit, ~160-frame fade (`ef_footprint`) — `footprint_marks.gd`
- [x] ~~Slip on ice / banana peels~~ — no ice or peels in GCN; `slip_net` is the net's skid (see Net)
- [x] Bump / knock-back off buildings, signs, rocks; slide along cliff & water edges — walls and banks slide the player along (`FieldCollision.revise_xz`, the `mCoBG` wall revise); the GameCube has no knock-back (its only fall is the bad-luck trip while dashing, `TUMBLE`)
- [x] ~~Fall off a cliff edge~~ — GCN cliffs are walls; `m_player_main_fall` is the pitfall drop (done)

## 8. Interaction system (Field A button)

- [~] Context verb chosen from nearby actor + equipment: pick up, talk, shake, sit, read, open door, dig, etc. (`m_player` Field A) — `interaction.gd`, `interaction_query.gd`
- [x] Pick up dropped items / fruit / shells off the ground (`m_player_main_pickup`) — `item_pickup.gd`. What is dropped, shaken from trees or brought down off a balloon stays on its unit and is saved (`FieldItems`)
- [~] Talk to villagers & special NPCs (`m_player_main_talk`) — partial
- [~] Shake trees (fruit, furniture, bells, bees, wasp nest) (`m_player_main_shake_tree`) — `tree_use.gd`
- [~] Push signs to read; read bulletin board; read gravestones/signposts (`ac_sign`) — community board (`MESSAGE_BOARD0`, `obj_*_notice`) is placed from the FG templates and hosts the first-job "post a notice" chore and opens the board's posts (`NoticeBoardOverlay`, §26). Sight-map boards (`MAP_BOARD0`) open the town map without needing the item; tune boards (`MUSIC_BOARD0`) open the town tune editor; fences (`FENCE0` / `WOOD_FENCE`) are solid props; the station statue (`DOUZOU`) is placed and shows once a house reaches the statue (§26)
- [~] Knock on villager doors (`m_player_main_knock_door`)
- [~] Enter/exit buildings: step-in animation, door swing, screen wipe (`m_player_main_door`) — `structure_door.gd`, `scene_transition.gd`
- [x] Hand an item to a villager / receive an item (give / receive animations) (`m_player_main_give`, `recieve`, `ac_handOverItem`) — `HandOver`, `HandOverItem`
- [x] ~~Refuse / decline prompt~~ — `m_player_main_refuse` is only a brake-to-standstill state (the paper-airplane catch, a room message); the port stops the player there
- [x] Pick fruit vs. shake whole tree — GCN only shakes; fruit falls and is picked up off the ground (`TreeUse`)
- [x] Pluck weeds (`m_player_main_remove_grass`) — A on a weed: `ZASSOU1`, out on frame 17 with `zassou_nuku`, flies off over the shoulder (`weed.tscn`)
- [~] Pick / dig up flowers; pick mushrooms (`m_mushroom`) — mushrooms are ground items (`MushroomUse`)
- [x] Talk to gyroids — house gyroids (`HaniwaTalk`); GCN has no pets or reflections

## 9. Tools

- [~] **Net** — hold A to ready, creep, skid out of a dash, release to swing; tick-exact catch sphere from keyframe 6; wall / ground / villager strike cuts the swing (`AMI_HIT`); empty swing → `STOP_NET` (`m_player_item_net`, `m_player_main_{ready,ready_walk,slip,swing,stop}_net`) — `net_swing.gd`, `netting.gd`. The bee swarm can be netted (see §bees). Missing: swing effects. The golden net reaches further (21 GX)
- [~] **Fishing rod** — see §13 (`m_player_item_rod`) — `fishing.gd` (substantial)
- [x] **Shovel** — dig and fill holes, bury items and pitfall seeds, dig up fossils, gyroids and shine spots, hit the money rock, plant saplings, bounce off stone (`hole_use.gd`, `buried_use.gd`, `MoneyRock`, `ToolUse`). The golden shovel turns up 100 Bells one new hole in ten
- [x] **Axe** — chop trees (multi-hit → stump), the golden axe (`tree_use.gd`). It bounces off rocks and banks (`REFLECT_AXE`, `AXE_HANE1`) and wears out: 9 damage a stage, 1 a tree, 3 a bounce, seven chipped stages (`ITM_AXE_USE_1-7`, heads `tol_axe_1_b` / `_c`, `TOOL_BROKEN1-3`), then it breaks (`BROKEN_AXE`, report 0x3067) — `AxeWear`; its head and handle fly off over the shoulder, bounce and fade (`ef_break_axe`, `BrokenAxePiece`)
- [~] **Fishing rod / net / axe / shovel** durability & the **golden** variants — the golden axe from the wishing well; Tortimer waits outside the house with the golden rod once every fish is caught and the golden net once every insect is (`aPRD_setup_present`, `PresentVisit`). Once Tortimer has gone, or the well spirit has given the axe, the player holds the golden tool up (`YATTA1`) and says so in a green report (`demo_get_golden_item`, `Player.get_golden_item`). Each plays its jingle (all insects, all fish, the chores tune for the axe). The golden shovel grows on the golden tree from a shovel buried in the shine spot's hole (`GOLD_TREE_SHOVEL`); its first pickup gets the same demo
- [x] ~~Slingshot~~ — _not in the GameCube game_ (balloons snag in trees instead; see §34 balloons)
- [x] ~~Watering can~~ — _not in GCN_ (flowers don't need water on the GameCube)
- [~] **Umbrella** — held in rain/snow, twirl, many designs (`m_player_item_umbrella`, `rotate_umbrella`) — `HeldUmbrella` + 32 `ToolData` umbrellas (`data/items/umbrellas/`, ROM names/prices): opens out of the hand (`UMB_OPEN1`, handle/canopy scale tables), right arm holds `ply_1_umbrella1` over walk/idle (`PART_TABLE_NET`), A twirls (`UMB_ROT1` + SE 0x432), folds away through doors / on unequip (`UMB_CLOSE1`), switches the rain loop to the under-umbrella one; Nook stocks one a day on the umbrella stand; title demo 2 carries the gelato umbrella. Missing: design umbrellas (`ITM_MY_ORG_UMBRELLA0-7`), the `KASAMIZU` twirl spray (no effect system)
- [x] **Fans, pinwheels, balloons** — held in hand like tools (`m_player_item_fan` / `_windmill` / `_balloon`): fans on `UTIWA_WAIT1`, pinwheels and balloons on `KAZA1`, each on its `tol_*` model; the pinwheel spins with your movement and the wind (`HeldPinwheel`); the seven later pinwheels and balloons share the first one's clip. Balloons sway on the string: trailing the hand, bobbing at a walk and turning slowly back and forth (`m_player_item_balloon`, `HeldBalloon`). The party popper / timer / handbill aren't GameCube items; the pitfall seed is buried (§ Shovel)
- [~] **Bug / fish held up** show-off pose + species report (`m_player_main_notice_net`, `notice_rod`) — net: pull (`GET_M1`, report at 50 ticks, turn past keyframe 17), notice (pockets + catch record, collection-complete 0xA4E/0xA4F + `YATTA2`, full-pockets 0xA4D), put-away (`PUTAWAY_M1`, shrink to keyframe 17). The catch jingle (0x28) runs under the report, the collection-complete one (0x4B) under the follow-up. Pockets full: Swap opens the exchange pockets, the pocket picked goes on the ground. The rod's last missing fish gets "I caught every kind of fish!", `YATTA2` and the 0x4C jingle. Missing: the release clip
- [x] Held tool renders on the right hand with its own animation clips (`Player_actor_Item_draw`, `mPlayer_JOINT_HAND`) — `held_tool.gd`, `ToolCarry`
- [~] Tool ready ↔ put-away transitions and SE — net, rod and umbrella have theirs; shovel and axe swap straight
- [x] ~~Wetsuit / diving~~ — _not in GCN_

## 10. Inventory, items, catalog

- [x] 15 pocket slots; grab/drop (click-to-place and single-button `mTG_move_catch` quick
  grab), multi-select mark + Drop All (`mTG_mark_proc`/`TYPE_TAG_PUT_ALL`), drop to ground
  (`m_inventory_ovl`) — `inventory_overlay.tscn`, `inventory_chrome.gd`, `inventory.gd`.
  **Not** sort or stack-splitting — the original has neither (GC pockets are 15
  independent one-item slots with no count field; this port's stacking is its own
  deliberate divergence, see `docs/decomp_notes/inventory.md`), so those were dropped
  from scope rather than built.
- [x] Pockets ↔ Fish/Insect encyclopedia pages (`mIV_PAGE_*`, 8×5 grid, right-edge folder tabs); caught-once registry `SpeciesLog` — `encyclopedia_catalog.gd`, `species_log.gd`; page-flip sine swing (`page_move_timer`) matches decomp's 40-frame transition
- [x] Portrait player animations: walk-in-place default + `CHANGE`/`EAT`/`CATCH` one-shots (`mIV_ANIM_*`) — `inventory_overlay.gd`
- [x] Wallet (bells) separate; 30,000-bell bag stacks — withdraw (`mTG_select_tag_decide_money`
  affordability-gated denomination picker) and deposit (drop a bag on the wallet slot, or the
  pre-existing "Use" verb) both work. The ABD terminal at the post office is `BankOverlay` (§11).
- [x] "Throw away" confirmation — mail only (Yes/No, `mTG_dump_mail`), matching decomp: ordinary
  pocket items never had an in-menu discard, only mail and a couple of special items did.
  Dropped "item info popup" from this line — decomp's pockets screen has no such panel either
  (`inventory_overlay.gd` already hides the invented Detail block for the same reason).
- [x] "Read a letter" opens the real board window (`m_board_ovl.c`, `mSM_BD_OPEN_READ`), not a
  text toast — the letter's actual stationery art (all 64 `lat_letterNN` display lists with
  their ruled lines, baked by `menu_ui.py`) with header/body/footer text in the sender's ink
  colour (`letter_color[]`) at the board's own offsets, dropping in from the top —
  `letter_reader_overlay.tscn`, `LetterBoard`, `LetterChrome`. Read-only (decomp confirms
  `mBD_roll_control`/pagination/caret are write-mode-only, dead code for reading).
- [~] **Catalog** of every item you've ever owned/received; order from catalog at Nook's (`m_catalog_ovl`) — `CatalogBook`: furniture / clothing / wallpaper / carpet / stationery / umbrellas register as they reach the pockets (`mSP_CollectCheck`); Nook takes up to 5 paid orders that arrive enclosed in a letter the next morning (`mPO_delivery_mail_with_order_ftr`). The browser is `CatalogOverlay` (§21). Missing: non-orderable flags beyond "rare"
- [~] Item data tables: tools, fruit, fossils, umbrellas, tickets, turnips, stationery and money as `.tres`; furniture, clothing, wallpaper and carpet from the disc (`FtrCatalog`, `ItemCatalog`). Shells as `.tres`; paintings and Redd's forgeries are furniture made by `ReddBook.ensure_art_items`
- [x] Fruit: native fruit per town + foreign fruit (apple, orange, peach, pear, cherry); coconuts on beach palms — `Game.town_fruit`, `TreeUse`
- [x] ~~Perfect fruit~~ — _not in GCN_
- [x] Sea shells wash up on the beach: twenty owed when a session starts, one more every tenth minute, on free wave units of the beach acres away from the player, up to four an acre, a conch or white scallop one time in four (`mFI_SetShell`); Nook pays a quarter of `mSP_ItemNo2ItemPrice` (160/80/600/120/240/1800/1400/1000) — `ShellUse`
- [x] The town's ball (`ac_ball`): one of three balls lies in town; run into it to kick it (walking rolls it, running lofts it), it rolls to a stop, bounces, glances off walls, settles in holes, is lost in water and a new one turns up elsewhere next load; a shovel lifts it out of a hole and an axe knocks it aside — `FieldBall`, `BallUse`
- [x] Furniture "in hand" vs. "as item": furniture is a pocket item until placed; wallpaper / carpet are pocket items used on a room — `FurnitureUse`, `VisualRoomPaint`
- [~] Wrapping paper — wrap/unwrap a droppable item as a present (`Inventory.wrap_slot`, the
  "Wrap" tag) works; attaching a wrapped gift to outgoing mail depends on the mail-writer UI
  and isn't wired up yet (`ac_present_demo`)
- [~] Lost items / forgotten items handling — `PoliceBook.keep_item` / `keep_all_items` (`mPB_keep_item` / `mPB_keep_all_item_in_block`) and the 06:00 top-up exist; the field callers that turn items in (structures built over them, event clean-ups, snowmen, house moves) are not wired yet

## 11. Economy

- [x] Bells as currency; wallet cap 99,999; 30,000-bell bags — `Inventory`
- [x] **Post Office bank (ABD)**: the clerk's deposit line opens the terminal from the disc's `tyo_win` art — Cash (wallet plus money bags), a six-digit amount picked digit by digit, Balance to 999,999,999, Deposit / Withdrawal lit by direction; settling spends bags first and pays cash over the wallet cap as 30,000-bell bags; she then reads out the balance (`m_bank_ovl`, `aPG_deposit_*`) — `BankOverlay`, `BankTerminal`; `abd` console command. No interest on the GameCube: the post office mails a gift at 1M / 10M / 100M / 999,999,999 Bells, one per game start (`mMl_send_postoffice_mail`)
- [x] **Tom Nook home loan**: each size has its loan, paid any amount at the counter; the next upgrade is offered once it is paid off; the last ends in the statue (`m_repay_ovl`) — `HouseUpgrade`, `NookHouseTalk`, `Statue`
- [x] House sizes: small → medium → large → upper floor, basement as a separate order (`m_home`) — `HouseUpgrade` (duplicate of §18)
- [x] **HRA — Happy Room Academy**: welcome letter, then at game start a scored letter the day after the layout changes (or a 2-in-10 tip otherwise): points by origin, necessities, base / theme / set series with matching wallpaper and carpet, lucky pieces, facing the wall, theme obstacles; rewards at 70,000 / 100,000 (house and manor models); wing paper (`m_mark_room`, `m_mark_room_ovl`) — `HappyRoomAcademy`, tables from `hra.py`. Missing: the clutter rule's loose items (rooms don't hold loose items yet). Feng shui is its own score (see Feng shui)
- [x] Feng shui: each piece's colour from the disc (`mMkRm_ftr_info`) pays on its side — yellow west (money), red east (goods), orange north and green south (both), lucky anywhere — with the face-to-the-wall penalty, over every room of the house when you head out (`m_huusui_room_ovl`) — `FengShui`. Money power lengthens the money rock; goods power raises Nook's rare / uncommon odds
- [~] Selling: Nook buys almost anything at set prices; fish/bugs/fossils/paintings prices; foreign fruit premium — `ShopBook.sell_result`: catalog price / 4, foreign fruit 2000 / 4 (`Game.town_fruit`), worthless items taken for free, quest items refused, 30,000-bell bags when the wallet overflows (refused with no room), half the payout counts toward Nook's sales. Shells, paintings (980) and forgeries are priced. Missing: the unassessed fossil's price is a guess (100)
- [x] Turnip market (**Stalk Market**): Sow Joan sells turnips Sunday AM; Nook buys at fluctuating daily price; turnips rot after a week; spoiled-turnip uses (`m_kabu_manager`, `ac_ev_kabuPeddler`, `ac_yomise`) — `KabuMarket` ports `Kabu_manager` (Sunday price 70–129, spike ×8 / random / falling trends with the decomp's transition odds; one price per day, not AM/PM, in GCN); Nook quotes it under "Other things" and buys 10/50/100 bundles (never on Sunday), spoiled turnips as junk. Joan sells them on Sunday mornings (§30). Turnips spoil once a Sunday morning comes round, on the ground, in every resident's pockets, set down in their houses and in the gyroids' storage, and spoiled ones on the ground are cleared at the next renewal (`mAGrw_SpoilKabu`, `mAGrw_ClearSpoiledKabu`, `mAGrw_SpoilAllPossession`, `FieldItems.renew`).
- [x] Lottery / raffle at Nook's on the last day of the month (`mEv_EVENT_LOTTERY`) — see §21
- [x] Nook's point card / "Nook Points" — _not in GCN_ (`m_shop.c` has only raffle tickets); skip
- [x] ~~Flea market~~ — _not in GCN_

## 12. Fishing (§ of tools, detailed)

- [~] Cast: fixed ~100 GX ahead, only onto water (5-point probe) (`ready_rod`, `request_proc_index_fromReady_rod`) — `fishing.gd`, `tool_use.gd`
- [~] Bobber parabola ~50 frames, ends on water contact; lies flat then stands up (`aUKI_set_proc_cast`, `aUKI_rotate_calc`) — `bobber.gd`
- [~] Fish-shadow AI: wait / swim / approach / touch / nibble / bite / comeback / escape (`ac_gyo_test` `aGTT_*`) — `fish_shadow.gd`
- [~] Shadow size classes, per-species speed / search radius / bite time (`aGTT_speed`, `gyoei_type[]`) — `fish_size.gd`
- [~] At most 2 live shadows, distance-culled; scared fish leaves a fading puff (`aGYO_MAX_GYOEI`, `ac_gyo_kage`) — `fish_school.gd`
- [~] Nibble dip → bite shudder → hook timing window (`ac_uki` status chain) — `fishing.gd`
- [~] Reel-in beats: pull / swing up / reel empty, per-beat player + rod clips (`vib_rod`, `fly_rod`, `collect_rod`) — `fishing.gd` `reel_beats`
- [~] Show-off pose, turn square to camera, catch report at frame 42 (`m_player_main_notice_rod`) — `held_catch.gd`, `held_fish.gd`
- [~] Species report dialogue; shorter report if already donated; "pockets full → toss back / swap" (`Get_sakana_msg_num`, `0x1348`) — partial
- [x] **40 fish** plus the junk catches (empty can, boot, old tire), with month × time × water availability and rarity from the disc tables (`ac_set_ovl_gyoei`, `ac_gyoei_type.c_inc`) — `data/creatures/*.tres`, `fish_spawn_table.json`, `FishSpawnScheduler`
- [x] Half-month term split + transition ramp for spawn weights (`gyoei_term`) — `FishSpawnScheduler.term_blend`
- [x] Water types: river, pond, sea (`WaterBodies`); waterfall- and pool-only fish bite only in acres with a waterfall or a pool, river-mouth fish in river acres (`aSOG_gyoei_place_check`, US rules). The island's water waits on the island
- [x] Coelacanth only while raining/snowing, in the sea, outside the day slot (`aSOG_add_kaseki_range_data`) — `FishSpawnScheduler`
- [x] Non-fish catches: boot, tire, empty can — `FishCatalog` by shadow size
- [x] Trash items (boot / can / tire) as junk, sellable to Nook for nothing
- [x] Fishing tourney (June & November Sundays): Chip measures your bass and hands over a prize for each new record (`ac_ev_angler`, `AnglerTalk`); the day's record is kept (`m_fishrecord`), villagers keep fishing until 17:50, and a player still on top gets Chip's letter with lottery or event furniture they don't own — `FishRecord`
- [x] Fish records (`m_fishrecord`): up to five tourney days kept, the winner posted on the community board after 18:00 — `FishRecord`

## 13. Bug catching

- [~] Net swing hitbox, timing, whiff, bug flees (`ac_insect`, `ac_npc_act_chase_insect`) — `aINS_set_catch_range` (24 / 8 GX, facing gate from insect → player angle) + one-frame `Check_StopNet` panic — `net_swing.gd`, `bug_field.gd`, `bug_actor.gd`. Villagers chase bugs and fish shadows (`aNPC_ACT_CHASE_INSECT`, `VillagerOutdoor`)
- [~] Bug spawn tables by month / time / habitat (tree trunk, flying, on flowers, on the ground, in the ground (mole cricket), by water, tree stumps, rotten food, street lamps at night) (`ac_set_ovl_insect`, `ac_insect_data`) — `bug_catalog.gd`, `bug_habitats.gd`
- [x] **40 individual insect types** (`aINS_INSECT_TYPE_NUM`): butterflies, cicadas, bees/wasps, dragonflies, locusts, crickets, beetles, ladybugs, mantis, tarantula, firefly, cockroach, snail, mole cricket, pond skater, bagworm, pill bug, spider, ant, and mosquito (`ac_insect_h.h`, `ac_insect_data.c_inc`) — all 40 in `data/creatures`, moved by 16 behaviour families (`scripts/systems/bugs/`)
- [x] Bee swarm from a shaken tree chases you and stings → swollen face; going indoors loses them (`ac_bee`) — `BeeSwarm`. Two seconds into the chase the net takes them: any swing under way within 40 GX, else the net's reach within 24 GX; netted, they're a bee to show off and pocket (`aBEE_caught`)
- [x] Wasp nest = the bee swarm from a shaken tree (see above); getting stung — `BeeSwarm`, `Player.run_stung_bee`
- [x] ~~Tarantula~~ — not in the GameCube game (the spider hangs from trees, `bug_mino`)
- [x] Firefly glow at night near water in summer — `bug_hotaru.gd`
- [x] ~~Cicada shells~~ — not in the GameCube game; cicadas sit on trunks and fly off when approached (`bug_semi.gd`)
- [~] Bug sounds are time-gated and positional (cicada cries, crickets) through `Ongen`. Missing: the full insect SE set
- [~] Ants come out on dropped candy / trash (spawn area 8, `BugSpawnScheduler`). Missing: the separate `ac_ant` actor
- [x] Cockroaches in a house left closed too long; stomp them (`m_cockroach`, `ac_house_goki`) — see §18
- [x] ~~Bug-off~~ — GCN has no bug tourney (fishing only)

## 14. Digging, buried items, rocks

- [~] Dig a hole on empty ground; fill a hole (`DIG_SCOOP`, `FILL_SCOOP`, `HOLE00`–`HOLE24`) — `hole_use.gd`, `scenes/world/hole.tscn`
- [x] Bury an item in a hole; dig it back up (`mTG_TYPE_FIELD_DEFAULT_BURY`, `bIT_common_hole_throw`) — pockets "Bury" → `BuriedUse.bury` (`KIND_ITEM` shows the crack)
- [x] Daily dig spots: fossils (crack mark, up to 5), a shine spot of bells, and three gyroids after rain (`mMsm_DepositFossil`, `mAGrw_SetDigItem`, `mAGrw_SetHaniwa`) — `BuriedUse`
- [x] Money spot: the daily shine spot digs up a bag of bells (`mAGrw_SetDigItem`) — `BuriedUse`; bare trees can hold bells when shaken (`TreeUse`). A bag buried back in that hole grows a money tree half the time (more with money power, always with Money Luck), else a plain sapling; grown, it drops three bags of that size once. A spare shovel grows the golden tree (`bIT_common_bury_after`, `PlantGrowth.plant_special`)
- [x] **Rock**: the money rock — a random rock, re-picked once spent, pays a bag per shovel hit inside a ~6.4 s window (386 ticks) (100 ×3, 1,000 ×3, then 10,000; money-luck fortune one tier up), only onto a free unit beside it (`mAGrw_SetMoneyStone`, `bIT_actor_ten_coin_entryR`) — `MoneyRock`, `rock.gd` (`ply_1_not_dig1` bounce)
- [~] **Gyroids**: the 127 gyroids, each its own model. A day that turns fine after rain or snow orders three different ones for the next growth, each under a crack mark in its own acre (`mEnv_PreRainNowFine_Init`, `mAGrw_SetHaniwa`) — `BuriedUse.bury_gyroids`, `Game.haniwa_scheduled`. In a room, a switched-on gyroid poses its own clip by the rhythm counter, the six fast ones twice a step and the plinkoids over two (`ac_hnw_common.c`) — `GyroidRhythm`, `gyroid_dance.tscn`. Missing: their voices (the rhythm sequence 246 needs the engine's rhythm callbacks in the offline renderer) and following the room music's tempo (fixed at the rhythm group's 120 BPM)
- [x] **Pitfall**: bury a pitfall seed in a hole → invisible trap; player/villager falls in (`BURIED_PITFALL_HOLE`, `bIT_actor_pit_*`, `m_player_main_*_pitfall`) — the pit opens under them and closes after
- [x] **Fossils**: 25 dug up unidentified → mailed to the museum or shown to Blathers → identified, donated or sold; skeleton groups — `FossilCatalog`, `FarwayBook`, `MuseumDialogue`
- [x] ~~Fake rocks~~ — rocks are fixed obstacles on the GameCube (one is the money rock)
- [x] Shovel bounces off ground it can't dig (`REFLECT_SCOOP`, `ply_1_not_dig1`): stone clangs, wood thuds, a bush rustles; water is an air swing — `ToolUse.scoop_outcome`. The player steps back (4.8 GX a frame, braking 0.326 a tick, as the axe does off a bank) and two impact stars fly from the strike (`eEC_EFFECT_DIG_SCOOP` → `ef_impact_star`, `ImpactStar`)
- [x] Groundhog Day: no digging. `ac_ghog` is the shrine-acre stand and Resetti the groundhog (see §Events)

## 15. Plants & flora

- [~] Trees: sapling → young → full; needs a clear 3×3-ish space or it won't grow (`m_all_grow`, `mAGrw_RenewalFgItem`) — `plant_growth.gd`
- [~] Daily growth resolves at 06:00 (`planted_renew`) — `Game.plant_states`
- [~] Shake tree: fruit (3), or furniture/bells/bag (non-fruit trees, 1/day), or bees (`shake_content`) — `tree_use.gd`
- [~] Chop tree with axe → multi-hit → falls → stump; stumps can grow mushrooms / be sat on; dig up stump (`bg_item` cut) — `tree_use.gd`
- [x] Fruit trees: apple, orange, peach, pear, cherry, coconut (beach), with a native fruit per town — `TreeUse`, `PlantGrowth`
- [x] Plant fruit → fruit tree; plant a sapling → tree; money and golden trees from the shine hole (see §14) — `PlantGrowth`
- [x] Cedars and palms vs. hardwoods (`mNT_TREE_TYPE_CEDAR` / `PALM`), placed by the acre templates. December 10–25, up to three plain grown hardwoods or cedars an acre wear twinkling lights (`mAGrw_SetXmasTree`, `obj_x_tree5_light` / `obj_x_ceder5_light`, tints stepping every 32 frames) — `PlantGrowth.set_xmas_trees`, `XmasLights`
- [x] Cherry-blossom bloom on hardwoods in early April — `VisualSeasons` (duplicate of §2)
- [x] Tree count affects the environment rating — `TownAssessment` (§4)
- [x] **Flowers**: tulips, pansies, cosmos in three colours each (`FLOWER_NUM` 9) — `data/plants/`
- [x] Flowers from Nook (seed bags), the lost and found and quests. Tortimer's only flowers are Groundhog Day's potted-flower furniture (`0x4DE + RANDOM(9)`, `TortimerHoliday`)
- [x] ~~Flowers wilt without water~~ — GCN flowers need no water; only `KILL_PLANT` units clear them (our watering is an extension)
- [x] ~~Flower breeding / hybrids~~ — not in the GameCube game (hybrids arrive in Wild World)
- [x] Trampled flowers when dashing — see §7
- [x] ~~Dandelions, four-leaf clovers~~ — not in the GameCube game
- [~] Weeds: five per renewal day since the last one on free grass units (`mAGrw_SetGrass`, `mCoBG_PLANT4`), so a long absence brings many; pulled for nothing — `WeedUse`; renewals crossed indoors or while away are banked and sown when the field loads. Rating / complaints with the town assessment
- [x] Pull-all-weeds: weeds are plucked for nothing (`WeedUse`); the Wisp's wish clears them
- [x] Mushrooms (Oct 15–25): up to five set at 8:00–9:15 beside grown trees, away from the player's acre row and column, then one goes every quarter hour; sell for 5,000 (`m_mushroom`, `mEv_EVENT_MUSHROOM_SEASON`) — `MushroomUse`. The GameCube has the one mushroom item, no rare kinds
- [x] ~~Jacob's ladder / lily of the valley~~ — not in the GameCube game (`FLOWER_NUM` 9)
- [~] Lotus / water lilies in ponds (`ac_lotus`) — FG `LOTUS` places `lotus.tscn`: leaf sway on the baked clip, flower drawn May 26 – Aug 25. Pad / flower colours are placeholders (palette is `aLOT_obj_0N_lotus_pal` per term, not baked); no bobber shake. Lotus as an item still missing
- [x] Coconut palms on the beach — acre templates and `TreeUse`
- [x] ~~Other decorative trees~~ — GCN has hardwoods, cedars and palms only

## 16. Villagers (animal residents)

- [~] One NPC actor, behaviour driven by "looks"/personality tables (`m_npc`, `ac_npc`) — `villager.tscn`, `villager_ai.gd`
- [x] Up to **15 villagers** (starts at 6, one move-in per day at most); 236 animals in the GCN roster
- [x] Personalities: Normal, Peppy, Snooty, Cranky, Lazy, Jock (6) — `data/personalities/`
- [x] Species models: the full GCN roster's skeletons and textures from the disc — `VillagerCatalog`, `VillagerTextures`
- [~] Daily schedules per personality: wake, wander acres, visit shops, go to specific acres (shrine / friend's house / own house), sleep (`m_npc_schedule`, `ac_npc_schedule_*`) — `villager_schedule.gd`
- [~] Field roam: pathing between goal acres, walker cap (`m_npc_walk`) — `villager_walk.gd`, `villager_motor.gd`
- [~] Appear indoors when awake at home; asleep = off the map (`ac_npc_think_sleep`) — `villager_home.gd`
- [~] Head/eyes track the player when near (`ac_npc_head`) — `npc_head_look.gd`
- [~] Face: texture-swap eyes & mouth; blink bursts; emotion holds; mouth flap while talking (`ac_npc_anime`, `aNPC_check_kutipaku`) — `npc_face.gd`, `npc_face_anim.gd`
- [~] Feel glyphs (manpu) above head: laugh cards, shock, "!", lightbulb, sweat, anger, sleep-Zzz, love hearts (`ef_warau`, `ef_shock`, `ef_ha`, `ef_hirameki`, `ef_lovelove`, …) — `npc_manpu.gd`, `npc_feel_glyphs`
- [~] Manpu set: `NpcManpu` plays the reaction clips and feel glyphs the messages call for (`aNPC_check_manpu_demoCode`). Missing: some rarer glyphs
- [x] Activities villagers do (`ac_npc_act_*`): clap when you show off a catch, chase bugs / watch fish shadows (`VillagerOutdoor`). The GCN field villager has no fishing / singing / reading acts of its own. greet each other in passing (`aNPC_ACT_GREETING`, `VillagerGreeting`) with the trend / catchphrase / mood reactions. Villagers out walking run after the ball when it lies ahead of them (`aNPC_check_ball`) and kick it on
- [~] Villagers chase bugs and watch fish shadows (`VillagerOutdoor`); fishing / bug contests ask you to catch something (`VillagerQuests`)
- [x] Umbrella open/close in rain (`ac_npc_act_umb_open/close`, `aNPC_ctrl_umbrella`) — their own `npc_def_list` umbrella, one opening at a time, `UMBRELLA1` arm pose. Missing: Able-design umbrellas in hand
- [x] Villager falls in your pitfall; talking to them gets them out (`ac_npc_act_pitfall`, `aNPC_act_revive`, feel `PITFALL` → `MSG_8327`)
- [x] Hitting a villager with the net or a tool → they jump, and get annoyed when it repeats (`aNPC_check_uzai`, `aNPC_ACT_REACT_TOOL`) — `villager.gd`
- [x] **Moving in**: new villager on a free SIGN plot, introduces self on first meeting (`mNpc_Grow`, `MSG_11573`) — `town_residents.gd`. GCN has no moving boxes
- [~] **Moving out**: full town + 10 days → fewest-memories villager leaves with a goodbye letter (`mNpc_ForceRemove`) — `town_residents.gd`. The "thinking of moving" talk (`remove_animal_idx`) is picked but its dialogue isn't wired (only matters for card transfer)
- [x] Move-in / move-out cadence tied to friendship, time played, town population (`mNpc_CheckGrow`, `mNpc_ForceRemove`)
- [~] **Friendship** per resident: s8 0–127 starting at 1, best-friend at 80, moved by "Let's talk!", message orders, letters and quests (`Anmmem_c`, `mNpc_AddFriendship`) — `relationship.gd`, `villager_talk_manager.gd`
- [~] Villager **memory**: last talk, letters, favours, gifts, met days (`Anmmem_c`) — `Relationship`, `VillagerState`
- [~] Catchphrase: you can change a villager's catchphrase (`aQMgr_order_change_gobi`). Nicknames and taught greetings are later games
- [x] ~~Greetings you can teach~~ — later games
- [~] Gift-giving both ways: letters with presents (+3), villager replies with a present half the time, Valentine's letters with gifts (`mNpc_SendMailtoNpc`, `mNpc_Remail`, `mNpc_SendVtdayMail`) — `villager_letters.gd`. Handing gifts in person and villagers wearing gifted shirts still to come
- [x] **Villager quests** — deliveries (clothes / lost items), errand chains (fetch what they lent), contests (fruit, fish, bug, flowers, letter, snowman; ball: kick it into the villager who asked and they call you over, `mQst_NextSoccer`), deadlines, give-up, rewards (`m_quest.c`, `ac_quest_talk_init.c`, `ac_quest_manager.c`) — `villager_quests.gd`, `villager_talk_manager.gd`. Wishing-well disposal of quest items (`aSHR_talk` apologize). A snowman built in the asker's acre counts (`mQst_NextSnowman`). The ball kicked into the asker counts (`mQst_NextSoccer`).
- [~] Trading furniture / clothing with villagers (chat trades: `aQMgr_order_decide_trade` / `_trade`) — `villager_talk_manager.gd`. Goods come from the shop's A / B / C lists; no hand-over animation yet
- [x] Villager asks to buy something from your pockets / sell you something (chat trade topics)
- [x] Villager house interiors from the disc's room tables, themed per villager (`InteriorCatalogNpc`, `VillagerHome`) — on the GameCube only the island villager's room takes gifted furniture (`mNpc_SetIslandFtr`, GBA)
- [x] ~~Sick villagers → medicine~~ — not in the GameCube game (Wild World on)
- [~] Villager reactions to your appearance: bee-stung face, new shirt (`DialogueGreeting`). GCN has no haircuts
- [~] Villager comments on weeds, holidays, weather, time of day, your birthday — the disc's greeting and rumour banks (`DialogueGreeting`, `VillagerTalkManager`)
- [x] ~~Cranky mellows / Snooty warms~~ — GCN personalities only change lines with friendship tiers, which `DialogueGreeting` follows
- [x] Villager games: GCN chat "games" are the quiz / trade / contest topics (`VillagerTalkManager`); no hide and seek
- [x] Villagers sing the town tune in their own voice as a talk starts (`mMld_ActorMakeMelody`, `melody_inst = voice_type`) — the animalese "a" pitched along the tune (`DialogueVoice.melody_voice`, `Audio.play_melody`); K.K. songs are K.K.'s alone

## 17. Dialogue & text

- [x] Message window: cloud and nameplate rasterised from `con_kaiwa2_modelT` / `con_kaiwaname_modelT` and tinted (235, 255, 235) like `mMsg_DrawWindowBody`, NES I4 font atlas, 18-frame scale in/out, the disc's `FONT_nes_tex_next` turn mark in blue with the triangle-wave alpha (`m_msg`, `m_msg_draw_window`) — `message_window_chrome.gd`, `MessageBody`, dialogue overlay
- [x] Typewriter per frame like `mMsg_Main_Cursol_ControlCursol` (a glyph every other frame, fast text, PAUSE waits, SETCURSORJUST timing), speaker-sex nameplate colour (`m_msg_draw_font`) — `dialogue_overlay.gd`
- [x] Choice panel: `con_waku_swaku3` window, the disc's `FONT_nes_tex_choice` mark in (0, 195, 185), scale in/out (`m_choice`) — `choice_panel`, `message_choice_mark.gd`
- [~] Dialogue data + runner + conditions; greeting picks opening line (`m_string`, `DialogueGreeting`) — `dialogue_runner.gd`, `dialogue_catalog.gd`. Choices inside a message (`OPENCHOICE` before more pages: the questionnaire, K.K.'s options) pick and then carry on through the rest of the message
- [~] Message-bank coverage: the disc banks are extracted and played (`DialogueCatalog`); authored stand-ins remain for a few menus
- [x] Text effects from the message codes: colour (`TEXTCOLOR` / `COLORCHARS`), size about the line type's pivot (`CHARSCALE` / `LINESCALE` / `LINETYPE`), `LINEOFS`, `PAUSE`, `SNDTRGSYS` sounds, `CAPTIALIZE`, `CUTARTICLE`, player / town / catchphrase / item / free-string substitution; pages that turn themselves (`MSGCLEAR`) or on a timer (`MSGTIMEEND`). GCN has no shake code; icon glyphs are font cells
- [~] **Animalese** voice per syllable, pitch by speaker (`jaudio` seqs 243–245) — `DialogueVoice`, `VoiceCatalog`
- [~] Keyboard entry (`m_editor_ovl` pad keyboard, `KeyboardPanel`): letters and the gyroid board (`LetterWriterOverlay`), names — design / album folder / catchphrase / song request (`NameEntryOverlay`). the town tune editor (`TownTuneOverlay`), the community board's posts (`NoticeBoardOverlay`)
- [~] Word filter for user text (`m_editEndChk_ovl`) — `EditEndPrompt` runs the end check on letters and design names
- [~] "..." silent responses; scrolling long letters; page-turn SE — page-turn SE (`page_okuri`, skipped on `BTN2` / `SNDNOPAGE` pages); a mid-page `BTN` stops with the turn mark and A writes on in the same page (`{btn}`) and the letter board's roll while writing (`mBD_roll_control`)

## 18. Player house & interiors

- [~] Small house on day 1 (4×4 interior); upgrades via Nook loans to medium (6×6), large (8×8), and upper floor (2nd floor, 6×6); basement is a separate unlock (49,800 bells). The statue is a reward state, not a room size; no side/back rooms, mansion, or attic exist in GCN — `PlayerHouse` / `HouseUpgrade` / `NookHouseTalk`: next-day builds, loans (148k / 398k / 798k / 49.8k), statue offer, statue actor (§26). Missing: roof colour recolour
- [x] Room grid; place furniture on the floor and against walls (`ac_arrange_room`, `ac_arrange_ftr`) — `InteriorBook`, `FurnitureGrip`
- [x] Wallpaper + carpet per room — `VisualRoomPaint`
- [~] Furniture rotate (4 or 8 orientations), stack on surfaces, put items on tables (`m_player_main_rotate_furniture`, `rotate_octagon`) — `FurnitureGrip`: A-grip + stick push / pull / turn about the held end, B pick-up, sit / lie by walking in, per-floor furniture cap; missing: bubu puff, bed rolling, octagon (gyroid) rotation
- [x] Wall-mounted items and clocks; rugs are carpets. The buildings' clocks (`ac_house_clock`: Nook's, the post office, the police box, the museum, Able's) turn their hands to the time — `HouseClock`
- [~] Interior editing mode / catalog reorder; "store in Nook's" / storage — dresser / wardrobe / closet conversations (`FurnitureStorage`)
- [~] Music player furniture (stereo/radio/etc.) plays a chosen K.K. song; gyroids beat along (`ac_radio`, `ac_my_room_melody`) — `FurnitureMusic` / `MinidiskCatalog`: discs, music box, one player at a time, aerobics radio, gyroid hop; missing: song titles, K.K. as the disc source, gyroid voices
- [~] Lit lamps at night, sit and lie (`FurnitureSeat`), music players (`FurnitureMusic`), storage (`FurnitureStorage`). Missing: the Famicom (§28), fireplace / fountain / bath effects
- [x] Doorplate / house nameplate (`ac_nameplate`): the sign on the south-west unit of a villager's plot reads "{name}'s house" in an orange window from the south — `house.gd`
- [~] Basement = free storage room once unlocked — orderable at Nook's after the medium loan; decorates like any floor
- [~] House exterior model changes with size; door mat; roof — `obj_{s,w}_myhome1..4` by size, fish weathervane / insect plaque via `CompleteTalk`; palette recolour not rendered
- [x] ~~Move house location~~ — not in GCN
- [~] Cockroaches spawn if you don't play for weeks; house dusty — `HouseGoki` / `house_goki.gd`: 6-day rule, up to 3 out, furniture flushes, startle, stomp; missing: death puff, cottage, dust
- [x] HRA judges the main room, and the upper floor in part (origins, sets, luck, facing, clutter); never the basement (§11)
- [x] Other residents' houses can be entered (`ac_my_house` has no owner check): their rooms stand in for yours while you are inside (`Game.enter_resident_house`); a notebook on a table there opens the owner's calendar, and their diary to read only (`mSM_OVL_CALENDAR`'s player, `mSM_OVL_DIARY` arg 1)

## 19. Furniture & collectibles

- [x] Furniture DB with sizes, HRA points, feng-shui colour, series and sell price from the disc — `FtrCatalog`, `HappyRoomAcademy`, `FengShui`
- [x] Series and themes from the HRA tables — `hra.py`
- [x] Themed sets award HRA bonus when all present + matching wallpaper/carpet — `HappyRoomAcademy`
- [~] Special / rare furniture is in the item tables (`FtrCatalog`); the Famicom only works as furniture once §28's emulator exists
- [ ] **NES/Famicom consoles as furniture** → playable games (see §28)
- [~] Gyroid furniture: place, switch on and off, dance — see §14. Missing: their sounds
- [x] ~~Musical instruments you can play~~ — GCN: no free-play
- [x] Snowmen: two snowballs each snowman season (Dec 25 – Feb 17) that grow on snow and shrink off it; roll the body and head together and the faster jumps on top. Graded on head ÷ body against 0.85, with lines to match; a perfect one mails a Snowman-series piece. Up to three stand, melting over three days. Walk into one to knock it down (`ac_snowman`, `ac_psnowman`, `m_snowman`) — `SnowmanRules`, `SnowmanUse`, `snowball.gd`, `snowman.gd`
- [x] Feng-shui / lucky items (see Feng shui)
- [x] Furniture comes from Nook's, the catalogue, villagers, events, HRA, balloons, tourneys, the lost and found, Redd, Saharah, the Wisp
- [x] Wallpaper & carpet catalogue pages — `CatalogOverlay`

## 20. Design / pattern tool

- [x] 32×32 pixel pattern editor, 16-colour palette (16 preset palettes), full tool set
  (PEN/NURI-fill/WAKU-shapes/MARK-stamps/UNDO), 8-slot design book (`m_design_ovl`) —
  `design_editor_overlay.tscn`, `design_list_overlay.tscn`, `design_book.gd`. All three
  design screens draw like the original from ROM art baked by
  `tools/asset_pipeline/design_ui.py` (`--kind design-ui`):
  - Editor: the `des_win` board, mode areas, 1:1 preview, grid, the 15-colour column
    with its palette number, the `des_tool` icons and per-tool `des_cursor` sprites,
    all at their original screen coordinates.
  - Book (`inv_original`): scrolling cloth, 2x4 wells, the pointing hand
    (`HandCursor`). From the pockets' pencil tab it opens beside the pockets
    (`mNW_OPEN_INV`).
  - Album (`sav_win1` + `inv_original2`): per-folder cloth and colours, stacked tabs.

  Not done: the menus' slide-in animation, the waku rubber-band rotation of the
  shape cursor, and the Start-button prompt still uses a plain panel rather than
  the message window.
- [~] Apply patterns as: shirt, hat, umbrella, wallpaper?, or place on the ground / as signboards / hung on walls — shirt (design book "C" wear, `cloth.idx >= CLOTH_NUM + 1`) the house-door design (§1 gyroid) and signboards (`SignboardUse`) work; design umbrellas (`ITM_MY_ORG_UMBRELLA0-7`, dragging a design onto the umbrella slot) not yet
- [x] The **Able Sisters** design display board: put your design on a mannequin / stand, take a copy of one, or swap (§22); villagers pick the displayed designs up (§22 trends)
- [x] ~~Pro designs~~ — not in GCN
- [x] ~~Free patterns from visitors~~ — GCN visitors don't hand out designs (Gracie sells clothes); `ac_broker_design` is the e-Reader card path (§28)
- [x] Design storage (`m_cporiginal_ovl`): the Able Sisters design album, 8 folders × 12 (§22). `m_cpedit_ovl` is the Memory Card copy/edit shell around it — no Memory Card layer in the port
- [x] ~~Town flag design~~ — `ac_flag` is the Animal Island flag (`island.flag_design`), part of the GBA island (§28); the GameCube town has no flagpole
- [ ] e-Reader design cards import (§28)

## 21. Nook's store

- [x] 4 building types over time + purchase volume: **Nook's Cranny → Nook 'n' Go → Nookway → Nookington's**; upgrades at 25,000 / 90,000 / 240,000 bells, with Nookington's also requiring a visiting foreign player (`ac_shop_level`, `m_shop`) — `ShopBook`: stored level (`shop_info.shop_level`), sales capped at the next threshold until the upgrade lands (`mSP_PlusSales`), a renovation booked two days out once earned (`aSL_JudgeRenewShop`, never across raffle day or Sale Day, cancelled if the clock runs backwards), closed for renovations from opening time the day before, reopening upgraded at the new building's opening hour; renovation-notice and grand-opening letters; `visitor` flag gates Nookington's (`shop visitor` debug command until multi-town visits exist). `shop0`–`shop3` interiors
- [x] Nookington's second floor (`shop3_2`) is built, and a visitor from another town walking into the shop sets the flag it needs (`mSP_SetNewVisitor`). Timmy & Tommy (`ac_npc_mamedanuki`, `rcf`) keep the upstairs counter: the same selling, catalog and shelf offers in their own echoing lines (`twins_shop_*`, authored), no house business; they stand at their units rather than following you between zones
- [x] Daily stock (`mSP_MakeGoodsList`, `ac_shop_goods`) — `ShopGoods.roll`: per-level counts (`l_zakka/conbini/super/dsuper_goods`), Cranny tools unlocked by sales (net 3k / rod 8k / axe 12k), Nookway+ paint (colour rotates each restock) + signboard + cedar sapling + rare-furniture slot (`ItemData.shop_rare`), stationery as a 4-sheet pad, distinct flower-seed bags, one umbrella, Halloween candy (Oct 16–30), Sale Day grab bags priced at the year (open with three free slots: rare goods or a pinwheel). Furniture, clothing, carpets, wallpaper and (Nookway+) a diary come from the disc's A / B / C lists, dealt common / uncommon / rare each session and rolled against goods power (`mSP_GetItemList`). In December the first furniture slots hold the festive trees until the 24th and the festive candle and flag from the 26th (`mSP_SetSeasonFTR`). Missing: seed bags plant pansies until flower species exist
- [x] Stock rotates at 06:00; sells out; sold-out slot shows empty
- [x] Sell items to Nook (he names a price, you confirm); can't sell some things — counter menu "I want to sell" opens the pockets in sell mode (`mSM_IV_OPEN_SELL`: "Sell", or "Sell all" on marked items), then Nook quotes the total and asks (`aNSC_buy_sum_check`, `nook_shop_sell`, `ShopBook.sell_result`, §11)
- [x] Nook buys turnips at fluctuating price (§11) — `KabuMarket`
- [x] Catalog ordering; items delivered by mail next day — "Order from the catalog" opens the original catalog (`CatalogOverlay`: nine tabbed pages in `m_catalog_ovl_data.c_inc` order, turning preview, wallpaper / carpet drawn on the room-corner model `mCL_rom_myhome1_*` with their own pages, price or Not for Sale, star on complete pages); Nook quotes the pick (5 order slots, `CatalogBook`, `CatalogPages`)
- [~] Sale days, the flooring/wallpaper wall — Sale Day grab bags, sale-event balloon gift on the first talk (`aNSC_check_present_balloon`); missing: the bargain-event FG layout (`mSP_GetNowShopFgNum` event kinds), wallpaper/carpet preview on the shop walls (`change_wall_proc`)
- [x] Nook gives you your first job (§29)
- [x] Nook's hours (`mSP_GetShopOpenTime`): Cranny / Nookway / Nookington's 9–22, Nook 'n' Go 7–23, raffle day opens at 10, forced open during the part-time job; the door says why it's closed (renovations / opening hour)
- [~] Tom Nook talk (`ac_npc_shop_common`): house business first, then the counter menu — sell / catalog order / other (turnip price) — and shelf offers ("That's X, N Bells") with try-on for clothes (`aNSC_show_item_check`); `NookShopTalk`. Timmy & Tommy upstairs at Nookington's and the password options are in. April Fools' Day's trick on the first talk (`AprilFools`). Missing: HRA talk
- [x] ~~Emotion / Redd membership card~~ — not in the GameCube shop code
- [x] Raffle tickets & end-of-month drawing (`ac_npc_shop_mastersp`): furniture / clothes / wallpaper / carpet / umbrella purchases each earn a month ticket (stack of 5; mailed next morning when the pockets are full, `aNSC_setup_ticket_remain`); on the last day Nook shows three prizes (the first one you don't own), five same-month tickets per spin, 5% / 10% / 20% for 1st / 2nd / 3rd, each prize won once
- [x] Roof paint sold at Nookway+: no pocket item, the roof changes at the next game start (`next_outlook_pal`)
- [x] Nook's secret codes (`m_mail_password_check`, `m_passwordMake_ovl`, `m_passwordChk_ovl`): "Hear code" trades a pocket item for a code addressed to a friend's town and name; "Say code" takes a code and hands over its item wrapped, three a session, at home only — the GameCube algorithm byte for byte (`SecretCode`, checked against the decomp's encoder), so real codes work. Items map through `CodeItems`. Missing: the password windows' own art (the design-name window stands in)

## 22. Able Sisters (Nook's neighbour)

GCN Able Sisters is a design shop, not a clothing store: no Bell stock, no counter
(`ShopBook.restock(ABLE_ID)` stocks nothing). The old "sells shirts / hats / wallpaper"
and "umbrella stand" lines described later games (`ac_shop_umbrella` is Nook's stand) and
were dropped. See [shops](decomp_notes/shops.md) § Able Sisters.

- [x] Shop building + interior (`ac_needlework_shop`, `ac_needlework_indoor`, `ac_misin`) — `able_sisters.tscn`, `needlework.tscn`, `NeedleworkPresenter`: 4 mannequins + 4 umbrella stands at the `manekin_pos` / `umbrella_pos` GX, the animated machine + fabric (`obj_misin`, `aMSN_DustCloth_c`), back-wall clock; open 07:00–02:00 (`aNW_check_opend`)
- [x] **Mabel** runs the shop (`ac_npc_needlework`, `SP_NPC_NEEDLEWORK0`) — `mabel.gd`: runs up to greet you on the first approach (0x2FD1 first visit / 0x2FD2 after); A opens the 6-way (`aNNW_set_6_ways`) with the first-time lead until "What's this?" has been picked (`needlework_first_talk_flags & 0x40`), and sub-flows that end in `WHAT_HAPPEN` bounce back to the menu; she sees you off when you face the exit from the row inside (`player_go_away` → think 10 → 0x2FD3 → leave). Her area-table roaming (`aNNW_next_target2`) is simplified to "run to the player when within 115 GX"; pressing A at a display opens the trade straight away instead of her running over first (`aNNW_THINK_OMATIKUDASI`)
- [x] **Design a pattern** (`aNNW_TALK_DESIGN_*`): 350 Bells checked up front with sacks counted (`mSP_money_check`), charged only once the design is saved *and* named (`aNNW_talk_design_close3`); closing the list or quitting the editor unsaved costs nothing (0x2FE9); re-dresses you if you rewrote the design you're wearing (`CLOTH_CHANGE2`)
- [x] **Save a pattern** → the design album (`m_cporiginal_ovl`, `mNW_OPEN_CPORIGINAL`) — `design_album_overlay.tscn` + `DesignBook.album`: 8 folders × 12 designs with 12-character folder names, the hand swaps album ↔ album, album ↔ your 8, and your 8 among themselves (`mCO_swap_image`); closing asks keep / discard (`mSM_OVL_EDITENDCHK`); the worn slot changing re-dresses you (`change_flg` → `CLOTH_CHANGE3`). Kept in the save rather than on a Memory Card
- [x] The **display board** (`aNNW_TALK_TRADE_*`): A at a mannequin / umbrella stand → "Display mine!" (copy yours up), "I want it!" (copy theirs into one of your 8), "Can we trade?" (swap), with the 8-slot / replace confirms; wearing the design you traded away re-dresses you (`CLOTH_CHANGE`)
- [x] **Trends** — villagers wear the shop's designs (`Animal_c.cloth == RSV_CLOTH` + `cloth_original_id`, `umbrella_id` = `ITM_MY_ORG_UMBRELLA0..3`) — `NeedleworkTrend` + `VillagerState.cloth_design` / `umbrella_design`: picked up and passed around through the greeting reactions (`aNPC_act_greeting_reaction` rates: change into a shop shirt / umbrella, copy a friend's shirt, back to a normal shirt, reset both); "Any suggestions?" names the most-worn shirt then umbrella in four tiers (`aNNW_trend_check_*`, 0 / 1 / <5 / 5+); displaying over or trading away a design sends its wearers back to their own clothes (`aNNW_trend_delete_*`), buying a copy doesn't. Villagers paint the design over their cloth surfaces. Spread through live villager greetings (`VillagerGreeting`) only where villagers meet; Able umbrellas in hand aren't drawn yet, so umbrella wear only feeds the report
- [x] **What's this?** (`aNNW_TALK_CHECK_LISTEN` → `LISTEN_SISTER*`): Mabel's pitch, then "Any tips?" plays the explanation with the camera on both sisters and Sable adding a line
- [x] **Sable** at the sewing machine (`SP_NPC_NEEDLEWORK1`, `aNNW_THINK_MISIN_WAIT`) — `sable.gd`: the machine and fabric stop while she talks and start again after (`misin_clip` stop / move); she only looks up at you once `nw_visitor.days >= 5`
- [x] Sable's story arc (`aNNW_get_make_sister_message`, `aNNW_message_table`): the visit-day counter ticks once per real day she's spoken to, capped at 10 (`aNNW_day_day`); the row is picked from the count *before* today's tick, so the first talk of days 4–7 tells that day's chapter (`aNNW_story_first_table` 5/9/13/17) and later talks a follow-up; ≥8 days she's at ease. Three-part rows play Sable → Mabel (turned to face her, `aNNW_THINK_AINOTE`) → Sable; story 9 ends with Sable turning to you (`aNNW_talk_ane_3`). **No free pattern** — the GCN arc has no gift (nothing in `ac_npc_needlework_talk.c_inc` hands one over; that's later games)
- [ ] ROM text: the greeting, menu-lead, story and explanation lines are authored stand-ins until the message banks (`0x2FD1`–`0x3035`, `0x3012+`) and the design-name strings (`0x6DF`/`0x6E7`) are extracted; `NeedleworkTalk` prefers the ROM line when the bank is present
- [ ] **Other things** → GBA design tool / upload / e-Reader cards (`ac_npc_needlework_gba.c_inc`, `aNNW_TALK_GBA_*`, `CARD_E_*`): the menu is there and answers "no Game Boy Advance connected" (0x3008); the link itself is §28
- [x] April Fool's lines for both sisters (`aprilfool_control_clip`, `AprilFools`): Mable's trick instead of the menu, Sable's instead of her story
- [x] Foreign-player rules (`mPr_FOREIGNER`): a visitor gets 0x2FEE instead of the album, and Sable treats them as day 0 — no tick, no look up (`mabel.gd`, `sable.gd`)

## 23. Museum

- [~] Building + 4 wings; **Blathers** the owl curator (nocturnal, sleepy by day) (`ac_museum`, `ac_npc_curator`) — `museum/*`, `museum_book.gd`
- [~] Donate fish / insect / fossil / painting; one-per-species; assessment dialogue (`m_museum_display`) — `museum_display.gd`, `museum_presenter.gd`; rejections play the full `HandOver.player_offers_npc_rejects` GET+examine+RETURN sequence and fossil-piece acknowledgment for incomplete skeletons lands (see [museum.md](decomp_notes/museum.md)). Missing vs. decomp: GET/PUTAWAY hand-over split for *accepted* donations specifically, the 40-entry insect-only extra trivia table. The museum-complete letter with the museum model goes to every resident at their next start of play (`MuseumCompMail`; on the disc it can never come, since two of the 15 paintings are always turned away)
- [~] Fish tanks with the species swimming; insect terrariums/cases; each donated species animates (`ac_museum_fish_*`, `ac_museum_insect_*`) — `museum_fish_actor.gd`, `museum_insect_actor.gd`
- [~] Fossil hall with the skeleton mounts from fossil groups (`ac_museum_fossil`) — `museum_fossil.tscn`, `MuseumDisplay`
- [x] Art gallery: paintings on the walls (`museum_painting.tscn`); Redd's forgeries are rejected by Blathers (`MuseumBook`)
- [x] Blathers gives species facts on donation — `MuseumDialogue` trivia
- [x] Museum completion tracking; per-species "already donated" path — `MuseumBook`
- [x] ~~Museum shop / observatory / café~~ — not in GCN
- [x] ~~Rooftop / second floor~~ — not in GCN
- [x] Museum is open 24h; Blathers drowsy 06:00–18:00 — `museum_blathers.gd`

## 24. Post Office

- [~] Building + interior; **Pelly** (day) / **Phyllis** (night) at the counter (`ac_post_office`, `ac_npc_post_girl`) — `post_office.tscn`, `post_girl.tscn`, `post_book.gd`
- [x] Write & send letters: real address book gated to villagers who've met the player
  (`Relationship.MET`) plus a "Museum" entry, a real 6-line character-grid keyboard
  (`m_editor_ovl.c`'s `mED_TYPE_BOARD`, same line/width cap as reading), Save/Keep
  editing/Discard confirm (`mSM_OVL_EDITENDCHK`) — `letter_address_overlay.tscn`,
  `letter_paper_picker_overlay.tscn`, `letter_writer_overlay.tscn`. Gift attachment via
  the hand (`mTG_present_proc`) — pick an item, "Present" it onto the unsent letter.
  Sending is still the separate Post Office step, matching decomp. The player freely
  picks any of the 64 real paper designs when writing, rather than being limited to a
  stationery stack they own; header/footer are auto-filled, not separately editable.
- [x] Stationery types — all 64 designs' real art render in both the read window and the
  write-time picker (`LetterChrome`, baked by `menu_ui.py`), `MailData.paper_type`
  round-trips through save. Missing (separate, smaller gaps): specific papers awarded
  by events/villagers, and letter paper affecting villager reaction.
- [~] Your mailbox at your house: receive letters, gifts, HRA reports, bank interest, event mail, catalog deliveries (`ac_mailbox`) — `scenes/world/mailbox.tscn` + received-mail path, flag raises/lowers on unread mail in every season, lid opens/closes around the Letters menu with the cursor seeded on the last-used slot (`aMBX_pl_open`/`_pl_close`, `mMB_get_last_mail_idx`); Museum fossil-identification replies land here (`FarwayBook` — the in-code name predates confirming decomp's actual address-book contact is just called "Museum", `mPr_CheckMuseumAddress`). Missing: the player's walk-up/hop before the lid opens (`aMBX_pl_wait`/`Player_actor_*_Mail_jump`); villager letters, mom's letters, bank gifts and event mail all arrive
- [x] Post office desk holds letters for delivery (`PostBook`, 5 slots): rounds at 9:00 and 17:00 and once at the start of a session (`mPO_delivery_proc`, `mPO_first_work`) carry held letters to a mailbox with room; letters to villagers leave the desk
- [x] Villagers send you letters (with gifts if friendship is high); replies build friendship — `VillagerLetters`
- [x] Send a gift to a villager by mail → thank-you letter and sometimes a present back — `VillagerLetters`
- [x] **ABD bank** terminal (§11) — `BankOverlay`; balance gifts by mail instead of interest
- [x] ~~Pay the loan at the Post Office~~ — GCN: pay at Nook's
- [x] ~~Parcels / forwarding~~ — not in GCN beyond catalogue deliveries by letter
- [x] ~~Closed hours & knock~~ — the GameCube post office never closes: Pelly by day, Phyllis by night with her own (grumpier) lines, `draw_type` +1 (`PostDisplay`)
- [x] ~~Pelly's storyline~~ — no storyline on the GameCube: Pete's unrequited love is villager chat, and the date is an April Fools' lie (15277/15278)
- [~] Codes mailed to villagers (`mNpc_ReceiveHPMail`): not yet — Nook redeems them (§ shop)

## 25. Police Station

Behaviour ported from `m_police_box.c`, `ac_police_box.c`, `ac_npc_police2*`,
`ac_npc_police*`, `bg_police_item*` and `ef_room_sunshine_police.c`; details in
[post / police](decomp_notes/post_police.md). Tests: `tests/unit/test_police_box.gd`.

- [~] Building exterior (`ac_police_box`) — `police_station.tscn`: shell, 3×3 plus-offset hull, door (`INTO_S1`, triforce wipe), exit stand `+60,+60`, window lights 18:00–05:00. Missing: the 320-per-frame env-colour fade between on/off (lights snap)
- [~] Interior (`SCENE_POLICE_BOX`) — `police_box.tscn`: `police_indoor` shell, enter `{200,0,380}` north, exit `EXIT_DOOR1`, BGM. Unverified against a real render in this pass (no generated assets in the container)
- [x] Lost-and-found storage rules (`PoliceBox_c`, `police_book.gd`): 20 slots; new town gets 1 furniture + 2 shirts once (never refilled when emptied); `keep_item` appends at the occupied count and drops the oldest when full; ITEM1/FTR only; claimed gaps packed when you walk out (`mPB_copy_itemBuf`); `keep_all_item_in_block` batch rules
- [x] 06:00 top-up (`mPB_force_set_keep_item`): once per renewal, only with ≤ 5 kept, 50% roll; goods 86% (furniture 36 / stationery 23 / clothing 30 / carpet 6 / wallpaper 5), tools & saplings 5%, flower bags 5% (first 8 bags), umbrella 4%
- [~] Lost-and-found display (`bg_police_item`): each kept item drawn as its field card (`obj_item_*`) at its `RSV_POLICE_ITEM_N` unit centre on the BG under it. Units read from `FG_TYPE_POLICE_INDOOR` (0xCE) in the generated FG catalog; the authored fallback table is unverified. The furniture/cloth pools are the shop's A / B / C lists (`ShopGoods`)
- [x] Claiming (`aPOL2_message_ctrl` / `aPOL2_check_answer`): face a kept item + A → Booker asks (0x077E, item name with article) → "yes" puts it in the first empty pocket (tickets stack), plays `ITEM_GET`, removes it; pockets full → 0x0781
- [x] **Booker** (`ac_npc_police2`, `booker.gd`): greets you on walk-in (0x0784 empty / 0x0785 items); talk 0x077D / 0x0786 / 0x0787; tails the player through the 4×5 zone grid (stop < ~50 GX, walk < ~70 GX, run beyond; waypoint routing round the shelves; turn-in-place past 90°; 11.25°/frame turns; walk 1.0 / run 4.0 speeds); turns to you before every talk
- [~] Booker / Copper lines: the disc bank's own text plays when the dialogue bank has been generated (`msg_<n>`); otherwise authored stand-ins in `booker_talk.json` / `copper_talk.json`. The claim confirm and Copper's menu always use the authored graph (choices). April Fools' lines (`aprilfool_control`) not wired
- [~] Window sunshine (`ef_room_sunshine_police`): left/right beams stretched by time of day, sun/moon window colour, rain × 0.6, camera-side culling, `windowlight_alpha` ramp (05:00–18:00, incl. the noon and `s16`-wrap blinks) — `police_sunshine.tscn`. Needs `obj_koban_shine` from the pipeline (`XLU_ONLY_STATICS`); not yet seen rendered
- [x] **Copper** (`ac_npc_police`, `copper.tscn`): stands two units east of the station facing south; walk-out greeting (0x0771) after leaving the police box; time-of-day menu (0x0772–0x0775) → event hint / lost-and-found count (0x0782 / 0x0783) / never mind (0x0777); 06:00–07:00 exercises (5%, fair weather) and 02:00–04:00 dozing (5%). Gone from his post while either aerobics event runs, leading the routine at the shrine instead (`AerobicsLeader`). His unit is held on the grid, so nothing can be dropped under him (the GameCube sends anything there to the lost and found, `mFI_SetFGStructureKeep`)
- [~] Copper's event hint (`aPOL_get_hint_msg_no`): first-job hint, none / later / today / running per special visitor. A running visit other than the sale needs the visitor's acre (`mEv_get_event_place`); no visitor is placed in town yet, so that answers "nothing" like the original's not-found path
- [x] Ask for a town map — a visitor from another town gets Copper's map option first (`aPOL_check_select2` → `mPr_SetNewMap`, 0x18CA)
- [x] ~~Ask about a villager's location / who's moved in / who's moving out~~ — not in GCN (Copper's menu is the three options above)
- [x] Every town has the police station from day 1 (`mRF_BLOCKKIND_POLICE` block)
- [x] Lost & found also holds forgotten umbrellas etc. (umbrella / tool / flower-bag top-up rolls)

## 26. Town Hall & civic

- [x] No Town Hall on the GameCube (it arrives in Wild World): Tortimer only appears at events, and Pelly / Phyllis work the post office (§ post office)
- [~] Tortimer hands out event items & hosts most holidays (`ac_ev_soncho`, `ac_ev_speech_soncho`) — holiday speeches and the wishing-well visits with his calendar trophies (§31), and the second bridge (§ Bridges)
- [x] Town Hall services (recycling, donations, environment rating): not on the GameCube; the town tune is set at the melody board by the station (`m_mscore_ovl`)
- [x] **Town tune** editor at the tune board: 16 frog steps (G low … E, random, rest, tie), play, erase-all prompt, "Is this OK?" (save / rewrite / keep the old tune), plays as it opens; saved with the town (`m_mscore_ovl`, `ac_mscore_control`, `m_melody`) — `TownTuneOverlay`, `TownTune`, art from `menu_ui.py` (`ui/mscore/`); `tune [open|reset]` console command. The e-Reader button only closes
- [x] Town name is fixed after creation
- [x] Player statue by the station (`ac_douzou`) once a house's loan ends in the statue: owner's figure and face (winter set in winter), rank sets size and gold / silver / bronze / jade colours, plaque reads `MSG_DOZOU` in a red window — `Statue`, `statue_metal.gdshader`, face textures from `weather_sprites.py`; `house statue built [rank]` console command. Glints in the statue's colour twinkle over it, more often the finer the metal (`ef_douzou_light`, `StatueSparkle`)
- [x] Wishy the Star: not on the GameCube; the wishing well (`ac_shrine`) rates the town, takes quest items off your hands and is Tortimer's holiday spot
- [x] Recycle bin: not on the GameCube (`ac_reserve` is the plot / dock sign); the dump (`ac_dump`) is the closest thing
- [~] Community board: 15 dated posts from the disc's `kei_win` art, seeded with the four starter handbills, page turning and jumps, writing a post on the keyboard with "Is this OK?"; 41 seasonal notices post themselves as their dates pass (sports fairs and daylight saving move with the year), the latest five after an absence (`m_notice`, `m_notice_ovl`) — `NoticeBoard`, `NoticeBoardOverlay`; `board` console command. Each tourney's champion goes up at 18:00 (handbill 0x242). On a check with nothing seasonal, at most once a day and three days apart, a resident who knows you may bury a pitfall seed or lottery / event furniture in a random acre and post where (40%, `mNtc_check_treasure`, `BuriedTreasure`)
- [x] Signboards (`ac_sign`): Nookway sells them; put down outside one stands up as a white sign, talked to it posts one of your designs (12388; visitors get 12389), and it can be picked up again — `SignboardUse`, `signboard.tscn`. The GameCube has no acre-naming signposts
- [~] The plaza / town square as the event stage (K.K., fireworks, Tortimer speeches) — festival crowds stand in their event-map slots, fireworks go up over the pond; K.K. plays at the station

## 27. Train station & travel

- [~] Station building; **Porter** the monkey stationmaster (`ac_station`, `ac_npc_station_master`) — `intro_station_stage.gd`
- [~] Arrival by train on a new game: Rover on the train, get off, Porter greets, walk to Nook (`ac_train0/1`, `ac_intro_demo`) — `intro_train_stage.gd`, `intro_station_stage.gd`
- [x] Travelling by train: Porter on the platform asks "Are you planning on going on a trip?" (0x0943), checks there is another town and no other passport out (0x0946 / 0x095E), saves the passport and the town (0x094F) and sees you off (0x0965) — `PorterTalk`, `Travel`. The other slot's K.K. welcomes the visitor (0x5130) and they get off on that town's platform; leaving, Porter saves that town and the passport (0x095C / 0x0955); back home K.K. copies them in (0x5128) and Porter says "Welcome home" (0x0966). Missing: the train pulling in and out on screen for these trips
- [x] ~~Send a villager away / moving truck~~ — not on the GameCube: a newcomer's house simply appears and a leaver's goes (`m_npc` move in / out, §17); the player can only talk a villager out of leaving
- [x] Gulliver washes up on the **beach**, not the train — see §30
- [x] ~~Flag on the flagpole outside the station~~ — island only (`ac_flag`, §28)
- [x] Train departure/arrival animation, whistle, `ef_kisha_kemuri` smoke — `TrainService`, `FieldTrain`, `FieldFx`

## 28. Peripherals & connectivity

- [ ] **GBA ↔ GCN link**: connect a Game Boy Advance for **Animal Island** (`m_island`, `m_gba_ovl`, `m_eappli`)
  - [ ] Kapp'n (`ac_npc_sendo`) rows you to the island and back, sings
  - [ ] The island has its own acre, a summer cottage (`ac_cottage`), a special islander villager, tropical fruit & fish/bugs
  - [ ] Islander moves to your town if befriended
  - [ ] Downloadable island to the GBA to play on the go; changes sync back
  - [ ] Island exclusive furniture / the island tune
- [ ] **e-Reader** card support (`m_card`, `ac_broker_design`, password systems)
  - [ ] Character/villager cards, item cards, NES game cards, town-tune cards, design cards, special-character cards
  - [ ] Villagers you scan in can move to town
- [~] **Secret codes / passwords**: Tom Nook makes and redeems them (`SecretCode`, `CodeItems`). Missing: codes mailed to villagers (Famicom / popularity / e-Card types)
- [ ] **NES / Famicom games as furniture** (`famicom_emu.c`, `src/static/Famicom`, `src/static/jaudio_NES`)
  - [ ] ~15–19 built-in NES titles playable in your house on a Famicom console _(verify list & count)_
  - [ ] Save state per game; some obtained only via e-Reader / events (e.g. Punch-Out, Zelda)
  - [ ] Playable on GBA when downloaded
- [ ] GBA / e-Reader detection & menus (no Memory Cards here; saves are files)
- [x] ~~Broadband/modem adapter~~ — _not used_

## 29. First job / new-player onboarding

- [~] Nook gives a job in exchange for the house: change into the uniform, plant a tree/flowers, deliver furniture & a letter, meet a villager, write on the bulletin board, then the shop opens; get an axe; final notice (`ac_npc_rcn_guide2`, `mQst_SetFirstJob*`) — `first_job.gd`, `tom_nook.tscn`
- [~] Uniform shirt (`shirt_016`) worn during the job — `first_job.gd`
- [~] Post-job: Nook explains the loan; see §21's house business
- [x] Starting letters — mom's (`MotherMail`) and the museum's intro (`FarwayBook`)
- [x] Mom (and once a year Dad) write (`mPr_SendMailFromMother`): on the birthday with a cake, on 1/1 … 12/12, April Fools', Mother's / Father's Day and Christmas Eve; otherwise a 1-in-5 chance a day of one of 56 everyday letters, some with a present, and a seasonal letter once those run out — on the month's own paper — `MotherMail`

## 30. Special visitors & recurring NPCs

Event NPCs are `EventNpc` scenes placed by `EventManager` presenters (`scenes/world/event_manager.gd`, `scripts/systems/events/`); their talks are `BankTalk` scripts over the disc messages. See [events](decomp_notes/events.md).

- [x] **K.K. Slider** — Saturday nights at the station; request a song by exact title, a random uncollected one, or a made-up tune; the show (quiet, live BGM, staff roll, weather cues) and the aircheck (`ac_npc_totakeke`, `KkTalk`). Missing: staff-roll lights/camera, exact strum/beat sync
- [x] **Crazy Redd** — tent on an empty lot, three wares at 4× price, sales talk (`ac_ev_broker`, `ac_ev_broker2`, `ReddStock` / `ReddTalk`); facing the way out he sees you off (0x0791, or 0x0792 after a sale) and you leave the tent
- [x] **Saharah** — trades a carpet for yours at 3000 × 2^n (`ac_ev_carpetPeddler`, `SaharahTalk`)
- [x] **Wendell** — fish for an event wallpaper (`ac_ev_artist`, `WendellTalk`)
- [x] **Gracie** — car on a lot, fashion check, car-wash minigame, Event / group-A clothing (`ac_ev_designer`, `GracieTalk`)
- [x] **Gulliver** — on the beach, wake him, Jonason gift (`ac_ev_dozaemon`, `GulliverTalk`); with full pockets he keeps it until you come back to him the same day (no letter on the GameCube)
- [x] **Wisp** — one night in a week (rolled 2–4 days ahead), 0:00–3:59, in a town with eight or more weeds: invisible until you bump into him ("Excuse me…", then "Thank you for noticing me!"), then half-seen and wandering; five spirits each in their own acre come out as you enter it and stack in one pocket slot; all five back buys a wish — no weeds, a new roof colour (four pages of three) or something the catalogue lacks; at 4:00 "It's 4 o'clock!" and he spins away (`ac_ev_ghost`, `ac_ins_hitodama`) — `WispEvent`, `WispTalk`, `wisp.gd`
- [x] **Joan** — Sunday mornings, turnips (`ac_ev_kabuPeddler`, `JoanTalk`). Her give order is simplified (take → give → lines)
- [x] **Katrina** — fortune tent (50 Bells, destiny) (`ac_ev_gypsy`, `KatrinaTalk`) and the New Year's shrine lottery (fortune letter + destiny) (`ac_ev_miko`, `MikoTalk`). Destiny effects on villagers / luck are not wired
- [x] **Jingle** — Toy Day: wish questions in a new acre each time, a Christmas present; new shirts fool him (`ac_ev_santa`, `JingleTalk`)
- [x] **Franklin** — hides on Harvest Festival day; his knife and fork by the feast table buys one of 12 harvest presents (`ac_ev_turkey`, `FranklinTalk`)
- [x] ~~Pavé / dancers~~ — later games
- [x] **Chip** — bass tourney judge: measures, keeps the day's record (villagers can beat it), A/B/C prize (`ac_ev_angler`, `AnglerTalk`)
- [x] ~~Nat~~ — not GCN
- [x] ~~Dr. Shrunk~~ — not GCN
- [x] **Mr. Resetti / Don Resetti** (§1), and Resetti as Groundhog Day's groundhog (§Events)
- [x] **Rover** — on the train in the intro (`intro_train_stage.gd`), for the first resident and every newcomer (`ac_npc_guide` / `ac_npc_guide2`). The GameCube has no later Rover visits
- [x] **Porter** — greets you off the train in the intro, stands on the platform in normal play and handles trips (`StationPorter`, `PorterTalk`)
- [ ] **Kapp'n** — boat to the island (`ac_npc_sendo`, `ac_boat`, `ac_boat_demo`)
- [x] **Tom Nook**, **Blathers**, **Pelly & Phyllis**, **Copper & Booker**, **Sable & Mabel**, **Tortimer**, **Joan** — see their sections. Timmy & Tommy: see §21
- [x] **Countdown NPCs** for New Year's Eve — lines by minutes to midnight, the leader calls out each term, party poppers and fireworks at midnight (`ac_countdown_npc0/1`)
- [x] **Blanca** (`ac_npc_mask_cat`, `ac_npc_mask_cat2`, `mEv_EVENT_MASK_NPC`): she meets the traveller off the train (always when visiting, every other trip home), asks for a face (0x33F2 / 0x33F3) and the design editor opens on her blank face (palette 15); a face back gets her verdict (0x31E1–3), a blank one "Shaky fingers!" (0x321A) and another go. The town keeps the face and the painter; she then takes the weekly slot on days Gulliver isn't due, her story moving on with the first talk each day (0x31E4 + 4·n), until ten talks or a week — `MaskCat`, `BlancaTalk`, `blanca.tscn` (`mka_1`, face on the face quad). Missing: the train interior scene she sits in (she waits on the platform)
- [x] **Night-stall Redd** at the fireworks: fans / pinwheels / balloons, 8 colours a night (`ac_ev_yomise`, `YomiseTalk`)

## 31. Holidays & seasonal events

From `m_event_schedule.c_inc` (117 unique event IDs across 134 schedule-table rows). Localised USA set:

- [x] Event scheduler: every row resolved per date/hour, weekly visitor, special-visit roll, weather override, `/event` debug commands — `event_calendar.gd`, `event_schedule.gd`, `data/events/schedule.json` ([events](decomp_notes/events.md))
- [x] Festival presenter: props, residents in their map slots (`data/events/event_map.json`, `FestivalCrowd`) with their slot's animations and talk, hidden from the field meanwhile

- [x] New Year's Day — shrine crowd, Katrina's lottery, Tortimer. Missing: the hatsumōde queue choreography (`ac_hatumode_control`)
- [x] Groundhog Day — crowd lines by minutes to 8:00; ten seconds after 8:00 the "groundhog", Mr. Resetti, pops up on the shrine acre with his weather line (`ac_ev_majin`, `aGHC_birth_reset`), then Tortimer's speech and weather verdict — `GroundhogResetti`, `SpeechTortimer`. Missing: the event title card and BGM handoff
- [x] Valentine's Day — villagers send letters with chocolate (`VillagerLetters.send_valentines`)
- [x] Snowman season / Kamakura — snow cabin with a resident guest (greeting game, Kamakura trade list); the snowman balls (`snowman_start`, `SnowmanPresenter`)
- [x] Spring / Fall **Sports Fair** — residents in gym clothes at their stations with their lines; Tortimer. The games run: tug-of-war on a shared rope with a flag-waving referee (`TugOfWar`), ball toss into the baskets with cheers (`BallToss`, `TossBall`), and the four-lap foot race round the shrine with warm-up, starter's pistol, trips, finish and team swap (`FootRace`)
- [x] April Fools' Day — rumours, mom's letter, the calendar; villagers' first hello of the day is an April Fools' line (`MSG_15236`, islanders `MSG_15254`), as Spring Cleaning's is (`MSG_15297`); Porter, Tom Nook, Blathers, Mable, Sable, Copper, Booker, Pelly and Phyllis each try one trick on every resident (`ac_aprilfool_control`, `AprilFools`; Pete and Kapp'n aren't in town)
- [x] Cherry Blossom Festival — picnic mats, seated / dancing residents, Tortimer
- [x] Nature Day, Spring Cleaning, Mother's / Father's Day, Graduation, Town / Founders' / Labor / Explorers' / Officers' / Mayor's / Sale / Snow Day — Tortimer at the wishing well with his calendar trophy (`ac_ev_soncho2`, `TortimerHoliday`)
- [x] Fishing Tourney — anglers at the pond, Chip, weigh stand
- [x] Summer Camper — tent on an empty lot, an out-of-town villager inside (greeting game, Tent trade list)
- [x] Fireworks Show — crowd with fans, Redd's stall, fireworks over the pond (bigger sets in the last hour)
- [x] Morning Aerobics — residents doing the routine by the radio, Copper out front calling it and Tortimer exercising behind (`AerobicsLeader`). Tortimer's exercise card (`mSC_Radio_*`, `RadioCard`): a one-stamp card on the first visit, one stamp a day, a lost card remembered and replaced, old cards taken back, no new cards from August 19, and the aerobics radio on the fourteenth stamp
- [x] Meteor Shower — moon-viewing crowd with meteor lines, shooting stars on the pond (`MeteorShower`)
- [x] Harvest Moon — moon-viewing crowd
- [x] Mushroom season (Oct 15–25) — `MushroomUse`
- [x] **Halloween** — Jack (moves acre after each talk), residents in costume chase the player; candy → present, else a trick (pocket swap or shirt) (`ac_ev_pumpkin`, `ac_halloween_npc`, `TrickOrTreatTalk`)
- [x] **Harvest Festival** — seated feast crowd, Tortimer; Franklin (separate row)
- [~] The day after — **Sale Day** at Nook's — grab bags (`mSP_Chk_HukubukuroSail`); see §21
- [x] Snow Day — Tortimer at the well (see the holiday line above); snow follows the weather tables
- [x] **Toy Day** — Jingle
- [x] **New Year's Eve** — countdown crowd, party poppers, fireworks at midnight
- [~] Weekly: K.K. (Sat night), turnips (Sun AM), Tortimer/mayor rounds — K.K. and Joan are placed by the event manager; Tortimer comes on holidays and, in a full town, about the second bridge
- [~] Monthly: lottery (last day), Nook stock reshuffle — raffle + monthly prize reshuffle done. No bank interest on the GameCube (balance gifts instead); the HRA writes daily after changes, not monthly
- [~] "Rumor" pre-event villager chatter for each holiday (`mEv_EVENT_RUMOR_*`) — villagers bring up coming visitors and live rumours with their dates (`aQMgr_decide_msg_special_ev` / `_calendar_ev`)
- [x] Tortimer "soncho" variant appearances for each holiday (`mEv_EVENT_SONCHO_*`) — except the January / February vacations and the bridge
- [x] ~~Player birthday party~~ — GCN: the present visit and cards instead (§2)
- [~] Weather overrides for events — the event scheduler applies `mEv_EVENT_WEATHER_*` rows (`EventCalendar`)
- [x] Minor holidays: the calendar is the disc's own GAFE01 event table (`data/events/schedule.json`), so only the US release's days run

## 32. Audio

- [~] Sequenced BGM engine (`jaudio_NES`, `m_bgm`, `audiorom.img`) — `audio.gd`, `bgm_catalog.gd`
- [~] **24 hourly field themes**, rain theme, title, train, shops, museum, post office, police, house, Able's (`BgmCatalog`). Missing: the island
- [x] Music crossfades on the hour (`mBGMPs_FLAG_CROSSFADE` → `Audio.play_bgm` fade); rooms play their own music — no caves on the GameCube
- [~] **K.K. Slider songs** — the Saturday show and aircheck music players (§30, `FurnitureMusic`)
- [~] SFX bank (seq 242): footsteps by surface (`FootstepSe`), tools, UI, doors, catches (`SeCatalog`). Gaps where the converted bank lacks an SE
- [~] **Animalese** speech — see §17
- [~] Town tune played on the hour outdoors as the time signal (`mBGMTime_signal_melody`) — `Audio.play_melody` on the note SEs; the step length (0.25 s) is an estimate, and clocks / villager humming don't use it yet
- [ ] Gyroid voices layered onto room music (`ac_my_room_melody`, seq 246 rhythm group) — gyroids dance silently for now
- [~] Ambient: the surf on the beach acres and rivers / waterfalls inland from each acre's bg sound sources, the pond's water and its summer frogs (`aFD_OperateWaterSound`, `FieldAmbience`); rain is the weather loop, cicadas and crickets come from the insects. No birds or owls on the GameCube. Missing: panning, and the frog loop renders silent from the bank
- [~] Positional audio for sound sources (train, insects) through `Ongen` (`Na_OngenPos`)
- [ ] NES game audio via the Famicom APU emulation (`ks_nes_core`)
- [x] Fanfares (`mBGMPsComp_make_ps_fanfare`): the pre-rendered jingle sequences play on their own layer over the music, which stops and starts over when they come off (`Audio.push_fanfare` / `pop_fanfare`) — net and rod catches, collection complete, golden tools, digging something up (held up with "Check it out!"; pockets full: swap a pocket into the hole or bury it again, `DigReport`), the loan paid off and Nook's chores done (`YATTA1` and "YESSSSS!!!" on walking back out, `run_complete_payment`)

## 33. UI, menus, misc systems

- [x] ~~Start / pause menu~~ — the GameCube has none: the pockets, map and letters open straight from the field; options live on the title screen
- [x] **Diary** — the player writes it: a page per month (31 lines, 992 characters) on the disc's three-sheet page with the month tab, scrolled while reading and rolled to the line while writing, opened by "Read" on any of the sixteen notebooks set down on a table in your rooms (`m_diary_ovl`, `aMR_CheckDiaryOnMe`) — `DiaryOverlay`. It opens through the calendar
- [x] Held **map** item / sight-map boards — `MapOverlay` (§4)
- [x] ~~HUD clock~~ — GCN has no HUD; the time shows on the pockets screen
- [x] Options: K.K.'s "Before I go..." menu sets the sound (stereo / mono / headphones; mono folds the master bus), how animals speak (Animalese / Bebebese / silence) and rumble, kept in `user://config.cfg` (`Config_c`, `aNPS2_setup_*_option`) — `GameConfig`. The GameCube has no text-speed, screen-position or brightness options
- [x] Rumble / vibration on tool use, catches, bumps (`m_vibctl`, `m_player_vibration`): dig, fill, stump, shovel and axe bounces, axe cuts, net hits, tree shakes, weed pulls, tumbles, the bobber landing and fish nibbles / bites by size, through `Input.start_joy_vibration`; off when K.K.'s rumble option is off — `GameConfig.rumble`
- [x] "Copying data" / autosave indicator — n/a: the GameCube saves only when you quit, and that talk carries its own "Do not turn the power off" lines; the port writes its save file then
- [~] The **name entry keyboard** for text input — see §17 keyboard entry
- [~] Nook catalog browser UI, shop buy/sell UI, bank UI, HRA letter viewer, letter writer UI — the catalog is the original `m_catalog_ovl` screen, goods come off the shelves, selling goes through the pockets, letters use the original board / address book / Is-this-OK prompt; all menus slide in and out like `mSM_move_Move` (`MenuSlide`). the bank's ABD screen (`BankOverlay`). HRA reports are ordinary letters on the GameCube (no viewer)
- [x] ~~Photo feature~~ — GCN has none
- [~] Trademark / logo / attract-mode title demo loop (`m_titledemo`, `m_trademark`, `ac_animal_logo`) — logo actor, 5 recorded demos, the demo loop, the fixed FG table, fixed villagers, apple tree and start chime landed; Nintendo logo stage skipped on purpose; gelato umbrella landed with the umbrella tool (demo 2) ([title](decomp_notes/title.md))
- [x] ~~Debug menus~~ — _out of scope_ (`m_debug*`); a dev console exists for testing

## 34. Simulation glue / world objects

- [~] FG object system: trees, rocks, flowers, weeds, signs, holes, buried marks, dropped items, structures, plot reserves (`m_bg_item`) — `WorldObjectRegistry`, `FgCatalog`
- [x] Daily FG renewal: weeds spread, plants grow, buried spots move, the money rock resets, shop restocks, turnips on the ground spoil — `field_renewed`. Shells wash up per session and every tenth minute instead (`ShellUse`, see above)
- [~] Collision: heightfield, cliff / bank walls, water, structure footprints (`m_collision_bg`) — `FieldCollision`
- [x] Blob shadows under actors & items (`m_actor_shadow`) — `ActorBlobShadow`
- [~] Effects: dust, splash, petals, footprints, manpu, weather (`StepFx`, `FieldFx`). Missing: most of the ~130 `ef_*` effects
- [~] XLU passes (water, footprints, shadows) and acre culling — `GeneratedVisual`
- [x] Balloon presents (`m_fuusen`, `ac_fuusen`) — `BalloonSky` rolls at :x3 every five minutes (5% start, +2.5–5% per miss, goods / bad luck, +25% after one got away near you); `Balloon` is born on the wind's map edge, drifts downwind 110 GX up, turns toward a bare grown tree and snags in its crown; a full shake drops the wrapped present (80% C-list furniture, else a foreign fruit), a bump wobbles it; it escapes after 10 minutes snagged or at the map edge / station. `/balloon [near]` launches one. Missing: town rank term (0), the snag sound (SE 0x402 not in the converted bank), wind gusts; drifting uses a cliff check in place of full wall collision
- [~] Wind (`m_kankyo_weather`: daily calm / normal / strong range by season, 10-minute drift, Koinobori day) — `Wind`; drives balloons only so far
- [x] Airplane: not in a GameCube town. `ac_airplane` is a paper glider the player throws (hold Z, flick the stick), placed only in the debug fields `fd1` / `fd2`
- [x] ~~Message-in-a-bottle~~ — not in GCN (`ac_mbg` is a debug model)
- [x] The lighthouse light sweeps at night and its switch turns it on and off (`ac_toudai`, `ac_lighthouse_switch`) — `lighthouse_beacon.gd`, `lighthouse_switch.gd`. The mayor's lighthouse quest period is out of scope
- [x] Windmill: not in a GameCube town. `ac_windmill` (`WINDMILL0`–`4`) exists, but no acre template on the disc places one

## 35. Multiplayer / multi-town

- [x] 4 residents share one town and one save; one plays at a time — see §1
- [x] Each resident: own house and rooms, pockets, mailbox, catalogue, encyclopedia, own designs, friendships and errands, loan, HRA, diary and calendar (`PlayerRoster.PRIVATE_KEYS`). Their plots outdoors show their house size and their gyroid runs the visitor path (buy from their store, read their message)
- [x] Residents write to each other: the other residents share the address book's first page with the Museum, and a posted letter waits on the post office desk for the next round (9:00 / 17:00, `mPO_delivery_proc`) and arrives in their mailbox as unread mail (`PostUse.resident_candidates`, `PostBook.deliver`, `PlayerRoster.deliver_mail`)
- [x] Visiting another town: two town slots (Slot A / Slot B, picked at the title), the traveller's own part in a passport; a visitor has no house there, can shop (Nookington's), gets a map from Copper, and can only leave through Porter (quitting drops the visit, like `save_menu` refusing a foreigner). The Wisp stays away from visitors
- [x] Transfer rules: pockets and cash travel in the passport and the home copy keeps none ("you took all your items and cash with you", 0x5135); a passport is used once (copied home, then deleted); someone else's passport must be overwritten at Porter's (0x095E)

---

## Content-count worksheet (pin against decomp tables)

| Set | Count (verify) | Decomp source |
| --- | --- | --- |
| Fish | 45 fish types + 5 extended catches | `aGYO_TYPE_NUM`, `aGYO_TYPE_EXTENDED_NUM`, `ac_gyoei_type.c_inc`, `ac_set_ovl_gyoei.c` |
| Insects | 40 individual types | `aINS_INSECT_TYPE_NUM`, `ac_insect_data.c_inc`, `ac_set_ovl_insect.c` |
| Fossils | ~25 items / ~13 skeletons | `ac_museum_fossil.c` |
| Paintings | 15 | `ac_museum_picture.c` |
| Gyroids | 127 | `m_melody.c`, `ac_my_room_melody.c_inc` |
| Furniture | ~1000+ | `ac_furniture_data.c_inc`, `f_furniture.c` |
| Wallpaper / carpet | ~90 each | `m_item_name.c` |
| Clothing (shirts) | ~230 | `m_item_name.c` |
| Umbrellas | 32 standard designs | `ac_t_umbrella.c` |
| Villagers (roster) | ~215 | `ac_npc_data.c_inc`, `m_name_table.c` |
| K.K. songs | 55 | `m_music_ovl.c`, `m_mscore_ovl.c`, `audioheaders.c` |
| NES games | ~15–19 | `src/static/Famicom`, `famicom_emu.c` |
| Stationery | 64 designs | `m_mail.c`, `lat_letterNN` |
| Hourly BGM tracks | 24 | `m_bgm.c` |
| Holidays / events | 117 unique event IDs / 134 schedule rows | `m_event_schedule.c_inc` |
| Calendar terms | 18 | `lb_rtc.c` |

---

_Last synced against ac-decomp `GAFE01_00` on 2026-09-07._
