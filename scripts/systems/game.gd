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

const DEFAULT_PLAYER_NAME := "Player"
const DEFAULT_TOWN_NAME := "Town"
const DEFAULT_PLAYER_GENDER := &"male"

var inventory: Inventory = Inventory.new()
var villagers: VillagerRoster = VillagerRoster.new()
var relationships: RelationshipBook = RelationshipBook.new()
var interiors: InteriorBook = InteriorBook.new()
var shops: ShopBook = ShopBook.new()
var museum: MuseumBook = MuseumBook.new()
var species_log: SpeciesLog = SpeciesLog.new()
var police: PoliceBook = PoliceBook.new()
var post: PostBook = PostBook.new()
var farway: FarwayBook = FarwayBook.new()
var redd: ReddBook = ReddBook.new()
var designs: DesignBook = DesignBook.new()
var first_job: FirstJob = FirstJob.new()
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
## After spawn, walk INTO_S1 past the door (museum entrance / wing links).
var play_door_arrive: bool = false
var interior_session: Interior
var player_name: String = DEFAULT_PLAYER_NAME
var town_name: String = DEFAULT_TOWN_NAME
var player_gender: StringName = DEFAULT_PLAYER_GENDER
var player_face: int = 0
## Worn shirt (`Private_c.cloth.item`). Default `ITM_CLOTH001`.
var cloth_id: StringName = FirstJob.DEFAULT_CLOTH_ID
## Worn original design display slot (`cloth.idx >= CLOTH_NUM+1`). -1 = normal shirt.
var worn_design_slot: int = -1
## Town map unlocked after first-job furniture delivery (`Common.map_flag`).
var has_map: bool = false
## Session weather (`mEnv_WEATHER_*`). Rolled by `Weather` on `field_renewed`.
var weather: StringName = &"clear"
## `mEnv_WEATHER_INTENSITY_*` (none/light/normal/heavy).
var weather_intensity: int = int(Weather.Intensity.NONE)
var dialogue_vars: Dictionary = {}
var phase: Phase = Phase.TITLE
var player_position: Vector3 = DEFAULT_SPAWN
var player_yaw: float = 0.0
var removed_interactables: Array[String] = []
var stump_interactables: Array[String] = []
var hole_interactables: Array[String] = []
var plant_states: Dictionary = {}
## Buried dig spots: persist_id → {kind, item_id, cell_x, cell_z} (`mFI` deposit / shine).
var buried_deposits: Dictionary = {}
var interact_prompt: String = ""
var world_mode: WorldData.Mode = WorldData.Mode.TEST
var world_seed: int = WorldGenerator.DEFAULT_SEED
## Town grass motif (`bg_tex_idx`): 0 triangle, 1 square, 2 circle.
var grass_pattern: int = WorldData.GrassPattern.TRIANGLE
## Station arrival (`ac_intro_demo`) runs inside the generated world, not a test acre.
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

## `mMmd` museum donation: Blathers opens the pockets so the player picks what to hand
## over. `museum_donate_result` holds the last outcome for his response dialogue.
var museum_donate_pending: bool = false
var museum_donate_result: Dictionary = {}
signal museum_donate_resolved(donated: bool)


func _init() -> void:
	villagers.book = relationships
	if museum == null:
		museum = MuseumBook.new()


func _ready() -> void:
	if museum == null:
		museum = MuseumBook.new()
	ReddBook.ensure_art_items()
	if not Clock.field_renewed.is_connected(_on_field_renewed):
		Clock.field_renewed.connect(_on_field_renewed)


func has_continue() -> bool:
	return SaveService.has_save()


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
	## player set on the train.
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
		data = WorldGenerator.generate(world_seed)
	else:
		data = WorldGenerator.authored_test_town()
	data.grass_pattern = grass_pattern
	FieldCatalog.set_grass_pattern(grass_pattern)
	return data


func continue_game() -> void:
	if SaveService.load_game() != OK:
		start_new_game()
		return
	if current_room_id != &"":
		_change_scene(INTERIOR_SCENE)
	else:
		_change_scene(WORLD_SCENE)


func return_to_title() -> void:
	capture_player_from_tree()
	SaveService.save_game()
	_set_phase(Phase.TITLE)
	_change_scene(TITLE_SCENE)


func notify_world_ready() -> void:
	if world_mode == WorldData.Mode.TEST:
		give_test_tools()
	if intro_station_active:
		_set_phase(Phase.INTRO)
	else:
		_set_phase(Phase.PLAYING)


func notify_title_ready() -> void:
	_set_phase(Phase.TITLE)
	set_interact_prompt("")


