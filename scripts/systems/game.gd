extends Node

## Composition root. Owns session phase, scene changes, interiors, shops, and world deltas that are not autoloads.

enum Phase { TITLE, INTRO, PLAYING }

const TITLE_SCENE := "res://scenes/ui/title.tscn"
## K.K. player-select opening (`ac_npc_p_sel`) before the Rover train.
const INTRO_KK_SCENE := "res://scenes/ui/intro_kk.tscn"
const INTRO_SCENE := "res://scenes/ui/intro_train.tscn"
const INTRO_STATION_SCENE := "res://scenes/ui/intro_station.tscn"
const WORLD_SCENE := "res://scenes/world/world.tscn"
const INTERIOR_SCENE := "res://scenes/world/interior.tscn"
const DEFAULT_SPAWN := Vector3(0.0, 0.1, 6.0)
const TEST_BELLS := 2000
const TEST_TOOL_IDS: Array[StringName] = [
	&"shovel",
	&"axe",
	&"net",
	&"fishing_rod",
	&"watering_can",
	&"apple_sapling",
	&"wood_chair",
	&"wood_table",
	&"wood_dresser",
	&"wood_tv",
	&"wall_blue",
	&"floor_tile",
]

signal phase_changed(phase: Phase)
signal prompt_changed(text: String)
signal notice_posted(text: String)
signal weather_changed(weather: StringName)
signal cloth_changed(cloth_id: StringName)
signal design_changed
## The player's face texture changed (`mPlib_change_player_face`): bee swelling.
signal face_changed

const DEFAULT_PLAYER_NAME := "Player"
const DEFAULT_TOWN_NAME := "Town"
const DEFAULT_PLAYER_GENDER := &"male"

var inventory: Inventory = Inventory.new()
var villagers: VillagerRoster = VillagerRoster.new()
## `animals[]` slots + move-in / move-out bookkeeping (`m_npc.c`).
var residents: TownResidents = TownResidents.new()
## `mSDI_StartInitAfter` runs once per load; the world resolves several times a session.
var _residents_session_done: bool = false
## `mNpc_Talk_Info_c` for this session (patience, "any work?" flag). Not saved.
var npc_talk_info: NpcTalkInfo = NpcTalkInfo.new()
## Deliveries, errands and villager contests (`Private_c.deliveries/errands`,
## `Animal_c.contest_quest`).
var quests: VillagerQuests = VillagerQuests.new()
## A villager asked for an item (`mSM_IV_OPEN_QUEST` / `_TAKE`): `quest_handover_pocket` is the
## only pocket offered, or with `quest_handover_mode` "fish" / "insect" any fish / bug.
var quest_handover_pending: bool = false
var quest_handover_pocket: int = -1
var quest_handover_mode: String = "quest"
signal quest_handover_resolved(item_id: StringName, pocket: int)
## `Private_c.hint_count`: first-job hints villagers still owe (bit 7 = all given).
var first_job_hint_count: int = 0
## Year the Valentine's letters went out (`event_save_common.valentines_day_date`).
var valentine_year: int = 0
## `Private_c.celebrated_birthday_year` / `birthday_present_npc`: the year the birthday
## visit came, and who brought it (left out of that year's cards).
var celebrated_birthday_year: int = 0
var birthday_present_npc: StringName = &""
## `EventDates.ordinal` of the last birthday-card check (the last play date).
var birthday_card_day: int = 0
## Mom's letters (`mPr_mother_mail_info_c`): the last day checked and which went out. Saved.
var mother_mail: Dictionary = MotherMail.new_state()
## `Common_Get(complete_payment_type)`: a paid-off loan or the end of Nook's chores, cheered
## the next time the player walks out of a door (`m_player_main_complete_payment`).
const PAYMENT_HOUSE := &"house"
const PAYMENT_ARBEIT := &"arbeit"
var complete_payment: StringName = &""
## Tortimer's exercise card (`mPr_day_day_c radiocard`): last stamp date and stamps. Saved.
var radio_card: Dictionary = RadioCard.new_state()
## The calendar's played days and Tortimer days (`mCD_player_calendar_c`). Saved.
var calendar: Dictionary = CalendarBook.new_state()
## The fishing tourney's records (`Save_Get(fishRecord)`), `FishRecord`. Saved.
var fish_records: Array = []
## `treasure_buried_time` / `treasure_checked_time` as ordinals (0 never). Saved.
var treasure_buried_day: int = 0
## `Save_Get(haniwa_scheduled)`: fine weather after rain orders gyroids for the next growth
## (`mAGrw_OrderSetHaniwa`); `BuriedUse.renew` buries them and clears it.
var haniwa_scheduled: bool = false
## `HOLE_SHINE`: the hole the day's shine spot left (`bIT_common_bury_after`).
var shine_hole: StringName = &""
var treasure_checked_day: int = 0
## The last board check wrote no seasonal notice, so a villager may bury treasure.
var treasure_due: bool = false
var relationships: RelationshipBook = RelationshipBook.new()
var interiors: InteriorBook = InteriorBook.new()
## The town's human residents and which one is playing (`PlayerRoster`). Read from the save at
## Continue; a fresh town starts with an empty roster and the new resident in slot 0.
var roster: PlayerRoster = PlayerRoster.new()
var shops: ShopBook = ShopBook.new()
var museum: MuseumBook = MuseumBook.new()
var species_log: SpeciesLog = SpeciesLog.new()
var police: PoliceBook = PoliceBook.new()
var post: PostBook = PostBook.new()
var farway: FarwayBook = FarwayBook.new()
var redd: ReddBook = ReddBook.new()
## Every catalog item the player has owned + Nook mail orders (`m_catalog_ovl`).
var catalog: CatalogBook = CatalogBook.new()
## `Save_Get(fruit)`: the town's native fruit. Other fruit sells to Nook at the foreign price.
var town_fruit: StringName = &"apple"
## Holidays, weekly visitors and the special-NPC schedule (`m_event`); see `EventCalendar`.
var events: EventCalendar = EventCalendar.new()
## The waterfall rainbow after rain (`mEnv_rainbow_*`).
var rainbow: Rainbow = Rainbow.new()
## The community board's posts (`m_notice`).
var notice_board: NoticeBoard = NoticeBoard.new()
## The Happy Room Academy's membership and marks (`m_mark_room`).
var hra: HappyRoomAcademy = HappyRoomAcademy.new()
var _rainbow_accum: float = 0.0
var designs: DesignBook = DesignBook.new()
var first_job: FirstJob = FirstJob.new()
## The town train (`m_train_control`), run for the whole session.
var train: TrainService
var current_room_id: StringName = &""
var outdoor_return: Vector3 = DEFAULT_SPAWN
var outdoor_return_yaw: float = 0.0
var spawn_at_room_door: bool = false
## Museum wing door spawns (`Door_data_c.exit_position` / orientation).
var has_interior_spawn: bool = false
var interior_spawn_gx: Vector3 = Vector3.ZERO
var interior_spawn_yaw: float = 0.0
## After a room load, ignore walk-in doors until the player steps clear of sensors.
var block_auto_enter_doors: bool = false
## After indoor leave, world plays structure leave + player GO_OUT (`mPlayer_INDEX_OUTDOOR`).
var emerge_from_door: bool = false
## Set by `continue_game` for an outdoor save: the world spawns the player at their own door.
var continue_from_house: bool = false
## After spawn, walk INTO_S1 past the door (museum entrance / wing links).
var play_door_arrive: bool = false
## `Common_Get(last_scene_no)`: the room the player last walked out of (Copper greets
## you outside the police box). Session-only.
var last_room_id: StringName = &""
var interior_session: IndoorSession
var player_name: String = DEFAULT_PLAYER_NAME
var town_name: String = DEFAULT_TOWN_NAME
var player_gender: StringName = DEFAULT_PLAYER_GENDER
var player_face: int = 0
## Worn shirt (`Private_c.cloth.item`). Default `ITM_CLOTH001`.
var cloth_id: StringName = FirstJob.DEFAULT_CLOTH_ID
## `Private_c.destiny` (`mPr_DESTINY_*`): the day's fortune from Katrina (`ac_ev_gypsy`) or
## the New Year shrine (`ac_ev_miko`); both reset it at the next calendar day.
enum Destiny { NORMAL, POPULAR, UNPOPULAR, BAD_LUCK, MONEY_LUCK, GOODS_LUCK }
var destiny_type: int = Destiny.NORMAL
var destiny_date: Vector3i = Vector3i.ZERO
## Worn original design display slot (`cloth.idx >= CLOTH_NUM+1`). -1 = normal shirt.
var worn_design_slot: int = -1
## Town map unlocked after first-job furniture delivery (`Common.map_flag`).
var has_map: bool = false
## `Save_Get(num_statues)` — how many Nook house statues the town has built (0..3, gold →
## jade); the next one takes the following rank.
var num_statues: int = 0
## `mPr_FLAG_POSTOFFICE_GIFT0..3`: balance milestones already rewarded (`BankTerminal.GIFTS`).
var bank_gift_flags: int = 0
## `Save_Get(melody)`: the town tune (`TownTune`), set at the tune board.
var town_tune: PackedByteArray = TownTune.default_notes()
## `Private_c.complete_fish_insect_flags` — see `CompleteTalk`.
var complete_flags: int = 0
## `goki_shocked_flag`: the first roach of a session startles the player, once.
var goki_shocked: bool = false
## `player_bee_swell_flag`: stung by bees — the swollen face lasts until the game is reset
## (common data, never saved).
var bee_swell: bool = false
## `player_bee_chase_flag`: a swarm is out after the player (villagers cry "Bees!").
var bee_chase: bool = false
## `npclist[].conversation_flags.beesting`, inverted: villagers who have greeted the player
## since the sting and so no longer remark on the face.
var bee_greeted: Dictionary = {}
## `Private_c.reset_count`: sessions ended without saving (saved).
var reset_count: int = 0
## `Common_Get(reset_flag)`: this session follows one of those — Mr. Resetti is waiting.
var reset_flag: bool = false
## `Save.cheated_flag` / `npc_force_go_home`: the clock was found earlier than the last save
## (`aNPS2_game_start_wait`). Saved; it bars the birthday surprise.
var cheated_flag: bool = false
## Session weather (`mEnv_WEATHER_*`). Rolled by `Weather` on `field_renewed`.
var weather: StringName = &"clear"
## False until `sync_events` has adopted the clock for this session.
var _events_ready: bool = false

