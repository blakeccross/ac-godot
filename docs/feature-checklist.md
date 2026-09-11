# Animal Crossing (GameCube) — 1:1 Feature Checklist

Goal: recreate **every** system and content set from *Animal Crossing* for the
Nintendo GameCube (`GAFE01`, USA rev 0 — the [ac-decomp](https://github.com/ACreTeam/ac-decomp)
target) in Godot 4. The only intended deviation is **HD textures / re-authored art**;
behaviour, numbers, schedules, and content should match the original.

> **Scope note.** This checklist supersedes the "build one good version, then stop"
> stance in [scope.md](scope.md) for anything the team decides to pursue. Items are
> listed whether or not they are currently in scope so nothing is forgotten.
> `docs/decomp_notes/` holds the behavioural detail for systems already studied.

## Legend

- `[ ]` — not started
- `[~]` — partial / scaffolding exists (see notes)
- `[x]` — complete and verified faithful to the original

Numbers marked _(verify)_ are from memory and should be pinned against the decomp
data tables before a category is called done.

---

## 1. Boot, save, and session

- [~] Title screen: New Game / Continue (`m_scene`, `m_start_data_init`) — `scenes/ui/title.tscn`
- [~] New town vs. load-existing branch (`mSDI_StartInitNew`)
- [ ] Up to **4 human residents** per town; pick which one you play each session (`player_select.c`)
- [ ] Create-a-character on the train (name, town name, face is derived from Rover's questions) (`ac_npc_guide`)
- [~] Character creation flow driven by Rover Q&A (`ac_npc_guide` / intro train) — `intro_train_stage.gd`
- [ ] Delete a resident / delete the town (`save_menu.c`)
- [~] Save + return to title on quit (`save_menu.c`, `m_save`) — `save_service.gd`
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
- [ ] Seasons: snow cover Dec–Feb, cherry-blossom trees early April, coloured foliage in autumn, bare trees in winter
- [ ] Season affects grass colour / acre visuals, tree models, river ice? (no — but snow ground)
- [ ] Weekday tracking; shop closed days; K.K. on Saturday night
- [ ] "Played days" counter, first-day flags, "haven't played in a while" reactions
- [ ] Birthday stored per resident; birthday event

## 3. Weather & environment

- [~] Rain / snow / clear by term probability tables (`m_kankyo_weather.c_inc`) — `weather.gd`
- [ ] Rain intensity: drizzle vs. downpour; snow: flurry vs. heavy
- [~] Weather particles + puddles / wet sand shader — `WeatherFx`, `beach_wet.gdshader`
- [ ] Cherry-blossom petal fall (Apr 3–8) (`ac_weather_sakura`, `ev_cherry_manager`)
- [ ] Falling leaves in autumn (`ac_weather_leaf`)
- [ ] Rainbow after rain
- [ ] Fog / haze mornings
- [ ] Rain changes indoor & outdoor BGM; more fish/bugs (coelacanth, frogs, snails, etc.)
- [ ] Lightning flashes; aurora (northern lights) on winter nights
- [ ] Shooting stars on clear nights → wish (`ef_flash` / meteor)
- [ ] Full-moon / moon phase art (`ef_night13_moon`, `ef_night15_moon`)
- [ ] Wind affects grass, flags, windmills, balloons (`ef_kaze`, `ac_windmill`, `ac_flag`, `ac_koinobori`)

## 4. Town generation & geography

- [~] Procedural town: 5×6 acre grid, cliffs/terraces (3 elevations), river, waterfalls, ponds, sea + beach (`m_random_field`, `m_field_make`) — `town_field_generator.gd`
- [ ] Fixed known-seed towns (A–D style) selectable — `REFERENCE` world mode reserved
- [ ] River mouth, river forks, round pond, waterfall placement rules
- [ ] Beach along the south edge; tide; ocean horizon; rocks in surf
- [ ] Acre-edge scroll / camera hand-off between acres
- [ ] Town map generated and shown in pause menu / held map item (`m_map_ovl`) — `town_map.gd`, `scenes/ui/map_overlay.tscn`
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
- [ ] Clothing: equipped shirt shows on model; hats; accessories/glasses; umbrella held in rain (`m_player_item_umbrella`)
- [ ] Change clothes anywhere from pockets (`m_player_main_change_cloth`, `ef_kigae`)
- [ ] Pockets = **15 item slots** + separate wallet (`m_private` `mPr_POCKETS_SLOT_COUNT`) — `inventory.gd`
- [ ] Carrying a piece of furniture / large item in hands (walk slower) (`m_player_main_hold`, `pickup_furniture`)
- [ ] Trip / stumble when running into things or on ants (`m_player_main_tumble`, `stung`)
- [ ] Fall in a pitfall; struggle out (`m_player_main_fall_pitfall`, `struggle_pitfall`, `climbup_pitfall`)
- [ ] Get stung by bees → swollen face for the day; villagers react; medicine cures (`m_player_main_stung_bee`)
- [ ] Mosquito bites in summer (`ac_ins_ka`, `stung_mosquito`)
- [ ] Tired / sleepy animations late at night (`m_player_main_tired`, `ef_ikigire`, `ef_neboke`)
- [ ] Push / pull furniture and snowballs (`m_player_main_push`, `push_snowball`)
- [ ] Sit on the ground, on benches/chairs (`m_player_main_sitdown`)
- [ ] Lie in bed / roll in bed / stand up from bed → save (`m_player_main_lie_bed`, `roll_bed`)
- [ ] Wade in shallow water; can't swim (`m_player_main_wade`)
- [ ] Radio-exercise / morning aerobics participation (`m_player_main_radio_exercise`)
- [ ] Emotions / reactions system — expressions triggered from a menu (`ef_warau`, `ef_naku`, `ef_pun`, manpu) — _(GCN set, verify list)_

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
- [ ] Push signs to read; read bulletin board; read gravestones/signposts (`ac_sign`)
- [~] Knock on villager doors (`m_player_main_knock_door`)
- [~] Enter/exit buildings: step-in animation, door swing, screen wipe (`m_player_main_door`) — `structure_door.gd`, `scene_transition.gd`
- [ ] Hand an item to a villager / receive an item (give / recieve animations) (`m_player_main_give`, `recieve`, `ac_handOverItem`)
- [ ] Refuse / decline prompt (`m_player_main_refuse`)
- [ ] Pick fruit vs. shake whole tree distinction
- [ ] Pluck weeds (`m_player_main_remove_grass`)
- [ ] Pick / dig up flowers; pick mushrooms (`m_mushroom`)
- [ ] Talk to your own reflection / gyroids / pets? (gyroid greeting)

## 9. Tools

- [ ] **Net** — swing, catch bugs, catch bees; whiff; hold-ready walk (`m_player_item_net`, `m_player_main_swing_net`, `ready_walk_net`) — `netting.gd` _(partial)_
- [~] **Fishing rod** — see §13 (`m_player_item_rod`) — `fishing.gd` (substantial)
- [ ] **Shovel** — dig holes, bury items, dig fossils/gyroids/pitfalls, hit rocks, plant trees, whack villagers, reflect off stone (`m_player_item_scoop`, `dig_scoop`, `fill_scoop`, `reflect_scoop`) — `hole_use.gd`, `buried_use.gd` _(partial)_
- [ ] **Axe** — chop trees (multi-hit → stump), break on overuse, golden axe never breaks (`m_player_item_axe`, `swing_axe`, `broken_axe`, `ef_break_axe`) — `tree_use.gd` _(partial)_
- [ ] **Fishing rod / net / axe / shovel** durability & the **golden** variants (golden axe from perfect town, golden rod/net/shovel from milestones) (`demo_get_golden_item`)
- [ ] **Slingshot** — shoot floating presents/balloons out of the sky (`ac_balloon`, `ac_fuusen`, `m_fuusen`)
- [ ] **Watering can** — _not in GCN_ (villagers water flowers themselves; skip)
- [ ] **Umbrella** — held in rain/snow, twirl, many designs (`m_player_item_umbrella`, `rotate_umbrella`)
- [ ] **Fan / uchiwa** (festival), **timer**, **party popper / clacker**, **handbill**, **pitfall seed** as usable items (`m_player_item_fan`, `ac_t_utiwa`, `ef_clacker`)
- [ ] **Bug / fish held up** show-off pose + species report (`m_player_main_notice_net`, `notice_rod`)
- [ ] Held tool renders on the right hand with its own animation clips (`Player_actor_Item_draw`, `mPlayer_JOINT_HAND`) — `held_tool.gd`
- [ ] Tool ready ↔ put-away transitions and SE for every tool (`putaway_*`, `ready_*`)
- [ ] Wetsuit / diving — _not in GCN_ (skip)

## 10. Inventory, items, catalog

- [~] 15 pocket slots; drag/drop, sort, split stacks, drop to ground (`m_inventory_ovl`) — `inventory_overlay.tscn`, `inventory_chrome.gd`
- [x] Pockets ↔ Fish/Insect encyclopedia pages (`mIV_PAGE_*`, 8×5 grid, right-edge folder tabs); caught-once registry `SpeciesLog` — `encyclopedia_catalog.gd`, `species_log.gd`
- [x] Portrait player animations: walk-in-place default + `CHANGE`/`EAT`/`CATCH` one-shots (`mIV_ANIM_*`) — `inventory_overlay.gd`
- [ ] Wallet (bells) separate; 30,000-bell bag stacks; withdraw/deposit at bank
- [ ] Item info popup; "throw away" confirmation
- [ ] **Catalog** of every item you've ever owned/received; order from catalog at Nook's (`m_catalog_ovl`)
- [ ] Item data tables: furniture, clothing, wallpaper, carpet, umbrellas, tools, stationery, fruit, shells, fossils, gyroids, paintings, music, misc (`m_item_name`, `ac_furniture_data`)
- [ ] Fruit: native fruit per town + non-native (apple, orange, peach, pear, cherry); coconut on beach palms
- [ ] Perfect fruit? _(not in GCN — skip)_
- [ ] Sea shells wash up on the beach on a timer; sell to Nook / Tommy (`ac_mbg` beach items)
- [ ] Furniture "in hand" vs. "as item" states; wallpaper/carpet items
- [ ] Wrapping paper — wrap an item as a present to give/mail (`ac_present_demo`)
- [ ] Lost items / forgotten items handling

## 11. Economy

- [ ] Bells as currency; wallet cap; 30k bags
- [ ] **Post Office bank (ABD)**: deposit, withdraw, interest paid by mail monthly (`m_bank_ovl`)
- [ ] **Tom Nook home loan**: 4 (or 5) escalating amounts; pay any amount; statue/"paid off" reward; house expands on payoff (`m_repay_ovl`, `mQst` house upgrade)
- [ ] House sizes: tent → 1-room → expanded room → +2nd floor / basement / side rooms → mansion (`m_home`, `m_house`, room types)
- [ ] **HRA — Happy Room Academy**: weekly letter scoring your house layout; feng shui, sets, matching series, gyroids, furniture count; rank letters (`m_huusui_room`, `mark_room`)
- [ ] Feng shui: colour-by-direction bonuses (`m_huusui_room_ovl`)
- [ ] Selling: Nook buys almost anything at set prices; fish/bugs/fossils/paintings prices; foreign fruit premium
- [ ] Turnip market (**Stalk Market**): Sow Joan sells turnips Sunday AM; Nook buys at fluctuating daily AM/PM price; turnips rot after a week; spoiled-turnip uses (`m_kabu_manager`, `ac_ev_kabuPeddler`, `ac_yomise`)
- [ ] Lottery / raffle at Nook's on the last day of the month (`mEv_EVENT_LOTTERY`)
- [ ] Nook's point card / "Nook Points" — _(verify GCN)_
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
- [ ] **40 fish** _(verify — 45 spawn types incl. non-fish)_ with month × time-of-day × water-type availability + rarity (`ac_set_ovl_gyoei`, `ac_gyoei_type.c_inc`)
- [ ] Half-month term split + transition ramp for spawn weights (`gyoei_term`) — _(currently simplified)_
- [ ] Water types: river, river mouth, pond, waterfall pool, sea, island (`aSOG_RANGE_PROC_*`)
- [ ] Coelacanth only while raining/snowing, in the sea, outside the day slot (`aSOG_add_kaseki_range_data`)
- [ ] Non-fish catches: boot, tire, tin can, seaweed? _(verify GCN junk list)_
- [ ] Trash items (boot/can/tire) as furniture-less junk, sellable to Nook
- [ ] Fishing tourney (June & November Sundays), Chip judges, biggest fish wins furniture (`mEv_EVENT_FISHING_TOURNEY_1/2`, `ac_turi_npc0`, `ac_ev_angler`)
- [ ] Fish records board / "biggest catch" tracking (`m_fishrecord`)

## 13. Bug catching

- [~] Net swing hitbox, timing, whiff, bug flees (`ac_insect`, `ac_npc_act_chase_insect`) — `netting.gd`, `bug_actor.gd` _(partial)_
- [~] Bug spawn tables by month / time / habitat (tree trunk, flying, on flowers, on the ground, in the ground (mole cricket), by water, tree stumps, rotten food, street lamps at night) (`ac_set_ovl_insect`, `ac_insect_data`) — `bug_catalog.gd`, `bug_habitats.gd`
- [ ] **40 insects** _(verify)_: butterflies, bees/wasps, beetles, dung beetle, ladybug, mantis, dragonflies, cicadas (7 kinds), grasshopper/locust, cricket, bell cricket, pine cricket, spider, tarantula, ant, pill bug, snail, mole cricket (dig sound), firefly, mosquito, fly, cockroach, bagworm, pond skater, diving beetle, mantid, walking stick, etc.
- [ ] Bee swarm from a shaken tree chases you; hide indoors or net them; sting → swollen face (`ac_bee`, `bee_swarm.gd`)
- [ ] Wasp nest drops from tree; getting stung (`ac_bee` variant)
- [ ] Tarantula aggressive chase behaviour at night
- [ ] Firefly glow at night near water in summer
- [ ] Cicada shells on trees; cicadas fly off when you approach
- [ ] Bug sounds are directional and time-gated (crickets at night, cicadas by day)
- [ ] Ants swarm on dropped rotten food / candy (`ac_ant`)
- [ ] Cockroaches in a house left closed too long; stomp them (`m_cockroach`, `ac_house_goki`)
- [ ] Bug-off / bug tourney? _(GCN has no dedicated bug tourney — verify; fishing only)_

## 14. Digging, buried items, rocks

- [~] Dig a hole on empty ground; fill a hole (`DIG_SCOOP`, `FILL_SCOOP`, `HOLE00`–`HOLE24`) — `hole_use.gd`, `scenes/world/hole.tscn`
- [~] Bury an item in a hole; dig it back up (`PUTIN_SCOOP`, `buried_use.gd`)
- [ ] Buried "X" marks / glowing spot: one per day → **fossil** or **bells** or **gyroid** or (after rain) more gyroids (`ac_gyo_kaseki` naming aside — fossils via FG)
- [ ] Money spot: dig up 100 bells, replant bells (100–30,000) → money tree grows bags of bells once (`m_all_grow` money tree)
- [ ] **Rock**: one random rock per day yields bells when hit with the shovel (up to ~8 hits, escalating, timed, must not be blocked from behind) — the "money rock"
- [ ] Rocks are otherwise immovable obstacles; fake rock? _(GCN: no)_
- [ ] **Pitfall**: plant a pitfall seed → invisible trap; player/villager falls in (`ac_ghog`? / pitfall FG, `m_player_main_*_pitfall`)
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
- [ ] Lotus / water lilies in ponds (`ac_lotus`), lotus as item
- [ ] Coconut palms on the beach; coconuts plantable only on the beach
- [ ] Cherry / persimmon / other decorative? _(verify)_

## 16. Villagers (animal residents)

- [~] One NPC actor, behaviour driven by "looks"/personality tables (`m_npc`, `ac_npc`) — `villager.tscn`, `villager_ai.gd`
- [ ] **~15 villagers** live in town at once; ~215 species/characters total in the GCN roster _(verify)_
- [ ] Personalities: **Normal, Peppy, Snooty, Cranky, Lazy, Jock** (6); + Big Sister/Uchi? — _no, GCN is 6_ — `personalities/`
- [ ] Species models: cat, dog, rabbit, squirrel, bear, cub, pig, cow, bull, horse, sheep, goat, wolf, dog, duck, chicken, ostrich, penguin, eagle, elephant, rhino, hippo, gorilla, monkey, koala, kangaroo, anteater, alligator, frog, octopus, deer, mouse, hamster, tiger, lion, chameleon? _(verify GCN species list)_ — `generated_visual.attach_villager`
- [~] Daily schedules per personality: wake, wander acres, visit shops, go to specific acres (shrine / friend's house / own house), sleep (`m_npc_schedule`, `ac_npc_schedule_*`) — `villager_schedule.gd`
- [~] Field roam: pathing between goal acres, walker cap (`m_npc_walk`) — `villager_walk.gd`, `villager_motor.gd`
- [~] Appear indoors when awake at home; asleep = off the map (`ac_npc_think_sleep`) — `villager_home.gd`
- [~] Head/eyes track the player when near (`ac_npc_head`) — `npc_head_look.gd`
- [~] Face: texture-swap eyes & mouth; blink bursts; emotion holds; mouth flap while talking (`ac_npc_anime`, `aNPC_check_kutipaku`) — `npc_face.gd`, `npc_face_anim.gd`
- [~] Feel glyphs (manpu) above head: laugh cards, shock, "!", lightbulb, sweat, anger, sleep-Zzz, love hearts (`ef_warau`, `ef_shock`, `ef_ha`, `ef_hirameki`, `ef_lovelove`, …) — `npc_manpu.gd`, `npc_feel_glyphs`
- [ ] Full manpu set: `KONPU`, `PUN_YUGE`, `DOYON`, `GIMONHU`, `KANTANHU`, `NAMIDA`, `NEBOKE`, `MUKA`, etc.
- [ ] Activities villagers do: sit and think, fish, catch bugs, water flowers, sing, exercise, read, talk to each other, shop, deliver mail for you, clap (`ac_npc_act_*`)
- [ ] Villager catches a bug/fish and shows it off; asks you to catch something
- [ ] Umbrella open/close in rain (`ac_npc_act_umb_open/close`)
- [ ] Villager falls in your pitfall; you dig them out; anger/forgiveness (`ac_npc_act_pitfall`)
- [ ] Hitting a villager with the net/axe/shovel → anger, "watch it!" (`m_watch_my_step`)
- [ ] **Moving in**: new villager, boxes at the plot, introduces self (`ac_npc_act_greeting`, `mEv` move-in)
- [ ] **Moving out**: villager announces plans days ahead; you can talk them into staying; boxes; gone next day; leaves a goodbye letter/gift (`ac_go_home_npc`)
- [ ] Move-in / move-out cadence tied to friendship, time played, town population
- [ ] **Friendship** per resident: points, best-friend at 80, decays over neglect (`Anmmem_c`, `mNpc_AddFriendship`) — `relationship.gd`, `relationship_book.gd`
- [ ] Villager **memory**: last time you spoke, letters exchanged, favours done, gifts, whether you've been mean (`Anmmem_c`)
- [ ] Nicknames: villager gives you a nickname; you can set what villagers call each other / call you; catchphrase ("hippie", etc.); you can change a villager's catchphrase
- [ ] Greetings you can teach; greeting spreads between villagers
- [ ] Gift-giving both ways; wrapped gifts; villager mails you a thank-you + item
- [ ] Errands: deliver package to another villager, deliver a letter, return lost item, buy/sell an item, find furniture (`ac_quest_errand`)
- [ ] Trading furniture / clothing with villagers; villager wants a specific item
- [ ] Villager asks to buy something from your pockets / sell you something
- [ ] Villager house interiors themed by personality; changes over time with items you give
- [ ] Sick villagers → give medicine (from Nook) → friendship boost
- [ ] Villager games: hide and seek, "which hand", quizzes, "what am I thinking" (`ac_npc` talk minigames)
- [ ] Villager sings K.K. songs / hums the town tune
- [ ] Villager reactions to your appearance: bee-stung face, bad haircut (n/a), new shirt, holding furniture, being naked, wearing a hat/mask
- [ ] Villager comments on weeds, litter, flowers, your house, the town rating, holidays, weather, time of day, your birthday
- [ ] Special personality: **Cranky→mellows**, **Snooty→warms** as friendship rises

## 17. Dialogue & text

- [~] Message window: cloud lobes + nameplate, NES I4 font atlas, 18-frame scale in/out, continue-mark triangle-wave alpha (`m_msg`, `m_msg_draw_window`) — `message_window_chrome.gd`, dialogue overlay
- [~] Typewriter reveal (15 / 30 glyphs per sec), speaker-sex nameplate colour (`m_msg_draw_font`) — `message_window_chrome.gd`
- [~] Choice panel: mid-right teal, cyan mark, scale in/out (`m_choice`) — `choice_panel`, `message_choice_mark.gd`
- [~] Dialogue data + runner + conditions; greeting picks opening line (`m_string`, `DialogueGreeting`) — `dialogue_runner.gd`, `dialogue_catalog.gd`
- [ ] Full message-bank coverage: villagers (per personality × mood × topic), special NPCs, signs, letters, system prompts
- [ ] Text effects: shake, colour, size, pause, icon inserts (item/bell/leaf glyphs), player-name / town-name / catchphrase substitution
- [ ] **Animalese** voice synthesis per syllable, pitch by speaker (`jaudio` seqs 243–245) — `dialogue_voice.gd` _(partial)_
- [ ] Keyboard entry: letters, item names, town tune, patterns, sign text, character names (on-screen keyboard)
- [ ] Word-filter / bad-word list for user text (`m_editEndChk_ovl`)
- [ ] "..." silent responses; scrolling long letters; page-turn SE

## 18. Player house & interiors

- [ ] Tent on day 1; upgrades via Nook loans to: basic room → bigger room → +second floor → +basement → +left/right/back rooms → mansion + attic
- [ ] Room = grid; place furniture on floor, against walls, on tables (`ac_arrange_room`, `ac_arrange_ftr`)
- [ ] Wallpaper + carpet per room; ceiling? (no)
- [ ] Furniture rotate (4 or 8 orientations), stack on surfaces, put items on tables (`m_player_main_rotate_furniture`, `rotate_octagon`)
- [ ] Wall-mounted items (paintings, clocks, wall clock ticking `ac_house_clock`); rugs
- [ ] Interior editing mode / catalog reorder; "store in Nook's" / storage
- [ ] Music player furniture (stereo/radio/etc.) plays a chosen K.K. song; gyroids beat along (`ac_radio`, `ac_my_room_melody`)
- [ ] Lighting: lamps light up at night; some furniture is interactive (sit, lie, TV static `famicom_emu`, fireplace, fountain, toilet, bath `ef_furo_yuge`)
- [ ] Doorplate / house nameplate (`ac_nameplate`)
- [ ] Basement = free storage room once unlocked
- [ ] House exterior model changes with size; door mat; roof
- [ ] Move house location? _(GCN: no)_
- [ ] Cockroaches spawn if you don't play for weeks; house dusty
- [ ] HRA judges the main room only (§11)
- [ ] Other residents' houses in your town enterable? _(only the one you play; others are just exteriors + villager homes)_

## 19. Furniture & collectibles

- [ ] Full furniture DB with series/sets, sizes, HRA points, feng-shui colour, sell price (`ac_furniture_data`, `f_furniture.c`)
- [ ] Series: e.g. Classic, Modern, Regal, Ranch, Cabin/Cabana, Exotic, Blue, Green, Kiddie, Lovely, Snowman, Mushroom, Robo, Spooky, Harvest, Jingle/Festive, Space, Pavé? _(verify GCN series list)_
- [ ] Themed sets award HRA bonus when all present + matching wallpaper/carpet
- [ ] Special/rare: Nintendo items (famicom, N64, GameCube, Mario/Zelda/Metroid themed), Trophies, King Tut mask, models, instruments
- [ ] **NES/Famicom consoles as furniture** → playable games (see §26)
- [ ] Gyroid furniture (§14): the giant collection; each has an on/off wind state and a sound
- [ ] Musical instruments you can play? _(GCN: no free-play)_
- [ ] Snowman series: build a perfect snowman → mails you a Snowman-series item over the following days (`ac_snowman`, `ac_psnowman`, `m_snowman`)
- [ ] Feng-shui / lucky items
- [ ] Furniture obtained from: Nook's shop, catalog order, villagers, events, HRA, balloons, fishing/bug tourneys, lost-and-found, Redd, Saharah (carpets/wallpaper), fortune (Katrina n/a in GCN)
- [ ] Wallpaper & carpet catalog; special ones (mosaic wall, etc.)

## 20. Design / pattern tool

- [ ] 32×32 pixel pattern editor, 15-colour palette, mirror/tools (`m_design_ovl`, `m_editor_ovl`, `m_ledit_ovl`)
- [ ] Apply patterns as: shirt, hat, umbrella, wallpaper?, or place on the ground / as signboards / hung on walls
- [ ] The **Able Sisters** design display board: submit your design → sold in the shop; wear other players' designs
- [ ] "Pro" designs? _(GCN: no pro designs)_
- [ ] Wendell / Saharah / gypsy hand you free patterns (`ac_ev_designer`, `ac_broker_design`)
- [ ] Design catalog / storage (`m_cpedit_ovl`, `m_cporiginal_ovl`)
- [ ] Town flag design (on the flagpole at the station) (`ac_flag`)
- [ ] e-Reader design cards import (§28)

## 21. Nook's store

- [~] 5 upgrade tiers over time + purchase volume: **Nook's Cranny → Nook 'n' Go → Nook's → Nookway → Nookington's** (`ac_shop_level`, `m_shop`) — `shop_book.gd`, `shop0`–`shop3` interiors
- [ ] Nookington's has a second floor with Timmy & Tommy; requires a friend from another town to visit to trigger the final upgrade
- [~] Daily stock: a few furniture, wallpaper, carpet, tools, stationery, seeds, umbrella, a "special" (`ac_shop_goods`, `ac_shop_goods_data`) — `shop_stock.gd`
- [ ] Stock rotates at 06:00; sells out; sold-out slot shows empty
- [ ] Sell items to Nook (he names a price, you confirm); can't sell some things
- [ ] Nook buys turnips at fluctuating price (§11)
- [ ] Catalog ordering kiosk; items delivered by mail next day
- [ ] Sale days, "Nook's Point"/members, the flooring/wallpaper wall
- [ ] Nook gives you your first job (§29) and the initial furniture set
- [ ] Nook's closed hours (roughly 09:00–22:00; later tiers longer); knock when closed
- [ ] Tom Nook dialogue moods; Timmy & Tommy (nephews) at higher tiers
- [ ] Emotion/Redd membership card sold by Nook (the "secret" black-market referral)
- [ ] Point-card / raffle tickets; end-of-month lottery drawing at the store

## 22. Able Sisters (Nook's neighbour)

- [~] Shop building + interior (`ac_needlework_shop`, `ac_misin`) — `able_sisters.tscn`, `needlework.tscn`
- [ ] **Mabel** runs the counter; **Sable** at the sewing machine (silent for weeks, then warms up if you visit daily) (`ac_npc_needlework`, `ac_npc_sleep_obaba`)
- [ ] Sells: shirts (rotating daily stock), a few hats, accessories, umbrellas, carpets & wallpaper (some days)
- [ ] The **design board**: browse & buy player-made patterns; upload your own (`ac_broker_design`, `ac_shop_design`)
- [ ] Sable's backstory dialogue chain unlocked by consecutive-day visits → she gives you a free pattern
- [ ] Umbrella stand (`ac_shop_umbrella`)
- [ ] Mannequin displaying featured outfit (`ac_shop_manekin`)

## 23. Museum

- [~] Building + 4 wings; **Blathers** the owl curator (nocturnal, sleepy by day) (`ac_museum`, `ac_npc_curator`) — `museum/*`, `museum_book.gd`
- [~] Donate fish / insect / fossil / painting; one-per-species; assessment dialogue (`m_museum_display`) — `museum_display.gd`, `museum_presenter.gd`
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
- [ ] Write & send letters (up to 3 lines + optional attached gift); costs bells (`m_mail`, `ac_pterminal`)
- [ ] Stationery types (dozens); some from events/villagers; letter paper affects villager reaction
- [~] Your mailbox at your house: receive letters, gifts, HRA reports, bank interest, event mail, catalog deliveries (`ac_mailbox`) — `scenes/world/mailbox.tscn` + received-mail path, flag raises/lowers on unread mail in every season, lid opens/closes around the Letters menu with the cursor seeded on the last-used slot (`aMBX_pl_open`/`_pl_close`, `mMB_get_last_mail_idx`); Farway Museum replies land here. Missing: the player's walk-up/hop before the lid opens (`aMBX_pl_wait`/`Player_actor_*_Mail_jump`); villager/event/bank mail not wired yet
- [ ] Mailbox full (10 items) → Post Office holds overflow; retrieve there
- [ ] Villagers send you letters (with gifts if friendship high); reply to build friendship
- [ ] Send a gift to a villager by mail → thank-you letter + item back
- [ ] **ABD bank** terminal (§11): deposit/withdraw, balance, monthly interest by mail
- [ ] Pay Tom Nook's loan from the Post Office? _(GCN: pay at Nook's)_
- [ ] Parcel / package pickup; forwarding
- [ ] Post office closed hours & knock; Pelly/Phyllis moods (Phyllis is grumpy)
- [ ] Pelly's storyline / the pigeon romance (`ac_npc_conv_master` engineer)
- [ ] Password / secret-code redemption at the Post Office (`m_mail_password_check`, `m_passwordChk_ovl`)

## 25. Police Station

- [~] Building + interior; **Copper** (stands guard) & **Booker** (timid) (`ac_police_box`, `ac_npc_police`, `ac_npc_police2`) — `police_station.tscn`, `police_box.tscn`, `police_book.gd`
- [~] **Lost and found**: items you (or the game) dropped in town get turned in; claim them (`police_display.gd`)
- [ ] Ask about a villager's location / who's moved in / who's moving out
- [ ] Ask for a town map / directions
- [ ] Report / hear about the town's news
- [ ] Booker's nervous dialogue; Copper's terse dialogue
- [ ] Not every town has the police station from day 1? _(GCN: present)_
- [ ] Lost & found also holds forgotten umbrellas etc.

## 26. Town Hall & civic

- [ ] Town Hall building + interior; **Tortimer** the mayor; **Pelly** also works the Town Hall desk in some builds _(verify GCN — Town Hall has Pelly + Tortimer)_ (`m_soncho`, `ac_soncho`, `ac_douzou`)
- [ ] Tortimer hands out event items & hosts most holidays (`ac_ev_soncho`, `ac_ev_speech_soncho`)
- [ ] Town Hall services: recycling bin (free items left by others / the game), donations, environment info, set the town tune _(verify which desk)_
- [ ] **Town tune** editor: 16 notes, played on the hour by the town / hummed by villagers (`m_melody`, seq 248) 
- [ ] Change town flag? / town name is fixed after creation
- [ ] Tortimer statue in the plaza (`ac_douzou`) on loan payoff / founders' day
- [ ] Wishing Well: talk to the well spirit **Wishy the Star**; wish for a nice town; environment feedback (`ac_shrine`? / well)
- [ ] Recycle bin (`ac_reserve`? / recycling) — items rotate daily, free to take
- [ ] Bulletin board in the plaza: town notices, event announcements, villager birthday posts, player messages (`m_board_ovl`, `m_hboard_ovl`, `ac_htable`)
- [ ] Signboards / signposts around town naming acres, warning of cliffs, advertising (`ac_sign`)
- [ ] The plaza / town square as the event stage (K.K., fireworks, Tortimer speeches)

## 27. Train station & travel

- [~] Station building; **Porter** the monkey stationmaster (`ac_station`, `ac_npc_station_master`) — `intro_station_stage.gd`
- [~] Arrival by train on a new game: Rover on the train, get off, Porter greets, walk to Nook (`ac_train0/1`, `ac_intro_demo`) — `intro_train_stage.gd`, `intro_station_stage.gd`
- [ ] The train as the transition when a **friend visits from another Memory Card / town** (co-op): guest arrives at the station, explores your town, can trade/patterns; final Nookington's upgrade trigger (`m_train_control`, `ac_train_window`)
- [ ] Send a villager away / villager arrives by moving truck vs. train
- [ ] Gulliver? _(GCN Gulliver washes up on the **beach**, not the train)_
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

- [ ] **K.K. Slider** — Saturdays 20:00–24:00 at the train station; request a song by name or get a random one; take home a bootleg (aircheck); ~50 songs _(verify count)_ (`ac_npc_totakeke`, `mEv_EVENT_KK_SLIDER`, `m_music_ovl`, `m_mscore_ovl`)
- [ ] **Crazy Redd** — travelling black-market tent (needs Nook's referral card); furniture (some rare), carpets/wallpaper, and forged/real paintings; stock rotates (`ac_ev_broker`, `ac_ev_broker2`, `ac_br_shop`)
- [ ] **Saharah** — camel rug peddler; sells randomly, buys your old carpets; exclusive carpets/wallpaper (`ac_ev_gypsy`, `ac_ev_carpetPeddler`)
- [ ] **Wendell** — hungry walrus artist; give him food → free design pattern (`ac_ev_designer`, `ac_ev_artist`)
- [ ] **Gracie** — giraffe fashion designer with a car; assesses your outfit → gives Gracie-brand furniture/clothing if you pass; wash the car errand (`ac_s_car`, `ac_buggy`, `m_player_main_wash_car`, `ac_ev_castaway`?)
- [ ] **Gulliver** — seagull washed up (drunk) on the beach; wake him repeatedly → he flies off → mails a foreign item days later (`ac_ev_dokutu`? / castaway)
- [ ] **Wisp / Genie** — ghost you free from a bottle/lamp at night → wish granted (item or town favour) (`ac_ev_ghost`, `mEv_EVENT_GHOST`)
- [ ] **Sow Joan** — turnip seller, Sunday mornings (`ac_ev_kabuPeddler`, `ac_yomise`)
- [ ] **Katrina** the fortune teller — _not in GCN_ (skip; there is a gypsy/fortune role — verify)
- [ ] **Jingle** — reindeer, Toy Day (Dec 24); collects/gives presents (`ac_ev_santa`, `mEv_EVENT_TOY_DAY_*`)
- [ ] **Franklin** — turkey chef, Harvest Festival (US Thanksgiving); hides from villagers; fetch ingredients → furniture (`ac_ev_turkey`, `ac_harvest_npc*`, `mEv_EVENT_HARVEST_FESTIVAL`)
- [ ] **Pavé / dancers** — _later games_ (skip)
- [ ] **Chip** — beaver, fishing tourney host & judge (`ac_ev_angler`, `ac_turi_npc0`)
- [ ] **Nat** — _not GCN_ (skip)
- [ ] **Dr. Shrunk** — _not GCN_ (skip; emotions come from villagers)
- [ ] **Mr. Resetti / Don Resetti** (§1)
- [ ] **Rover** — cat on the train (new game + occasional visits) (`ac_npc_guide`)
- [ ] **Porter** — station master monkey (`ac_npc_station_master`)
- [ ] **Kapp'n** — boat to the island (`ac_npc_sendo`, `ac_boat`, `ac_boat_demo`)
- [ ] **Tom Nook**, **Timmy & Tommy**, **Blathers**, **Pelly & Phyllis**, **Copper & Booker**, **Sable & Mabel**, **Tortimer**, **Wishy**, **Joan**
- [ ] **Countdown NPCs** for New Year's Eve (`ac_countdown_npc0/1`)
- [ ] **Mask salesman** on weekdays (`ac_npc_mask_cat`, `mEv_EVENT_MASK_NPC`)
- [ ] **The shrine miko / hatsumōde** priest (`ac_ev_miko`, `ac_hatumode_control`) — _(JP; verify in GAFE)_

## 31. Holidays & seasonal events

From `m_event_schedule.c_inc` (117 schedule rows). Localised USA set:

- [ ] New Year's Day (Jan 1) — countdown the night before, Tortimer speech, party poppers
- [ ] Groundhog Day (Feb 2)
- [ ] Valentine's Day (Feb 14) — chocolate from a villager
- [ ] Snowman season / Kamakura (Dec–Feb) — build snowmen
- [ ] Spring Equinox / **Spring Sports Fair** (Mar 19–21) — aerobics, foot race, ball toss, tug-of-war
- [ ] April Fools' Day (Apr 1)
- [ ] Cherry Blossom Festival & petals (Apr 3–8)
- [ ] Nature Day (Apr 22)
- [ ] Spring Cleaning (May 1)
- [ ] Mother's Day (2nd Sun May), Father's Day (3rd Sun Jun)
- [ ] Fishing Tourney (June & November Sundays)
- [ ] Summer Camper / Graduation Day (June)
- [ ] Fireworks Show (Jul 4) — Tortimer sets them off in the plaza
- [ ] Town Day / Founders' Day (town-specific July date; Aug 21)
- [ ] Morning Aerobics (Jul 25 – Aug 31, 06:00 daily)
- [ ] Meteor Shower (Aug 12) — wish on shooting stars
- [ ] Labor Day (1st Mon Sep)
- [ ] Autumn Equinox / **Fall Sports Fair** (Sep 21–23)
- [ ] Explorers' Day (2nd Mon Oct)
- [ ] Mushroom season (mid-Oct)
- [ ] **Halloween** (Oct 31, 18:00–24:00) — wear a mask, trick-or-treat villagers, Jack the pumpkin king, candy, lollipops, spooky furniture (`ac_halloween_npc`, `ef_halloween`, `ac_ev_pumpkin`)
- [ ] Officers' Day (Nov 11), Mayor's Day
- [ ] **Harvest Festival** (4th Thu Nov) — Franklin
- [ ] The day after — **Sale Day** at Nook's
- [ ] Snow Day (Dec 1) — snow begins
- [ ] **Toy Day** (Dec 24) — Jingle, presents, Toy Day furniture; Tortimer Dec 23
- [ ] **New Year's Eve** (Dec 31 23:00) — countdown, fireworks, party
- [ ] Weekly: K.K. (Sat night), turnips (Sun AM), Tortimer/mayor rounds
- [ ] Monthly: bank interest, HRA report, lottery (last day), Nook stock reshuffle
- [ ] "Rumor" pre-event villager chatter for each holiday (`mEv_EVENT_RUMOR_*`)
- [ ] Tortimer "soncho" variant appearances for each holiday (`mEv_EVENT_SONCHO_*`)
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
- [ ] Town tune (16 notes) played on the hour and by clocks (`m_melody`, seq 248)
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
- [ ] The **name entry keyboard** for all text input
- [ ] Nook catalog browser UI, shop buy/sell UI, bank UI, HRA letter viewer, letter writer UI
- [ ] Photo / no screenshot feature (GCN has none)
- [ ] Trademark / logo / attract-mode title demo loop (`m_titledemo`, `m_trademark`, `ac_animal_logo`)
- [ ] Debug menus & dev overlays — _explicitly out of scope_ (`m_debug*`)

## 34. Simulation glue / world objects

- [ ] FG (foreground) object system: trees, rocks, flowers, weeds, signs, holes, buried marks, dropped items, structures, villager plot reserves (`m_bg_item`, `WorldObjectRegistry`) — `world_object_registry.gd`
- [ ] Daily FG renewal: weeds spread, flowers breed/wilt, plants grow, buried spot relocates, rock resets, shells respawn, recycle bin rotates, shop restocks
- [ ] Collision: heightfield, cliff/bank walls, 45° diagonals, water slide-off, structure footprints, plant caps (`m_collision_bg`) — `field_collision.gd`
- [ ] Blob shadows under actors & items (`m_actor_shadow`) — `actor_blob_shadow.gd`
- [ ] Effects library: dust, splash, sparkle, coins, leaves, sweat, music notes, impact stars, hearts, "?"/"!" etc. (`ef_*`, ~130 effects)
- [ ] Object draw sorting, XLU passes (water, footprints, shadows), acre culling
- [ ] Balloon presents drift across the sky on windy days; slingshot to drop (`ac_balloon`, `ac_fuusen`)
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
| Fish | ~40 (45 spawn types) | `ac_gyoei_type.c_inc`, `ac_set_ovl_gyoei.c` |
| Insects | ~40 | `ac_insect_data.c_inc`, `ac_set_ovl_insect.c` |
| Fossils | ~25 items / ~13 skeletons | `ac_museum_fossil.c` |
| Paintings | ~25 | `ac_museum_picture.c` |
| Gyroids | ~127 | `m_melody.c`, `ac_my_room_melody.c_inc` |
| Furniture | ~1000+ | `ac_furniture_data.c_inc`, `f_furniture.c` |
| Wallpaper / carpet | ~90 each | `m_item_name.c` |
| Clothing (shirts) | ~230 | `m_item_name.c` |
| Umbrellas | ~30 | `ac_t_umbrella.c` |
| Villagers (roster) | ~215 | `ac_npc_data.c_inc`, `m_name_table.c` |
| K.K. songs | ~50 | `m_music_ovl.c`, `m_mscore_ovl.c` |
| NES games | ~15–19 | `src/static/Famicom`, `famicom_emu.c` |
| Stationery | ~60 | `m_mail.c` |
| Hourly BGM tracks | 24 | `m_bgm.c` |
| Holidays / events | 117 schedule rows | `m_event_schedule.c_inc` |
| Calendar terms | 18 | `lb_rtc.c` |

---

_Last synced against ac-decomp `GAFE01_00` on 2026-09-07._
