extends Node

## Composition root. Owns the session phase, the scene changes, and every saved book that is
## not an autoload. The work itself lives in the classes it holds: `TownUpkeep` for the
## calendar, `MailDelivery` for letters, `PocketRequests` for "pick something" prompts, and
## so on.

enum Phase { TITLE, INTRO, PLAYING }

const TITLE_SCENE := "res://scenes/ui/title.tscn"
## K.K. player-select opening (`ac_npc_p_sel`) before the Rover train.
const INTRO_KK_SCENE := "res://scenes/ui/intro_kk.tscn"
const INTRO_SCENE := "res://scenes/ui/intro_train.tscn"
const WORLD_SCENE := "res://scenes/world/world.tscn"
const INTERIOR_SCENE := "res://scenes/world/interior.tscn"

const DEFAULT_SPAWN := PlayerState.DEFAULT_SPAWN
const DEFAULT_PLAYER_NAME := PlayerState.DEFAULT_PLAYER_NAME
const DEFAULT_PLAYER_GENDER := PlayerState.DEFAULT_PLAYER_GENDER
const DEFAULT_TOWN_NAME := TownState.DEFAULT_TOWN_NAME

## `Private_c.destiny` (`mPr_DESTINY_*`): the day's fortune from Katrina (`ac_ev_gypsy`) or
## the New Year shrine (`ac_ev_miko`); both reset it at the next calendar day.
const Destiny := PlayerState.Destiny

## `Common_Get(complete_payment_type)`: a paid-off loan or the end of Nook's chores, cheered
## the next time the player walks out of a door (`m_player_main_complete_payment`).
const PAYMENT_HOUSE := &"house"
const PAYMENT_ARBEIT := &"arbeit"

const GOODS_POWER_MIN := -30
const GOODS_POWER_MAX := 50

## What the test town (`WorldData.Mode.TEST`) hands the player.
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

const _ESC_BLOCKING_UI: Array[String] = [
	"inventory_ui", "dialogue_ui", "shop_ui", "map_ui", "debug_console_ui", "design_ui",
	"design_list_ui", "name_entry_ui", "pause_ui", "settings_ui",
]

signal phase_changed(phase: Phase)
signal prompt_changed(text: String)
signal notice_posted(text: String)
signal weather_changed(weather: StringName)
signal cloth_changed(cloth_id: StringName)
signal design_changed

# Saved state: the playing resident, the town, and the per-system books.

## The playing resident's saved state (`Private_c`) and the town's (`PlayerState`,
## `TownState`).
var resident: PlayerState = PlayerState.new()
var town: TownState = TownState.new()
var inventory: Inventory = Inventory.new()
var villagers: VillagerRoster = VillagerRoster.new()
## `animals[]` slots + move-in / move-out bookkeeping (`m_npc.c`).
var residents: TownResidents = TownResidents.new()
## Deliveries, errands and villager contests (`Private_c.deliveries/errands`,
## `Animal_c.contest_quest`).
var quests: VillagerQuests = VillagerQuests.new()
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
var travel_book: TravelBook = TravelBook.new()
var redd: ReddBook = ReddBook.new()
var lighthouse: LighthouseBook = LighthouseBook.new()
## Every catalog item the player has owned + Nook mail orders (`m_catalog_ovl`).
var catalog: CatalogBook = CatalogBook.new()
## Holidays, weekly visitors and the special-NPC schedule (`m_event`); see `EventCalendar`.
var events: EventCalendar = EventCalendar.new()
## The waterfall rainbow after rain (`mEnv_rainbow_*`).
var rainbow: Rainbow = Rainbow.new()
## The community board's posts (`m_notice`).
var notice_board: NoticeBoard = NoticeBoard.new()
## The Happy Room Academy's membership and marks (`m_mark_room`).
var hra: HappyRoomAcademy = HappyRoomAcademy.new()
var designs: DesignBook = DesignBook.new()
var first_job: FirstJob = FirstJob.new()

# Session state: parts that live only until the game is reset or quit.

var phase: Phase = Phase.TITLE
## The town train (`m_train_control`), run for the whole session.
var train: TrainService = TrainService.new()
## `mNpc_Talk_Info_c` for this session (patience, "any work?" flag).
var npc_talk_info: NpcTalkInfo = NpcTalkInfo.new()
## "Pick something from your pockets" prompts raised by talks and furniture.
var pocket_requests: PocketRequests = PocketRequests.new()
## The station arrival (Porter, Nook, the house pick) of a new resident.
var intro: IntroProgress = IntroProgress.new()
var bees: BeeSting = BeeSting.new()
var interior_session: IndoorSession
var interact_prompt: String = ""