## `Save_Get(insect_term)` / `insect_term_transition_offset` — the month whose
## insect spawn table is currently "settled in" and a per-month random 0-5 day
## offset for the cross-month blend (`aSOI_ins_chk_term_info`). Session-scoped.
var insect_term_month: int = 0
var insect_term_offset: int = 0
## `Save_Get(gyoei_term)` / `gyoei_term_transition_offset` — same, for fish, but keyed
## to the 24 half-month terms (`aSOG_gyoei_chk_term_info`).
var gyoei_term: int = 0
var gyoei_term_offset: int = 0
## `mEnv_WEATHER_INTENSITY_*` (none/light/normal/heavy).
var weather_intensity: int = int(Weather.Intensity.NONE)
var dialogue_vars: Dictionary = {}
var phase: Phase = Phase.TITLE
var player_position: Vector3 = DEFAULT_SPAWN
var player_yaw: float = 0.0
var removed_interactables: Array[String] = []
var stump_interactables: Array[String] = []
var hole_interactables: Array[String] = []
## Weeds in the field (`GRASS_A`–`GRASS_C`): `weed_<x>_<z>` → variant 0–2. Saved.
var weeds: Dictionary = {}
## `Save.clear_grass`: a wish has cleared the town of weeds; none grow back (saved).
var clear_grass: bool = false
## Renewals not yet sown with weeds (crossed indoors or while the game was off). Saved.
var weed_days_pending: int = 0
## `mFAs_GetFieldRank`: the town's rating 0–6 from the last assessment.
var field_rank: int = 0
## `Save.good_field`: days in a row at rank 6 and the day last counted (−1 none). Saved.
var perfect_streak: int = 0
var perfect_streak_day: int = -1
## `Save.dust_flag`: trash pushed the rating to nothing; it stays there until it is all gone.
var dust_flag: bool = false
## `mSC_TROPHY_GOLDEN_AXE`: the wishing well has given the golden axe. Saved.
var golden_axe_got: bool = false
## `mPlib_Check_golden_item_get_demo_end(SHOVEL)`: the golden shovel's fanfare has played.
var golden_shovel_shown: bool = false
## `mFI_GetDigStatus`'s `old_pos`: where the golden shovel last dug (session only).
var golden_last_dig: Vector2i = Vector2i(-1, -1)
## `unk_nook_present_count`: presents Nook has handed over for codes this session.
var nook_code_gifts: int = 0
## `allgrow_ss_pos_info.stone_pos`: the rock that pays out Bells ("" none or spent). Saved.
var money_rock: String = ""
## The day the money rock was last picked (−1 never), so a spent one waits for tomorrow. Saved.
var money_rock_day: int = -1
## `ITM_FOOD_MUSHROOM` on the field: `mushroom_<x>_<z>` → 1. Saved.
var mushrooms: Dictionary = {}
## `Save.mushroom_time`: when mushrooms were last set or cleared (`Clock.absolute_minute`, −1
## never) and `active`: a new day has started, so the 8 AM crop may grow. Saved.
var mushroom_minute: int = -1
var mushroom_active: bool = false
## `mMsr_FirstClearMushroom` has run for this play session (not saved).
var mushrooms_session_cleared: bool = false
## Signboards the residents put up (`SignboardUse`): `signboard_<x>_<z>` → `{design}`. Saved.
var signboards: Dictionary = {}
## The second bridge Tortimer builds (`SecondBridge`, `Save_Get(bridge)`). Saved.
var bridge: Dictionary = {}
## Things lying on the field (`FieldItems`): `fitem_<x>_<z>` → {id, wrapped}. Saved.
var field_items: Dictionary = {}
## Sea shells on the beach (`ShellUse`): `shell_<x>_<z>` → item id. Saved.
var shells: Dictionary = {}
## Shells still to wash up: twenty when a session starts (`mFI_SetFirstSetShell`).
var shells_owed: int = ShellUse.FIRST_NUM
var shell_minute_counted: bool = false
## `Save.snowmen`: three slots, each {} or {head, body (sizes 0–1), score, cell [x, z], age}.
var snowmen: Array = [{}, {}, {}]
## `Save.snowman_year…hour` as `Clock.absolute_minute` (−1 never): no new balls until 6 AM.
var snowman_built_minute: int = -1
## `Common.snowman_msg_id` (`mSN_decide_msg`): rolled each play session, not saved.
var snowman_msg_id: int = 0
## The snowman-season balls (`mEv` common place / area): part → {cell [x, z], dist}. Saved.
var snowballs: Dictionary = {}
## The town's ball (`Common_Get(ball_pos)` / `ball_type`), `BallUse`. Saved.
var ball: Dictionary = {}
## `Private.sunburn`: {rank 0–8, changed (day number of the last change), hold (days)}.
var sunburn: Dictionary = {"rank": 0, "changed": -1, "hold": 0}
## The diary (`mCD_keep_diary_c`): month 1–12 → that month's page. Saved.
var diary: Dictionary = {}
## `Common.money_power` / `goods_power`: the house's feng shui (`FengShui`), recomputed on
## the way out to the field. Not saved.
var money_power: int = 0
var goods_power: int = 0
var plant_states: Dictionary = {}
## Buried dig spots: persist_id → {kind, item_id, cell_x, cell_z} (`mFI` deposit / shine).
var buried_deposits: Dictionary = {}
var interact_prompt: String = ""
var world_mode: WorldData.Mode = WorldData.Mode.TEST
var world_seed: int = WorldGenerator.DEFAULT_SEED
## Town grass motif (`bg_tex_idx`): 0 triangle, 1 square, 2 circle.
var grass_pattern: int = WorldData.GrassPattern.TRIANGLE
## Station arrival (`ac_intro_demo`) runs inside the generated world, not a test acre.
## K.K.'s scene runs the player select of an existing town (`ac_npc_p_sel2`) rather than the
## first-time opening (`ac_npc_p_sel`).
var player_select_mode: bool = false
## This town's identity, so a passport knows its home (`mLd_CheckThisLand`). Random per town.
var town_id: int = 0
## Playing as a visitor from another town (`mPr_FOREIGNER`): no house here, and the only way
## out is Porter at the station, who saves the town and the passport.
var foreigner: bool = false
## Come in on the train (a visitor, or a traveller back home): start on the platform.
var arrive_by_train: bool = false
## Blanca's face and painter in this town (`Save_Get(mask_cat)`, `MaskCat`).
var mask_cat: Dictionary = {}
## The resident has met Blanca on a train before (`mPr_FLAG_1`: 0x33F3, not 0x33F2).
var met_blanca: bool = false
## `mPr_FLAG_MASK_CAT_SCHEDULED`: she rode the last trip home, so not this one.
var mask_cat_scheduled: bool = false
## The roster slot a newcomer to an existing town takes (`aNPS2_TALK_START_TYPE3`), or -1
## for a brand-new town.
var joining_slot: int = -1
## Another resident whose house the player is inside (their rooms are swapped in), or -1.
var visiting_slot: int = -1
var _own_house_stash: Dictionary = {}
var intro_station_active: bool = false
## After Porter until debt/job finish — vacant myhome doors are enterable for the pick.
var intro_station_can_pick_house: bool = false
## Resume debt/job after leaving the chosen house (`IN_HOUSE` → outdoor).
var intro_station_resume_debt: bool = false
var intro_station_house_id: StringName = &""
## Player pressed A on a vacant plot; director plays `msg_2020` then enters.
signal intro_house_look_requested(house_id: StringName)
var intro_pending_house_id: StringName = &""
## `aNRG_demand_payment`: after the debt line Nook opens the pockets (`mSM_IV_OPEN_QUEST`)
## so the player hands over the starting money bag before the job talk.
var intro_payment_pending: bool = false
signal intro_payment_resolved(paid: bool)

## Title attract mode (`SCENE_TITLE_DEMO`): `title.tscn` hosts the generated town with a
## recorded player. Cleared by `reset_session`, so any real entry point drops it.
var title_demo_active: bool = false
var title_demo_index: int = 0

## `mMmd` museum donation: Blathers opens the pockets so the player picks what to hand
## over. `museum_donate_result` holds the last outcome for his response dialogue.
var museum_donate_pending: bool = false
var museum_donate_result: Dictionary = {}
signal museum_donate_resolved(donated: bool)
## Nook's "I want to sell" (`mSM_IV_OPEN_SELL`): the pockets are open for picking what to sell.
var shop_sell_pending: bool = false
## Pocket slots picked by "Sell" / "Sell all".
var shop_sell_slots: Array[int] = []
signal shop_sell_resolved(picked: bool)
## A drawer / music player asked for an item from the pockets (`mSM_IV_OPEN_PUTIN_FTR` /
## `mSM_IV_OPEN_MINIDISK`). `storage_putin_filter` is `&"any"` or `&"minidisk"`.
var storage_putin_pending: bool = false
var storage_putin_filter: StringName = &"any"
signal storage_putin_resolved(item_id: StringName)


func _init() -> void:
	villagers.book = relationships
	if museum == null:
		museum = MuseumBook.new()


func _ready() -> void:
	if museum == null:
		museum = MuseumBook.new()
	train = TrainService.new()
	train.name = "Train"
	add_child(train)
	ReddBook.ensure_art_items()
	if not Clock.field_renewed.is_connected(_on_field_renewed):
		Clock.field_renewed.connect(_on_field_renewed)
	if not Clock.time_changed.is_connected(sync_events):
		Clock.time_changed.connect(sync_events)
	if not events.event_started.is_connected(_on_event_started):
		events.event_started.connect(_on_event_started)
		events.event_ended.connect(_on_event_ended)


func has_continue() -> bool:
	for path: String in SaveService.slot_paths:
		if SaveService.has_save(path):
			return true
	return false


func start_new_game(
	mode: WorldData.Mode = WorldData.Mode.TEST,
	seed_value: int = WorldGenerator.DEFAULT_SEED,
	identity: Dictionary = {}
) -> void:
	reset_session()
	_apply_identity(identity)
	world_mode = mode
	world_seed = seed_value
	if world_mode == WorldData.Mode.GENERATED:
		grass_pattern = WorldGenerator.decide_grass_pattern(seed_value)
	else:
		grass_pattern = WorldData.GrassPattern.TRIANGLE
	if identity.is_empty() or not Clock.rtc_override:
		Clock.rtc_override = false
		Clock.sync_from_os()
	apply_weather_roll(Weather.roll())
	if world_mode == WorldData.Mode.TEST:
		give_test_tools()
	_change_scene(WORLD_SCENE)


func start_intro_sequence() -> void:
	## Title fades out black before the swap (`ac_animal_logo` / title-demo
	## `WIPE_TYPE_FADE_BLACK`); `intro_kk._ready` fades back in.
	await SceneTransition.play_wipe_out(SceneTransition.Style.FADE)
	reset_session()
	Clock.rtc_override = false
	Clock.sync_from_os()
	_set_phase(Phase.INTRO)
	_change_scene(INTRO_KK_SCENE)


func start_intro_station() -> void:
	## Debug entry: station arrival slice (`ac_intro_demo`) in a fresh town, with no
	## K.K. / Rover segment before it. The chained flow arrives here via
	## `finish_intro_sequence` instead.
	await SceneTransition.play_wipe_out(SceneTransition.Style.FADE)
	var seed_value: int = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())
	_begin_station_arrival(seed_value, {}, true)


func begin_title_demo(index: int) -> void:
	## `trademark_goto_demo_scene`: fixed date, time and weather (`tradeday_table`), a randomised
	## resident (`mPr_RandomSetPlayerData_title_demo`), a random grass motif
	## (`mFM_DecideBgTexIdx`), and the recording's tool and spawn. Nothing here is saved: every
	## real entry point (`start_*`, `continue_game`) begins with `reset_session()`.
	reset_session()
	title_demo_active = true
	title_demo_index = index
	var moment: Dictionary = TitleDemo.trade_day(index)
	Clock.set_datetime(
		Clock.MIN_YEAR + 1, int(moment["month"]), int(moment["day"]), int(moment["hour"])
	)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var who: Dictionary = TitleDemo.random_identity(rng)
	player_gender = who["gender"] as StringName
	player_face = int(who["face"])
	cloth_id = who["cloth"] as StringName
	world_mode = WorldData.Mode.GENERATED
	world_seed = WorldGenerator.DEFAULT_SEED
	grass_pattern = rng.randi_range(0, WorldData.GRASS_PATTERN_COUNT - 1)
	set_weather(moment["weather"] as StringName)
	var tool_id: StringName = TitleDemo.tool_item_id(index)
	if tool_id != &"":
		var tool: ItemData = ItemCatalog.get_item(tool_id)
		if tool != null:
			inventory.add(tool, 1)
			for i: int in Inventory.POCKET_SLOTS:
				var slot: InventorySlot = inventory.slot_at(i)
				if slot != null and not slot.is_empty() and slot.item.item_id == tool_id:
					inventory.equip_slot(i)
					break
	var town := WorldData.new()
	town.columns = WorldGenerator.FG_X * WorldGenerator.UT
	town.rows = WorldGenerator.FG_Z * WorldGenerator.UT
	town.cell_size = 2.0
	player_position = TitleDemo.gx_to_world(town, TitleDemo.spawn_gx(index))
	player_yaw = TitleDemo.spawn_yaw(index)


func _begin_station_arrival(seed_value: int, identity: Dictionary, sync_clock: bool) -> void:
	## New town + outdoor station-arrival demo (decomp: `aNGD_scene_change_wait_init`
	## creates the town, then `ac_intro_demo` runs Porter → Nook → house pick → debt).
	reset_session()
	_apply_identity(identity)
	if sync_clock:
		Clock.rtc_override = false
		Clock.sync_from_os()
	intro_station_active = true
	intro_station_can_pick_house = false
	intro_station_resume_debt = false
	intro_station_house_id = &""
	intro_pending_house_id = &""
	world_mode = WorldData.Mode.GENERATED
	world_seed = seed_value
	grass_pattern = WorldGenerator.decide_grass_pattern(seed_value)
	apply_weather_roll(Weather.roll())
	_grant_intro_start_items()
	intro_payment_pending = false
	_set_phase(Phase.INTRO)
	_change_scene(WORLD_SCENE)


## K.K. found a passport from another town (`aNPS2_TALK_START_TYPE2`): arrive by train as a
## visitor.
func start_visit() -> void:
	reset_session()
	player_select_mode = false
	if SaveService.load_visitor(Travel.read_passport()) != OK:
		abort_intro_sequence()
		return
	resume_clock(SaveService.last_elapsed)
	_arrive_by_train()


## K.K. found this town's own traveller's passport (`aNPS2_TALK_START_TYPE1`): copy them back
## into their slot and come home on the train.
func start_return() -> void:
	var slot: int = Travel.adopt_passport()
	if slot < 0:
		abort_intro_sequence()
		return
	reset_session()
	player_select_mode = false
	if SaveService.load_game("", slot) != OK:
		abort_intro_sequence()
		return
	resume_clock(SaveService.last_elapsed)
	SaveService.mark_session_open(reset_count)
	_arrive_by_train()


func _arrive_by_train() -> void:
	arrive_by_train = true
	current_room_id = &""
	continue_from_house = false
	update_notice_board()
	_set_phase(Phase.PLAYING)
	_change_scene(WORLD_SCENE)


## Porter saw the traveller off (`aSTM_game_end_init`): the train leaves for the title.
func depart_by_train() -> void:
	await SceneTransition.play_wipe_out(SceneTransition.Style.FADE)
	_set_phase(Phase.TITLE)
	_change_scene(TITLE_SCENE)


## A newcomer's arrival in the saved town (`mCD_START_COND_2`): the town as it is, an empty
## resident in `joining_slot`, then the same station arrival — Porter, Nook, a vacant house.
func _begin_resident_arrival(identity: Dictionary) -> void:
	var slot: int = joining_slot
	joining_slot = -1
	reset_session()
	if SaveService.load_game("", slot) != OK:
		var seed_value: int = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())
		_begin_station_arrival(seed_value, identity, false)
		return
	resume_clock(SaveService.last_elapsed)
	var town: String = town_name
	_apply_identity(identity)
	town_name = town
	intro_station_active = true
	intro_station_can_pick_house = false
	intro_station_resume_debt = false
	intro_station_house_id = &""
	intro_pending_house_id = &""
	_grant_intro_start_items()
	intro_payment_pending = false
	_set_phase(Phase.INTRO)
	_change_scene(WORLD_SCENE)


