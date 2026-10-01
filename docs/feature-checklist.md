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
- [ ] Up to **4 human residents** per town; pick which one you play each session (`player_select.c`)
- [ ] Create-a-character on the train (name, town name, face is derived from Rover's questions) (`ac_npc_guide`)
- [~] Character creation flow driven by Rover Q&A (`ac_npc_guide` / intro train) — `intro_train_stage.gd`
- [ ] Delete a resident / delete the town (`save_menu.c`)
- [~] Save + return to title on quit (`save_menu.c`, `m_save`) — `save_service.gd`
- [x] **House gyroid** outside each house plot is the save point (`ac_haniwa`, `ACTOR_PROP_HANIWA0`–`3`) — `scenes/world/haniwa.tscn` + `HaniwaTalk` + `HaniwaStore`: FG placement two units south of every house, `hnw_move` bob / dance speeds and turn-to-player, empty-plot freeze facing front, first-job "need a friend" line; owner menu: **Save** (walk to the door → door opens → save → title), **Store an item** (4-slot consignment table in the pockets: free / display only / for sale with a 5-digit price, take back), **Other things** → **About the door** (post one of your designs on the front door / remove it) and **Set message** (4-line visitor message, ROM default text); sale **proceeds** collected on the next talk (wallet, then 30 000-bell bags); **visitor** flow (read the message, pay and take) is in place but can't trigger in a one-resident town. `BGM_ENTER_HOUSE` is a plain BGM swap rather than a pushed demo track
- [ ] Memory Card management, copy, "the game was not saved correctly" recovery (`save_check.c_inc`, `m_flashrom`, `s_cpak`)
- [ ] **Mr. Resetti** appears at spawn if you reset without saving; escalating lectures; **Don Resetti** on repeat offences (`ac_npc_restart`)
- [ ] `zurumode` / cheat-detection "gnat" bug swarm anti-tamper behaviour (`zurumode.c`)
- [ ] RTC read, clock-not-set prompt, clock-was-changed detection & penalty (weeds, villager anger) (`lb_rtc.c`, `ac_npc_rtc`)
- [ ] "Continue where you left off" spawn point (last outdoor position / in bed)

## 2. Time, calendar, seasons

- [~] Real-time clock drives the whole simulation (`m_time`, `lb_rtc`) — `clock.gd`
- [~] Day / night with 8 lighting windows, per-term colour tables (`m_kankyo` `klight_chg_tim`) — `Clock.outdoor_light()`
- [~] Daily renewal at **06:00** (weeds spread, stock rotates, plants grow, villager moves resolve) — `field_renewed`
- [~] 18 calendar terms, years 2001–2030 (`lb_rtc`)
- [x] Seasons: snow cover Dec–Feb, cherry-blossom trees early April, coloured foliage in autumn, bare trees in winter — `VisualSeasons`, `Acre.apply_season`
- [x] Season affects grass colour / acre visuals, tree models (no river ice; snow ground) — `Clock.season`, seasonal textures from the pipeline's `seasons` kind
- [~] Weekday tracking; shop closed days; K.K. on Saturday night — K.K. on Saturday night and Joan on Sunday morning come through the event manager (§30); Nook closes for renovations
- [ ] "Played days" counter, first-day flags, "haven't played in a while" reactions
- [ ] Birthday stored per resident; birthday event

## 3. Weather & environment

- [~] Rain / snow / clear by term probability tables (`m_kankyo_weather.c_inc`) — `weather.gd`
- [x] Rain intensity: drizzle vs. downpour; snow: flurry vs. heavy — `Weather.Intensity` from `mEnv_RandomWeather`, stepped levels in `WeatherFx` (`aWeather_RenewWeatherLevel`)
- [~] Weather particles + puddles / wet sand shader — `WeatherFx`, `beach_wet.gdshader`
- [x] Snow flakes and cherry petals drawn with the disc's `ef_yuki01` / `ef_hanabira01` cards, with the decomp's spawn box, fall speed, wobble, wind drift, floor reset and petal tumble (`ac_weather_snow`, `ac_weather_sakura`) — `WeatherFx`, `weather_sprites.py`
- [x] Falling leaves: not ambient on the GameCube; `mEnv_WEATHER_LEAVES` is only used by the K.K. show (no work needed)
- [x] Rainbow after rain: a clear/sakura day after rain/snow reserves it; it fades in 9:00–15:00 in summer and fades out slowly, drawn at the waterfall as `obj_fallS_rainbowT_model` billboarded about the fall with its two-texture combiner (`mEnv_PreRainNowFine_Init`, `mEnv_rainbow_power_calc`, `ac_fallS`) — `Rainbow`, `waterfall.gd`, `fall_rainbow.gdshader`; `rainbow` console command
- [x] Fog: distance fog follows the per-time `kcolor` tables (`mEnv_SetFog`) — `Clock.outdoor_light()`; the GameCube has no separate foggy-morning weather
- [ ] Rain changes indoor & outdoor BGM; more fish/bugs (coelacanth, frogs, snails, etc.)
- [~] Lightning flashes in storms — `WeatherFx._tick_lightning` (approximate). No aurora on the GameCube
- [ ] Shooting stars (`eEC_EFFECT_SHOOTING_SET`): only on the Meteor Shower event on the GameCube, not on ordinary clear nights
- [x] Harvest Moon reflection on the pond: glides east to west 18:00–21:00, sways and ripples, with its disc/ripple combiner (`ef_night13_moon`, `ef_moon01_01_modelT`) — `PondMoon`, `pond_moon.gdshader`
- [~] Wind: balloons drift with it, the house's fish weathervane points into it and its propeller spins with its power (`aMHS_actor_draw_before`) — `Wind`, `HouseWeathervane`. The GameCube grass does not sway; `ac_windmill` / `ac_koinobori` only loop their animation; `ac_flag` (speed from wind power) is not placed yet

## 4. Town generation & geography

- [~] Procedural town: 5×6 acre grid, cliffs/terraces (3 elevations), river, waterfalls, ponds, sea + beach (`m_random_field`, `m_field_make`) — `town_field_generator.gd`
- [ ] Fixed known-seed towns (A–D style) selectable — `REFERENCE` world mode reserved
- [ ] River mouth, river forks, round pond, waterfall placement rules
- [ ] Beach along the south edge; tide; ocean horizon; rocks in surf
- [ ] Acre-edge scroll / camera hand-off between acres
- [x] Town map from the held map item (blue) or the sight-map boards (yellow), drawn like `mMP_set_dl` from the disc's `kan_win` / `kan_tizu` art: acre tiles, the selected acre's letter and number, the label frame sized to its labels, building names or residents (the player plus "free" plots; villagers by name with their house marks tinted by ground height), you-are-here mark, the easing, pulsing cursor (`m_map_ovl`) — `map_overlay.gd`, layers from `menu_ui.py` (`ui/map_screen/`); `map` console command
- [ ] Bridge(s) across the river; town can gain a second bridge (`ac_bridge_a`, `mEv_EVENT_BRIDGE_MAKE`)
- [ ] Building slots: player houses ×4, Nook's, Able Sisters, Museum, Town Hall, Post Office, Police Station, Wishing Well, Train Station, Dump, Lighthouse
- [ ] Villager house plots (up to ~15 villager homes) with reserved lots (`ac_reserve`)
- [ ] Named landmarks / the town gate & train tracks (`ac_station`, `ac_train_door`)
- [ ] Cliffs block movement; only ramps/stairs connect elevations
- [ ] "Perfect town" / environment assessment: trees, weeds, litter, flowers, permanent residents → rating; golden axe reward; special music; Jacob's-ladder / lily-of-the-valley spawn (`m_field_assessment`)

## 5. Player character

- [~] Body model, head model, face texture set (from Rover Q&A), skin/tan state (`m_player`, `m_player_draw`) — `scenes/actors/player.tscn`
- [ ] Suntan / sunburn from staying out in summer; fades over time
- [ ] Hair style / colour set by creation questions (no salon in GCN)
- [ ] Clothing: equipped shirt shows on model; hats; accessories/glasses; umbrella held in rain (`m_player_item_umbrella`) — umbrella done (see Umbrella)
- [x] Change clothes anywhere from pockets — "Wear" swaps inside the menu (`Game.wear_cloth_from_slot`). `m_player_main_change_cloth` / `ef_kigae` is the shop try-on and the Halloween prank, not the pockets
- [x] Pockets = **15 item slots** + separate wallet (`m_private` `mPr_POCKETS_SLOT_COUNT`) — `inventory.gd` (duplicate of the line below, kept in sync)
- [ ] Carrying a piece of furniture / large item in hands (walk slower) (`m_player_main_hold`, `pickup_furniture`)
- [x] Trip / stumble when running into things or on ants (`m_player_main_tumble`, `stung`) — `player.gd` `TUMBLE` gaits + `_tumble_events`
- [x] Fall in a pitfall; struggle out (`m_player_main_fall_pitfall`, `struggle_pitfall`, `climbup_pitfall`) — `Player.run_pitfall`; seeds are buried with the pockets' "Bury" (shovel + hole, `mTG_TYPE_FIELD_DEFAULT_BURY`) into `BuriedUse` `KIND_PITFALL`; villagers fall in too and climb out when talked to (`aNPC_act_pitfall` / `revive`)
- [x] Get stung by bees → swollen face; villagers react (`m_player_main_stung_bee`, `notice_bee`, `mNpc_SetTalkBee`) — `Player.run_stung_bee`, `PlayerFace`, `Game.bee_*`, `DialogueGreeting` `BEE_STUNG` / `BEE_CHASE`. The swell lasts until the game is reset (common data); GCN has no medicine
- [x] Mosquito bites in summer (`ac_ins_ka`, `stung_mosquito`, `notice_mosquito`) — `BugKa` bite → `BugField.take_bite` → `Player.run_stung_mosquito` (`MSG_12387`)
- [ ] ~~Tired / sleepy animations late at night~~ — GCN `m_player_main_tired` only follows `wash_car`; there is no late-night tiredness
- [~] Push / pull furniture and snowballs (`m_player_main_push`, `push_snowball`) — furniture done (`FurnitureGrip`); snowballs not yet
- [x] Sit on benches/chairs (`m_player_main_sitdown`) — `FurnitureSeat`
- [~] Lie in bed / roll in bed / stand up from bed → save (`m_player_main_lie_bed`, `roll_bed`) — in/out of bed and the bed wait done; rolling not yet
- [x] Wade across acre borders (`m_player_main_wade`) — `AcreWade`, `Player._begin_wade`
- [x] Radio-exercise / morning aerobics participation (`m_player_main_radio_exercise`) — `RadioExercise` C-stick patterns (right stick or I/J/K/L) → `Player.run_radio_exercise`, on the shrine acre during aerobics or by the aerobics radio
- [ ] ~~Emotions menu~~ — GCN has no player emotion menu (later games); `ef_warau` / `ef_naku` / `ef_pun` are villager manpu, done with dialogue

## 6. Camera

- [~] 3/4 fixed-angle follow camera, ~20° FOV, ~45°, focus distance 620 (`m_camera2`) — `follow_camera` / `FollowCamera`
- [ ] Camera rotates 90° per acre / snaps to acre orientation
- [~] Special cameras: door enter/exit, talking, sitting, fishing show-off, demos — `door_camera.gd`, `talk_camera.gd`
- [ ] C-stick / look controls (if any); pause zoom
- [ ] Cutscene / `m_demo` director for events (`m_demo.c`)

## 7. Movement & locomotion

- [~] Analog walk (~4.875 u/frame) and run (~7.5 u/frame); B / L / R to dash (`m_player_main_walk`, `run`, `dash`) — `player_locomotion.gd`
- [~] Turn-in-place, dash turn, skid (`turn_dash`) — partial
- [ ] Trample flowers when running through them (they wilt); walking is safe
- [~] Grass wears into dirt paths where you walk repeatedly; regrows slowly (`ac_field_draw` wear) — _(check)_
- [~] Per-foot footprints on sand/snow, slope-fit, ~160-frame fade (`ef_footprint`) — `footprint_marks.gd`
- [ ] Slip on ice / banana peels (`m_player_main_slip_net`? / ice)
- [ ] Bump / knock-back off buildings, signs, rocks; slide along cliff & water edges
- [ ] Fall off a cliff edge → short drop (`m_player_main_fall`)

## 8. Interaction system (Field A button)

- [~] Context verb chosen from nearby actor + equipment: pick up, talk, shake, sit, read, open door, dig, etc. (`m_player` Field A) — `interaction.gd`, `interaction_query.gd`
- [~] Pick up dropped items / fruit / shells off the ground (`m_player_main_pickup`) — partial
- [~] Talk to villagers & special NPCs (`m_player_main_talk`) — partial
- [~] Shake trees (fruit, furniture, bells, bees, wasp nest) (`m_player_main_shake_tree`) — `tree_use.gd`
- [~] Push signs to read; read bulletin board; read gravestones/signposts (`ac_sign`) — community board (`MESSAGE_BOARD0`, `obj_*_notice`) is placed from the FG templates and hosts the first-job "post a notice" chore and opens the board's posts (`NoticeBoardOverlay`, §26). Sight-map boards (`MAP_BOARD0`) open the town map without needing the item; tune boards (`MUSIC_BOARD0`) open the town tune editor; fences (`FENCE0` / `WOOD_FENCE`) are solid props; the station statue (`DOUZOU`) is placed and shows once a house reaches the statue (§26)
- [~] Knock on villager doors (`m_player_main_knock_door`)
- [~] Enter/exit buildings: step-in animation, door swing, screen wipe (`m_player_main_door`) — `structure_door.gd`, `scene_transition.gd`
- [ ] Hand an item to a villager / receive an item (give / recieve animations) (`m_player_main_give`, `recieve`, `ac_handOverItem`)
- [ ] Refuse / decline prompt (`m_player_main_refuse`)
- [ ] Pick fruit vs. shake whole tree distinction
- [ ] Pluck weeds (`m_player_main_remove_grass`)
- [ ] Pick / dig up flowers; pick mushrooms (`m_mushroom`)
- [ ] Talk to your own reflection / gyroids / pets? (gyroid greeting)

## 9. Tools

- [~] **Net** — hold A to ready, creep, skid out of a dash, release to swing; tick-exact catch sphere from keyframe 6; wall / ground / villager strike cuts the swing (`AMI_HIT`); empty swing → `STOP_NET` (`m_player_item_net`, `m_player_main_{ready,ready_walk,slip,swing,stop}_net`) — `net_swing.gd`, `netting.gd`. Missing: catching bees (`ac_bee` is still a placeholder), golden net, swing effects
- [~] **Fishing rod** — see §13 (`m_player_item_rod`) — `fishing.gd` (substantial)
- [ ] **Shovel** — dig holes, bury items, dig fossils/gyroids/pitfalls, hit rocks, plant trees, whack villagers, reflect off stone (`m_player_item_scoop`, `dig_scoop`, `fill_scoop`, `reflect_scoop`) — `hole_use.gd`, `buried_use.gd` _(partial)_
- [ ] **Axe** — chop trees (multi-hit → stump), break on overuse, golden axe never breaks (`m_player_item_axe`, `swing_axe`, `broken_axe`, `ef_break_axe`) — `tree_use.gd` _(partial)_
- [ ] **Fishing rod / net / axe / shovel** durability & the **golden** variants (golden axe from perfect town, golden rod/net/shovel from milestones) (`demo_get_golden_item`)
- [ ] **Slingshot** — _not in the GameCube game_ (balloons snag in trees instead; see §33 balloons)
- [ ] **Watering can** — _not in GCN_ (villagers water flowers themselves; skip)
- [~] **Umbrella** — held in rain/snow, twirl, many designs (`m_player_item_umbrella`, `rotate_umbrella`) — `HeldUmbrella` + 32 `ToolData` umbrellas (`data/items/umbrellas/`, ROM names/prices): opens out of the hand (`UMB_OPEN1`, handle/canopy scale tables), right arm holds `ply_1_umbrella1` over walk/idle (`PART_TABLE_NET`), A twirls (`UMB_ROT1` + SE 0x432), folds away through doors / on unequip (`UMB_CLOSE1`), switches the rain loop to the under-umbrella one; Nook stocks one a day on the umbrella stand; title demo 2 carries the gelato umbrella. Missing: design umbrellas (`ITM_MY_ORG_UMBRELLA0-7`), the `KASAMIZU` twirl spray (no effect system)
- [ ] **Fan / uchiwa** (festival), **timer**, **party popper / clacker**, **handbill**, **pitfall seed** as usable items (`m_player_item_fan`, `ac_t_utiwa`, `ef_clacker`)
- [~] **Bug / fish held up** show-off pose + species report (`m_player_main_notice_net`, `notice_rod`) — net: pull (`GET_M1`, report at 50 ticks, turn past keyframe 17), notice (pockets + catch record, collection-complete 0xA4E/0xA4F + `YATTA2`, full-pockets 0xA4D), put-away (`PUTAWAY_M1`, shrink to keyframe 17). Missing: exchange inventory, fanfares, release clip
- [ ] Held tool renders on the right hand with its own animation clips (`Player_actor_Item_draw`, `mPlayer_JOINT_HAND`) — `held_tool.gd`
- [ ] Tool ready ↔ put-away transitions and SE for every tool (`putaway_*`, `ready_*`)
- [ ] Wetsuit / diving — _not in GCN_ (skip)

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
- [~] Wallet (bells) separate; 30,000-bell bag stacks — withdraw (`mTG_select_tag_decide_money`
  affordability-gated denomination picker) and deposit (drop a bag on the wallet slot, or the
  pre-existing "Use" verb) both work. Missing: an actual bank/ABD terminal UI — `deposit_savings`/
  `withdraw_savings` exist on `Inventory` but nothing in-scene calls them yet.
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
- [~] **Catalog** of every item you've ever owned/received; order from catalog at Nook's (`m_catalog_ovl`) — `CatalogBook`: furniture / clothing / wallpaper / carpet / stationery / umbrellas register as they reach the pockets (`mSP_CollectCheck`); Nook takes up to 5 paid orders that arrive enclosed in a letter the next morning (`mPO_delivery_mail_with_order_ftr`). Missing: the catalog browser pages (orders use the shop paper list), non-orderable flags beyond "rare"
- [ ] Item data tables: furniture, clothing, wallpaper, carpet, umbrellas, tools, stationery, fruit, shells, fossils, gyroids, paintings, music, misc (`m_item_name`, `ac_furniture_data`)
- [ ] Fruit: native fruit per town + non-native (apple, orange, peach, pear, cherry); coconut on beach palms
- [ ] Perfect fruit? _(not in GCN — skip)_
- [ ] Sea shells wash up on the beach on a timer; sell to Nook / Tommy (`ac_mbg` beach items) — shell prices are in `mSP_ItemNo2ItemPrice` (160/80/600/120/240/1800/1400/1000) for when the items exist
- [ ] Furniture "in hand" vs. "as item" states; wallpaper/carpet items
- [~] Wrapping paper — wrap/unwrap a droppable item as a present (`Inventory.wrap_slot`, the
  "Wrap" tag) works; attaching a wrapped gift to outgoing mail depends on the mail-writer UI
  and isn't wired up yet (`ac_present_demo`)
- [~] Lost items / forgotten items handling — `PoliceBook.keep_item` / `keep_all_items` (`mPB_keep_item` / `mPB_keep_all_item_in_block`) and the 06:00 top-up exist; the field callers that turn items in (structures built over them, event clean-ups, snowmen, house moves) are not wired yet

## 11. Economy

- [ ] Bells as currency; wallet cap; 30k bags
- [x] **Post Office bank (ABD)**: the clerk's deposit line opens the terminal from the disc's `tyo_win` art — Cash (wallet plus money bags), a six-digit amount picked digit by digit, Balance to 999,999,999, Deposit / Withdrawal lit by direction; settling spends bags first and pays cash over the wallet cap as 30,000-bell bags; she then reads out the balance (`m_bank_ovl`, `aPG_deposit_*`) — `BankOverlay`, `BankTerminal`; `abd` console command. No interest on the GameCube: the post office mails a gift at 1M / 10M / 100M / 999,999,999 Bells, one per game start (`mMl_send_postoffice_mail`)
- [ ] **Tom Nook home loan**: 4 (or 5) escalating amounts; pay any amount; statue/"paid off" reward; house expands on payoff (`m_repay_ovl`, `mQst` house upgrade)
- [ ] House sizes: small house (4×4) → medium (6×6) → large (8×8) → upper floor (2nd floor); basement is a separate unlock, and no side/back rooms or mansion exist in GCN (`m_home`, `m_house`, room types)
- [x] **HRA — Happy Room Academy**: welcome letter, then at game start a scored letter the day after the layout changes (or a 2-in-10 tip otherwise): points by origin, necessities, base / theme / set series with matching wallpaper and carpet, lucky pieces, facing the wall, theme obstacles; rewards at 70,000 / 100,000 (house and manor models); wing paper (`m_mark_room`, `m_mark_room_ovl`) — `HappyRoomAcademy`, tables from `hra.py`. Missing: the clutter rule's loose items (rooms don't hold loose items yet). Feng shui (`m_huusui_room`) only feeds money / goods luck and isn't built
- [ ] Feng shui: colour-by-direction bonuses (`m_huusui_room_ovl`)
- [~] Selling: Nook buys almost anything at set prices; fish/bugs/fossils/paintings prices; foreign fruit premium — `ShopBook.sell_result`: catalog price / 4, foreign fruit 2000 / 4 (`Game.town_fruit`), worthless items taken for free, quest items refused, 30,000-bell bags when the wallet overflows (refused with no room), half the payout counts toward Nook's sales. Missing: shell / fossil / painting price data
- [~] Turnip market (**Stalk Market**): Sow Joan sells turnips Sunday AM; Nook buys at fluctuating daily price; turnips rot after a week; spoiled-turnip uses (`m_kabu_manager`, `ac_ev_kabuPeddler`, `ac_yomise`) — `KabuMarket` ports `Kabu_manager` (Sunday price 70–129, spike ×8 / random / falling trends with the decomp's transition odds; one price per day, not AM/PM, in GCN); Nook quotes it under "Other things" and buys 10/50/100 bundles (never on Sunday), spoiled turnips as junk. Missing: Joan, turnips spoiling on the ground (`mAGrw_SpoilKabu`)
- [x] Lottery / raffle at Nook's on the last day of the month (`mEv_EVENT_LOTTERY`) — see §21
- [x] Nook's point card / "Nook Points" — _not in GCN_ (`m_shop.c` has only raffle tickets); skip
- [ ] Flea market? — _not in GCN_ (skip)

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
- [ ] **45 fish types** plus **5 extended fishing catches** (whale, empty can, boot, old tire, salmon2), with month × time-of-day × water-type availability + rarity (`aGYO_TYPE_NUM`, `aGYO_TYPE_EXTENDED_NUM`, `ac_set_ovl_gyoei`, `ac_gyoei_type.c_inc`)
- [ ] Half-month term split + transition ramp for spawn weights (`gyoei_term`)
- [ ] Water types: river, river mouth, pond, waterfall pool, sea, island (`aSOG_RANGE_PROC_*`)
- [ ] Coelacanth only while raining/snowing, in the sea, outside the day slot (`aSOG_add_kaseki_range_data`)
- [ ] Non-fish catches: boot, tire, tin can, seaweed? _(verify GCN junk list)_
- [ ] Trash items (boot/can/tire) as furniture-less junk, sellable to Nook
- [ ] Fishing tourney (June & November Sundays), Chip judges, biggest fish wins furniture (`mEv_EVENT_FISHING_TOURNEY_1/2`, `ac_turi_npc0`, `ac_ev_angler`)
- [ ] Fish records board / "biggest catch" tracking (`m_fishrecord`)

## 13. Bug catching

- [~] Net swing hitbox, timing, whiff, bug flees (`ac_insect`, `ac_npc_act_chase_insect`) — `aINS_set_catch_range` (24 / 8 GX, facing gate from insect → player angle) + one-frame `Check_StopNet` panic — `net_swing.gd`, `bug_field.gd`, `bug_actor.gd`. Villagers chase bugs and fish shadows (`aNPC_ACT_CHASE_INSECT`, `VillagerOutdoor`)
- [~] Bug spawn tables by month / time / habitat (tree trunk, flying, on flowers, on the ground, in the ground (mole cricket), by water, tree stumps, rotten food, street lamps at night) (`ac_set_ovl_insect`, `ac_insect_data`) — `bug_catalog.gd`, `bug_habitats.gd`
- [ ] **40 individual insect types** (`aINS_INSECT_TYPE_NUM`): butterflies, cicadas, bees/wasps, dragonflies, locusts, crickets, beetles, ladybugs, mantis, tarantula, firefly, cockroach, snail, mole cricket, pond skater, bagworm, pill bug, spider, ant, and mosquito (`ac_insect_h.h`, `ac_insect_data.c_inc`)
- [ ] Bee swarm from a shaken tree chases you; hide indoors or net them; sting → swollen face (`ac_bee`, `bee_swarm.gd`)
- [ ] Wasp nest drops from tree; getting stung (`ac_bee` variant)
- [ ] Tarantula aggressive chase behaviour at night
- [ ] Firefly glow at night near water in summer
- [ ] Cicada shells on trees; cicadas fly off when you approach
- [ ] Bug sounds are directional and time-gated (crickets at night, cicadas by day)
- [ ] Ants swarm on dropped rotten food / candy (`ac_ant`)
- [x] Cockroaches in a house left closed too long; stomp them (`m_cockroach`, `ac_house_goki`) — see §18
- [ ] Bug-off / bug tourney? _(GCN has no dedicated bug tourney — verify; fishing only)_

## 14. Digging, buried items, rocks

- [~] Dig a hole on empty ground; fill a hole (`DIG_SCOOP`, `FILL_SCOOP`, `HOLE00`–`HOLE24`) — `hole_use.gd`, `scenes/world/hole.tscn`
- [x] Bury an item in a hole; dig it back up (`mTG_TYPE_FIELD_DEFAULT_BURY`, `bIT_common_hole_throw`) — pockets "Bury" → `BuriedUse.bury` (`KIND_ITEM` shows the crack)
- [ ] Buried "X" marks / glowing spot: one per day → **fossil** or **bells** or **gyroid** or (after rain) more gyroids (`ac_gyo_kaseki` naming aside — fossils via FG)
- [ ] Money spot: dig up 100 bells, replant bells (100–30,000) → money tree grows bags of bells once (`m_all_grow` money tree)
- [ ] **Rock**: one random rock per day yields bells when hit with the shovel (up to ~8 hits, escalating, timed, must not be blocked from behind) — the "money rock"
- [ ] Rocks are otherwise immovable obstacles; fake rock? _(GCN: no)_
- [x] **Pitfall**: bury a pitfall seed in a hole → invisible trap; player/villager falls in (`BURIED_PITFALL_HOLE`, `bIT_actor_pit_*`, `m_player_main_*_pitfall`) — the pit opens under them and closes after
- [ ] **Gyroids**: ~127 gyroid variants _(verify)_, dug up after rain, wind up as playable furniture that hums/beats with room music (`ac_my_room_melody`, `m_melody`)
- [ ] **Fossils**: dig up unidentified → Blathers assesses → real fossil (donate or sell); fossil groups (T. rex, mammoth, etc.) _(verify count, ~25 items)_
- [ ] Shovel reflects with a clang off stone / the museum wall / certain FG (`reflect_scoop`)
- [ ] Groundhog Day: dig near the shrine? (`ac_groundhog_control`, `ac_ghog`)

## 15. Plants & flora

- [~] Trees: sapling → young → full; needs a clear 3×3-ish space or it won't grow (`m_all_grow`, `mAGrw_RenewalFgItem`) — `plant_growth.gd`
- [~] Daily growth resolves at 06:00 (`planted_renew`) — `Game.plant_states`
- [~] Shake tree: fruit (3), or furniture/bells/bag (non-fruit trees, 1/day), or bees (`shake_content`) — `tree_use.gd`
- [~] Chop tree with axe → multi-hit → falls → stump; stumps can grow mushrooms / be sat on; dig up stump (`bg_item` cut) — `tree_use.gd`
- [ ] Fruit trees: apple, orange, peach, pear, cherry, coconut (beach), + native designation
- [ ] Plant fruit → fruit tree; plant a sapling item → tree; plant money → money tree
- [ ] Cedar/pine trees (conifers) vs. hardwoods; cedar only grows in certain acres; Christmas-tree lights in December
- [ ] Cherry-blossom bloom skin on hardwoods Apr 1–10ish
- [ ] Tree count affects environment rating; too many/too few penalised
- [ ] **Flowers**: red/white/yellow tulips, pansies, roses, cosmos, dandelions, sunflowers _(verify GCN species)_
- [ ] Flowers from Nook (bags of seeds), Tortimer, HRA, events, or dug up
- [ ] Flowers wilt without water; villagers & the player? water them; rain waters all
- [ ] Flower breeding: adjacent flowers spawn a new flower, sometimes a **hybrid** colour (black/blue/purple roses, etc.)
- [ ] Trampled flowers (running) wilt; wilted flowers revive with water or die
- [ ] Dandelions → puff stage → blow away; four-leaf clovers rare pickup
- [ ] Weeds: spread daily, faster if you don't play; pull for nothing (or sell tiny); too many → poor rating & villager complaints
- [ ] Pull-all-weeds errand / Nature Day
- [ ] Mushrooms: appear in autumn (mid-Oct) around trees/stumps; common + rare + rare furniture; some poisonous-looking (`m_mushroom`, `mEv_EVENT_MUSHROOM_SEASON`)
- [ ] "Jacob's ladder" & "lily of the valley" spawn only in a perfect-rated town
- [~] Lotus / water lilies in ponds (`ac_lotus`) — FG `LOTUS` places `lotus.tscn`: leaf sway on the baked clip, flower drawn May 26 – Aug 25. Pad / flower colours are placeholders (palette is `aLOT_obj_0N_lotus_pal` per term, not baked); no bobber shake. Lotus as an item still missing
- [ ] Coconut palms on the beach; coconuts plantable only on the beach
- [ ] Cherry / persimmon / other decorative? _(verify)_

## 16. Villagers (animal residents)

- [~] One NPC actor, behaviour driven by "looks"/personality tables (`m_npc`, `ac_npc`) — `villager.tscn`, `villager_ai.gd`
- [x] Up to **15 villagers** (starts at 6, one move-in per day at most); 236 animals in the GCN roster
- [ ] Personalities: **Normal, Peppy, Snooty, Cranky, Lazy, Jock** (6); + Big Sister/Uchi? — _no, GCN is 6_ — `personalities/`
- [ ] Species models: cat, dog, rabbit, squirrel, bear, cub, pig, cow, bull, horse, sheep, goat, wolf, dog, duck, chicken, ostrich, penguin, eagle, elephant, rhino, hippo, gorilla, monkey, koala, kangaroo, anteater, alligator, frog, octopus, deer, mouse, hamster, tiger, lion, chameleon? _(verify GCN species list)_ — `generated_visual.attach_villager`
- [~] Daily schedules per personality: wake, wander acres, visit shops, go to specific acres (shrine / friend's house / own house), sleep (`m_npc_schedule`, `ac_npc_schedule_*`) — `villager_schedule.gd`
- [~] Field roam: pathing between goal acres, walker cap (`m_npc_walk`) — `villager_walk.gd`, `villager_motor.gd`
- [~] Appear indoors when awake at home; asleep = off the map (`ac_npc_think_sleep`) — `villager_home.gd`
- [~] Head/eyes track the player when near (`ac_npc_head`) — `npc_head_look.gd`
- [~] Face: texture-swap eyes & mouth; blink bursts; emotion holds; mouth flap while talking (`ac_npc_anime`, `aNPC_check_kutipaku`) — `npc_face.gd`, `npc_face_anim.gd`
- [~] Feel glyphs (manpu) above head: laugh cards, shock, "!", lightbulb, sweat, anger, sleep-Zzz, love hearts (`ef_warau`, `ef_shock`, `ef_ha`, `ef_hirameki`, `ef_lovelove`, …) — `npc_manpu.gd`, `npc_feel_glyphs`
- [ ] Full manpu set: `KONPU`, `PUN_YUGE`, `DOYON`, `GIMONHU`, `KANTANHU`, `NAMIDA`, `NEBOKE`, `MUKA`, etc.
- [~] Activities villagers do (`ac_npc_act_*`): clap when you show off a catch, chase bugs / watch fish shadows (`VillagerOutdoor`). The GCN field villager has no fishing / singing / reading acts of its own. greet each other in passing (`aNPC_ACT_GREETING`, `VillagerGreeting`) with the trend / catchphrase / mood reactions. Missing: running after the ball
- [ ] Villager catches a bug/fish and shows it off; asks you to catch something
- [x] Umbrella open/close in rain (`ac_npc_act_umb_open/close`, `aNPC_ctrl_umbrella`) — their own `npc_def_list` umbrella, one opening at a time, `UMBRELLA1` arm pose. Missing: Able-design umbrellas in hand
- [x] Villager falls in your pitfall; talking to them gets them out (`ac_npc_act_pitfall`, `aNPC_act_revive`, feel `PITFALL` → `MSG_8327`)
- [ ] Hitting a villager with the net/axe/shovel → anger, "watch it!" (`m_watch_my_step`)
- [x] **Moving in**: new villager on a free SIGN plot, introduces self on first meeting (`mNpc_Grow`, `MSG_11573`) — `town_residents.gd`. GCN has no moving boxes
- [~] **Moving out**: full town + 10 days → fewest-memories villager leaves with a goodbye letter (`mNpc_ForceRemove`) — `town_residents.gd`. The "thinking of moving" talk (`remove_animal_idx`) is picked but its dialogue isn't wired (only matters for card transfer)
- [x] Move-in / move-out cadence tied to friendship, time played, town population (`mNpc_CheckGrow`, `mNpc_ForceRemove`)
- [~] **Friendship** per resident: s8 0–127 starting at 1, best-friend at 80, moved by "Let's talk!", message orders, letters and quests (`Anmmem_c`, `mNpc_AddFriendship`) — `relationship.gd`, `villager_talk_manager.gd`
- [ ] Villager **memory**: last time you spoke, letters exchanged, favours done, gifts, whether you've been mean (`Anmmem_c`)
- [ ] Nicknames: villager gives you a nickname; you can set what villagers call each other / call you; catchphrase ("hippie", etc.); you can change a villager's catchphrase
- [ ] Greetings you can teach; greeting spreads between villagers
- [~] Gift-giving both ways: letters with presents (+3), villager replies with a present half the time, Valentine's letters with gifts (`mNpc_SendMailtoNpc`, `mNpc_Remail`, `mNpc_SendVtdayMail`) — `villager_letters.gd`. Handing gifts in person and villagers wearing gifted shirts still to come
- [~] **Villager quests** — deliveries (clothes / lost items), errand chains (fetch what they lent), contests (fruit, fish, bug, flowers, letter; ball and snowman offered but not completable), deadlines, give-up, rewards (`m_quest.c`, `ac_quest_talk_init.c`, `ac_quest_manager.c`) — `villager_quests.gd`, `villager_talk_manager.gd`. Missing: wishing well disposal, ball / snowman actors
- [~] Trading furniture / clothing with villagers (chat trades: `aQMgr_order_decide_trade` / `_trade`) — `villager_talk_manager.gd`. Goods come from the shop pools, not the ROM A/B/C lists; no hand-over animation yet
- [x] Villager asks to buy something from your pockets / sell you something (chat trade topics)
- [ ] Villager house interiors themed by personality; changes over time with items you give
- [ ] Sick villagers → give medicine (from Nook) → friendship boost
- [ ] Villager games: hide and seek, "which hand", quizzes, "what am I thinking" (`ac_npc` talk minigames)
- [ ] Villager sings K.K. songs / hums the town tune
- [ ] Villager reactions to your appearance: bee-stung face, bad haircut (n/a), new shirt, holding furniture, being naked, wearing a hat/mask
- [ ] Villager comments on weeds, litter, flowers, your house, the town rating, holidays, weather, time of day, your birthday
- [ ] Special personality: **Cranky→mellows**, **Snooty→warms** as friendship rises

## 17. Dialogue & text

- [x] Message window: cloud and nameplate rasterised from `con_kaiwa2_modelT` / `con_kaiwaname_modelT` and tinted (235, 255, 235) like `mMsg_DrawWindowBody`, NES I4 font atlas, 18-frame scale in/out, the disc's `FONT_nes_tex_next` turn mark in blue with the triangle-wave alpha (`m_msg`, `m_msg_draw_window`) — `message_window_chrome.gd`, `MessageBody`, dialogue overlay
- [x] Typewriter per frame like `mMsg_Main_Cursol_ControlCursol` (a glyph every other frame, fast text, PAUSE waits, SETCURSORJUST timing), speaker-sex nameplate colour (`m_msg_draw_font`) — `dialogue_overlay.gd`
- [x] Choice panel: `con_waku_swaku3` window, the disc's `FONT_nes_tex_choice` mark in (0, 195, 185), scale in/out (`m_choice`) — `choice_panel`, `message_choice_mark.gd`
- [~] Dialogue data + runner + conditions; greeting picks opening line (`m_string`, `DialogueGreeting`) — `dialogue_runner.gd`, `dialogue_catalog.gd`
- [ ] Full message-bank coverage: villagers (per personality × mood × topic), special NPCs, signs, letters, system prompts
- [x] Text effects from the message codes: colour (`TEXTCOLOR` / `COLORCHARS`), size about the line type's pivot (`CHARSCALE` / `LINESCALE` / `LINETYPE`), `LINEOFS`, `PAUSE`, `SNDTRGSYS` sounds, `CAPTIALIZE`, `CUTARTICLE`, player / town / catchphrase / item / free-string substitution; pages that turn themselves (`MSGCLEAR`) or on a timer (`MSGTIMEEND`). GCN has no shake code; icon glyphs are font cells
- [ ] **Animalese** voice synthesis per syllable, pitch by speaker (`jaudio` seqs 243–245) — `dialogue_voice.gd` _(partial)_
- [~] Keyboard entry (`m_editor_ovl` pad keyboard, `KeyboardPanel`): letters and the gyroid board (`LetterWriterOverlay`), names — design / album folder / catchphrase / song request (`NameEntryOverlay`). the town tune editor (`TownTuneOverlay`), the community board's posts (`NoticeBoardOverlay`)
- [ ] Word-filter / bad-word list for user text (`m_editEndChk_ovl`)
- [~] "..." silent responses; scrolling long letters; page-turn SE — page-turn SE (`page_okuri`, skipped on `BTN2` / `SNDNOPAGE` pages); a mid-page `BTN` stops with the turn mark and A writes on in the same page (`{btn}`) and the letter board's roll while writing (`mBD_roll_control`)

## 18. Player house & interiors

- [~] Small house on day 1 (4×4 interior); upgrades via Nook loans to medium (6×6), large (8×8), and upper floor (2nd floor, 6×6); basement is a separate unlock (49,800 bells). The statue is a reward state, not a room size; no side/back rooms, mansion, or attic exist in GCN — `PlayerHouse` / `HouseUpgrade` / `NookHouseTalk`: next-day builds, loans (148k / 398k / 798k / 49.8k), statue offer, statue actor (§26). Missing: roof colour recolour
- [ ] Room = grid; place furniture on floor, against walls, on tables (`ac_arrange_room`, `ac_arrange_ftr`)
- [ ] Wallpaper + carpet per room; ceiling? (no)
- [~] Furniture rotate (4 or 8 orientations), stack on surfaces, put items on tables (`m_player_main_rotate_furniture`, `rotate_octagon`) — `FurnitureGrip`: A-grip + stick push / pull / turn about the held end, B pick-up, sit / lie by walking in, per-floor furniture cap; missing: bubu puff, bed rolling, octagon (gyroid) rotation
- [ ] Wall-mounted items (paintings, clocks, wall clock ticking `ac_house_clock`); rugs
- [~] Interior editing mode / catalog reorder; "store in Nook's" / storage — dresser / wardrobe / closet conversations (`FurnitureStorage`)
- [~] Music player furniture (stereo/radio/etc.) plays a chosen K.K. song; gyroids beat along (`ac_radio`, `ac_my_room_melody`) — `FurnitureMusic` / `MinidiskCatalog`: discs, music box, one player at a time, aerobics radio, gyroid hop; missing: song titles, K.K. as the disc source, gyroid voices
- [ ] Lighting: lamps light up at night; some furniture is interactive (sit, lie, TV static `famicom_emu`, fireplace, fountain, toilet, bath `ef_furo_yuge`)
- [ ] Doorplate / house nameplate (`ac_nameplate`)
- [~] Basement = free storage room once unlocked — orderable at Nook's after the medium loan; decorates like any floor
- [~] House exterior model changes with size; door mat; roof — `obj_{s,w}_myhome1..4` by size, fish weathervane / insect plaque via `CompleteTalk`; palette recolour not rendered
- [ ] Move house location? _(GCN: no)_
- [~] Cockroaches spawn if you don't play for weeks; house dusty — `HouseGoki` / `house_goki.gd`: 6-day rule, up to 3 out, furniture flushes, startle, stomp; missing: death puff, cottage, dust
- [x] HRA judges the main room, and the upper floor in part (origins, sets, luck, facing, clutter); never the basement (§11)
- [ ] Other residents' houses in your town enterable? _(only the one you play; others are just exteriors + villager homes)_

## 19. Furniture & collectibles

- [ ] Full furniture DB with series/sets, sizes, HRA points, feng-shui colour, sell price (`ac_furniture_data`, `f_furniture.c`)
- [ ] Series: e.g. Classic, Modern, Regal, Ranch, Cabin/Cabana, Exotic, Blue, Green, Kiddie, Lovely, Snowman, Mushroom, Robo, Spooky, Harvest, Jingle/Festive, Space, Pavé? _(verify GCN series list)_
- [x] Themed sets award HRA bonus when all present + matching wallpaper/carpet — `HappyRoomAcademy`
- [ ] Special/rare: Nintendo items (famicom, N64, GameCube, Mario/Zelda/Metroid themed), Trophies, King Tut mask, models, instruments
- [ ] **NES/Famicom consoles as furniture** → playable games (see §26)
- [ ] Gyroid furniture (§14): the giant collection; each has an on/off wind state and a sound
- [ ] Musical instruments you can play? _(GCN: no free-play)_
- [ ] Snowman series: build a perfect snowman → mails you a Snowman-series item over the following days (`ac_snowman`, `ac_psnowman`, `m_snowman`)
- [ ] Feng-shui / lucky items
- [ ] Furniture obtained from: Nook's shop, catalog order, villagers, events, HRA, balloons, fishing/bug tourneys, lost-and-found, Redd, Saharah (carpets/wallpaper), fortune (Katrina n/a in GCN)
- [ ] Wallpaper & carpet catalog; special ones (mosaic wall, etc.)

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
- [~] Apply patterns as: shirt, hat, umbrella, wallpaper?, or place on the ground / as signboards / hung on walls — shirt (design book "C" wear, `cloth.idx >= CLOTH_NUM + 1`) and the house-door design (§1 gyroid) work; design umbrellas (`ITM_MY_ORG_UMBRELLA0-7`, dragging a design onto the umbrella slot) not yet
- [x] The **Able Sisters** design display board: put your design on a mannequin / stand, take a copy of one, or swap (§22); villagers pick the displayed designs up (§22 trends)
- [ ] "Pro" designs? _(GCN: no pro designs)_
- [ ] Wendell / Saharah / gypsy hand you free patterns (`ac_ev_designer`, `ac_broker_design`)
- [x] Design storage (`m_cporiginal_ovl`): the Able Sisters design album, 8 folders × 12 (§22). `m_cpedit_ovl` is the Memory Card copy/edit shell around it — no Memory Card layer in the port
- [ ] Town flag design (on the flagpole at the station) (`ac_flag`)
- [ ] e-Reader design cards import (§28)

## 21. Nook's store

- [x] 4 building types over time + purchase volume: **Nook's Cranny → Nook 'n' Go → Nookway → Nookington's**; upgrades at 25,000 / 90,000 / 240,000 bells, with Nookington's also requiring a visiting foreign player (`ac_shop_level`, `m_shop`) — `ShopBook`: stored level (`shop_info.shop_level`), sales capped at the next threshold until the upgrade lands (`mSP_PlusSales`), a renovation booked two days out once earned (`aSL_JudgeRenewShop`, never across raffle day or Sale Day, cancelled if the clock runs backwards), closed for renovations from opening time the day before, reopening upgraded at the new building's opening hour; renovation-notice and grand-opening letters; `visitor` flag gates Nookington's (`shop visitor` debug command until multi-town visits exist). `shop0`–`shop3` interiors
- [ ] Nookington's has a second floor with Timmy & Tommy; requires a friend from another town to visit to trigger the final upgrade — `shop3_2` room exists; Timmy & Tommy (`ac_npc_mamedanuki`, they share the shop-master code) not yet placed
- [x] Daily stock (`mSP_MakeGoodsList`, `ac_shop_goods`) — `ShopGoods.roll`: per-level counts (`l_zakka/conbini/super/dsuper_goods`), Cranny tools unlocked by sales (net 3k / rod 8k / axe 12k), Nookway+ paint (colour rotates each restock) + signboard + cedar sapling + rare-furniture slot (`ItemData.shop_rare`), stationery as a 4-sheet pad, distinct flower-seed bags, one umbrella, Halloween candy (Oct 16–30), Sale Day grab bags priced at the year (open with three free slots: rare goods or a pinwheel). Missing: the ABC rarity lists (`mSP_GetGoodsPercent`), which need the full ROM item lists; seed bags plant pansies until flower species exist
- [x] Stock rotates at 06:00; sells out; sold-out slot shows empty
- [x] Sell items to Nook (he names a price, you confirm); can't sell some things — counter menu "I want to sell" opens the pockets in sell mode (`mSM_IV_OPEN_SELL`: "Sell", or "Sell all" on marked items), then Nook quotes the total and asks (`aNSC_buy_sum_check`, `nook_shop_sell`, `ShopBook.sell_result`, §11)
- [x] Nook buys turnips at fluctuating price (§11) — `KabuMarket`
- [x] Catalog ordering; items delivered by mail next day — "Order from the catalog" opens the original catalog (`CatalogOverlay`: nine tabbed pages in `m_catalog_ovl_data.c_inc` order, turning preview, wallpaper / carpet drawn on the room-corner model `mCL_rom_myhome1_*` with their own pages, price or Not for Sale, star on complete pages); Nook quotes the pick (5 order slots, `CatalogBook`, `CatalogPages`)
- [~] Sale days, the flooring/wallpaper wall — Sale Day grab bags, sale-event balloon gift on the first talk (`aNSC_check_present_balloon`); missing: the bargain-event FG layout (`mSP_GetNowShopFgNum` event kinds), wallpaper/carpet preview on the shop walls (`change_wall_proc`)
- [ ] Nook gives you your first job (§29) and the initial furniture set
- [x] Nook's hours (`mSP_GetShopOpenTime`): Cranny / Nookway / Nookington's 9–22, Nook 'n' Go 7–23, raffle day opens at 10, forced open during the part-time job; the door says why it's closed (renovations / opening hour)
- [~] Tom Nook talk (`ac_npc_shop_common`): house business first, then the counter menu — sell / catalog order / other (turnip price) — and shelf offers ("That's X, N Bells") with try-on for clothes (`aNSC_show_item_check`); `NookShopTalk`. Missing: Timmy & Tommy, April Fool's lines, HRA talk, the password (code) options
- [ ] Emotion/Redd membership card sold by Nook — _not found in the decomp's shop-master code (`ac_npc_shop_common`)_; verify where the referral lives before building
- [x] Raffle tickets & end-of-month drawing (`ac_npc_shop_mastersp`): furniture / clothes / wallpaper / carpet / umbrella purchases each earn a month ticket (stack of 5; mailed next morning when the pockets are full, `aNSC_setup_ticket_remain`); on the last day Nook shows three prizes (the first one you don't own), five same-month tickets per spin, 5% / 10% / 20% for 1st / 2nd / 3rd, each prize won once
- [x] Roof paint sold at Nookway+: no pocket item, the roof changes at the next game start (`next_outlook_pal`)
- [ ] Nook's secret codes / passwords (make a code for a friend, enter a code for a gift, 3 a day) (`m_passwordMake_ovl`, `m_passwordChk_ovl`) — see §28

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
- [ ] April Fool's lines for both sisters (`aprilfool_control_clip`) — no April Fool's system yet
- [ ] Foreign-player rules (`mPr_FOREIGNER`: no album, Sable's arc stuck at day 0) — no visiting players yet

## 23. Museum

- [~] Building + 4 wings; **Blathers** the owl curator (nocturnal, sleepy by day) (`ac_museum`, `ac_npc_curator`) — `museum/*`, `museum_book.gd`
- [~] Donate fish / insect / fossil / painting; one-per-species; assessment dialogue (`m_museum_display`) — `museum_display.gd`, `museum_presenter.gd`; rejections play the full `HandOver.player_offers_npc_rejects` GET+examine+RETURN sequence and fossil-piece acknowledgment for incomplete skeletons lands (see [museum.md](decomp_notes/museum.md)). Missing vs. decomp: GET/PUTAWAY hand-over split for *accepted* donations specifically, the 40-entry insect-only extra trivia table, museum-complete mail
- [~] Fish tanks with the species swimming; insect terrariums/cases; each donated species animates (`ac_museum_fish_*`, `ac_museum_insect_*`) — `museum_fish_actor.gd`, `museum_insect_actor.gd`
- [ ] Fossil hall with skeleton mounts assembled from fossil groups (`ac_museum_fossil`)
- [ ] Art gallery: paintings on the walls; Redd sells real + forged art; forgeries rejected by Blathers (`ac_museum_picture`, `ac_mural`)
- [ ] Blathers gives species facts/trivia on donation and when examined
- [ ] Museum completion tracking; "first donation of a species today" shorter path
- [ ] Museum shop / observatory / café — _not in GCN_ (skip)
- [ ] Rooftop / second floor — _GCN: no_
- [ ] Museum is open 24h; Blathers present but drowsy in daytime

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
- [~] Your mailbox at your house: receive letters, gifts, HRA reports, bank interest, event mail, catalog deliveries (`ac_mailbox`) — `scenes/world/mailbox.tscn` + received-mail path, flag raises/lowers on unread mail in every season, lid opens/closes around the Letters menu with the cursor seeded on the last-used slot (`aMBX_pl_open`/`_pl_close`, `mMB_get_last_mail_idx`); Museum fossil-identification replies land here (`FarwayBook` — the in-code name predates confirming decomp's actual address-book contact is just called "Museum", `mPr_CheckMuseumAddress`). Missing: the player's walk-up/hop before the lid opens (`aMBX_pl_wait`/`Player_actor_*_Mail_jump`); villager/event/bank mail not wired yet
- [ ] Mailbox full (10 items) → Post Office holds overflow; retrieve there
- [ ] Villagers send you letters (with gifts if friendship high); reply to build friendship
- [ ] Send a gift to a villager by mail → thank-you letter + item back
- [x] **ABD bank** terminal (§11) — `BankOverlay`; balance gifts by mail instead of interest
- [ ] Pay Tom Nook's loan from the Post Office? _(GCN: pay at Nook's)_
- [ ] Parcel / package pickup; forwarding
- [ ] Post office closed hours & knock; Pelly/Phyllis moods (Phyllis is grumpy)
- [ ] Pelly's storyline / the pigeon romance (`ac_npc_conv_master` engineer)
- [ ] Password / secret-code redemption at the Post Office (`m_mail_password_check`, `m_passwordChk_ovl`)

## 25. Police Station

Behaviour ported from `m_police_box.c`, `ac_police_box.c`, `ac_npc_police2*`,
`ac_npc_police*`, `bg_police_item*` and `ef_room_sunshine_police.c`; details in
[post / police](decomp_notes/post_police.md). Tests: `tests/unit/test_police_box.gd`.

- [~] Building exterior (`ac_police_box`) — `police_station.tscn`: shell, 3×3 plus-offset hull, door (`INTO_S1`, triforce wipe), exit stand `+60,+60`, window lights 18:00–05:00. Missing: the 320-per-frame env-colour fade between on/off (lights snap)
- [~] Interior (`SCENE_POLICE_BOX`) — `police_box.tscn`: `police_indoor` shell, enter `{200,0,380}` north, exit `EXIT_DOOR1`, BGM. Unverified against a real render in this pass (no generated assets in the container)
- [x] Lost-and-found storage rules (`PoliceBox_c`, `police_book.gd`): 20 slots; new town gets 1 furniture + 2 shirts once (never refilled when emptied); `keep_item` appends at the occupied count and drops the oldest when full; ITEM1/FTR only; claimed gaps packed when you walk out (`mPB_copy_itemBuf`); `keep_all_item_in_block` batch rules
- [x] 06:00 top-up (`mPB_force_set_keep_item`): once per renewal, only with ≤ 5 kept, 50% roll; goods 86% (furniture 36 / stationery 23 / clothing 30 / carpet 6 / wallpaper 5), tools & saplings 5%, flower bags 5% (first 8 bags), umbrella 4%
- [~] Lost-and-found display (`bg_police_item`): each kept item drawn as its field card (`obj_item_*`) at its `RSV_POLICE_ITEM_N` unit centre on the BG under it. Units read from `FG_TYPE_POLICE_INDOOR` (0xCE) in the generated FG catalog; the authored fallback table is unverified. The furniture/cloth pools are the shop pools — the ABC / common priority lists are not modelled (`ShopGoods`)
- [x] Claiming (`aPOL2_message_ctrl` / `aPOL2_check_answer`): face a kept item + A → Booker asks (0x077E, item name with article) → "yes" puts it in the first empty pocket (tickets stack), plays `ITEM_GET`, removes it; pockets full → 0x0781
- [x] **Booker** (`ac_npc_police2`, `booker.gd`): greets you on walk-in (0x0784 empty / 0x0785 items); talk 0x077D / 0x0786 / 0x0787; tails the player through the 4×5 zone grid (stop < ~50 GX, walk < ~70 GX, run beyond; waypoint routing round the shelves; turn-in-place past 90°; 11.25°/frame turns; walk 1.0 / run 4.0 speeds); turns to you before every talk
- [~] Booker / Copper lines: the disc bank's own text plays when the dialogue bank has been generated (`msg_<n>`); otherwise authored stand-ins in `booker_talk.json` / `copper_talk.json`. The claim confirm and Copper's menu always use the authored graph (choices). April Fools' lines (`aprilfool_control`) not wired
- [~] Window sunshine (`ef_room_sunshine_police`): left/right beams stretched by time of day, sun/moon window colour, rain × 0.6, camera-side culling, `windowlight_alpha` ramp (05:00–18:00, incl. the noon and `s16`-wrap blinks) — `police_sunshine.tscn`. Needs `obj_koban_shine` from the pipeline (`XLU_ONLY_STATICS`); not yet seen rendered
- [~] **Copper** (`ac_npc_police`, `copper.tscn`): stands two units east of the station facing south; walk-out greeting (0x0771) after leaving the police box; time-of-day menu (0x0772–0x0775) → event hint / lost-and-found count (0x0782 / 0x0783) / never mind (0x0777); 06:00–07:00 exercises (5%, fair weather) and 02:00–04:00 dozing (5%). Missing: removed during morning-aerobics events (`mEv_EVENT_MORNING_AEROBICS`); items under his unit sent to the lost and found on spawn
- [~] Copper's event hint (`aPOL_get_hint_msg_no`): first-job hint, none / later / today / running per special visitor. A running visit other than the sale needs the visitor's acre (`mEv_get_event_place`); no visitor is placed in town yet, so that answers "nothing" like the original's not-found path
- [ ] Ask for a town map — GCN: only a *foreign* player gets the extra "map" option (`aPOL_check_select2` → `mPr_SetNewMap`); needs visiting between towns
- [x] ~~Ask about a villager's location / who's moved in / who's moving out~~ — not in GCN (Copper's menu is the three options above)
- [x] Every town has the police station from day 1 (`mRF_BLOCKKIND_POLICE` block)
- [x] Lost & found also holds forgotten umbrellas etc. (umbrella / tool / flower-bag top-up rolls)

## 26. Town Hall & civic

- [x] No Town Hall on the GameCube (it arrives in Wild World): Tortimer only appears at events, and Pelly / Phyllis work the post office (§ post office)
- [~] Tortimer hands out event items & hosts most holidays (`ac_ev_soncho`, `ac_ev_speech_soncho`) — holiday speeches and the wishing-well visits with his calendar trophies (§31)
- [x] Town Hall services (recycling, donations, environment rating): not on the GameCube; the town tune is set at the melody board by the station (`m_mscore_ovl`)
- [x] **Town tune** editor at the tune board: 16 frog steps (G low … E, random, rest, tie), play, erase-all prompt, "Is this OK?" (save / rewrite / keep the old tune), plays as it opens; saved with the town (`m_mscore_ovl`, `ac_mscore_control`, `m_melody`) — `TownTuneOverlay`, `TownTune`, art from `menu_ui.py` (`ui/mscore/`); `tune [open|reset]` console command. The e-Reader button only closes
- [ ] Change town flag? / town name is fixed after creation
- [x] Player statue by the station (`ac_douzou`) once a house's loan ends in the statue: owner's figure and face (winter set in winter), rank sets size and gold / silver / bronze / jade colours, plaque reads `MSG_DOZOU` in a red window — `Statue`, `statue_metal.gdshader`, face textures from `weather_sprites.py`; `house statue built [rank]` console command. Missing: the sparkle effect (`ef_douzou_light`)
- [x] Wishy the Star: not on the GameCube; the wishing well (`ac_shrine`) is scenery plus Tortimer's holiday spot
- [x] Recycle bin: not on the GameCube (`ac_reserve` is the plot / dock sign); the dump (`ac_dump`) is the closest thing
- [~] Community board: 15 dated posts from the disc's `kei_win` art, seeded with the four starter handbills, page turning and jumps, writing a post on the keyboard with "Is this OK?"; 41 seasonal notices post themselves as their dates pass (sports fairs and daylight saving move with the year), the latest five after an absence (`m_notice`, `m_notice_ovl`) — `NoticeBoard`, `NoticeBoardOverlay`; `board` console command. Missing: Chip's tourney results and villagers' buried-treasure tips (their systems are not built)
- [ ] Signboards / signposts around town naming acres, warning of cliffs, advertising (`ac_sign`)
- [~] The plaza / town square as the event stage (K.K., fireworks, Tortimer speeches) — festival crowds stand in their event-map slots, fireworks go up over the pond; K.K. plays at the station

## 27. Train station & travel

- [~] Station building; **Porter** the monkey stationmaster (`ac_station`, `ac_npc_station_master`) — `intro_station_stage.gd`
- [~] Arrival by train on a new game: Rover on the train, get off, Porter greets, walk to Nook (`ac_train0/1`, `ac_intro_demo`) — `intro_train_stage.gd`, `intro_station_stage.gd`
- [ ] The train as the transition when a **friend visits from another Memory Card / town** (co-op): guest arrives at the station, explores your town, can trade/patterns; final Nookington's upgrade trigger (`m_train_control`, `ac_train_window`)
- [ ] Send a villager away / villager arrives by moving truck vs. train
- [x] Gulliver washes up on the **beach**, not the train — see §30
- [ ] Flag on the flagpole outside the station (`ac_flag`)
- [ ] Train departure/arrival animation, whistle, `ef_kisha_kemuri` smoke

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
- [ ] **Secret codes / passwords**: villagers & Nook trade codes for items; Tom Nook / Post Office redemption (`m_passwordMake_ovl`, `m_passwordChk_ovl`, `m_mail_password_check`)
- [ ] **NES / Famicom games as furniture** (`famicom_emu.c`, `src/static/Famicom`, `src/static/jaudio_NES`)
  - [ ] ~15–19 built-in NES titles playable in your house on a Famicom console _(verify list & count)_
  - [ ] Save state per game; some obtained only via e-Reader / events (e.g. Punch-Out, Zelda)
  - [ ] Playable on GBA when downloaded
- [ ] Memory Card A/B, GBA, e-Reader, second controller detection & menus
- [ ] Broadband/modem adapter — _not used_ (skip)

## 29. First job / new-player onboarding

- [~] Nook gives a job in exchange for the house: change into the uniform, plant a tree/flowers, deliver furniture & a letter, meet a villager, write on the bulletin board, then the shop opens; get an axe; final notice (`ac_npc_rcn_guide2`, `mQst_SetFirstJob*`) — `first_job.gd`, `tom_nook.tscn`
- [~] Uniform shirt (`shirt_016`) worn during the job — `first_job.gd`
- [ ] Post-job: Nook thanks you, explains the loan, catalog, stock
- [ ] Tutorial letters from Tortimer / mom (starting items, "welcome to town")
- [ ] Mom & Dad send letters + gifts periodically (birthday, holidays, first month)

## 30. Special visitors & recurring NPCs

Event NPCs are `EventNpc` scenes placed by `EventManager` presenters (`scenes/world/event_manager.gd`, `scripts/systems/events/`); their talks are `BankTalk` scripts over the disc messages. See [events](decomp_notes/events.md).

- [x] **K.K. Slider** — Saturday nights at the station; request a song by exact title, a random uncollected one, or a made-up tune; the show (quiet, live BGM, staff roll, weather cues) and the aircheck (`ac_npc_totakeke`, `KkTalk`). Missing: staff-roll lights/camera, exact strum/beat sync
- [x] **Crazy Redd** — tent on an empty lot, three wares at 4× price, sales talk (`ac_ev_broker`, `ac_ev_broker2`, `ReddStock` / `ReddTalk`). Missing: goodbye walk on exit
- [x] **Saharah** — trades a carpet for yours at 3000 × 2^n (`ac_ev_carpetPeddler`, `SaharahTalk`)
- [x] **Wendell** — fish for an event wallpaper (`ac_ev_artist`, `WendellTalk`)
- [x] **Gracie** — car on a lot, fashion check, car-wash minigame, Event / group-A clothing (`ac_ev_designer`, `GracieTalk`)
- [x] **Gulliver** — on the beach, wake him, Jonason gift (`ac_ev_dozaemon`, `GulliverTalk`). Missing: the foreign-item letter days later
- [ ] **Wisp** — spirits scattered at night, catch five for a wish (weeds / roof colour / item) (`ac_ev_ghost`, `mEv_EVENT_GHOST`). Needs the spirit field actors; row still in `EventSchedule.UNSUPPORTED`
- [x] **Joan** — Sunday mornings, turnips (`ac_ev_kabuPeddler`, `JoanTalk`). Her give order is simplified (take → give → lines)
- [x] **Katrina** — fortune tent (50 Bells, destiny) (`ac_ev_gypsy`, `KatrinaTalk`) and the New Year's shrine lottery (fortune letter + destiny) (`ac_ev_miko`, `MikoTalk`). Destiny effects on villagers / luck are not wired
- [x] **Jingle** — Toy Day: wish questions in a new acre each time, a Christmas present; new shirts fool him (`ac_ev_santa`, `JingleTalk`)
- [x] **Franklin** — hides on Harvest Festival day; his knife and fork by the feast table buys one of 12 harvest presents (`ac_ev_turkey`, `FranklinTalk`)
- [ ] **Pavé / dancers** — _later games_ (skip)
- [x] **Chip** — bass tourney judge: measures, keeps the day's record (villagers can beat it), A/B/C prize (`ac_ev_angler`, `AnglerTalk`)
- [ ] **Nat** — _not GCN_ (skip)
- [ ] **Dr. Shrunk** — _not GCN_ (skip; emotions come from villagers)
- [ ] **Mr. Resetti / Don Resetti** (§1)
- [ ] **Rover** — cat on the train (new game + occasional visits) (`ac_npc_guide`)
- [ ] **Porter** — station master monkey (`ac_npc_station_master`)
- [ ] **Kapp'n** — boat to the island (`ac_npc_sendo`, `ac_boat`, `ac_boat_demo`)
- [ ] **Tom Nook**, **Timmy & Tommy**, **Blathers**, **Pelly & Phyllis**, **Copper & Booker**, **Sable & Mabel**, **Tortimer**, **Wishy**, **Joan**
- [x] **Countdown NPCs** for New Year's Eve — lines by minutes to midnight, the leader calls out each term, party poppers and fireworks at midnight (`ac_countdown_npc0/1`)
- [ ] **Blanca / mask cat** (`ac_npc_mask_cat`, `mEv_EVENT_MASK_NPC`) — needs the face-drawing editor; row still unsupported
- [x] **Night-stall Redd** at the fireworks: fans / pinwheels / balloons, 8 colours a night (`ac_ev_yomise`, `YomiseTalk`)

## 31. Holidays & seasonal events

From `m_event_schedule.c_inc` (117 unique event IDs across 134 schedule-table rows). Localised USA set:

- [x] Event scheduler: every row resolved per date/hour, weekly visitor, special-visit roll, weather override, `/event` debug commands — `event_calendar.gd`, `event_schedule.gd`, `data/events/schedule.json` ([events](decomp_notes/events.md))
- [x] Festival presenter: props, residents in their map slots (`data/events/event_map.json`, `FestivalCrowd`) with their slot's animations and talk, hidden from the field meanwhile

- [x] New Year's Day — shrine crowd, Katrina's lottery, Tortimer. Missing: the hatsumōde queue choreography (`ac_hatumode_control`)
- [x] Groundhog Day — crowd lines by minutes to 8:00, Tortimer's 8:00 speech and weather verdict. Missing: the groundhog pop-up demo
- [ ] Valentine's Day (Feb 14) — chocolate from a villager
- [~] Snowman season / Kamakura — snow cabin with a resident guest (greeting game, Kamakura trade list). Missing: snowman balls event (`snowman_start`)
- [~] Spring / Fall **Sports Fair** — residents in gym clothes at their stations with their lines; Tortimer. Missing: the foot race / ball toss / tug-of-war games themselves
- [ ] April Fools' Day (Apr 1)
- [x] Cherry Blossom Festival — picnic mats, seated / dancing residents, Tortimer
- [x] Nature Day, Spring Cleaning, Mother's / Father's Day, Graduation, Town / Founders' / Labor / Explorers' / Officers' / Mayor's / Sale / Snow Day — Tortimer at the wishing well with his calendar trophy (`ac_ev_soncho2`, `TortimerHoliday`)
- [x] Fishing Tourney — anglers at the pond, Chip, weigh stand
- [x] Summer Camper — tent on an empty lot, an out-of-town villager inside (greeting game, Tent trade list)
- [x] Fireworks Show — crowd with fans, Redd's stall, fireworks over the pond (bigger sets in the last hour)
- [~] Morning Aerobics — residents doing the routine by the radio. Missing: Copper and Tortimer's radio exercise card (`mSC_Radio_*`)
- [~] Meteor Shower — moon-viewing crowd with meteor lines. Missing: shooting-star effect (`eEC_EFFECT_SHOOTING_SET`)
- [x] Harvest Moon — moon-viewing crowd
- [ ] Mushroom season (mid-Oct)
- [x] **Halloween** — Jack (moves acre after each talk), residents in costume chase the player; candy → present, else a trick (pocket swap or shirt) (`ac_ev_pumpkin`, `ac_halloween_npc`, `TrickOrTreatTalk`)
- [x] **Harvest Festival** — seated feast crowd, Tortimer; Franklin (separate row)
- [~] The day after — **Sale Day** at Nook's — grab bags (`mSP_Chk_HukubukuroSail`); see §21
- [ ] Snow Day (Dec 1) — snow begins
- [x] **Toy Day** — Jingle
- [x] **New Year's Eve** — countdown crowd, party poppers, fireworks at midnight
- [~] Weekly: K.K. (Sat night), turnips (Sun AM), Tortimer/mayor rounds — K.K. and Joan are placed by the event manager; Tortimer only appears on holidays
- [~] Monthly: lottery (last day), Nook stock reshuffle — raffle + monthly prize reshuffle done. No bank interest on the GameCube (balance gifts instead); the HRA writes daily after changes, not monthly
- [~] "Rumor" pre-event villager chatter for each holiday (`mEv_EVENT_RUMOR_*`) — villagers bring up coming visitors and live rumours with their dates (`aQMgr_decide_msg_special_ev` / `_calendar_ev`)
- [x] Tortimer "soncho" variant appearances for each holiday (`mEv_EVENT_SONCHO_*`) — except the January / February vacations and the bridge
- [ ] Player Birthday party — villagers throw a party at your house or theirs, cake, presents
- [ ] Weather overrides for events (clear for fireworks, snow for Toy Day) (`mEv_EVENT_WEATHER_*`)
- [ ] La-di-day / other minor JP holidays present in code — _(verify which survive in GAFE01)_

## 32. Audio

- [~] Sequenced BGM engine (`jaudio_NES`, `m_bgm`, `audiorom.img`) — `audio.gd`, `bgm_catalog.gd`
- [ ] **24 hourly field themes**; different arrangement for rain; seasonal? (no); title, train, K.K. intro, shop, museum, post office, police, house (by size/wallpaper), Able's, Town Hall, island
- [ ] Music crossfades on the hour; muffled when indoors; stops in caves? (n/a)
- [ ] **K.K. Slider songs** (~50) with vocal/animalese arrangements; the in-house "music box" playback vs. the live Saturday performance (`m_mscore_ovl`)
- [ ] SFX bank (seq 242): footsteps by surface, tools, UI, doors, water, digging, tree, bells jingle, item get fanfare
- [ ] **Animalese** speech (seqs 243–245), pitch per speaker sex/personality
- [~] Town tune played on the hour outdoors as the time signal (`mBGMTime_signal_melody`) — `Audio.play_melody` on the note SEs; the step length (0.25 s) is an estimate, and clocks / villager humming don't use it yet
- [ ] Gyroid hums layered onto room music (`ac_my_room_melody`)
- [ ] Ambient: birds (day), crickets/owls (night), cicadas (summer day), ocean waves, river, waterfall, wind, rain, thunder
- [ ] Stereo/positional audio for sound sources (villagers, water, bug/insect calls)
- [ ] NES game audio via the Famicom APU emulation (`ks_nes_core`)
- [ ] Fanfares: new species, fossil, loan paid, HRA rank up, birthday

## 33. UI, menus, misc systems

- [ ] Start / pause menu: map, inventory, diary?, options
- [ ] **Diary** — auto-written daily log of notable events (`m_diary`, `m_diary_ovl`)
- [ ] Held **map** item / pause map with acre labels, building icons, your house
- [ ] HUD clock (optional), bells display when relevant
- [ ] Options: text speed, TV/audio mode (mono/stereo/surround), rumble, screen position, brightness (`initial_menu.c`)
- [ ] Rumble / vibration on tool use, catches, bumps (`m_vibctl`, `m_player_vibration`)
- [ ] "Copying data" / autosave indicator
- [~] The **name entry keyboard** for text input — see §17 keyboard entry
- [~] Nook catalog browser UI, shop buy/sell UI, bank UI, HRA letter viewer, letter writer UI — the catalog is the original `m_catalog_ovl` screen, goods come off the shelves, selling goes through the pockets, letters use the original board / address book / Is-this-OK prompt; all menus slide in and out like `mSM_move_Move` (`MenuSlide`). the bank's ABD screen (`BankOverlay`). HRA reports are ordinary letters on the GameCube (no viewer)
- [ ] Photo / no screenshot feature (GCN has none)
- [~] Trademark / logo / attract-mode title demo loop (`m_titledemo`, `m_trademark`, `ac_animal_logo`) — logo actor, 5 recorded demos, the demo loop, the fixed FG table, fixed villagers, apple tree and start chime landed; Nintendo logo stage skipped on purpose; gelato umbrella landed with the umbrella tool (demo 2) ([title](decomp_notes/title.md))
- [ ] Debug menus & dev overlays — _explicitly out of scope_ (`m_debug*`)

## 34. Simulation glue / world objects

- [ ] FG (foreground) object system: trees, rocks, flowers, weeds, signs, holes, buried marks, dropped items, structures, villager plot reserves (`m_bg_item`, `WorldObjectRegistry`) — `world_object_registry.gd`
- [ ] Daily FG renewal: weeds spread, flowers breed/wilt, plants grow, buried spot relocates, rock resets, shells respawn, recycle bin rotates, shop restocks
- [ ] Collision: heightfield, cliff/bank walls, 45° diagonals, water slide-off, structure footprints, plant caps (`m_collision_bg`) — `field_collision.gd`
- [ ] Blob shadows under actors & items (`m_actor_shadow`) — `actor_blob_shadow.gd`
- [ ] Effects library: dust, splash, sparkle, coins, leaves, sweat, music notes, impact stars, hearts, "?"/"!" etc. (`ef_*`, ~130 effects)
- [ ] Object draw sorting, XLU passes (water, footprints, shadows), acre culling
- [x] Balloon presents (`m_fuusen`, `ac_fuusen`) — `BalloonSky` rolls at :x3 every five minutes (5% start, +2.5–5% per miss, goods / bad luck, +25% after one got away near you); `Balloon` is born on the wind's map edge, drifts downwind 110 GX up, turns toward a bare grown tree and snags in its crown; a full shake drops the wrapped present (80% C-list furniture, else a foreign fruit), a bump wobbles it; it escapes after 10 minutes snagged or at the map edge / station. `/balloon [near]` launches one. Missing: town rank term (0), the snag sound (SE 0x402 not in the converted bank), wind gusts; drifting uses a cliff check in place of full wall collision
- [~] Wind (`m_kankyo_weather`: daily calm / normal / strong range by season, 10-minute drift, Koinobori day) — `Wind`; drives balloons only so far
- [ ] Airplane / helicopter flyover (`ac_airplane`)
- [ ] Message-in-a-bottle on the beach (`ac_mbg` beach spawns) — random letter/pattern _(verify GCN)_
- [ ] The lighthouse light sweeps at night; switch it (`ac_toudai`, `ac_lighthouse_switch`)
- [ ] Windmill turning in wind (`ac_windmill`)

## 35. Multiplayer / multi-town

- [ ] 4 residents share one town, one Memory Card; play one at a time (couch "multiplayer")
- [ ] Each resident: own house, pockets, catalog, friendships, loan, HRA score
- [ ] Residents leave letters / gifts / patterns for each other; can enter each other's houses? _(GCN: no — only your own)_
- [ ] Visiting another town via a second Memory Card + the train: guest walks around, trades, copies patterns, shops; triggers Nookington's
- [ ] Item/bell/pattern transfer rules & anti-duplication

---

## Content-count worksheet (pin against decomp tables)

| Set | Count (verify) | Decomp source |
| --- | --- | --- |
| Fish | 45 fish types + 5 extended catches | `aGYO_TYPE_NUM`, `aGYO_TYPE_EXTENDED_NUM`, `ac_gyoei_type.c_inc`, `ac_set_ovl_gyoei.c` |
| Insects | 40 individual types | `aINS_INSECT_TYPE_NUM`, `ac_insect_data.c_inc`, `ac_set_ovl_insect.c` |
| Fossils | ~25 items / ~13 skeletons | `ac_museum_fossil.c` |
| Paintings | 15 | `ac_museum_picture.c` |
| Gyroids | ~127 | `m_melody.c`, `ac_my_room_melody.c_inc` |
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