## Title attract mode (`SCENE_TITLE_DEMO`): `title.tscn` hosts the generated town with a
## recorded player. Cleared by `reset_session`, so any real entry point drops it.
var title_demo_active: bool = false
var title_demo_index: int = 0

## K.K.'s scene runs the player select of an existing town (`ac_npc_p_sel2`) rather than the
## first-time opening (`ac_npc_p_sel`).
var player_select_mode: bool = false
## Playing as a visitor from another town (`mPr_FOREIGNER`): no house here, and the only way
## out is Porter at the station, who saves the town and the passport.
var foreigner: bool = false
## Come in on the train (a visitor, or a traveller back home): start on the platform.
var arrive_by_train: bool = false
## The roster slot a newcomer to an existing town takes (`aNPS2_TALK_START_TYPE3`), or -1
## for a brand-new town.
var joining_slot: int = -1
## Set by `continue_game` for an outdoor save: the world spawns the player at their own door.
var continue_from_house: bool = false

## `Common_Get(reset_flag)`: this session follows one of those, so Mr. Resetti is waiting.
var reset_flag: bool = false
## Debug console `resetti off`: he stays home, and unsaved quits do not raise the count.
var resetti_disabled: bool = false

# Where the player is: the room they are in, and how they came in and will go back out.

var current_room_id: StringName = &""
var arrival: InteriorArrival = InteriorArrival.new()
var outdoor_return: Vector3 = DEFAULT_SPAWN
var outdoor_return_yaw: float = 0.0
## After a room load, ignore walk-in doors until the player steps clear of sensors.
var block_auto_enter_doors: bool = false
## After indoor leave, world plays structure leave + player GO_OUT (`mPlayer_INDEX_OUTDOOR`).
var emerge_from_door: bool = false
## `Common_Get(last_scene_no)`: the room the player last walked out of (Copper greets
## you outside the police box).
var last_room_id: StringName = &""

# Small per-session flags, each read by the one feature named in its comment.

## A paid-off loan or the end of Nook's chores, waiting for the next door (`PAYMENT_*`).
var complete_payment: StringName = &""
## The last board check wrote no seasonal notice, so a villager may bury treasure.
var treasure_due: bool = false
## `Save_Get(insect_term)` / `insect_term_transition_offset`: the 0-based month the insect
## spawn table is heading into and how many days (0-5) before its 1st the cross-month blend
## starts (`aSOI_ins_chk_term_info`).
var insect_term_month: int = 0
var insect_term_offset: int = 0
## `mFI_GetDigStatus`'s `old_pos`: where the golden shovel last dug.
var golden_last_dig: Vector2i = Vector2i(-1, -1)
## `unk_nook_present_count`: presents Nook has handed over for codes this session.
var nook_code_gifts: int = 0
## `mMsr_FirstClearMushroom` has run for this play session.
var mushrooms_session_cleared: bool = false
## Shells still to wash up: twenty when a session starts (`mFI_SetFirstSetShell`).
var shells_owed: int = ShellUse.FIRST_NUM
var shell_minute_counted: bool = false
## `Common.snowman_msg_id` (`mSN_decide_msg`): rolled each play session.
var snowman_msg_id: int = 0
## `Common.money_power` / `goods_power`: the house's feng shui (`FengShui`), recomputed on
## the way out to the field.
var money_power: int = 0
var goods_power: int = 0
## `goki_shocked_flag`: the first roach of a session startles the player, once.
var goki_shocked: bool = false

## `mSDI_StartInitAfter` runs once per load; the world resolves several times a session.
var _residents_session_done: bool = false
## False until `sync_events` has adopted the clock for this session.
var _events_ready: bool = false


func _init() -> void:
	villagers.book = relationships


func _ready() -> void:
	DisplayConfig.ensure_loaded()
	DisplayConfig.apply(get_window())
	train.name = "Train"
	add_child(train)
	ReddBook.ensure_art_items()
	Clock.field_renewed.connect(TownUpkeep.on_field_renewed)
	Clock.day_changed.connect(TownUpkeep.on_day_changed)
	Clock.time_changed.connect(sync_events)
	events.event_started.connect(_on_event_started)
	events.event_ended.connect(_on_event_ended)