## Walk into another resident's house: their rooms and house record stand in for the
## player's own until they come back out (`aMHS_goto_next_pl_scene` to that house's scene).
func enter_resident_house(slot: int) -> void:
	if slot < 0 or slot == roster.current or visiting_slot == slot:
		return
	if visiting_slot >= 0:
		leave_resident_house()
	_own_house_stash = PlayerRoster.capture_house(interiors)
	PlayerRoster.restore_house(interiors, roster.slots[slot])
	visiting_slot = slot


## Back outside from another resident's house: their rooms go back to their slot.
func leave_resident_house() -> void:
	if visiting_slot < 0:
		return
	var theirs: Dictionary = PlayerRoster.capture_house(interiors)
	var priv: Dictionary = roster.slots[visiting_slot]
	priv[PlayerRoster.KEY_ROOMS] = theirs[PlayerRoster.KEY_ROOMS]
	priv[PlayerRoster.KEY_HOUSE] = theirs[PlayerRoster.KEY_HOUSE]
	roster.forget_house(visiting_slot)
	PlayerRoster.restore_house(interiors, _own_house_stash)
	_own_house_stash = {}
	visiting_slot = -1


func _grant_intro_start_items() -> void:
	## `m_start_data_init.c`: a new resident starts with one QUEST-flagged 1,000-bell
	## bag in pocket slot 0 — the down payment Nook collects after the house tour.
	var bag: ItemData = ItemCatalog.get_item(&"money_1000")
	if bag != null and inventory.count_of(&"money_1000") == 0:
		inventory.add(bag, 1, InventoryItem.Condition.QUEST)


func notify_intro_payment_made() -> void:
	if not intro_payment_pending:
		return
	intro_payment_pending = false
	intro_payment_resolved.emit(true)


func notify_intro_payment_declined() -> void:
	if not intro_payment_pending:
		return
	intro_payment_pending = false
	intro_payment_resolved.emit(false)


## Blathers asks for a donation — open the pockets so the player picks (`mMmd` / IV_OPEN).
func request_museum_donation() -> void:
	museum_donate_pending = true
	museum_donate_result = {}
	if get_tree() == null:
		return
	var inv_ui: Node = get_tree().get_first_node_in_group("inventory_ui")
	if inv_ui != null and inv_ui.has_method("open"):
		inv_ui.call("open")


## The player picked an item in the donate-select pockets. Books the outcome and tells
## Blathers to respond. Rejections do not consume the item.
func take_museum_donation(item_id: StringName) -> void:
	if not museum_donate_pending:
		return
	museum_donate_pending = false
	museum_donate_result = donate_museum_result(item_id)
	museum_donate_result["item_id"] = String(item_id)
	museum_donate_resolved.emit(true)


## Pockets closed with nothing chosen.
func cancel_museum_donation() -> void:
	if not museum_donate_pending:
		return
	museum_donate_pending = false
	museum_donate_result = {}
	museum_donate_resolved.emit(false)


## Nook opens the pockets in sell mode (`aNSC_buy_menu_close_wait_init`). Picking
## "Sell" / "Sell all" or closing resolves `shop_sell_resolved`.
func request_shop_sell() -> void:
	shop_sell_pending = true
	shop_sell_slots = []
	if get_tree() == null:
		return
	var inv_ui: Node = get_tree().get_first_node_in_group("inventory_ui")
	if inv_ui != null and inv_ui.has_method("open"):
		inv_ui.call("open")


func take_shop_sell(slots: Array[int]) -> void:
	if not shop_sell_pending:
		return
	shop_sell_pending = false
	shop_sell_slots = slots
	shop_sell_resolved.emit(not slots.is_empty())


func cancel_shop_sell() -> void:
	if not shop_sell_pending:
		return
	shop_sell_pending = false
	shop_sell_slots = []
	shop_sell_resolved.emit(false)


## Open the pockets so the player picks something to put away. `storage_putin_resolved` fires
## with the chosen item id, or `&""` when the pockets close without a pick.
func request_storage_putin(filter: StringName = &"any") -> void:
	storage_putin_pending = true
	storage_putin_filter = filter
	var inv_ui: Node = get_tree().get_first_node_in_group("inventory_ui") if get_tree() != null else null
	if inv_ui != null and inv_ui.has_method("open"):
		inv_ui.call("open")
	else:
		cancel_storage_putin()


func take_storage_putin(item_id: StringName) -> void:
	if not storage_putin_pending:
		return
	storage_putin_pending = false
	storage_putin_resolved.emit(item_id)


func cancel_storage_putin() -> void:
	if not storage_putin_pending:
		return
	storage_putin_pending = false
	storage_putin_resolved.emit(&"")


func complete_intro_station() -> void:
	## Stay in the current generated world; unlock normal play + first job.
	intro_station_active = false
	intro_station_can_pick_house = false
	intro_station_resume_debt = false
	intro_payment_pending = false
	intro_pending_house_id = &""
	## `aID_retire_rcn_guide_wait`: `Now_Private->inventory.loan = mPlayer_DEBT0` once
	## Nook has left — the balance after the 1,000-bell down payment.
	if inventory != null:
		inventory.set_loan(Inventory.INTRO_HOUSE_DEBT)
	## `mQst_SetFirstJobStart` after Nook EXIT (`aID_retire_rcn_guide_wait`).
	if first_job != null:
		first_job.begin_after_house()
	_set_phase(Phase.PLAYING)
	set_interact_prompt("Visit Tom Nook's shop")


func request_intro_house_look(house_id: StringName) -> void:
	## Vacant myhome interact during pick — Nook lines (`msg_2020`) before the door.
	if not intro_station_active or not intro_station_can_pick_house:
		return
	if house_id == &"":
		return
	intro_station_can_pick_house = false
	intro_pending_house_id = house_id
	set_interact_prompt("")
	intro_house_look_requested.emit(house_id)


func claim_intro_house(house_id: StringName) -> void:
	if not intro_station_active:
		return
	intro_station_house_id = house_id
	## The pick outlives the intro: the saved house record carries it (`PlayerHouse.owned_building_id`).
	var record: House = interiors.player_house() if interiors != null else null
	if record != null and house_id != &"":
		record.outdoor_building_id = house_id
	intro_pending_house_id = &""
	intro_station_can_pick_house = false
	intro_station_resume_debt = true


func advance_intro_to_train() -> void:
	## After K.K. fades out (`aNPS_setup_game_start` → `SCENE_START_DEMO`). The K.K. scene
	## has already run its strum-synced `%FadeRect` to black; hold the screen opaque across
	## the load so the train scene can fade itself back in (`aNPS` `transition.wipe_type =
	## WIPE_TYPE_FADE_BLACK`).
	SceneTransition.hold_black()
	_set_phase(Phase.INTRO)
	_change_scene(INTRO_SCENE)


func notify_intro_ready() -> void:
	_set_phase(Phase.INTRO)
	set_interact_prompt("")


func finish_intro_sequence(identity: Dictionary) -> void:
	## Rover's train pulls into town (`aNGD_scene_change_wait_init`): make the new town
	## and continue straight into the outdoor station arrival, keeping the clock the
	## player set on the train. A newcomer to a saved town arrives in that town instead.
	if joining_slot >= 0:
		_begin_resident_arrival(identity)
		return
	var seed_value: int = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())
	_begin_station_arrival(seed_value, identity, false)


func debug_finish_station_arrival(identity: Dictionary) -> void:
	## Exit path for the standalone `intro_station.tscn` dev scene, which has already
	## played its own Porter/Nook beats — drop into the world and start the first job.
	var seed_value: int = int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())
	start_new_game(WorldData.Mode.GENERATED, seed_value, identity)
	_grant_intro_start_items()
	if first_job != null:
		first_job.begin_after_house()
		_set_phase(Phase.PLAYING)
		set_interact_prompt("Visit Tom Nook's shop")


func abort_intro_sequence() -> void:
	intro_station_active = false
	intro_station_can_pick_house = false
	intro_station_resume_debt = false
	intro_station_house_id = &""
	intro_pending_house_id = &""
	## Drop any pending scene wipe so the title is not left under a black hold.
	SceneTransition.cancel_wipe()
	_set_phase(Phase.TITLE)
	_change_scene(TITLE_SCENE)


func _apply_identity(identity: Dictionary) -> void:
	if identity.is_empty():
		return
	player_name = str(identity.get("player_name", DEFAULT_PLAYER_NAME))
	if player_name.strip_edges().is_empty():
		player_name = DEFAULT_PLAYER_NAME
	town_name = str(identity.get("town_name", DEFAULT_TOWN_NAME))
	if town_name.strip_edges().is_empty():
		town_name = DEFAULT_TOWN_NAME
	player_gender = IntroSequence.normalize_gender(
		identity.get("player_gender", DEFAULT_PLAYER_GENDER)
	)
	player_face = clampi(
		int(identity.get("player_face", 0)), 0, IntroSequence.FACE_TYPE_NUM - 1
	)


func resolve_world_data() -> WorldData:
	var data: WorldData
	if world_mode == WorldData.Mode.GENERATED:
		data = WorldGenerator.generate(world_seed, title_demo_active)
		if not title_demo_active:
			_resolve_residents(data)
	else:
		data = WorldGenerator.authored_test_town()
	data.grass_pattern = grass_pattern
	FieldCatalog.set_grass_pattern(grass_pattern)
	return data


## New town: the generator's starters become the roster. Then, once per load, the
## `mSDI_StartInitAfter` villager steps (moving candidate, move-out, move-in, new house),
## and the houses are rebuilt from the roster.
func _resolve_residents(data: WorldData) -> void:
	if residents.is_empty():
		residents.adopt_from_houses(WorldGenerator.generated_houses(data))
	if not _residents_session_done:
		_residents_session_done = true
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var report: Dictionary = residents.start_session(_residents_context(data, rng))
		if report.get("moved_in", &"") != &"":
			villagers.get_or_create(report["moved_in"] as StringName)
		## `mNpc_ChangePresentCloth`.
		for id: StringName in residents.resident_ids():
			villagers.get_or_create(id).wear_present_cloth()
		## `mNpc_Remail`.
		VillagerLetters.send_replies(
			residents, relationships, Clock.day_number(), player_name, rng, _deliver_villager_mail
		)
		_check_valentines(rng)
	WorldGenerator.apply_residents(data, residents)


func _residents_context(data: WorldData, rng: RandomNumberGenerator) -> Dictionary:
	return {
		"rng": rng,
		"day": Clock.day_number(),
		"minute": Clock.absolute_minute(),
		"met": func(id: StringName) -> bool: return player_met(id),
		"letters": func(_id: StringName) -> int: return 0,
		"field_rank": field_rank,
		"reserves": data.reserve_cells,
		"on_goodbye": func(id: StringName, looks: int) -> void: _villager_moved_out(id, looks, rng),
	}


## `mNpc_GetAnimalMemoryIdx(player) != -1`: the player has a memory in this animal, made on
## first talk.
func player_met(villager_id: StringName) -> bool:
	return relationships.has_id(villager_id) and relationships.get_or_create(villager_id).has_memory


## `mNpc_ForceRemove`: goodbye letter to the player (`mNpc_SetGoodbyMailData`, mail
## `0x20E + looks × 3 + rand(3)`), then the animal's memories go with it (`mNpc_ClearAnimalInfo`).
func _villager_moved_out(villager_id: StringName, looks: int, rng: RandomNumberGenerator) -> void:
	var villager: VillagerData = VillagerCatalog.get_villager(villager_id)
	var name: String = villager.display_name if villager != null else String(villager_id)
	if looks >= 0 and looks < TownResidents.LOOKS_NUM and MailBank.has_bank():
		var mail_no: int = 0x20E + looks * 3 + rng.randi_range(0, 2)
		var text: Dictionary = MailBank.letter(mail_no, player_name, {0: player_name, 1: name, 3: town_name})
		var mail := MailData.new()
		mail.sender_id = villager_id
		mail.sender_name = name
		mail.sender_type = MailData.NameType.NPC
		mail.recipient_type = MailData.NameType.PLAYER
		mail.recipient_name = player_name
		mail.font = MailData.LetterFont.RECV
		mail.header = str(text["header"])
		mail.body = str(text["body"])
		mail.footer = str(text["footer"])
		## `mNpc_GetPaperType`: a random stationery pick (the shop paper lists aren't ported).
		mail.paper_type = rng.randi_range(0, MailBank.PAPER_NUM - 1)
		## Home mailbox first, else the post office keeps it (`mNpc_SendGoodbyAnimalMailOne`).
		if inventory.add_received_mail(mail) < 0 and post != null:
			post.receipt_mail(mail)
	relationships.forget(villager_id)
	villagers.forget(villager_id)


func _physics_process(delta: float) -> void:
	## `mNpc_TalkInfoMove` runs every play frame.
	if phase == Phase.PLAYING:
		npc_talk_info.advance(delta)
		## `mEnv_rainbow_power_calc` runs in field (FG) scenes only.
		if current_room_id == &"":
			_rainbow_accum += delta * DecompTime.TICK_HZ
			while _rainbow_accum >= 1.0:
				_rainbow_accum -= 1.0
				rainbow.tick(Clock.month, Clock.day, Clock.now_sec(), Clock.season() == Clock.Season.SUMMER)


