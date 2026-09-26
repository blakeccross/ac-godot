extends StaticBody3D

## The gyroid outside a house plot (`ac_haniwa` / `ACTOR_PROP_HANIWA0`–`3`, skeleton `hnw`).
## Bobs on `hnw_move` — faster once the owner comes near, frozen outside an empty plot — and
## is where the player saves: "Save" walks them to the door, the door opens, and the game
## saves and returns to the title (`SCENE_PLAYERSELECT_SAVE`). Rules live in `HaniwaTalk`.

const MODEL_PATH := "res://assets/generated/characters/other/hnw.glb"
const ANIM_MOVE := "hnw_move"

## `world_builder.gd::_apply_common` sets these from the placement (`player_haniwa`,
## `player_haniwa_1`–`3`, one per `HOUSE0`–`3` plot).
@export var occupant_id: StringName = &"player_haniwa"
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.FURNITURE
@export var visual_id: StringName = &""

var house_idx: int = 0
var _action: HaniwaTalk.Action = HaniwaTalk.Action.WAIT
## `anim_frame_speed` (target) and `frame_control.speed` (current), cKF keyframes per 60 Hz tick.
var _target_speed: float = 0.0
var _speed: float = 0.0
var _stopped: bool = false
var _talking: bool = false
var _anim: AnimationPlayer
var _yaw: float = 0.0
## Current `hnw_move` keyframe (1..9).
var _frame: float = HaniwaTalk.MOVE_FIRST_FRAME


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("haniwa")
	house_idx = PlayerHouse.plot_of(String(name))
	_yaw = HaniwaTalk.look_yaw(house_idx, false, HaniwaTalk.Action.WAIT, 0.0)
	rotation.y = _yaw
	_attach_model()
	HostCollision.apply_box(self, footprint, HostCollision.CELL, 1.0)
	_setup_action(HaniwaTalk.Action.WAIT)
	_speed = _target_speed


func apply_grid_yaw(_facing: WorldGrid.Facing) -> void:
	## Faces its plot's front angle or the player (`aHNW_common_process`), not a grid facing.
	pass


func refresh_seasonal_visual() -> void:
	pass