func _physics_process(delta: float) -> void:
	if phase != Phase.PLAYING:
		return
	## `mNpc_TalkInfoMove` runs every play frame.
	npc_talk_info.advance(delta)
	## `mEnv_rainbow_power_calc` runs in field (FG) scenes only.
	if not is_indoors():
		rainbow.tick(
			Clock.month, Clock.day, Clock.now_sec(), Clock.season() == Clock.Season.SUMMER, delta
		)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause_menu"):
		return
	if phase != Phase.PLAYING:
		push_warning("Esc ignored: game phase is %s, not PLAYING." % Phase.keys()[phase])
		return
	## Menus close themselves on Esc first; if one is still open here it is stuck.
	for group: String in _ESC_BLOCKING_UI:
		var menu: Node = get_tree().get_first_node_in_group(group)
		if menu != null and bool(menu.is_open()):
			push_warning("Esc ignored: '%s' reports it is open." % group)
			return
	## Ask first; `PauseOverlay` saves and returns to the title on Yes.
	var pause_ui: PauseOverlay = PauseOverlay.find(get_tree())
	if pause_ui == null:
		return_to_title()
	else:
		pause_ui.open()
	get_viewport().set_input_as_handled()


# --- Starting, continuing and leaving a game -------------------------------------------------


func start_new_game(
	mode: WorldData.Mode = WorldData.Mode.TEST,
	seed_value: int = WorldGenerator.DEFAULT_SEED,
	identity: Dictionary = {}
) -> void:
	reset_session()
	_apply_identity(identity)
	town.world_mode = mode
	town.world_seed = seed_value
	if mode == WorldData.Mode.GENERATED:
		town.grass_pattern = WorldGenerator.decide_grass_pattern(seed_value)
	else:
		town.grass_pattern = WorldData.GrassPattern.TRIANGLE
	if identity.is_empty() or not Clock.rtc_override:
		Clock.rtc_override = false
		Clock.sync_from_os()
	apply_weather_roll(Weather.roll())
	if mode == WorldData.Mode.TEST:
		give_test_tools()
	_change_scene(WORLD_SCENE)


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
	SaveService.mark_session_open(resident.reset_count)
	## `mMl_start_send_mail` / `mNtc_set_auto_nwrite_data` at game start.
	MailDelivery.send_bank_gift()
	TownUpkeep.update_notice_board()
	MailDelivery.send_academy_mark()
	MuseumCompMail.send()
	if is_indoors():
		_change_scene(INTERIOR_SCENE)
	else:
		continue_from_house = not intro.active
		_change_scene(WORLD_SCENE)


func return_to_title() -> void:
	capture_player_from_tree()
	## A visitor can't save here (`save_menu_data_save_from`, `SAVE_ERROR_FLASHROM`): only Porter
	## sends them home with their things. Quitting drops this visit.
	if not foreigner:
		SaveService.save_game()
	_set_phase(Phase.TITLE)
	_change_scene(TITLE_SCENE)


## The real-time clock ran on while the game was off; a clock set back marks the save.
func resume_clock(elapsed: int) -> void:
	if not Clock.resume_after(elapsed):
		town.cheated_flag = true


func notify_title_ready() -> void:
	_set_phase(Phase.TITLE)
	set_interact_prompt("")


func notify_world_ready() -> void:
	if town.world_mode == WorldData.Mode.TEST:
		give_test_tools()
	if intro.active:
		_set_phase(Phase.INTRO)
	elif title_demo_active:
		_set_phase(Phase.TITLE)
	else:
		_set_phase(Phase.PLAYING)
	sync_events()


# --- The opening: K.K., Rover's train, then the station arrival -------------------------------


func start_intro_sequence() -> void:
	## Title fades out black before the swap (`ac_animal_logo` / title-demo
	## `WIPE_TYPE_FADE_BLACK`); `intro_kk._ready` fades back in.
	await SceneTransition.play_wipe_out(SceneTransition.Style.FADE)
	reset_session()
	Clock.rtc_override = false
	Clock.sync_from_os()
	_set_phase(Phase.INTRO)
	_change_scene(INTRO_KK_SCENE)


## Title -> K.K.'s player select for the saved town (`SCENE_PLAYERSELECT`).
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


## After K.K. fades out (`aNPS_setup_game_start` -> `SCENE_START_DEMO`). The K.K. scene has
## already run its strum-synced `%FadeRect` to black; hold the screen opaque across the load
## so the train scene can fade itself back in (`aNPS` `transition.wipe_type =
## WIPE_TYPE_FADE_BLACK`).
func advance_intro_to_train() -> void:
	SceneTransition.hold_black()
	_set_phase(Phase.INTRO)
	_change_scene(INTRO_SCENE)


func notify_intro_ready() -> void:
	_set_phase(Phase.INTRO)
	set_interact_prompt("")


## Rover's train pulls into town (`aNGD_scene_change_wait_init`): make the new town and
## continue straight into the outdoor station arrival, keeping the clock the player set on the
## train. A newcomer to a saved town arrives in that town instead.
func finish_intro_sequence(identity: Dictionary) -> void:
	if joining_slot >= 0:
		_begin_resident_arrival(identity)
	else:
		_begin_station_arrival(_random_seed(), identity, false)