## `mFI_CheckPlayerWade(mFI_WADE_START)`.
func notify_wade_start() -> void:
	npc_talk_info.on_wade_start()


## `vt_wt_mail_check`: Valentine's letters once, on February 14th.
func _check_valentines(rng: RandomNumberGenerator) -> void:
	if Clock.month != 2 or Clock.day != 14 or valentine_year == Clock.year:
		return
	valentine_year = Clock.year
	VillagerLetters.send_valentines(
		residents, relationships, player_gender == &"female", player_name, rng,
		func(mail: MailData) -> bool: return inventory.add_received_mail(mail) >= 0
	)


## Birthday cards once the birthday has passed since the last check
## (`mNpc_SendEventBirthdayCard2`). On the day itself the villager who will bring the present
## is picked now, so their card doesn't come as well.
func _check_birthday_cards(rng: RandomNumberGenerator) -> void:
	var today: int = EventDates.ordinal(Clock.year, Clock.month, Clock.day)
	var last: int = birthday_card_day
	birthday_card_day = today
	var bd: Vector2i = VillagerTalkManager.birthday()
	if not PresentVisit.birthday_passed(bd, last, today):
		return
	if celebrated_birthday_year != Clock.year:
		birthday_present_npc = (
			PresentVisit.birthday_npc(residents, relationships)
			if bd == Vector2i(Clock.month, Clock.day) else &""
		)
	var sent: int = PresentVisit.send_cards(
		residents, relationships, birthday_present_npc, player_name, rng,
		func(mail: MailData) -> bool: return inventory.add_received_mail(mail) >= 0 or post.receipt_mail(mail)
	)
	if sent > 0:
		post_notice("You've got mail!")


## `mCD_calendar_wellcome_on`: today goes on the calendar.
func note_played_today() -> void:
	CalendarBook.played_on(calendar, EventDates.ordinal(Clock.year, Clock.month, Clock.day))


## `mPO_business_proc`: the 9:00 and 17:00 rounds, and the first one of a session
## (`mPO_first_work`). Held letters reach the mailbox they are addressed to.
func _deliver_post(session_start: bool) -> void:
	if post == null or foreigner:
		return
	post.deliver(Clock.absolute_minute(), _post_to_resident, session_start)


func _post_to_resident(mail: MailData) -> bool:
	if mail.recipient_name == player_name:
		return inventory.add_received_mail(mail) >= 0
	for slot: int in PlayerRoster.MAX:
		if slot != roster.current and roster.name_of(slot) == mail.recipient_name:
			return roster.deliver_mail(slot, mail)
	## Nobody here by that name any more (`mMl_hunt_for_send_address` −1): it is dropped.
	return true


## `mPr_SendMailFromMother`: Mom writes, at most once a day.
func _check_mother_mail(rng: RandomNumberGenerator) -> void:
	var holiday: StringName = MotherMail.holiday(Clock.year, Clock.month, Clock.day)
	var sent: int = MotherMail.check(
		mother_mail, EventDates.ordinal(Clock.year, Clock.month, Clock.day), VillagerTalkManager.birthday(),
		holiday, player_name, rng,
		func(mail: MailData) -> bool: return inventory.add_received_mail(mail) >= 0 or post.receipt_mail(mail)
	)
	if sent >= 0:
		post_notice("You've got mail!")


## `mQst_SendRemail`: the contest-letter reply goes to the home mailbox only.
func deliver_to_mailbox(mail: MailData) -> bool:
	return inventory.add_received_mail(mail) >= 0


## Open the pockets so the player hands a villager their item. `quest_handover_resolved`
## fires with the item and pocket, or `&""` when the pockets close without one.
func request_quest_handover(pocket: int, mode: String = "quest") -> void:
	quest_handover_pending = true
	quest_handover_pocket = pocket
	quest_handover_mode = mode
	var inv_ui: Node = get_tree().get_first_node_in_group("inventory_ui") if get_tree() != null else null
	if inv_ui != null and inv_ui.has_method("open"):
		inv_ui.call("open")
	else:
		cancel_quest_handover()


## May this pocket be handed over right now?
func quest_handover_allows(pocket: int) -> bool:
	if not quest_handover_pending or inventory == null:
		return false
	var s: InventorySlot = inventory.slot_at(pocket)
	if s == null or s.is_empty():
		return false
	match quest_handover_mode:
		"fish", "insect":
			var data: ItemData = ItemCatalog.get_item(s.item.item_id)
			var want: int = ItemData.Category.FISH if quest_handover_mode == "fish" else ItemData.Category.BUG
			return data != null and data.category == want
		"take":
			## `mSM_IV_OPEN_TAKE`: any pocket (the peddler checks what it is).
			return true
		"shrine":
			## `mSM_IV_OPEN_SHRINE`: only quest items can go down the wishing well.
			return s.item.condition == InventoryItem.Condition.QUEST
	return pocket == quest_handover_pocket


func take_quest_handover(pocket: int) -> void:
	if not quest_handover_pending:
		return
	quest_handover_pending = false
	var s: InventorySlot = inventory.slot_at(pocket)
	var item: StringName = s.item.item_id if s != null and not s.is_empty() else &""
	quest_handover_resolved.emit(item, pocket)


func cancel_quest_handover() -> void:
	if not quest_handover_pending:
		return
	quest_handover_pending = false
	quest_handover_resolved.emit(&"", -1)


## `mQst_GetFlowerSeedNum` / `mQst_GetFlowerNum` / `mQst_GetNullNoNum` for a home acre.
func field_counts(block: Vector2i) -> Dictionary:
	return QuestField.counts(get_tree(), block)


## A villager's letter to the player: the mailbox, else the post office keeps it.
func _deliver_villager_mail(mail: MailData) -> bool:
	if inventory.add_received_mail(mail) >= 0:
		return true
	return post != null and post.receipt_mail(mail)


## Title → K.K.'s player select for the saved town (`SCENE_PLAYERSELECT`).
func start_player_select() -> void:
	await SceneTransition.play_wipe_out(SceneTransition.Style.FADE)
	reset_session()
	player_select_mode = true
	_set_phase(Phase.INTRO)
	_change_scene(INTRO_KK_SCENE)


## K.K. readies the town for a newcomer (`aNPS2_TALK_START_TYPE3`): Rover's train, then the
## station and a vacant house, in the saved town.
func start_new_resident(slot: int) -> void:
	player_select_mode = false
	joining_slot = slot
	advance_intro_to_train()


func continue_game(slot: int = -1) -> void:
	## Every real entry point starts clean; without this the title's attract-demo flag survived
	## into the loaded game and `notify_world_ready` kept the phase on TITLE (no Esc, no events).
	reset_session()
	player_select_mode = false
	if SaveService.load_game("", slot) != OK:
		start_new_game()
		return
	note_reset(SaveService.last_reset_code)
	resume_clock(SaveService.last_elapsed)
	SaveService.mark_session_open(reset_count)
	## `mMl_start_send_mail` / `mNtc_set_auto_nwrite_data` at game start.
	send_postoffice_gift()
	update_notice_board()
	mark_room()
	if current_room_id != &"":
		_change_scene(INTERIOR_SCENE)
	else:
		continue_from_house = not intro_station_active
		_change_scene(WORLD_SCENE)


func return_to_title() -> void:
	capture_player_from_tree()
	## A visitor can't save here (`save_menu_data_save_from`, `SAVE_ERROR_FLASHROM`): only Porter
	## sends them home with their things. Quitting drops this visit.
	if not foreigner:
		SaveService.save_game()
	_set_phase(Phase.TITLE)
	_change_scene(TITLE_SCENE)


func notify_world_ready() -> void:
	if world_mode == WorldData.Mode.TEST:
		give_test_tools()
	if intro_station_active:
		_set_phase(Phase.INTRO)
	elif title_demo_active:
		_set_phase(Phase.TITLE)
	else:
		_set_phase(Phase.PLAYING)
	sync_events()


func notify_title_ready() -> void:
	_set_phase(Phase.TITLE)
	set_interact_prompt("")


## The real-time clock ran on while the game was off; a clock set back marks the save.
func resume_clock(elapsed: int) -> void:
	if not Clock.resume_after(elapsed):
		cheated_flag = true


## `mFAs_GetFieldRank_Condition` / `mFAs_SetFieldRank`: rate the town now, keep the rank and
## the perfect-day streak. Returns the assessment ({rank, condition, block, …}).
## `at_well`: asked at the wishing well, where any remark at all also restarts the streak.
func rate_town(world: Node, rng: RandomNumberGenerator = null, at_well: bool = false) -> Dictionary:
	var roll := rng
	if roll == null:
		roll = RandomNumberGenerator.new()
		roll.randomize()
	var result: Dictionary = TownAssessment.evaluate(TownAssessment.survey(world), roll)
	## `dust_flag`: once trash sank the town, any trash left keeps it at nothing.
	if int(result["dust"]) >= TownAssessment.DUST_OVER_NUM:
		dust_flag = true
	elif dust_flag:
		if int(result["dust"]) > 0:
			result["rank"] = 0
			result["condition"] = TownAssessment.Condition.DUST_OVER
		else:
			dust_flag = false
	field_rank = int(result["rank"])
	if events != null:
		events.field_rank = field_rank
	if at_well and int(result["condition"]) != TownAssessment.Condition.NO_CASE:
		perfect_streak = 0
		perfect_streak_day = -1
	var next: Vector2i = TownAssessment.next_streak(field_rank, perfect_streak, perfect_streak_day, Clock.day_number())
	perfect_streak = next.x
	perfect_streak_day = next.y
	return result


## `mFAs_CheckGoodField`: fifteen perfect days in a row.
func perfect_town_long_enough() -> bool:
	return perfect_streak >= TownAssessment.PERFECT_STREAK_MAX


## `mHsRm_GetHuusuiRoom`.
func refresh_feng_shui() -> void:
	var p: Vector2i = FengShui.evaluate()
	money_power = p.x
	goods_power = p.y


## `mSN_MeltSnowman` at each renewal: a day older and smaller; gone after three days or once
## winter ends. The field drops the ones that melted when it next loads.
func melt_snowmen(days: int) -> void:
	var winter: bool = Clock.season() == Clock.Season.WINTER
	for i: int in snowmen.size():
		var e: Dictionary = snowmen[i]
		if e.is_empty():
			continue
		if not SnowmanRules.melt(e, days, winter):
			snowmen[i] = {}


## The renewals waiting for weeds, handed to the field once (`World` sows them).
func take_weed_days() -> int:
	var days: int = weed_days_pending
	weed_days_pending = 0
	return days


## `mCD_SetResetInfo`: the save was still marked open, so the last session ended without
## saving.
func note_reset(reset_code: int) -> void:
	reset_flag = reset_code != 0
	if reset_flag:
		reset_count += 1


## `Stung_bee` frame 21 of `HATI2`: the face swells (`mPlib_change_player_face`) and, on the
## first sting only, every villager gets a remark ready (`mNpc_SetTalkBee`).
func sting_by_bee() -> void:
	bee_chase = false
	if bee_swell:
		return
	bee_swell = true
	bee_greeted.clear()
	face_changed.emit()


## Whether `villager_id` still has the swollen-face remark to make.
func bee_remark_pending(villager_id: StringName) -> bool:
	return bee_swell and villager_id != &"" and not bee_greeted.has(villager_id)


## Any greeting spends the remark (`conversation_flags.beesting = FALSE`).
func note_bee_greeting(villager_id: StringName) -> void:
	if bee_swell and villager_id != &"":
		bee_greeted[villager_id] = true


## `mDemo_Copy_change_player_destiny`: record the fortune and the day it was received.
func set_destiny(kind: int) -> void:
	destiny_type = kind
	destiny_date = Vector3i(Clock.year, Clock.month, Clock.day)


## `Game_play_Reset_destiny`: a fortune only lasts the calendar day it was received.
func destiny() -> int:
	if destiny_type != Destiny.NORMAL and destiny_date != Vector3i(Clock.year, Clock.month, Clock.day):
		destiny_type = Destiny.NORMAL
	return destiny_type