## This plot's house belongs to the player (`mPr_NullCheckPersonalID(ownerID)` is false
## and `mHS_get_pl_no(house_idx) == player_no`). The other three plots are empty in a
## one-player town, and all four are while the station intro is still picking.
func has_owner() -> bool:
	return Game != null and PlayerHouse.is_owned_node(PlayerHouse.plot_building(house_idx))


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if _talking or _action >= HaniwaTalk.Action.PL_APPROACH_DOOR:
		return []
	return [Interaction.of(Interaction.TALK, "Talk to the gyroid", 20)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK or Game == null or _talking:
		return false
	var listener: Node3D = ctx.actor as Node3D if ctx != null else _player()
	var saving: bool = await _talk(listener)
	if saving:
		## Not awaited: the player's interact wrapper keeps them locked until this returns,
		## and the walk needs them free to move.
		_save_walk()
	return true


func _physics_process(delta: float) -> void:
	var player: Node3D = _player()
	var player_yaw: float = _yaw
	var dist_gx: float = INF
	if player != null:
		var to: Vector3 = player.global_position - global_position
		to.y = 0.0
		dist_gx = to.length() / FieldCatalog.GX_TO_METERS
		if to.length_squared() > 0.0001:
			player_yaw = atan2(to.x, to.z)
	## `aHNW_wait` / `aHNW_dance`.
	if _action == HaniwaTalk.Action.WAIT and dist_gx < HaniwaTalk.DANCE_NEAR_GX:
		_setup_action(HaniwaTalk.Action.DANCE)
	elif _action == HaniwaTalk.Action.DANCE and dist_gx > HaniwaTalk.DANCE_FAR_GX:
		_setup_action(HaniwaTalk.Action.WAIT)
	_common_process(delta, player_yaw)


## `aHNW_setupAction`: new target frame speed; an ownerless gyroid outside a talk plays its
## clip out and freezes.
func _setup_action(action: HaniwaTalk.Action) -> void:
	_action = action
	var owned: bool = has_owner()
	_target_speed = HaniwaTalk.anim_speed(action, owned, owned, _target_speed)


## `aHNW_common_process` + `cKF_SkeletonInfo_R_play`, one 60 Hz tick scaled by `delta`.
func _common_process(delta: float, player_yaw: float) -> void:
	var owned: bool = has_owner()
	var ticks: float = delta * DecompTime.TICK_HZ
	_speed = HaniwaTalk.chase_speed(_speed, _target_speed, ticks)
	if owned and _stopped:
		_stopped = false
		_setup_action(_action)
	elif HaniwaTalk.stops_at_end(_action, owned, _speed):
		_stopped = true
	else:
		_stopped = false
	_yaw = HaniwaTalk.chase_yaw(_yaw, HaniwaTalk.look_yaw(house_idx, owned, _action, player_yaw), delta)
	rotation.y = _yaw
	_step_frame(ticks)


## `cKF_SkeletonInfo_R_play` on `hnw_move` (keyframes 1 → 9): advance `speed` keyframes per
## 60 Hz tick, wrapping in REPEAT and holding the last one in STOP. The clip is baked at 30 fps,
## so keyframe `f` sits at `(f − 1) / 30` s. Seeked by hand: the four gyroids share one
## imported `Animation`, so its loop mode cannot carry per-gyroid state.
func _step_frame(ticks: float) -> void:
	var first: float = HaniwaTalk.MOVE_FIRST_FRAME
	var last: float = HaniwaTalk.MOVE_LAST_FRAME
	_frame += _speed * ticks
	if _stopped:
		_frame = minf(_frame, last)
	elif _frame >= last:
		_frame = first + fmod(_frame - first, last - first)
	if _anim == null or not _anim.has_animation(ANIM_MOVE):
		return
	if _anim.assigned_animation != ANIM_MOVE:
		_anim.play(ANIM_MOVE)
		_anim.pause()
	_anim.seek((_frame - first) / DecompTime.FRAME_HZ, true)


## `aHNW_dance` → the conversation. Returns true when the owner chose to save. Menus
## (consign, message, door pattern, visitor take) close the window, run, and the talk picks up
## again at "Request processed." (`aHNW_menu_open_wait` / `aHNW_menu_end_wait`).
func _talk(listener: Node3D) -> bool:
	var ui := DialogueOverlay.find(get_tree())
	var owned: bool = has_owner()
	## One resident per town: the owner is always the player (`OTHER_OWNER` is the visitor path).
	var owner_is_player: bool = owned
	var house: House = Game.interiors.player_house() if Game.interiors != null else null
	var msg: HaniwaTalk.Msg = HaniwaTalk.decide_msg(
		owned,
		owner_is_player,
		house != null and house.has_saved,
		Game.first_job != null and Game.first_job.is_active(),
		Game.relationships.friend_count() if Game.relationships != null else 0,
		house.haniwa_bells if house != null and owned else 0
	)
	if ui == null:
		Game.post_notice("The gyroid hums a tune.")
		return false
	if ui.is_open():
		ui.close()
	_talking = true
	## Dance at talk speed, facing the player.
	_setup_action(HaniwaTalk.Action.TALK_WITH_MASTER)
	if listener != null:
		TalkCamera.begin(listener, self, get_tree())
	var saving: bool = false
	match msg:
		HaniwaTalk.Msg.NO_OWNER, HaniwaTalk.Msg.NEED_FRIEND:
			await _play(DialogueCatalog.conversation(StringName("msg_%d" % HaniwaTalk.msg_no(msg))), {}, house)
		_:
			saving = await _run_menus(msg, house)
	if is_instance_valid(self):
		TalkCamera.end(get_tree())
		_talking = false
		_setup_action(HaniwaTalk.Action.DANCE)
	return saving


func _run_menus(msg: HaniwaTalk.Msg, house: House) -> bool:
	var data: DialogueData = HaniwaTalk.graph()
	if data == null:
		return false
	var vars: Dictionary = {HaniwaTalk.VAR_START: HaniwaTalk.START_MENU}
	match msg:
		HaniwaTalk.Msg.PROCEEDS:
			## `aHNW_check_proceeds`: the income line names the amount, then the hand-over runs.
			vars[HaniwaTalk.VAR_START] = HaniwaTalk.START_PROCEEDS
			vars["free0"] = str(house.haniwa_bells)
			var result: Dictionary = HaniwaStore.collect_proceeds(house, Game.inventory)
			vars[HaniwaTalk.VAR_HANDOVER] = "yes" if bool(result["ok"]) else "no"
			vars["free1"] = str(int(result["bags"]))
		HaniwaTalk.Msg.OTHER_OWNER:
			vars[HaniwaTalk.VAR_START] = HaniwaTalk.START_GUEST
	while is_instance_valid(self):
		vars[HaniwaTalk.VAR_HAS_ITEMS] = "yes" if HaniwaStore.has_items(house) else "no"
		var events: Array[Dictionary] = await _play(data, vars, house)
		var menu: String = ""
		for event: Dictionary in events:
			match str(event.get("op", "")):
				HaniwaTalk.EVENT_SAVE:
					return true
				HaniwaTalk.EVENT_MENU:
					menu = str(event.get("menu", ""))
		if menu == "":
			return false
		await _run_menu(menu, house)
		vars[HaniwaTalk.VAR_START] = (
			HaniwaTalk.START_GUEST_AFTER if menu == HaniwaTalk.MENU_TAKE else HaniwaTalk.START_RESUME
		)
		vars.erase("free0")
	return false


## Plays one stretch of the conversation; returns the events it fired. "Remove pattern"
## takes effect the moment it is chosen.
func _play(data: DialogueData, vars: Dictionary, house: House) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ui := DialogueOverlay.find(get_tree())
	if ui == null or data == null:
		return events
	var talk_ctx: DialogueContext = DialogueContext.from_game()
	talk_ctx.speaker_name = HaniwaTalk.SPEAKER_NAME
	talk_ctx.speaker_sex = MessageWindowChrome.SpeakerSex.OTHER
	talk_ctx.voice_mode = DialogueVoice.Mode.ANIMALESE
	talk_ctx.sound_spec = HaniwaTalk.SOUND_SPEC
	talk_ctx.mail_text = HaniwaStore.message(house)
	var frees := PackedStringArray()
	frees.resize(3)
	frees[2] = Game.player_name
	for key: String in vars:
		if key.begins_with("free"):
			frees[int(key.substr(4))] = str(vars[key])
		else:
			talk_ctx.set_var(key, vars[key])
	talk_ctx.frees = frees
	var capture := func(event: Dictionary) -> void:
		events.append(event)
		if str(event.get("op", "")) == HaniwaTalk.EVENT_DOOR_REMOVE and house != null:
			house.door_original = PlayerHouse.NO_DOOR_PATTERN
			Audio.play_se(&"461")
			_refresh_door()
	ui.event_fired.connect(capture)
	ui.play(data, talk_ctx)
	if ui.is_open():
		await ui.closed
	ui.event_fired.disconnect(capture)
	return events


## `aHNW_menu_open_wait`: open the submenu the choice asked for and wait for it to close.
func _run_menu(menu: String, house: House) -> void:
	var tree: SceneTree = get_tree()
	if tree == null or house == null:
		return
	match menu:
		HaniwaTalk.MENU_ENTRUST, HaniwaTalk.MENU_TAKE:
			var inv_ui: Node = tree.get_first_node_in_group("inventory_ui")
			if inv_ui != null and inv_ui.has_method("open_haniwa"):
				inv_ui.call("open_haniwa", house, menu == HaniwaTalk.MENU_ENTRUST)
				if bool(inv_ui.call("is_open")):
					await inv_ui.closed
		HaniwaTalk.MENU_MESSAGE:
			var writer: Node = tree.get_first_node_in_group("letter_writer_ui")
			if writer != null and writer.has_method("open_board"):
				writer.call(
					"open_board",
					HaniwaStore.message(house),
					HaniwaStore.MESSAGE_LINES,
					HaniwaStore.MESSAGE_LEN,
					func(text: String) -> void: house.haniwa_message = text
				)
				if bool(writer.call("is_open")):
					await writer.closed
		HaniwaTalk.MENU_DOOR:
			## `mNW_OPEN_DESIGN` → `door_original = mNW_get_image_no(slot)`, SE 0x461.
			var list_ui: Node = tree.get_first_node_in_group("design_list_ui")
			if list_ui != null and list_ui.has_method("open") and Game.designs != null:
				var picked: Array[int] = [-1]
				list_ui.call("open", "pick_trade", func(slot: int) -> void: picked[0] = slot)
				if bool(list_ui.call("is_open")):
					await list_ui.closed
					## The list emits `closed` before it hands over the pick.
					await tree.process_frame
				if picked[0] >= 0:
					house.door_original = Game.designs.resolved_index(picked[0])
					Audio.play_se(&"461")
					_refresh_door()


func _refresh_door() -> void:
	var node: Node = _house_node()
	if node is Node3D:
		PlayerHouse.apply_exterior_decorations(node as Node3D)


## `aHNW_save_end_wait` → `aHNW_pl_approach_door` → door opens → `SCENE_PLAYERSELECT_SAVE`.
func _save_walk() -> void:
	var house_record: House = Game.interiors.player_house() if Game.interiors != null else null
	if house_record != null:
		house_record.has_saved = true
	Audio.play_bgm(&"enter_house")
	_setup_action(HaniwaTalk.Action.PL_APPROACH_DOOR)
	var player := Player.find(get_tree())
	if player != null:
		var gx: float = FieldCatalog.GX_TO_METERS
		var speed: float = HaniwaTalk.DOOR_WALK_SPEED_GX * DecompTime.FRAME_HZ * gx
		var arrive: float = HaniwaTalk.DOOR_ARRIVE_GX * gx
		var frames: float = 0.0
		while is_instance_valid(player) and frames <= float(HaniwaTalk.DOOR_WALK_FRAMES):
			var offset := Vector2(
				(player.global_position.x - global_position.x) / gx,
				(player.global_position.z - global_position.z) / gx
			)
			var stage: int = HaniwaTalk.door_stage(house_idx, offset)
			var goal_gx: Vector2 = HaniwaTalk.door_goal_gx(house_idx, stage)
			var goal := global_position + Vector3(goal_gx.x * gx, 0.0, goal_gx.y * gx)
			player.begin_demo_walk(goal, speed, arrive)
			var near: float = Vector2(player.global_position.x - goal.x, player.global_position.z - goal.z).length()
			if stage == 1 and near < arrive * 2.0:
				break
			await get_tree().physics_frame
			frames += get_physics_process_delta_time() * DecompTime.TICK_HZ
		if is_instance_valid(player):
			player.end_demo_walk()
	var house: Node3D = _house_node() as Node3D
	if house != null:
		await StructureDoor.play_enter(house)
	await SceneTransition.play_wipe_out(SceneTransition.Style.FADE)
	## `return_to_title` saves where the player stands, which is now halfway through the
	## door. Continue from the porch instead, facing out (`rewrite_out_data`'s stand).
	if house != null and is_instance_valid(player):
		player.end_door_enter()
		var stand: Vector3 = StructureDoor.exit_stand(house)
		player.global_position = stand
		player.set_facing(StructureDoor.leave_yaw(house, stand))
	Game.return_to_title()


func _house_node() -> Node:
	if get_tree() == null:
		return null
	var want: String = PlayerHouse.plot_building(house_idx)
	for n: Node in get_tree().get_nodes_in_group("interactable"):
		if n.name == want:
			return n
	return null


func _player() -> Node3D:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("player") as Node3D


func _attach_model() -> void:
	if not ResourceLoader.exists(MODEL_PATH):
		return
	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if packed == null:
		return
	var pivot := Node3D.new()
	pivot.name = "GeneratedVisual"
	pivot.add_child(packed.instantiate())
	VisualAnimation.stop_autoplay(pivot)
	add_child(pivot)
	VisualFit.apply_actor_scale(pivot, &"hnw")
	VisualFit.align_actor_to_height_gx(pivot, 0.0)
	VisualMaterials.apply(pivot)
	_anim = VisualAnimation.find_animation_player(pivot)
	var placeholder: Node = get_node_or_null("Placeholder")
	if placeholder != null:
		placeholder.queue_free()