## Exit path for the standalone `intro_station.tscn` dev scene, which has already played its
## own Porter/Nook beats: drop into the world and start the first job.
func debug_finish_station_arrival(identity: Dictionary) -> void:
	start_new_game(WorldData.Mode.GENERATED, _random_seed(), identity)
	_grant_intro_start_items()
	first_job.begin_after_house()
	_set_phase(Phase.PLAYING)
	set_interact_prompt("Visit Tom Nook's shop")


func abort_intro_sequence() -> void:
	intro.clear()
	## Drop any pending scene wipe so the title is not left under a black hold.
	SceneTransition.cancel_wipe()
	_set_phase(Phase.TITLE)
	_change_scene(TITLE_SCENE)


## Nook has left: stay in the generated world, unlock normal play and start the first job.
func complete_intro_station() -> void:
	intro.finish()
	## `aID_retire_rcn_guide_wait`: `Now_Private->inventory.loan = mPlayer_DEBT0`, the balance
	## after the 1,000-bell down payment.
	inventory.set_loan(Inventory.INTRO_HOUSE_DEBT)
	## `mQst_SetFirstJobStart` after Nook EXIT.
	first_job.begin_after_house()
	_set_phase(Phase.PLAYING)
	set_interact_prompt("Visit Tom Nook's shop")


## New town + outdoor station-arrival demo (`aNGD_scene_change_wait_init` creates the town,
## then `ac_intro_demo` runs Porter -> Nook -> house pick -> debt).
func _begin_station_arrival(seed_value: int, identity: Dictionary, sync_clock: bool) -> void:
	reset_session()
	_apply_identity(identity)
	if sync_clock:
		Clock.rtc_override = false
		Clock.sync_from_os()
	intro.active = true
	town.world_mode = WorldData.Mode.GENERATED
	town.world_seed = seed_value
	town.grass_pattern = WorldGenerator.decide_grass_pattern(seed_value)
	apply_weather_roll(Weather.roll())
	_grant_intro_start_items()
	_set_phase(Phase.INTRO)
	_change_scene(WORLD_SCENE)


## A newcomer's arrival in the saved town (`mCD_START_COND_2`): the town as it is, an empty
## resident in `joining_slot`, then the same station arrival: Porter, Nook, a vacant house.
func _begin_resident_arrival(identity: Dictionary) -> void:
	var slot: int = joining_slot
	joining_slot = -1
	reset_session()
	if SaveService.load_game("", slot) != OK:
		_begin_station_arrival(_random_seed(), identity, false)
		return
	resume_clock(SaveService.last_elapsed)
	var kept_name: String = town.town_name
	_apply_identity(identity)
	town.town_name = kept_name
	intro.active = true
	_grant_intro_start_items()
	_set_phase(Phase.INTRO)
	_change_scene(WORLD_SCENE)


## `m_start_data_init.c`: a new resident starts with one QUEST-flagged 1,000-bell bag in
## pocket slot 0, the down payment Nook collects after the house tour.
func _grant_intro_start_items() -> void:
	var bag: ItemData = ItemCatalog.get_item(&"money_1000")
	if bag != null and inventory.count_of(&"money_1000") == 0:
		inventory.add(bag, 1, InventoryItem.Condition.QUEST)


func _apply_identity(identity: Dictionary) -> void:
	if identity.is_empty():
		return
	resident.player_name = str(identity.get("player_name", DEFAULT_PLAYER_NAME))
	if resident.player_name.strip_edges().is_empty():
		resident.player_name = DEFAULT_PLAYER_NAME
	town.town_name = str(identity.get("town_name", DEFAULT_TOWN_NAME))
	if town.town_name.strip_edges().is_empty():
		town.town_name = DEFAULT_TOWN_NAME
	resident.player_gender = IntroSequence.normalize_gender(
		identity.get("player_gender", DEFAULT_PLAYER_GENDER)
	)
	resident.player_face = clampi(
		int(identity.get("player_face", 0)), 0, IntroSequence.FACE_TYPE_NUM - 1
	)
	var shirt: StringName = IntroSequence.starting_cloth(resident.player_gender)
	if ItemCatalog.get_item(shirt) != null:
		resident.cloth_id = shirt


func _random_seed() -> int:
	return int(Time.get_unix_time_from_system()) ^ int(Time.get_ticks_usec())


# --- Travel: visitors from other towns and our own traveller coming home --------------------


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
	SaveService.mark_session_open(resident.reset_count)
	_arrive_by_train()


## Porter saw the traveller off (`aSTM_game_end_init`): the train leaves for the title.
func depart_by_train() -> void:
	await SceneTransition.play_wipe_out(SceneTransition.Style.FADE)
	_set_phase(Phase.TITLE)
	_change_scene(TITLE_SCENE)