func reset_session() -> void:
	roster = PlayerRoster.new()
	town_id = Travel.new_town_id()
	mask_cat = {}
	met_blanca = false
	mask_cat_scheduled = false
	foreigner = false
	arrive_by_train = false
	visiting_slot = -1
	_own_house_stash = {}
	destiny_type = Destiny.NORMAL
	destiny_date = Vector3i.ZERO
	inventory.clear()
	if train != null:
		train.reset()
	relationships.clear()
	interiors.clear()
	shops.clear()
	if museum == null:
		museum = MuseumBook.new()
	else:
		museum.clear()
	if species_log == null:
		species_log = SpeciesLog.new()
	else:
		species_log.clear()
	if police == null:
		police = PoliceBook.new()
	## `mPB_police_box_init` (`m_start_data_init`): a new town starts with three items.
	police.init_town()
	if post == null:
		post = PostBook.new()
	else:
		post.clear()
	interior_session = null
	insect_term_month = 0
	insect_term_offset = 0
	gyoei_term = 0
	gyoei_term_offset = 0
	current_room_id = &""
	outdoor_return = DEFAULT_SPAWN
	outdoor_return_yaw = 0.0
	spawn_at_room_door = false
	has_interior_spawn = false
	block_auto_enter_doors = false
	emerge_from_door = false
	play_door_arrive = false
	last_room_id = &""
	villagers.clear()
	villagers.book = relationships
	residents.clear()
	_residents_session_done = false
	npc_talk_info.clear()
	quests.clear()
	quest_handover_pending = false
	first_job_hint_count = 0
	valentine_year = 0
	celebrated_birthday_year = 0
	birthday_present_npc = &""
	birthday_card_day = 0
	mother_mail = MotherMail.new_state()
	radio_card = RadioCard.new_state()
	complete_payment = &""
	calendar = CalendarBook.new_state()
	fish_records.clear()
	treasure_buried_day = 0
	haniwa_scheduled = false
	shine_hole = &""
	treasure_checked_day = 0
	treasure_due = false
	VillagerWalk.reset()
	VillagerOutdoor.reset()
	Fishing.reset()
	player_position = DEFAULT_SPAWN
	player_yaw = 0.0
	removed_interactables.clear()
	stump_interactables.clear()
	hole_interactables.clear()
	weeds.clear()
	clear_grass = false
	weed_days_pending = 0
	field_rank = 0
	perfect_streak = 0
	perfect_streak_day = -1
	dust_flag = false
	golden_axe_got = false
	golden_shovel_shown = false
	golden_last_dig = Vector2i(-1, -1)
	nook_code_gifts = 0
	money_rock = ""
	money_rock_day = -1
	MoneyRock.reset()
	mushrooms_session_cleared = false
	mushrooms.clear()
	shells.clear()
	shells_owed = ShellUse.FIRST_NUM
	shell_minute_counted = false
	signboards.clear()
	field_items.clear()
	bridge = {}
	mushroom_minute = -1
	mushroom_active = false
	snowmen = [{}, {}, {}]
	snowman_built_minute = -1
	snowman_msg_id = randi_range(0, 2)
	ball = {}
	snowballs.clear()
	sunburn = {"rank": 0, "changed": -1, "hold": 0}
	Sunburn.reset_session()
	diary.clear()
	money_power = 0
	goods_power = 0
	plant_states.clear()
	buried_deposits.clear()
	player_name = DEFAULT_PLAYER_NAME
	town_name = DEFAULT_TOWN_NAME
	player_gender = DEFAULT_PLAYER_GENDER
	player_face = 0
	cloth_id = FirstJob.DEFAULT_CLOTH_ID
	has_map = false
	num_statues = 0
	reset_count = 0
	reset_flag = false
	cheated_flag = false
	bank_gift_flags = 0
	town_tune = TownTune.default_notes()
	complete_flags = 0
	goki_shocked = false
	bee_swell = false
	bee_chase = false
	bee_greeted.clear()
	if first_job == null:
		first_job = FirstJob.new()
	else:
		first_job.clear()
	weather = &"clear"
	weather_intensity = int(Weather.Intensity.NONE)
	dialogue_vars.clear()
	world_mode = WorldData.Mode.TEST
	world_seed = WorldGenerator.DEFAULT_SEED
	grass_pattern = WorldData.GrassPattern.TRIANGLE
	intro_station_active = false
	intro_station_can_pick_house = false
	intro_station_resume_debt = false
	intro_station_house_id = &""
	intro_pending_house_id = &""
	intro_payment_pending = false
	title_demo_active = false
	museum_donate_pending = false
	museum_donate_result = {}
	shop_sell_pending = false
	shop_sell_slots = []
	if farway == null:
		farway = FarwayBook.new()
	else:
		farway.clear()
	if redd == null:
		redd = ReddBook.new()
	else:
		redd.clear()
	if catalog == null:
		catalog = CatalogBook.new()
	else:
		catalog.clear()
	rainbow = Rainbow.new()
	notice_board = NoticeBoard.new()
	notice_board.seed(Clock.year, Clock.month, Clock.day, Clock.hour, Clock.minute)
	hra = HappyRoomAcademy.new()
	town_fruit = &"apple"
	events.clear()
	events.field_rank = field_rank
	_events_ready = false
	if designs == null:
		designs = DesignBook.new()
	else:
		designs.clear()
	worn_design_slot = -1
	set_interact_prompt("")


## `mEv_GetEventWeather`: fireworks, the meteor shower and the like force clear skies; Dec 24
## forces heavy snow. No-op when no event overrides the weather.
func apply_event_weather() -> void:
	match events.weather_override():
		&"clear":
			apply_weather_roll({"kind": Weather.Kind.CLEAR, "intensity": Weather.Intensity.NONE})
		&"snow":
			apply_weather_roll({"kind": Weather.Kind.SNOW, "intensity": Weather.Intensity.HEAVY})


## Bring `events` to the clock. The first sync after a session starts only adopts the current
## state (no announcements) and applies any event weather; later syncs report changes.
func sync_events() -> void:
	if phase != Phase.PLAYING or title_demo_active:
		return
	var first: bool = not _events_ready
	_events_ready = true
	if first and events.town_seed == 0:
		events.assign_town(world_seed)
	events.sync(EventCalendar.date_from_clock())
	_deliver_post(first)
	if first:
		apply_event_weather()


func _on_event_started(id: StringName) -> void:
	if String(id).begins_with("weather_"):
		apply_event_weather()
	if EventSchedule.announces(id):
		post_notice("%s has begun!" % EventSchedule.label(id))


func _on_event_ended(id: StringName) -> void:
	if String(id).begins_with("weather_") and events.weather_override() == &"":
		apply_weather_roll(Weather.roll())


func set_weather(next: StringName, intensity: int = -1) -> void:
	var next_intensity: int = intensity
	if next_intensity < 0:
		next_intensity = int(Weather.default_intensity_for(Weather.kind_from_name(next)))
	if weather == next and weather_intensity == next_intensity:
		return
	weather = next
	weather_intensity = next_intensity
	weather_changed.emit(weather)


func set_cloth(next: StringName) -> void:
	## Worn shirt (`Private_c.cloth`). Empty → default starter cloth.
	var id: StringName = next if next != &"" else FirstJob.DEFAULT_CLOTH_ID
	if cloth_id == id:
		return
	cloth_id = id
	if first_job != null:
		first_job.tick_cloth(cloth_id)
	cloth_changed.emit(cloth_id)


func wear_cloth_from_slot(index: int) -> bool:
	## Inventory Wear: swap pocket cloth with worn cloth (`m_hand_ovl` drop onto body).
	if inventory == null:
		return false
	var slot: InventorySlot = inventory.slot_at(index)
	if slot == null or slot.is_empty():
		return false
	if slot.item.condition != InventoryItem.Condition.NORMAL:
		return false
	var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
	if data == null or data.category != ItemData.Category.CLOTH:
		return false
	var previous: StringName = cloth_id
	var wearing: StringName = slot.item.item_id
	inventory.remove_from_slot(index, 1)
	if previous != &"" and previous != wearing:
		var prev_data: ItemData = ItemCatalog.get_item(previous)
		if prev_data != null:
			inventory.add(prev_data, 1)
	set_cloth(wearing)
	return true


func unlock_map() -> void:
	## First-job furniture end hands `ITM_TOWN_MAP` (`Common.map_flag`).
	if has_map:
		return
	has_map = true
	set_interact_prompt("Press Map to open the town map")


func _shop_open_for_first_job(room: Room) -> bool:
	if room == null or first_job == null or not first_job.is_active():
		return false
	return room.kind == Room.Kind.SHOP or room.kind == Room.Kind.NEEDLEWORK


func apply_weather_roll(result: Dictionary) -> void:
	## `{kind: Weather.Kind, intensity: Weather.Intensity}` from `Weather.roll`.
	var kind: Weather.Kind = result.get("kind", Weather.Kind.CLEAR) as Weather.Kind
	var intensity: Weather.Intensity = result.get("intensity", Weather.Intensity.NONE) as Weather.Intensity
	if kind == Weather.Kind.CLEAR:
		intensity = Weather.Intensity.NONE
	set_weather(Weather.kind_name(kind), int(intensity))


func cycle_weather_debug() -> void:
	## HUD debug: clear → rain → snow → sakura.
	var next: StringName = Weather.next_in_cycle(weather)
	set_weather(next)


func give_test_tools() -> void:
	for item_id: StringName in TEST_TOOL_IDS:
		if inventory.count_of(item_id) > 0:
			continue
		var data: ItemData = ItemCatalog.get_item(item_id)
		if data != null:
			inventory.add(data, 1)
	if inventory.wallet <= 0:
		inventory.add_bells(TEST_BELLS)
	if inventory.count_mail() <= 0:
		PostUse.write_letter(&"filbert", 0)


func capture_player_from_tree() -> void:
	if get_tree() == null:
		return
	var player := Player.find(get_tree())
	if player == null:
		return
	player_position = player.global_position
	player_yaw = player.facing_yaw()


func is_interactable_removed(persist_id: StringName) -> bool:
	if persist_id == &"":
		return false
	return removed_interactables.has(String(persist_id))


func mark_interactable_removed(persist_id: StringName) -> void:
	if persist_id == &"":
		return
	var key := String(persist_id)
	if not removed_interactables.has(key):
		removed_interactables.append(key)
	clear_stump(persist_id)


func is_stump(persist_id: StringName) -> bool:
	if persist_id == &"":
		return false
	return stump_interactables.has(String(persist_id))


func mark_stump(persist_id: StringName) -> void:
	if persist_id == &"" or is_interactable_removed(persist_id):
		return
	var key := String(persist_id)
	if not stump_interactables.has(key):
		stump_interactables.append(key)


func clear_stump(persist_id: StringName) -> void:
	if persist_id == &"":
		return
	stump_interactables.erase(String(persist_id))


func is_hole(persist_id: StringName) -> bool:
	if persist_id == &"":
		return false
	return hole_interactables.has(String(persist_id))


func mark_hole(persist_id: StringName) -> void:
	if persist_id == &"":
		return
	var key := String(persist_id)
	if not hole_interactables.has(key):
		hole_interactables.append(key)


func clear_hole(persist_id: StringName) -> void:
	if persist_id == &"":
		return
	hole_interactables.erase(String(persist_id))


func set_interact_prompt(text: String) -> void:
	if interact_prompt == text:
		return
	interact_prompt = text
	prompt_changed.emit(text)


func post_notice(text: String) -> void:
	notice_posted.emit(text)


func to_save() -> Dictionary:
	## `mCkRh_SavePlayTime` runs whenever the game is saved.
	HouseGoki.save_play_time(interiors.player_house())
	return {
		"player": {
			"x": player_position.x,
			"y": player_position.y,
			"z": player_position.z,
			"yaw": player_yaw,
		},
		"removed_interactables": removed_interactables.duplicate(),
		"stump_interactables": stump_interactables.duplicate(),
		"hole_interactables": hole_interactables.duplicate(),
		"weeds": weeds.duplicate(),
		"clear_grass": clear_grass,
		"weed_days_pending": weed_days_pending,
		"field_rank": field_rank,
		"perfect_streak": perfect_streak,
		"perfect_streak_day": perfect_streak_day,
		"dust_flag": dust_flag,
		"golden_axe_got": golden_axe_got,
		"golden_shovel_shown": golden_shovel_shown,
		"money_rock": money_rock,
		"money_rock_day": money_rock_day,
		"mushrooms": mushrooms.duplicate(),
		"shells": shells.duplicate(),
		"signboards": signboards.duplicate(true),
		"field_items": field_items.duplicate(true),
		"bridge": bridge.duplicate(true),
		"mushroom_minute": mushroom_minute,
		"mushroom_active": mushroom_active,
		"snowmen": snowmen.duplicate(true),
		"snowman_built_minute": snowman_built_minute,
		"snowballs": snowballs.duplicate(true),
		"ball": ball.duplicate(),
		"sunburn": sunburn.duplicate(),
		"diary": diary.duplicate(),
		"plants": plant_states.duplicate(true),
		"buried": buried_deposits.duplicate(true),
		"world_mode": int(world_mode),
		"world_seed": world_seed,
		"grass_pattern": grass_pattern,
		"villagers": villagers.to_save(),
		"residents": residents.to_save(),
		"relationships": relationships.to_save(),
		"interiors": interiors.to_save(),
		"shops": shops.to_save(),
		"museum": museum.to_save(),
		"species_log": species_log.to_save(),
		"police": police.to_save(),
		"post": post.to_save(),
		"farway": farway.to_save(),
		"redd": redd.to_save(),
		"catalog": catalog.to_save(),
		"town_fruit": String(town_fruit),
		"events": events.to_save(),
		"designs": designs.to_save(),
		"worn_design_slot": worn_design_slot,
		"current_room_id": String(current_room_id),
		"outdoor_return": {
			"x": outdoor_return.x,
			"y": outdoor_return.y,
			"z": outdoor_return.z,
			"yaw": outdoor_return_yaw,
		},
		"player_name": player_name,
		"town_name": town_name,
		"player_gender": String(player_gender),
		"player_face": player_face,
		"cloth_id": String(cloth_id),
		"destiny": {"type": int(destiny_type), "y": destiny_date.x, "m": destiny_date.y, "d": destiny_date.z},
		"has_map": has_map,
		"num_statues": num_statues,
		"reset_count": reset_count,
		"cheated_flag": cheated_flag,
		"bank_gift_flags": bank_gift_flags,
		"town_tune": Array(town_tune),
		"complete_flags": complete_flags,
		"first_job": first_job.to_save() if first_job != null else {},
		"weather": String(weather),
		"weather_intensity": weather_intensity,
		"dialogue_vars": dialogue_vars.duplicate(true),
		"first_job_hint_count": first_job_hint_count,
		"valentine_year": valentine_year,
		"celebrated_birthday_year": celebrated_birthday_year,
		"birthday_present_npc": String(birthday_present_npc),
		"birthday_card_day": birthday_card_day,
		"mother_mail": mother_mail.duplicate(),
		"radio_card": radio_card.duplicate(),
		"calendar": calendar.duplicate(true),
		"fish_records": fish_records.duplicate(true),
		"treasure_buried_day": treasure_buried_day,
		"town_id": town_id,
		"mask_cat": mask_cat.duplicate(true),
		"met_blanca": met_blanca,
		"mask_cat_scheduled": mask_cat_scheduled,
		"haniwa_scheduled": haniwa_scheduled,
		"shine_hole": String(shine_hole),
		"treasure_checked_day": treasure_checked_day,
		"quests": quests.to_save(),
		"rainbow": rainbow.to_save(),
		"notice_board": notice_board.to_save(),
		"hra": hra.to_save(),
	}