func reset_session() -> void:
	inventory.clear()
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
	else:
		police.clear()
	if post == null:
		post = PostBook.new()
	else:
		post.clear()
	interior_session = null
	current_room_id = &""
	outdoor_return = DEFAULT_SPAWN
	outdoor_return_yaw = 0.0
	spawn_at_room_door = false
	has_interior_spawn = false
	block_auto_enter_doors = false
	emerge_from_door = false
	play_door_arrive = false
	villagers.clear()
	villagers.book = relationships
	VillagerWalk.reset()
	Fishing.reset()
	player_position = DEFAULT_SPAWN
	player_yaw = 0.0
	removed_interactables.clear()
	stump_interactables.clear()
	hole_interactables.clear()
	plant_states.clear()
	buried_deposits.clear()
	player_name = DEFAULT_PLAYER_NAME
	town_name = DEFAULT_TOWN_NAME
	player_gender = DEFAULT_PLAYER_GENDER
	player_face = 0
	cloth_id = FirstJob.DEFAULT_CLOTH_ID
	has_map = false
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
	museum_donate_pending = false
	museum_donate_result = {}
	if farway == null:
		farway = FarwayBook.new()
	else:
		farway.clear()
	if redd == null:
		redd = ReddBook.new()
	else:
		redd.clear()
	if designs == null:
		designs = DesignBook.new()
	else:
		designs.clear()
	worn_design_slot = -1
	set_interact_prompt("")


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
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	player_position = player.global_position
	if player.has_method("facing_yaw"):
		player_yaw = float(player.call("facing_yaw"))


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
		"plants": plant_states.duplicate(true),
		"buried": buried_deposits.duplicate(true),
		"world_mode": int(world_mode),
		"world_seed": world_seed,
		"grass_pattern": grass_pattern,
		"villagers": villagers.to_save(),
		"relationships": relationships.to_save(),
		"interiors": interiors.to_save(),
		"shops": shops.to_save(),
		"museum": museum.to_save(),
		"species_log": species_log.to_save(),
		"police": police.to_save(),
		"post": post.to_save(),
		"farway": farway.to_save(),
		"redd": redd.to_save(),
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
		"has_map": has_map,
		"first_job": first_job.to_save() if first_job != null else {},
		"weather": String(weather),
		"weather_intensity": weather_intensity,
		"dialogue_vars": dialogue_vars.duplicate(true),
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
	shops.apply_snapshot(data.get("shops", {}))
	if museum == null:
		museum = MuseumBook.new()
	museum.apply_snapshot(data.get("museum", {}))
	if species_log == null:
		species_log = SpeciesLog.new()
	species_log.apply_snapshot(data.get("species_log", {}))
	if police == null:
		police = PoliceBook.new()
	police.apply_snapshot(data.get("police", {}))
	if post == null:
		post = PostBook.new()
	post.apply_snapshot(data.get("post", {}))
	if farway == null:
		farway = FarwayBook.new()
	farway.apply_snapshot(data.get("farway", {}))
	if redd == null:
		redd = ReddBook.new()
	redd.apply_snapshot(data.get("redd", {}))
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
	player_name = str(data.get("player_name", DEFAULT_PLAYER_NAME))
	town_name = str(data.get("town_name", DEFAULT_TOWN_NAME))
	player_gender = IntroSequence.normalize_gender(data.get("player_gender", DEFAULT_PLAYER_GENDER))
	player_face = clampi(int(data.get("player_face", 0)), 0, IntroSequence.FACE_TYPE_NUM - 1)
	cloth_id = StringName(str(data.get("cloth_id", FirstJob.DEFAULT_CLOTH_ID)))
	if cloth_id == &"":
		cloth_id = FirstJob.DEFAULT_CLOTH_ID
	has_map = bool(data.get("has_map", false))
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
	play_door_arrive = false
	if spawn_gx is Vector3:
		interior_spawn_gx = spawn_gx as Vector3
		interior_spawn_yaw = float(spawn_yaw) if spawn_yaw != null else 0.0
		has_interior_spawn = true
		spawn_at_room_door = false
		## Non-museum linked spawns may continue INTO_S1; museum wings stay on door_data.
		play_door_arrive = not _is_museum_room_id(room_id)
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
		## `aMHS_goto_next_pl_scene` HOMESIZE_S startX/Z.
		interior_spawn_gx = InteriorCatalog.PLAYER_SMALL_SPAWN_GX
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
	Audio.sync_rain_syslev(
		Weather.kind_from_name(weather), weather_intensity as Weather.Intensity, true
	)
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


func open_shop(shop_id: StringName, mode: StringName = Interaction.BUY) -> bool:
	if shop_id == &"":
		return false
	shops.ensure_today(shop_id)
	if get_tree() == null:
		return false
	var inv_ui: Node = get_tree().get_first_node_in_group("inventory_ui")
	if inv_ui != null and inv_ui.has_method("close"):
		inv_ui.call("close")
	var ui: Node = get_tree().get_first_node_in_group("shop_ui")
	if ui == null or not ui.has_method("open"):
		return false
	ui.call("open", shop_id, mode)
	return true


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


func _on_field_renewed(days: int) -> void:
	shops.renew(days)
	refresh_shop_set()
	if police != null:
		for _i: int in maxi(days, 1):
			police.force_set_keep_item()
	refresh_police_set()
	_deliver_farway_mail()
	if redd != null:
		redd.check_unlock()
	## One roll for the current date after renew (`mEnv_DecideWeather` / `aWeather_ChangeWeatherTime0`).
	apply_weather_roll(Weather.roll())


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
	var room: Room = leaving
	if room != null and room.parent_room_id != &"":
		return try_enter_interior(room.parent_room_id)
	current_room_id = &""
	interior_session = null
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
	Audio.sync_rain_syslev(
		Weather.kind_from_name(weather), weather_intensity as Weather.Intensity, false
	)
	return true


func bind_interior(session: Interior) -> void:
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
	var facing: WorldGrid.Facing = WorldGrid.facing_from_yaw(
		float(actor.call("facing_yaw")) if actor.has_method("facing_yaw") else actor.rotation.y
	)
	var cell: Vector2i = interior_session.grid.world_to_cell(actor.global_position)
	cell = interior_session.grid.step(cell, facing)
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


func _unhandled_input(event: InputEvent) -> void:
	if phase != Phase.PLAYING:
		return
	if event.is_action_pressed("pause_menu"):
		if (
			_group_is_open("inventory_ui")
			or _group_is_open("dialogue_ui")
			or _group_is_open("shop_ui")
			or _group_is_open("map_ui")
			or _group_is_open("debug_console_ui")
		):
			return
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