func _arrive_by_train() -> void:
	arrive_by_train = true
	current_room_id = &""
	continue_from_house = false
	TownUpkeep.update_notice_board()
	_set_phase(Phase.PLAYING)
	_change_scene(WORLD_SCENE)


# --- The town and its villagers ---------------------------------------------------------------


func resolve_world_data() -> WorldData:
	var data: WorldData
	if town.world_mode == WorldData.Mode.GENERATED:
		data = WorldGenerator.generate(town.world_seed, title_demo_active, town.imported_field)
		if not title_demo_active:
			_resolve_residents(data)
	else:
		data = WorldGenerator.authored_test_town()
	data.grass_pattern = town.grass_pattern
	FieldCatalog.set_grass_pattern(town.grass_pattern)
	return data


## `mNpc_GetAnimalMemoryIdx(player) != -1`: the player has a memory in this animal, made on
## first talk.
func player_met(villager_id: StringName) -> bool:
	return relationships.has_id(villager_id) and relationships.get_or_create(villager_id).has_memory


## `mQst_GetFlowerSeedNum` / `mQst_GetFlowerNum` / `mQst_GetNullNoNum` for a home acre.
func field_counts(block: Vector2i) -> Dictionary:
	return QuestField.counts(get_tree(), block)


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
			residents, relationships, Clock.day_number(), resident.player_name, rng,
			MailDelivery.to_mailbox_or_post
		)
		MailDelivery.send_valentines(rng)
	WorldGenerator.apply_residents(data, residents)


func _residents_context(data: WorldData, rng: RandomNumberGenerator) -> Dictionary:
	return {
		"rng": rng,
		"day": Clock.day_number(),
		"minute": Clock.absolute_minute(),
		"met": player_met,
		"letters": func(_id: StringName) -> int: return 0,
		"field_rank": town.field_rank,
		"reserves": data.reserve_cells,
		"on_goodbye": func(id: StringName, looks: int) -> void: _villager_moved_out(id, looks, rng),
	}


## `mNpc_ForceRemove`: a goodbye letter, then the animal's memories go with it
## (`mNpc_ClearAnimalInfo`).
func _villager_moved_out(villager_id: StringName, looks: int, rng: RandomNumberGenerator) -> void:
	MailDelivery.send_goodbye(villager_id, looks, rng)
	relationships.forget(villager_id)
	villagers.forget(villager_id)


# --- Weather and events -----------------------------------------------------------------------


func set_weather(next: StringName, intensity: int = -1) -> void:
	var next_intensity: int = intensity
	if next_intensity < 0:
		next_intensity = int(Weather.default_intensity_for(Weather.kind_from_name(next)))
	if town.weather == next and town.weather_intensity == next_intensity:
		return
	town.weather = next
	town.weather_intensity = next_intensity
	weather_changed.emit(town.weather)


## `result` is `{kind: Weather.Kind, intensity: Weather.Intensity}` from `Weather.roll`.
func apply_weather_roll(result: Dictionary) -> void:
	var kind: Weather.Kind = result.get("kind", Weather.Kind.CLEAR) as Weather.Kind
	var intensity: Weather.Intensity = result.get("intensity", Weather.Intensity.NONE) as Weather.Intensity
	if kind == Weather.Kind.CLEAR:
		intensity = Weather.Intensity.NONE
	set_weather(Weather.kind_name(kind), int(intensity))


## HUD debug: clear -> rain -> snow -> sakura.
func cycle_weather_debug() -> void:
	set_weather(Weather.next_in_cycle(town.weather))


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
		events.assign_town(town.world_seed)
	events.sync(EventCalendar.date_from_clock())
	MailDelivery.deliver_post_office_rounds(first)
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


# --- The resident: clothes, fortune, feng shui, stings ----------------------------------------


## Set the worn shirt (`Private_c.cloth`). Empty means the default starter cloth.
func set_cloth(next: StringName) -> void:
	var id: StringName = next if next != &"" else FirstJob.DEFAULT_CLOTH_ID
	if resident.cloth_id == id:
		return
	resident.cloth_id = id
	first_job.tick_cloth(id)
	cloth_changed.emit(id)


## Inventory "Wear": swap the pocket's shirt with the one worn (`m_hand_ovl` drop onto body).
func wear_cloth_from_slot(index: int) -> bool:
	var slot: InventorySlot = inventory.slot_at(index)
	if slot == null or slot.is_empty() or slot.item.condition != InventoryItem.Condition.NORMAL:
		return false
	var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
	if data == null or data.category != ItemData.Category.CLOTH:
		return false
	var previous: StringName = resident.cloth_id
	var wearing: StringName = slot.item.item_id
	inventory.remove_from_slot(index, 1)
	if previous != &"" and previous != wearing:
		var previous_data: ItemData = ItemCatalog.get_item(previous)
		if previous_data != null:
			inventory.add(previous_data, 1)
	set_cloth(wearing)
	return true