func apply_snapshot(data: Dictionary) -> void:
	var pose: Variant = data.get("player", {})
	if typeof(pose) == TYPE_DICTIONARY:
		var p: Dictionary = pose
		player_position = Vector3(
			float(p.get("x", DEFAULT_SPAWN.x)),
			float(p.get("y", DEFAULT_SPAWN.y)),
			float(p.get("z", DEFAULT_SPAWN.z))
		)
		player_yaw = float(p.get("yaw", 0.0))
	else:
		player_position = DEFAULT_SPAWN
		player_yaw = 0.0
	removed_interactables.clear()
	var removed: Variant = data.get("removed_interactables", [])
	if typeof(removed) == TYPE_ARRAY:
		for entry: Variant in removed:
			removed_interactables.append(str(entry))
	stump_interactables.clear()
	var stumps: Variant = data.get("stump_interactables", [])
	if typeof(stumps) == TYPE_ARRAY:
		for entry: Variant in stumps:
			var key := str(entry)
			if not removed_interactables.has(key):
				stump_interactables.append(key)
	weeds.clear()
	var saved_weeds: Variant = data.get("weeds", {})
	if typeof(saved_weeds) == TYPE_DICTIONARY:
		for key: Variant in saved_weeds:
			weeds[str(key)] = clampi(int(saved_weeds[key]), 0, 2)
	clear_grass = bool(data.get("clear_grass", false))
	weed_days_pending = maxi(int(data.get("weed_days_pending", 0)), 0)
	field_rank = clampi(int(data.get("field_rank", 0)), 0, TownAssessment.RANK_PERFECT)
	perfect_streak = clampi(int(data.get("perfect_streak", 0)), 0, TownAssessment.PERFECT_STREAK_MAX)
	perfect_streak_day = int(data.get("perfect_streak_day", -1))
	dust_flag = bool(data.get("dust_flag", false))
	golden_axe_got = bool(data.get("golden_axe_got", false))
	golden_shovel_shown = bool(data.get("golden_shovel_shown", false))
	money_rock = str(data.get("money_rock", ""))
	money_rock_day = int(data.get("money_rock_day", -1))
	signboards.clear()
	var saved_signs: Variant = data.get("signboards", {})
	if typeof(saved_signs) == TYPE_DICTIONARY:
		signboards = (saved_signs as Dictionary).duplicate(true)
	bridge = {}
	var saved_bridge: Variant = data.get("bridge", {})
	if typeof(saved_bridge) == TYPE_DICTIONARY and not (saved_bridge as Dictionary).is_empty():
		bridge = SecondBridge.new_state()
		bridge.merge(saved_bridge as Dictionary, true)
	field_items.clear()
	var saved_items: Variant = data.get("field_items", {})
	if typeof(saved_items) == TYPE_DICTIONARY:
		field_items = (saved_items as Dictionary).duplicate(true)
	shells.clear()
	var saved_shells: Variant = data.get("shells", {})
	if typeof(saved_shells) == TYPE_DICTIONARY:
		for key: Variant in saved_shells:
			shells[str(key)] = str(saved_shells[key])
	shells_owed = ShellUse.FIRST_NUM
	shell_minute_counted = false
	mushrooms_session_cleared = false
	mushrooms.clear()
	var saved_mushrooms: Variant = data.get("mushrooms", {})
	if typeof(saved_mushrooms) == TYPE_DICTIONARY:
		for key: Variant in saved_mushrooms:
			mushrooms[str(key)] = 1
	mushroom_minute = int(data.get("mushroom_minute", -1))
	mushroom_active = bool(data.get("mushroom_active", false))
	snowmen = [{}, {}, {}]
	var saved_snowmen: Variant = data.get("snowmen", [])
	if typeof(saved_snowmen) == TYPE_ARRAY:
		for i: int in mini((saved_snowmen as Array).size(), SnowmanRules.SAVE_COUNT):
			var e: Variant = saved_snowmen[i]
			if typeof(e) == TYPE_DICTIONARY and not (e as Dictionary).is_empty():
				snowmen[i] = (e as Dictionary).duplicate(true)
	snowman_built_minute = int(data.get("snowman_built_minute", -1))
	ball = (data.get("ball", {}) as Dictionary).duplicate() if typeof(data.get("ball", {})) == TYPE_DICTIONARY else {}
	snowballs.clear()
	var saved_balls: Variant = data.get("snowballs", {})
	if typeof(saved_balls) == TYPE_DICTIONARY:
		for key: Variant in saved_balls:
			if typeof(saved_balls[key]) == TYPE_DICTIONARY:
				snowballs[int(key)] = (saved_balls[key] as Dictionary).duplicate(true)
	snowman_msg_id = randi_range(0, 2)
	var saved_tan: Variant = data.get("sunburn", {})
	sunburn = {"rank": 0, "changed": -1, "hold": 0}
	if typeof(saved_tan) == TYPE_DICTIONARY:
		sunburn["rank"] = clampi(int((saved_tan as Dictionary).get("rank", 0)), 0, Sunburn.MAX_RANK)
		sunburn["changed"] = int((saved_tan as Dictionary).get("changed", -1))
		sunburn["hold"] = clampi(int((saved_tan as Dictionary).get("hold", 0)), 0, Sunburn.HOLD_DAYS)
	Sunburn.reset_session()
	diary.clear()
	var saved_diary: Variant = data.get("diary", {})
	if typeof(saved_diary) == TYPE_DICTIONARY:
		for key: Variant in saved_diary:
			var m: int = int(key)
			if m >= 1 and m <= 12:
				diary[m] = DiaryOverlay.clip(str(saved_diary[key]))
	hole_interactables.clear()
	var holes: Variant = data.get("hole_interactables", [])
	if typeof(holes) == TYPE_ARRAY:
		for entry: Variant in holes:
			hole_interactables.append(str(entry))
	plant_states.clear()
	var plants: Variant = data.get("plants", {})
	if typeof(plants) == TYPE_DICTIONARY:
		for key: Variant in (plants as Dictionary).keys():
			var rec: Variant = plants[key]
			if typeof(rec) == TYPE_DICTIONARY:
				plant_states[str(key)] = (rec as Dictionary).duplicate()
	buried_deposits.clear()
	var buried: Variant = data.get("buried", {})
	if typeof(buried) == TYPE_DICTIONARY:
		for key: Variant in (buried as Dictionary).keys():
			var rec: Variant = buried[key]
			if typeof(rec) == TYPE_DICTIONARY:
				buried_deposits[str(key)] = (rec as Dictionary).duplicate()
	world_mode = int(data.get("world_mode", WorldData.Mode.TEST)) as WorldData.Mode
	world_seed = int(data.get("world_seed", WorldGenerator.DEFAULT_SEED))
	if data.has("grass_pattern"):
		grass_pattern = WorldData.clamp_grass_pattern(int(data["grass_pattern"]))
	elif world_mode == WorldData.Mode.GENERATED:
		grass_pattern = WorldGenerator.decide_grass_pattern(world_seed)
	else:
		grass_pattern = WorldData.GrassPattern.TRIANGLE
	relationships.apply_snapshot(data.get("relationships", {}))
	interiors.apply_snapshot(data.get("interiors", {}))
	## `m_start_data_init.c`: a house ordered on an earlier day is built when the game starts,
	## and finished collections are noted for the villagers' congratulations.
	check_rehouse_order()
	CompleteTalk.start_set_info()
	goki_shocked = false
	bee_swell = false
	bee_chase = false
	bee_greeted.clear()
	HouseGoki.decide_family_count(interiors.player_house())
	shops.apply_snapshot(data.get("shops", {}))
	if museum == null:
		museum = MuseumBook.new()
	museum.apply_snapshot(data.get("museum", {}))
	if species_log == null:
		species_log = SpeciesLog.new()
	species_log.apply_snapshot(data.get("species_log", {}))
	if police == null:
		police = PoliceBook.new()
	if data.has("police"):
		police.apply_snapshot(data["police"])
	else:
		## Saves from before the lost and found was stored: treat as a new town's box.
		police.init_town()
	if post == null:
		post = PostBook.new()
	post.apply_snapshot(data.get("post", {}))
	if farway == null:
		farway = FarwayBook.new()
	farway.apply_snapshot(data.get("farway", {}))
	if redd == null:
		redd = ReddBook.new()
	redd.apply_snapshot(data.get("redd", {}))
	if catalog == null:
		catalog = CatalogBook.new()
	catalog.apply_snapshot(data.get("catalog", {}))
	catalog.record_inventory(inventory)
	town_fruit = StringName(str(data.get("town_fruit", "apple")))
	events.apply_snapshot(data.get("events", {}))
	events.field_rank = field_rank
	_events_ready = false
	if designs == null:
		designs = DesignBook.new()
	designs.apply_snapshot(data.get("designs", {}))
	worn_design_slot = int(data.get("worn_design_slot", -1))
	current_room_id = StringName(str(data.get("current_room_id", "")))
	var outdoor: Variant = data.get("outdoor_return", {})
	if typeof(outdoor) == TYPE_DICTIONARY:
		var o: Dictionary = outdoor
		outdoor_return = Vector3(
			float(o.get("x", DEFAULT_SPAWN.x)),
			float(o.get("y", DEFAULT_SPAWN.y)),
			float(o.get("z", DEFAULT_SPAWN.z))
		)
		outdoor_return_yaw = float(o.get("yaw", 0.0))
	else:
		outdoor_return = DEFAULT_SPAWN
		outdoor_return_yaw = 0.0
	villagers.book = relationships
	villagers.apply_snapshot(data.get("villagers", {}))
	## Saves from before the roster was stored adopt the generated starters on first resolve.
	residents.apply_snapshot(data.get("residents", {}))
	_residents_session_done = false
	npc_talk_info.clear()
	quests.apply_snapshot(data.get("quests", {}))
	rainbow.apply_snapshot(data.get("rainbow", {}))
	hra = HappyRoomAcademy.new()
	hra.apply_snapshot(data.get("hra", {}))
	notice_board = NoticeBoard.new()
	if data.has("notice_board"):
		notice_board.apply_snapshot(data["notice_board"])
	else:
		notice_board.seed(Clock.year, Clock.month, Clock.day, Clock.hour, Clock.minute)
	first_job_hint_count = clampi(int(data.get("first_job_hint_count", 0)), 0, 0xFF)
	valentine_year = int(data.get("valentine_year", 0))
	celebrated_birthday_year = int(data.get("celebrated_birthday_year", 0))
	birthday_present_npc = StringName(str(data.get("birthday_present_npc", "")))
	birthday_card_day = int(data.get("birthday_card_day", 0))
	treasure_buried_day = int(data.get("treasure_buried_day", 0))
	town_id = int(data.get("town_id", 0))
	mask_cat = (data.get("mask_cat", {}) as Dictionary).duplicate(true) if typeof(data.get("mask_cat")) == TYPE_DICTIONARY else {}
	met_blanca = bool(data.get("met_blanca", false))
	mask_cat_scheduled = bool(data.get("mask_cat_scheduled", false))
	if town_id == 0:
		town_id = Travel.new_town_id()
	haniwa_scheduled = bool(data.get("haniwa_scheduled", false))
	shine_hole = StringName(str(data.get("shine_hole", "")))
	treasure_checked_day = int(data.get("treasure_checked_day", 0))
	fish_records.clear()
	var saved_fish: Variant = data.get("fish_records", [])
	if typeof(saved_fish) == TYPE_ARRAY:
		for r: Variant in saved_fish:
			if typeof(r) == TYPE_DICTIONARY:
				var rec: Dictionary = r
				fish_records.append({"name": str(rec.get("name", "")), "player": bool(rec.get("player", false)),
					"size": int(rec.get("size", 0)), "ordinal": int(rec.get("ordinal", 0)),
					"minute": int(rec.get("minute", 0)), "settled": bool(rec.get("settled", false))})
	calendar = CalendarBook.new_state()
	var saved_cal: Variant = data.get("calendar", {})
	if typeof(saved_cal) == TYPE_DICTIONARY:
		for key: String in ["played", "events"]:
			var days: Array = []
			for n: Variant in (saved_cal as Dictionary).get(key, []):
				days.append(int(n))
			calendar[key] = days
	radio_card = RadioCard.from_save(data.get("radio_card", {}))
	mother_mail = MotherMail.new_state()
	var saved_mom: Variant = data.get("mother_mail", {})
	if typeof(saved_mom) == TYPE_DICTIONARY:
		for key: String in ["date", "normal", "monthly"]:
			mother_mail[key] = int((saved_mom as Dictionary).get(key, 0))
	player_name = str(data.get("player_name", DEFAULT_PLAYER_NAME))
	town_name = str(data.get("town_name", DEFAULT_TOWN_NAME))
	player_gender = IntroSequence.normalize_gender(data.get("player_gender", DEFAULT_PLAYER_GENDER))
	player_face = clampi(int(data.get("player_face", 0)), 0, IntroSequence.FACE_TYPE_NUM - 1)
	cloth_id = StringName(str(data.get("cloth_id", FirstJob.DEFAULT_CLOTH_ID)))
	var fortune: Dictionary = data.get("destiny", {})
	destiny_type = clampi(int(fortune.get("type", 0)), 0, Destiny.GOODS_LUCK)
	destiny_date = Vector3i(int(fortune.get("y", 0)), int(fortune.get("m", 0)), int(fortune.get("d", 0)))
	if cloth_id == &"":
		cloth_id = FirstJob.DEFAULT_CLOTH_ID
	has_map = bool(data.get("has_map", false))
	num_statues = clampi(int(data.get("num_statues", 0)), 0, 3)
	reset_count = maxi(int(data.get("reset_count", 0)), 0)
	cheated_flag = bool(data.get("cheated_flag", false))
	bank_gift_flags = int(data.get("bank_gift_flags", 0)) & 0xF
	town_tune = TownTune.sanitize(data.get("town_tune", null))
	complete_flags = int(data.get("complete_flags", 0)) & 0xF
	if first_job == null:
		first_job = FirstJob.new()
	first_job.from_save(data.get("first_job", {}))
	weather = StringName(str(data.get("weather", "clear")))
	if data.has("weather_intensity"):
		weather_intensity = int(data["weather_intensity"])
	elif data.has("weather_packed"):
		var unpacked: Dictionary = Weather.unpack(int(data["weather_packed"]))
		weather = Weather.kind_name(unpacked["kind"] as Weather.Kind)
		weather_intensity = int(unpacked["intensity"])
	else:
		weather_intensity = int(Weather.default_intensity_for(Weather.kind_from_name(weather)))
	dialogue_vars.clear()
	var vars_raw: Variant = data.get("dialogue_vars", {})
	if typeof(vars_raw) == TYPE_DICTIONARY:
		dialogue_vars = (vars_raw as Dictionary).duplicate(true)