## `mDemo_Copy_change_player_destiny`: record the fortune and the day it was received.
func set_destiny(kind: int) -> void:
	resident.destiny_type = kind
	resident.destiny_date = Vector3i(Clock.year, Clock.month, Clock.day)


## `Game_play_Reset_destiny`: a fortune only lasts the calendar day it was received.
func destiny() -> int:
	var today := Vector3i(Clock.year, Clock.month, Clock.day)
	if resident.destiny_type != Destiny.NORMAL and resident.destiny_date != today:
		resident.destiny_type = Destiny.NORMAL
	return resident.destiny_type


## `mPr_GetGoodsPower`: the house's feng shui moved by the day's fortune (goods luck +30,
## bad luck -30), held to -30...50.
func goods_power_now() -> int:
	var power: int = goods_power
	match destiny():
		Destiny.GOODS_LUCK:
			power += 30
		Destiny.BAD_LUCK:
			power -= 30
	return clampi(power, GOODS_POWER_MIN, GOODS_POWER_MAX)


## `mHsRm_GetHuusuiRoom`.
func refresh_feng_shui() -> void:
	var power: Vector2i = FengShui.evaluate()
	money_power = power.x
	goods_power = power.y


## `mCD_SetResetInfo`: the save was still marked open, so the last session ended without
## saving. A debug disable skips the visit and does not count it.
func note_reset(reset_code: int) -> void:
	if resetti_disabled:
		reset_flag = false
		return
	reset_flag = reset_code != 0
	if reset_flag:
		resident.reset_count += 1


## First-job furniture end hands `ITM_TOWN_MAP` (`Common.map_flag`).
func unlock_map() -> void:
	if resident.has_map:
		return
	resident.has_map = true
	set_interact_prompt("Press Map to open the town map")


## `mFI_CheckPlayerWade(mFI_WADE_START)`.
func notify_wade_start() -> void:
	npc_talk_info.on_wade_start()


func capture_player_from_tree() -> void:
	var player: Player = Player.find(get_tree())
	if player == null:
		return
	resident.player_position = player.global_position
	resident.player_yaw = player.facing_yaw()


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


# --- HUD messages -----------------------------------------------------------------------------


func set_interact_prompt(text: String) -> void:
	if interact_prompt == text:
		return
	interact_prompt = text
	prompt_changed.emit(text)


func post_notice(text: String) -> void:
	notice_posted.emit(text)


# --- Interiors --------------------------------------------------------------------------------


func is_indoors() -> bool:
	return current_room_id != &""


func is_decorating() -> bool:
	var room: Room = interiors.room(current_room_id) if is_indoors() else null
	return room != null and room.can_decorate


func in_police_box() -> bool:
	var room: Room = interiors.room(current_room_id) if is_indoors() else null
	return room != null and room.kind == Room.Kind.POLICE


func bind_interior(session: IndoorSession) -> void:
	interior_session = session


## `mHm_CheckRehouseOrder` for the player's house; rebuilds the live rooms when a build lands.
func check_rehouse_order() -> bool:
	if not HouseUpgrade.check_rehouse_order(interiors.player_house()):
		return false
	interiors.refresh_player_rooms()
	return true


## Walk into `target` (a building or room id). `spawn_gx` / `spawn_yaw` stand the player
## somewhere other than the room's own door. False if the room is shut or unknown.
func try_enter_interior(
	target: StringName, spawn_gx: Variant = null, spawn_yaw: Variant = null
) -> bool:
	var room_id: StringName = InteriorCatalog.resolve_entry(target)
	if room_id == &"":
		return false
	var room: Room = interiors.room(room_id)
	if room == null:
		return false
	if not InteriorCatalog.is_open_now(room) and not _shop_open_for_first_job(room):
		post_notice(InteriorCatalog.closed_notice(room))
		return false
	if not is_indoors():
		_remember_outdoor_return()
	close_shop()
	current_room_id = room_id
	## `ac_shop_design` -> `mSP_SetNewVisitor`: a visitor from another town shopped here.
	if foreigner and room.kind == Room.Kind.SHOP:
		shops.set_visitor()
	arrival = InteriorArrival.for_room(room_id, room, spawn_gx, spawn_yaw)
	block_auto_enter_doors = true
	var stage: Node = _museum_complete_stage()
	if stage != null and stage.has_method("switch_wing"):
		return stage.call("switch_wing", room_id) as bool
	_change_scene(INTERIOR_SCENE)
	return true