## `mHm_CheckRehouseOrder` for the player's house; rebuilds the live rooms when a build lands.
func check_rehouse_order() -> bool:
	var record: House = interiors.player_house()
	if not HouseUpgrade.check_rehouse_order(record):
		return false
	interiors.refresh_player_rooms()
	return true


func is_indoors() -> bool:
	return current_room_id != &""


func is_decorating() -> bool:
	if not is_indoors():
		return false
	var room: Room = interiors.room(current_room_id)
	return room != null and room.can_decorate


func try_enter_interior(
	target: StringName, spawn_gx: Variant = null, spawn_yaw: Variant = null
) -> bool:
	var room_id: StringName = InteriorCatalog.resolve_entry(target)
	if room_id == &"":
		return false
	var room: Room = interiors.room(room_id)
	if room == null:
		return false
	## Shop is force-open during first-job chores (`mSP_ShopOpen` + CheckFirstJob).
	if not InteriorCatalog.is_open_now(room) and not _shop_open_for_first_job(room):
		post_notice(InteriorCatalog.closed_notice(room))
		return false
	if not is_indoors():
		capture_player_from_tree()
		## `rewrite_out_data`: emerge outside the structure, not on the enter stand / roof.
		var host: Node3D = StructureDoor.find_near(self, player_position)
		if host != null:
			outdoor_return = StructureDoor.exit_stand(host)
			outdoor_return_yaw = StructureDoor.leave_yaw(host, outdoor_return)
		else:
			outdoor_return = player_position
			outdoor_return_yaw = player_yaw
	close_shop()
	current_room_id = room_id
	## `ac_shop_design` → `mSP_SetNewVisitor`: a visitor from another town shopped here.
	if foreigner and room.kind == Room.Kind.SHOP and shops != null:
		shops.set_visitor()
	play_door_arrive = false
	if spawn_gx is Vector3:
		interior_spawn_gx = spawn_gx as Vector3
		interior_spawn_yaw = float(spawn_yaw) if spawn_yaw != null else 0.0
		has_interior_spawn = true
		spawn_at_room_door = false
		## Non-museum linked spawns may continue INTO_S1; museum wings stay on door_data.
		play_door_arrive = not _is_museum_room_id(room_id) and not PlayerHouse.is_player_room(room_id)
	elif room_id == &"museum_entrance":
		## `aMsm_museum_enter_data` — not scene player data / generic south door cell.
		interior_spawn_gx = MuseumDisplay.ENTRANCE_SPAWN_GX
		interior_spawn_yaw = WorldGrid.yaw_for_furniture(MuseumDisplay.ENTRANCE_SPAWN_FACING)
		has_interior_spawn = true
		spawn_at_room_door = false
		## Museum: wipe to spawn facing north — no post-load walk.
		play_door_arrive = false
	elif ShopDisplay.nook_is_shop_room(room_id):
		## `aSHOP_shop_door_data` GX {160,0,300}, `mSc_DIRECT_NORTH` (all Nook levels).
		interior_spawn_gx = ShopDisplay.CRANNY_SPAWN_GX
		interior_spawn_yaw = WorldGrid.yaw_for_facing(ShopDisplay.CRANNY_SPAWN_FACING)
		has_interior_spawn = true
		spawn_at_room_door = false
	elif room_id == &"post_office":
		## `aPOFF_post_office_door_data` GX {160,0,300}, orient 4 = north.
		interior_spawn_gx = PostDisplay.SPAWN_GX
		interior_spawn_yaw = WorldGrid.yaw_for_facing(PostDisplay.SPAWN_FACING)
		has_interior_spawn = true
		spawn_at_room_door = false
	elif room_id == &"police_box":
		## `aPBOX_police_box_enter_data` GX {200,0,380}, `mSc_DIRECT_NORTH`.
		interior_spawn_gx = PoliceDisplay.SPAWN_GX
		interior_spawn_yaw = WorldGrid.yaw_for_facing(PoliceDisplay.SPAWN_FACING)
		has_interior_spawn = true
		spawn_at_room_door = false
	elif room_id == &"needlework":
		## `aNW_needlework_shop_door_data` GX {160,0,300}, orient 4 = north.
		## `rom_tailor` keeps the acre origin so this maps like the Nook shops.
		interior_spawn_gx = InteriorCatalog.ABLE_SPAWN_GX
		interior_spawn_yaw = WorldGrid.yaw_for_facing(InteriorCatalog.ABLE_SPAWN_FACING)
		has_interior_spawn = true
		spawn_at_room_door = false
	elif room.kind == Room.Kind.NPC:
		## `aHUS_npc_house_door_data` — not walkable-south `door_cell - 1`.
		interior_spawn_gx = InteriorCatalog.NPC_HOUSE_SPAWN_GX
		interior_spawn_yaw = WorldGrid.yaw_for_facing(WorldGrid.Facing.NORTH)
		has_interior_spawn = true
		spawn_at_room_door = false
	elif room_id == &"player_main":
		## `aMHS_goto_next_pl_scene` startX/Z for the current house size.
		interior_spawn_gx = PlayerHouse.enter_gx(interiors.player_house())
		interior_spawn_yaw = WorldGrid.yaw_for_facing(WorldGrid.Facing.NORTH)
		has_interior_spawn = true
		spawn_at_room_door = false
	else:
		has_interior_spawn = false
		spawn_at_room_door = true
	block_auto_enter_doors = true
	var stage: Node = _museum_complete_stage()
	if stage != null and stage.has_method("switch_wing"):
		return stage.call("switch_wing", room_id) as bool
	_change_scene(INTERIOR_SCENE)
	return true


func _is_museum_room_id(room_id: StringName) -> bool:
	if room_id == &"" or interiors == null:
		return false
	var room: Room = interiors.room(room_id)
	return room != null and room.kind == Room.Kind.MUSEUM


func _museum_complete_stage() -> Node:
	if get_tree() == null:
		return null
	var stages: Array[Node] = get_tree().get_nodes_in_group("museum_complete_stage")
	return stages[0] if not stages.is_empty() else null


## Nook's "See my catalog" (`aNSC_order_select_menu_close_wait_init` opens
## `mSM_OVL_CATALOG`). Returns the overlay to await `closed(item_id)` on, or null.
func open_catalog() -> CatalogOverlay:
	if get_tree() == null:
		return null
	var inv_ui: Node = get_tree().get_first_node_in_group("inventory_ui")
	if inv_ui != null and inv_ui.has_method("close"):
		inv_ui.call("close")
	var ui := get_tree().get_first_node_in_group("catalog_ui") as CatalogOverlay
	if ui == null:
		return null
	ui.open(catalog)
	return ui


func close_shop() -> void:
	if get_tree() == null:
		return
	var ui: Node = get_tree().get_first_node_in_group("shop_ui")
	if ui != null and ui.has_method("close"):
		ui.call("close")


func refresh_shop_set() -> void:
	if get_tree() == null:
		return
	var host: Node = get_tree().get_first_node_in_group("interior")
	if host != null and host.has_method("refresh_shop_set"):
		host.call("refresh_shop_set")


func refresh_police_set() -> void:
	if get_tree() == null:
		return
	var host: Node = get_tree().get_first_node_in_group("interior")
	if host != null and host.has_method("refresh_public_set"):
		host.call("refresh_public_set")
	elif host != null and host.has_method("refresh_shop_set"):
		host.call("refresh_shop_set")


## `mMl_send_postoffice_mail`: a balance milestone's gift by mail, one per game start.
func send_postoffice_gift() -> void:
	if inventory == null:
		return
	var gift: Dictionary = BankTerminal.due_gift(inventory.savings, bank_gift_flags)
	if gift.is_empty():
		return
	if inventory.add_received_mail(BankTerminal.gift_letter(gift, town_name, player_name)) >= 0:
		bank_gift_flags |= int(gift["flag"])


## `mMkRm_MarkRoom` at game start: the HRA's welcome, grade or tip, into the mailbox.
func mark_room() -> void:
	if interiors == null or inventory == null:
		return
	var house: House = interiors.player_house()
	if house == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var busy: bool = first_job != null and first_job.is_active()
	var letter: MailData = hra.mark(house, interiors.room(PlayerHouse.MAIN), interiors.room(PlayerHouse.UPPER),
		Vector3i(Clock.year, Clock.month, Clock.day), busy, player_name, rng)
	if letter != null:
		inventory.add_received_mail(letter)


## `mNtc_set_auto_nwrite_data`: seasonal notices whose day has come.
func update_notice_board() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var names: Array = fishing_names()
	var written: int = notice_board.auto_write(Clock.year, Clock.month, Clock.day, Clock.hour,
		NoticeBoard.common_free(town_name, shops.nook_level() if shops != null else 0),
		func(ordinal: int) -> Dictionary: return FishRecord.holder(fish_records, ordinal, names, rng))
	## `mFR_fishmail`: right after the board.
	var sent: int = FishRecord.send_mail(fish_records, EventDates.ordinal(Clock.year, Clock.month, Clock.day),
		Clock.hour, names, catalog.owned_ids() if catalog != null else [], player_name, rng,
		func(mail: MailData) -> bool: return inventory.add_received_mail(mail) >= 0 or post.receipt_mail(mail))
	if sent > 0:
		post_notice("You've got mail!")
	## `mNtc_check_treasure` when nothing seasonal went up.
	treasure_due = written == 0
	try_treasure(World.find(get_tree()) if get_tree() != null else null)


## A villager may bury treasure once the field is up (`BuriedTreasure`).
func try_treasure(world: Node) -> void:
	if not treasure_due or world == null or world.get("grid") == null:
		return
	treasure_due = false
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	BuriedTreasure.check(world, rng)


## `mEvMN_GetJointEventRandomNpc`: the residents who could be out fishing.
func fishing_names() -> Array:
	var out: Array = []
	for id: StringName in residents.resident_ids():
		var v: VillagerData = VillagerCatalog.get_villager(id)
		if v != null:
			out.append(v.display_name)
	return out


func _on_field_renewed(days: int) -> void:
	shops.renew(days)
	weed_days_pending += maxi(days, 0)
	melt_snowmen(days)
	## `mAGrw_ClearSpoiledKabu` / `mAGrw_SpoilKabu` / `mAGrw_SpoilAllPossession`.
	FieldItems.renew(FieldItems.sunday_passed(Clock.year, Clock.month, Clock.day, days), inventory, get_tree())
	var vt_rng := RandomNumberGenerator.new()
	vt_rng.randomize()
	_check_valentines(vt_rng)
	_check_birthday_cards(vt_rng)
	_check_mother_mail(vt_rng)
	note_played_today()
	HouseGoki.save_play_time(interiors.player_house())
	refresh_shop_set()
	## `mAGrw_RenewalFgItem` tops the lost and found up once per renewal, however many
	## days were skipped.
	if police != null:
		police.force_set_keep_item()
	refresh_police_set()
	_deliver_farway_mail()
	_deliver_shop_mail()
	if redd != null:
		redd.check_unlock()
	## One roll for the current date after renew (`mEnv_DecideWeather` / `aWeather_ChangeWeatherTime0`).
	var previous_weather: StringName = weather
	apply_weather_roll(Weather.roll())
	apply_event_weather()
	## Fine after rain or snow: a rainbow over the falls today and gyroids in the ground
	## with the next growth (`mEnv_PreRainNowFine_Init`).
	rainbow.note_weather_change(previous_weather, weather, Clock.month, Clock.day)
	if Rainbow.pre_rain_now_fine(previous_weather, weather):
		haniwa_scheduled = true
	update_notice_board()


## Farway Museum returns identified fossils (+ the one-time intro letter) each morning.
func _deliver_farway_mail() -> void:
	if farway == null or inventory == null:
		return
	var letters: Array[MailData] = farway.process_delivery()
	var delivered: int = 0
	for letter: MailData in letters:
		if inventory.add_received_mail(letter) >= 0:
			delivered += 1
	if delivered > 0:
		post_notice("You've got mail!")


## Nook's letters each morning: catalog orders, mailed raffle tickets, renovation notices.
func _deliver_shop_mail() -> void:
	if shops == null or inventory == null:
		return
	var letters: Array[MailData] = shops.take_mail()
	if catalog != null:
		letters.append_array(catalog.take_deliveries())
	var delivered: int = 0
	for letter: MailData in letters:
		if inventory.add_received_mail(letter) >= 0:
			delivered += 1
	if delivered > 0:
		post_notice("You've got mail!")


## Hand `count` dug fossils to the post office for the Farway Museum (`mMsm` mail-in).
func send_fossils_to_farway(count: int = 1) -> String:
	if farway == null or inventory == null:
		return "Nothing to send."
	var have: int = inventory.count_of(&"fossil")
	var n: int = clampi(count, 0, have)
	if n <= 0:
		return "You have no fossils to send."
	inventory.remove(&"fossil", n)
	for _i: int in n:
		farway.queue_fossil()
	return "We'll send %d to the Farway Museum. Expect a reply tomorrow." % n


func exit_interior() -> bool:
	if not is_indoors():
		return false
	close_shop()
	var leaving: Room = interiors.room(current_room_id)
	if leaving != null and leaving.kind == Room.Kind.SHOP and first_job != null:
		first_job.reset_shop_visit()
	if leaving != null and leaving.kind == Room.Kind.POLICE and police != null:
		## `aPOL2_player_getout_check` → `mPB_copy_itemBuf`: close the claimed gaps.
		police.copy_item_buf()
	last_room_id = current_room_id
	var room: Room = leaving
	if room != null and room.parent_room_id != &"":
		return try_enter_interior(room.parent_room_id)
	current_room_id = &""
	interior_session = null
	leave_resident_house()
	spawn_at_room_door = false
	has_interior_spawn = false
	play_door_arrive = false
	block_auto_enter_doors = true
	player_position = outdoor_return
	player_yaw = outdoor_return_yaw
	## Authored museum harness has no outdoor world — return to title.
	if _museum_complete_stage() != null:
		emerge_from_door = false
		_change_scene(TITLE_SCENE)
		return true
	emerge_from_door = true
	_change_scene(WORLD_SCENE)
	return true


func bind_interior(session: IndoorSession) -> void:
	interior_session = session


## Hand an inventory item to the museum (`mMmd_RequestMuseumDisplay`).
## Returns a short status string for notices / simple callers.
func donate_to_museum(item_id: StringName, player_no: int = 0) -> String:
	return String(donate_museum_result(item_id, player_no).get("message", ""))


## Structured donation outcome so Blathers' dialogue can branch on category / donor /
## completion. `reason` is one of: not_item, cannot_donate, forgery, already_donated,
## not_held, generic_fossil, ok.
func donate_museum_result(item_id: StringName, player_no: int = 0) -> Dictionary:
	if museum == null:
		museum = MuseumBook.new()
	var out: Dictionary = {
		"ok": false,
		"reason": "not_item",
		"category": -1,
		"index": -1,
		"donor": 0,
		"completed_set": false,
		"set_name": "",
		"completed_collection": false,
		"completed_museum": false,
		"message": "That's not something for the museum.",
	}
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null:
		return out
	var mapped: Dictionary = MuseumDisplay.map_item(data)
	out["category"] = int(mapped.get("category", -1))
	out["index"] = int(mapped.get("index", -1))
	## Raw dug fossils have no identity yet — the Farway Museum must examine them first.
	if item_id == &"fossil":
		out["reason"] = "generic_fossil"
		out["message"] = "Blathers can't identify an unexamined fossil."
		return out
	match museum.display_info_for_item(data):
		MuseumBook.DisplayInfo.CANNOT_DONATE:
			out["reason"] = "forgery" if _is_museum_forgery(data, out["index"]) else "cannot_donate"
			out["message"] = "Blathers can't take that."
			return out
		MuseumBook.DisplayInfo.ALREADY_DONATED:
			out["reason"] = "already_donated"
			out["donor"] = museum.info(out["category"], out["index"])
			out["message"] = "The museum already has that."
			return out
		_:
			pass
	if inventory.count_of(item_id) <= 0:
		out["reason"] = "not_held"
		out["message"] = "You don't have that."
		return out
	if not museum.request_display(data, player_no):
		out["reason"] = "already_donated"
		out["message"] = "The museum already has that."
		return out
	inventory.remove(item_id, 1)
	out["ok"] = true
	out["reason"] = "ok"
	out["donor"] = clampi(player_no, 0, 3) + 1
	var category: int = out["category"]
	var index: int = out["index"]
	if category == MuseumDisplay.Category.FOSSIL and MuseumDisplay.fossil_set_just_completed(museum, index):
		out["completed_set"] = true
		out["set_name"] = MuseumDisplay.fossil_set_name(index)
	out["completed_collection"] = _museum_collection_complete(category)
	out["completed_museum"] = museum.is_complete()
	out["message"] = _donate_message(out)
	return out


func _is_museum_forgery(data: ItemData, index: int) -> bool:
	if String(data.id).begins_with("art_forgery"):
		return true
	return index in MuseumBook.FORGERY_ART_INDICES and _mapped_category(data) == MuseumDisplay.Category.ART


func _mapped_category(data: ItemData) -> int:
	return int(MuseumDisplay.map_item(data).get("category", -1))


func _museum_collection_complete(category: int) -> bool:
	match category:
		MuseumDisplay.Category.FOSSIL:
			return museum.count_fossils() >= MuseumBook.FOSSIL_NUM
		MuseumDisplay.Category.ART:
			return museum.count_art() >= MuseumBook.DONATABLE_ART_NUM
		MuseumDisplay.Category.FISH:
			return museum.count_fish() >= MuseumBook.FISH_NUM
		MuseumDisplay.Category.INSECT:
			return museum.count_insects() >= MuseumBook.INSECT_NUM
	return false


func _donate_message(out: Dictionary) -> String:
	if out["completed_museum"]:
		return "That completes the collection — every wing is full!"
	if out["completed_collection"]:
		return "That completes a whole collection! Wonderful."
	if out["completed_set"]:
		return "That completes a skeleton! It will appear in the fossil wing."
	return "Donated! Visit the wing to see it on display."


func try_place_furniture(actor: Node3D) -> bool:
	if actor == null or interior_session == null or not is_decorating():
		return false
	var data: FurnitureData = _selected_furniture()
	if data == null:
		return false
	var facing: WorldGrid.Facing = WorldGrid.facing_from_player_yaw(
		float(actor.call("facing_yaw")) if actor.has_method("facing_yaw") else actor.rotation.y
	)
	var cell: Vector2i = interior_session.grid.world_to_cell(actor.global_position)
	cell = interior_session.grid.step(cell, facing)
	if interior_session.is_full():
		post_notice("This room can't hold any more furniture.")
		return false
	var entry: FurniturePlacement = interior_session.place(data, cell, facing)
	if entry == null:
		post_notice("Can't place that here.")
		return false
	inventory.remove(data.id, 1)
	var host: Node = get_tree().get_first_node_in_group("interior") if get_tree() else null
	if host != null and host.has_method("spawn_placement"):
		host.call("spawn_placement", entry)
	post_notice("Placed %s." % data.display_name)
	return true


func pick_up_furniture(placement_id: StringName) -> bool:
	if interior_session == null or not is_decorating():
		return false
	var entry: FurniturePlacement = interior_session.room.placement_by_id(placement_id)
	if entry == null:
		return false
	if entry.layer == 0 and _has_surface_items(entry):
		post_notice("Clear that first.")
		return false
	var data: ItemData = ItemCatalog.get_item(entry.furniture_id)
	if data == null or not inventory.has_space_for(data, 1):
		return false
	if not _return_placement_contents(entry):
		return false
	var furniture_id: StringName = interior_session.pick_up(placement_id)
	if furniture_id == &"":
		return false
	inventory.add(data, 1)
	_select_item(data.id)
	var host: Node = get_tree().get_first_node_in_group("interior") if get_tree() else null
	if host != null and host.has_method("despawn_placement"):
		host.call("despawn_placement", placement_id)
	post_notice("Picked up %s." % data.display_name)
	return true


func rotate_furniture(placement_id: StringName) -> bool:
	if interior_session == null or not is_decorating():
		return false
	if not interior_session.rotate(placement_id, 1):
		return false
	var host: Node = get_tree().get_first_node_in_group("interior") if get_tree() else null
	if host != null and host.has_method("refresh_placement"):
		host.call("refresh_placement", placement_id)
	return true


func _select_item(item_id: StringName) -> void:
	if item_id == &"":
		return
	for i: int in range(Inventory.POCKET_SLOTS - 1, -1, -1):
		var slot: InventorySlot = inventory.slot_at(i)
		if slot != null and not slot.is_empty() and slot.item.item_id == item_id:
			inventory.select(i)


func held_furniture() -> FurnitureData:
	var slot: InventorySlot = inventory.selected_slot()
	if slot == null or slot.is_empty():
		return null
	return ItemCatalog.get_item(slot.item.item_id) as FurnitureData


func _selected_furniture() -> FurnitureData:
	return held_furniture()


func try_apply_cover(data: ItemData) -> bool:
	if data == null or interior_session == null or not is_decorating():
		return false
	if data.category == ItemData.Category.WALL:
		if not interior_session.decorate_wall(data.id):
			return false
		inventory.remove(data.id, 1)
		post_notice("Changed the wallpaper.")
		return true
	if data.category == ItemData.Category.FLOOR:
		if not interior_session.decorate_floor(data.id):
			return false
		inventory.remove(data.id, 1)
		post_notice("Changed the carpet.")
		return true
	return false


func _has_surface_items(entry: FurniturePlacement) -> bool:
	if entry == null or interior_session == null:
		return false
	var data: FurnitureData = interior_session.furniture_of(entry.furniture_id)
	var size: Vector2i = entry.resolved_footprint(data)
	for cell: Vector2i in interior_session.grid.footprint_cells(entry.cell, size, entry.facing):
		if interior_session.surface_item_at(cell) != null:
			return true
	return false


func _return_placement_contents(entry: FurniturePlacement) -> bool:
	if entry == null:
		return true
	var needed: Array[ItemData] = []
	if entry.display_id != &"":
		var shown: ItemData = ItemCatalog.get_item(entry.display_id)
		if shown != null:
			needed.append(shown)
	for raw: String in entry.stored:
		var packed: ItemData = ItemCatalog.get_item(StringName(raw))
		if packed != null:
			needed.append(packed)
	for item: ItemData in needed:
		if not inventory.has_space_for(item, 1):
			post_notice("Pockets are full.")
			return false
	if entry.display_id != &"":
		var shown: ItemData = ItemCatalog.get_item(entry.display_id)
		if shown != null:
			inventory.add(shown, 1)
		entry.display_id = &""
	for raw: String in entry.stored:
		var packed: ItemData = ItemCatalog.get_item(StringName(raw))
		if packed != null:
			inventory.add(packed, 1)
	entry.stored.clear()
	return true


const _ESC_BLOCKING_UI: Array[String] = [
	"inventory_ui", "dialogue_ui", "shop_ui", "map_ui", "debug_console_ui", "design_ui",
	"design_list_ui", "name_entry_ui", "pause_ui",
]


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause_menu"):
		return
	if phase != Phase.PLAYING:
		push_warning("Esc ignored: game phase is %s, not PLAYING." % Phase.keys()[phase])
		return
	## Menus close themselves on Esc first; if one is still open here it is stuck.
	for group: String in _ESC_BLOCKING_UI:
		if _group_is_open(group):
			push_warning("Esc ignored: '%s' reports it is open." % group)
			return
	## Ask first; `PauseOverlay` saves and returns to the title on Yes.
	var pause_ui: Node = get_tree().get_first_node_in_group("pause_ui") if get_tree() != null else null
	if pause_ui != null and pause_ui.has_method("open"):
		pause_ui.call("open")
	else:
		return_to_title()
	get_viewport().set_input_as_handled()


func _set_phase(next: Phase) -> void:
	if phase == next:
		return
	phase = next
	phase_changed.emit(phase)


func _group_is_open(group: String) -> bool:
	if get_tree() == null:
		return false
	var ui: Node = get_tree().get_first_node_in_group(group)
	return ui != null and ui.has_method("is_open") and bool(ui.call("is_open"))


func _change_scene(path: String) -> void:
	Fishing.reset()
	var tree := get_tree()
	if tree == null:
		return
	tree.call_deferred("change_scene_to_file", path)