func exit_interior() -> bool:
	if not is_indoors():
		return false
	close_shop()
	var leaving: Room = interiors.room(current_room_id)
	if leaving != null and leaving.kind == Room.Kind.SHOP:
		first_job.reset_shop_visit()
	if leaving != null and leaving.kind == Room.Kind.POLICE:
		police.player_left()
	last_room_id = current_room_id
	if leaving != null and leaving.parent_room_id != &"":
		return try_enter_interior(leaving.parent_room_id)
	current_room_id = &""
	interior_session = null
	roster.leave_house(interiors)
	arrival.clear()
	block_auto_enter_doors = true
	resident.player_position = outdoor_return
	resident.player_yaw = outdoor_return_yaw
	## The authored museum harness has no outdoor world: it returns to the title.
	if _museum_complete_stage() != null:
		emerge_from_door = false
		_change_scene(TITLE_SCENE)
		return true
	emerge_from_door = true
	_change_scene(WORLD_SCENE)
	return true


## Nook's "See my catalog" (`aNSC_order_select_menu_close_wait_init` opens
## `mSM_OVL_CATALOG`). Returns the overlay to await `closed(item_id)` on, or null.
func open_catalog() -> CatalogOverlay:
	var inventory_ui: InventoryOverlay = InventoryOverlay.find(get_tree())
	if inventory_ui != null:
		inventory_ui.close()
	var catalog_ui: CatalogOverlay = CatalogOverlay.find(get_tree())
	if catalog_ui != null:
		catalog_ui.open(catalog)
	return catalog_ui


func close_shop() -> void:
	var shop_ui: Node = get_tree().get_first_node_in_group("shop_ui")
	if shop_ui != null:
		shop_ui.close()


func refresh_shop_set() -> void:
	var host: Interior = Interior.find(get_tree())
	if host != null:
		host.refresh_shop_set()


func refresh_police_set() -> void:
	var host: Interior = Interior.find(get_tree())
	if host != null:
		host.refresh_public_set()


## Note where to come back out: beside the structure's door (`rewrite_out_data`), not on the
## enter stand or the roof.
func _remember_outdoor_return() -> void:
	capture_player_from_tree()
	var host: Node3D = StructureDoor.find_near(self, resident.player_position)
	if host == null:
		outdoor_return = resident.player_position
		outdoor_return_yaw = resident.player_yaw
		return
	outdoor_return = StructureDoor.exit_stand(host)
	outdoor_return_yaw = StructureDoor.leave_yaw(host, outdoor_return)


## The shop is force-open during the first-job chores (`mSP_ShopOpen` + CheckFirstJob).
func _shop_open_for_first_job(room: Room) -> bool:
	if not first_job.is_active():
		return false
	return room.kind == Room.Kind.SHOP or room.kind == Room.Kind.NEEDLEWORK


func _museum_complete_stage() -> Node:
	var stages: Array[Node] = get_tree().get_nodes_in_group("museum_complete_stage")
	return stages[0] if not stages.is_empty() else null


# --- Saving -----------------------------------------------------------------------------------


func to_save() -> Dictionary:
	## `mCkRh_SavePlayTime` runs whenever the game is saved.
	HouseCockroaches.save_play_time(interiors.player_house())
	var out := {
		"villagers": villagers.to_save(),
		"residents": residents.to_save(),
		"relationships": relationships.to_save(),
		"interiors": interiors.to_save(),
		"shops": shops.to_save(),
		"museum": museum.to_save(),
		"species_log": species_log.to_save(),
		"police": police.to_save(),
		"post": post.to_save(),
		"travel_book": travel_book.to_save(),
		"redd": redd.to_save(),
		"lighthouse": lighthouse.to_save(),
		"catalog": catalog.to_save(),
		"events": events.to_save(),
		"designs": designs.to_save(),
		"current_room_id": String(current_room_id),
		"outdoor_return": {
			"x": outdoor_return.x,
			"y": outdoor_return.y,
			"z": outdoor_return.z,
			"yaw": outdoor_return_yaw,
		},
		"first_job": first_job.to_save(),
		"quests": quests.to_save(),
		"rainbow": rainbow.to_save(),
		"notice_board": notice_board.to_save(),
		"hra": hra.to_save(),
	}
	resident.write_save(out)
	town.write_save(out)
	return out


func apply_snapshot(data: Dictionary) -> void:
	town.read_save(data)
	resident.read_save(data)
	_reset_session_flags()
	relationships.apply_snapshot(data.get("relationships", {}))
	interiors.apply_snapshot(data.get("interiors", {}))
	## `m_start_data_init.c`: a house ordered on an earlier day is built when the game starts.
	check_rehouse_order()
	HouseCockroaches.decide_family_count(interiors.player_house())
	shops.apply_snapshot(data.get("shops", {}))
	museum.apply_snapshot(data.get("museum", {}))
	species_log.apply_snapshot(data.get("species_log", {}))
	## `mPr_StartSetCompleteTalkInfo` (`m_start_data_init`): finished collections are noted for
	## the villagers' congratulations once the encyclopedia is loaded.
	CompleteTalk.start_set_info()
	if data.has("police"):
		police.apply_snapshot(data["police"])
	else:
		## Saves from before the lost and found was stored: treat as a new town's box.
		police.init_town()
	post.apply_snapshot(data.get("post", {}))
	travel_book.apply_snapshot(data.get("travel_book", {}))
	redd.apply_snapshot(data.get("redd", {}))
	lighthouse.apply_snapshot(data.get("lighthouse", {}))
	catalog.apply_snapshot(data.get("catalog", {}))
	catalog.record_inventory(inventory)
	events.apply_snapshot(data.get("events", {}))
	events.field_rank = town.field_rank
	_events_ready = false
	designs.apply_snapshot(data.get("designs", {}))
	current_room_id = StringName(str(data.get("current_room_id", "")))
	_read_outdoor_return(data.get("outdoor_return", {}))
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
	first_job.from_save(data.get("first_job", {}))


func _read_outdoor_return(saved: Variant) -> void:
	if typeof(saved) != TYPE_DICTIONARY:
		outdoor_return = DEFAULT_SPAWN
		outdoor_return_yaw = 0.0
		return
	var fields: Dictionary = saved
	outdoor_return = Vector3(
		float(fields.get("x", DEFAULT_SPAWN.x)),
		float(fields.get("y", DEFAULT_SPAWN.y)),
		float(fields.get("z", DEFAULT_SPAWN.z))
	)
	outdoor_return_yaw = float(fields.get("yaw", 0.0))


## Everything a fresh town or a loaded save forgets: the per-session flags, not the books.
func _reset_session_flags() -> void:
	shells_owed = ShellUse.FIRST_NUM
	shell_minute_counted = false
	mushrooms_session_cleared = false
	snowman_msg_id = randi_range(0, 2)
	Sunburn.reset_session()
	goki_shocked = false
	bees.clear()


## Start a new town: every book and flag back to its first value.
func reset_session() -> void:
	town.reset()
	resident.reset()
	roster = PlayerRoster.new()
	foreigner = false
	arrive_by_train = false
	inventory.clear()
	## The title resets the session before this autoload is ready, when there is no train yet.
	if train.is_inside_tree():
		train.reset()
	relationships.clear()
	interiors.clear()
	shops.clear()
	museum.clear()
	species_log.clear()
	## `mPB_police_box_init` (`m_start_data_init`): a new town starts with three items.
	police.init_town()
	police.topup_waiting = false
	post.clear()
	travel_book.clear()
	redd.clear()
	lighthouse.clear()
	catalog.clear()
	designs.clear()
	first_job.clear()
	villagers.clear()
	villagers.book = relationships
	residents.clear()
	_residents_session_done = false
	npc_talk_info.clear()
	quests.clear()
	pocket_requests.clear()
	intro.clear()
	title_demo_active = false
	interior_session = null
	current_room_id = &""
	arrival.clear()
	outdoor_return = DEFAULT_SPAWN
	outdoor_return_yaw = 0.0
	block_auto_enter_doors = false
	emerge_from_door = false
	last_room_id = &""
	complete_payment = &""
	treasure_due = false
	insect_term_month = 0
	insect_term_offset = 0
	golden_last_dig = Vector2i(-1, -1)
	nook_code_gifts = 0
	money_power = 0
	goods_power = 0
	reset_flag = false
	resetti_disabled = false
	_reset_session_flags()
	VillagerWalk.reset()
	VillagerOutdoor.reset()
	Fishing.reset()
	MoneyRock.reset()
	rainbow = Rainbow.new()
	notice_board = NoticeBoard.new()
	notice_board.seed(Clock.year, Clock.month, Clock.day, Clock.hour, Clock.minute)
	hra = HappyRoomAcademy.new()
	events.clear()
	events.field_rank = town.field_rank
	_events_ready = false
	set_interact_prompt("")


# --- Internals --------------------------------------------------------------------------------


func _set_phase(next: Phase) -> void:
	if phase == next:
		return
	phase = next
	phase_changed.emit(phase)


func _change_scene(path: String) -> void:
	Fishing.reset()
	get_tree().call_deferred("change_scene_to_file", path)
