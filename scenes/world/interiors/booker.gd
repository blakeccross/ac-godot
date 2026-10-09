extends CharacterBody3D

## Booker in the police box (`ac_npc_police2` / `SP_NPC_POLICE2`, skeleton `pla_1`).
##
## - Walked in through the door (`door_actor_name != RSV_NO`): he starts in GREET and
##   speaks first (0x0784 / 0x0785) as soon as the player is free.
## - Otherwise he tails the player around the room: standing inside ~50 GX, walking
##   within ~70 GX, running beyond; in the player's own zone he just turns to face them,
##   in another zone he steps zone waypoint to zone waypoint around the shelves
##   (`aPOL2_decide_next_move_act`, `aPOL2_search_player2`, `PoliceDisplay.next_zone`).
## - Facing a lost-and-found unit and pressing A asks him about that item (0x077E);
##   "It's mine" moves it into the pockets or reports full pockets (0x0781).
## - Every talk: he stops, turns to the player at 11.25° a frame, then the window opens.

enum Act { GREET, WAIT, WALK_SAME, WALK_OTHER, RUN_SAME, RUN_OTHER, TURN, CHECK_ANSWER, TALK_END_WAIT }

const ANIM_WAIT := "npc_1_wait1"
const ANIM_WALK := "npc_1_walk1"
const ANIM_RUN := "npc_1_run1"
## `aPOL2_set_animation` per action.
const ACT_ANIM: Array[String] = [
	ANIM_WAIT, ANIM_WAIT, ANIM_WALK, ANIM_WALK, ANIM_RUN, ANIM_RUN, ANIM_WALK, ANIM_WAIT, ANIM_WAIT
]

## `aPOL2_set_walk_spd` / `_run_spd` in NPC speed units (30 GX/s each → 1.5 m/s), with
## accel / decel per 60 Hz frame at half weight (`aNPC_position_move`), in m/s².
const WALK_SPEED := 1.0 * 1.5
const WALK_ACCEL := 0.1 * 0.5 * 60.0 * 1.5
const WALK_DECEL := 0.2 * 0.5 * 60.0 * 1.5
const RUN_SPEED := 4.0 * 1.5
const RUN_ACCEL := 0.4 * 0.5 * 60.0 * 1.5
const RUN_DECEL := 0.8 * 0.5 * 60.0 * 1.5
## `chase_angle(..., DEG2SHORT_ANGLE2(11.25f))` at `game_GameFrame_2F` → 337.5°/s.
const TURN_RATE := deg_to_rad(11.25) * 30.0
## `aPOL2_search_player`: more than 90° off → stop and TURN first.
const TURN_ONLY := PI * 0.5

var act: Act = Act.WAIT
var _grid: WorldGrid = null
var _model: Node3D
var _body_anim: AnimationPlayer
var _face: NpcFace = NpcFace.new()
var _clip: String = ""
var _speed: float = 0.0
var _now_zone: int = 0
var _next_zone: int = 0
var _pl_zone: int = 0
## `_99C`: he greeted you with items this visit, so an emptied box gets 0x0787.
var _greeted_with_items: bool = false
## `item_idx`: the slot being asked about, -1 for a plain talk.
var _item_idx: int = -1
## A talk waiting on his turn (`mDemo_Check(...) && !mDemo_Check_ListenAble()`).
var _pending_msg: int = -1
var _talking: bool = false
var _talk_ctx: DialogueContext = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("police_set")
	## Characters layer (the player collides with him); mask 1 keeps him off the walls.
	collision_layer = 4
	collision_mask = 1
	_rng.randomize()
	_ensure_collision()
	_ensure_visual()
	_ensure_interact()
	## `aPOL2_actor_ct`: GREET only when the scene was entered through the door.
	_setup(Act.GREET if _entered_by_door() else Act.WAIT)


func bind_grid(grid: WorldGrid) -> void:
	_grid = grid


## The live room is only ever reached through its door; the F6 preview and tests are not.
func _entered_by_door() -> bool:
	return Game != null and Game.current_room_id == &"police_box"


func _process(delta: float) -> void:
	var uttering: bool = false
	if _talking and get_tree() != null:
		uttering = DialogueOverlay.uttering_in(get_tree())
	_face.tick(delta, uttering)


func _physics_process(delta: float) -> void:
	var player: Node3D = Player.find(get_tree()) if get_tree() != null else null
	_update_zones(player)
	if _pending_msg >= 0:
		_turn_then_speak(player, delta)
	else:
		match act:
			Act.GREET:
				if _player_free(player):
					_request(PoliceTalk.greet_msg(_keep_sum()))
			Act.WAIT, Act.WALK_SAME, Act.WALK_OTHER, Act.RUN_SAME, Act.RUN_OTHER:
				_move_act(player, delta)
			Act.TURN:
				_turn_act(player, delta)
			Act.CHECK_ANSWER, Act.TALK_END_WAIT:
				if not _talking:
					_setup(Act.WAIT)
	_apply_motion(delta)


## --- Talk requests ---------------------------------------------------------------------


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	return [Interaction.of(Interaction.TALK, "Talk to Booker", 20)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK or Game == null:
		return false
	if _talking or _pending_msg >= 0:
		return false
	## `aPOL2_set_norm_talk_info_message_ctrl`.
	_item_idx = -1
	_request(PoliceTalk.talk_msg(_keep_sum(), _greeted_with_items))
	return true


## The player pressed A facing `RSV_POLICE_ITEM_<slot>` (`aPOL2_message_ctrl`): a kept
## item there starts the claim talk from wherever he is.
func begin_claim(slot: int, _ctx: InteractionContext) -> bool:
	if Game == null or Game.police == null or _talking or _pending_msg >= 0:
		return false
	if Game.police.item_at(slot) == &"":
		return false
	_item_idx = slot
	_request(PoliceTalk.MSG_CLAIM)
	return true


func _request(msg_no: int) -> void:
	_pending_msg = msg_no
	_speed = 0.0
	velocity = Vector3.ZERO
	## `mPlib_request_main_demo_wait_type1`: the player waits while he turns.
	var player: Player = Player.find(get_tree()) if get_tree() != null else null
	if player != null:
		player.set_busy(true)


func _turn_then_speak(player: Node3D, delta: float) -> void:
	_play_act_anim(ANIM_WAIT)
	if player != null and not _chase_yaw(_yaw_to(player.global_position), delta):
		return
	var msg_no: int = _pending_msg
	_pending_msg = -1
	var from_greet: bool = act == Act.GREET
	if from_greet and msg_no == PoliceTalk.MSG_GREET_ITEMS:
		_greeted_with_items = true
	## GREET → TALK_END_WAIT; the item speak → CHECK_ANSWER; a plain talk → TALK_END_WAIT.
	_setup(Act.CHECK_ANSWER if msg_no == PoliceTalk.MSG_CLAIM else Act.TALK_END_WAIT)
	_open_talk(msg_no, player)


func _open_talk(msg_no: int, player: Node3D) -> void:
	var ctx: DialogueContext = DialogueContext.from_game()
	ctx.speaker_name = "Booker"
	if msg_no == PoliceTalk.MSG_CLAIM and Game != null and Game.police != null:
		PoliceTalk.fill_claim(ctx, Game.police.item_at(_item_idx))
	var data: DialogueData = PoliceTalk.conversation(msg_no, ctx)
	## `aPOL2_set_norm_talk_info_message_ctrl`: April Fools' Day's trick instead of the desk talk.
	if msg_no == PoliceTalk.MSG_TALK_ITEMS or msg_no == PoliceTalk.MSG_TALK_EMPTY:
		var trick: DialogueData = AprilFools.conversation(&"booker")
		if trick != null:
			data = trick
	var ui := DialogueOverlay.find(get_tree())
	var p: Player = player as Player
	if p != null:
		p.set_busy(false)
	if ui == null or data == null:
		_talking = false
		_item_idx = -1
		return
	if ui.is_open():
		ui.close()
	_talking = true
	_talk_ctx = ctx
	if player != null:
		TalkCamera.begin(player, self, get_tree())
	if not ui.event_fired.is_connected(_on_dialogue_event):
		ui.event_fired.connect(_on_dialogue_event)
	if ui.closed.is_connected(_on_talk_closed):
		ui.closed.disconnect(_on_talk_closed)
	ui.closed.connect(_on_talk_closed, CONNECT_ONE_SHOT)
	ui.play(data, ctx)


func _on_dialogue_event(event: Dictionary) -> void:
	if _item_idx < 0:
		return
	var result: PoliceBook.Claim = PoliceTalk.apply_event(event, _talk_ctx, _item_idx)
	if result == PoliceBook.Claim.OK:
		## `mFI_SetFG_common(RSV_NO, …)` marks the FG dirty so `bg_police_item` redraws.
		Audio.play_se(&"item_get", Player.find(get_tree()))
		Game.call_deferred("refresh_police_set")


func _on_talk_closed() -> void:
	var ui := DialogueOverlay.find(get_tree())
	if ui != null and ui.event_fired.is_connected(_on_dialogue_event):
		ui.event_fired.disconnect(_on_dialogue_event)
	_talking = false
	_talk_ctx = null
	_item_idx = -1
	TalkCamera.end(get_tree())


func _player_free(player: Node3D) -> bool:
	var p: Player = player as Player
	if p == null or p.is_busy() or p.is_door_entering():
		return false
	return not DialogueOverlay.open_in(get_tree())


func _keep_sum() -> int:
	return Game.police.keep_item_sum() if Game != null and Game.police != null else 0


## --- Movement (`aPOL2_decide_next_move_act` and friends) --------------------------------


func _move_act(player: Node3D, delta: float) -> void:
	var next: Act = _decide_next_move_act(player)
	if next != act:
		_setup(next)
		return
	match act:
		Act.WALK_OTHER, Act.RUN_OTHER:
			_search_player2(player, delta)
		_:
			_search_player(player, delta)


func _decide_next_move_act(player: Node3D) -> Act:
	if player == null:
		return act
	var d: Vector3 = _gx(player.global_position) - _gx(global_position)
	var dist_sq: float = d.x * d.x + d.z * d.z
	if dist_sq < PoliceDisplay.STOP_DIST_SQ:
		return Act.WAIT
	if _pl_zone != _now_zone:
		if act != Act.WALK_OTHER and act != Act.RUN_OTHER:
			_next_zone = PoliceDisplay.next_zone(_pl_zone, _now_zone, _rng.randi_range(0, 1))
		return Act.WALK_OTHER if dist_sq < PoliceDisplay.WALK_DIST_SQ else Act.RUN_OTHER
	_next_zone = _now_zone
	return Act.WALK_SAME if dist_sq < PoliceDisplay.WALK_DIST_SQ else Act.RUN_SAME


## `aPOL2_search_player`: face the player; more than 90° off means TURN in place first.
func _search_player(player: Node3D, delta: float) -> void:
	if player == null:
		return
	var want: float = _yaw_to(player.global_position)
	if absf(angle_difference(rotation.y, want)) > TURN_ONLY:
		_setup(Act.TURN)
		return
	_chase_yaw(want, delta)


## `aPOL2_search_player2`: head for the next zone's waypoint; near it, pick the next one.
func _search_player2(player: Node3D, delta: float) -> void:
	if player == null:
		return
	var goal: Vector3 = PoliceDisplay.zone_waypoint_gx(_next_zone)
	var here: Vector3 = _gx(global_position)
	var d := Vector2(goal.x - here.x, goal.z - here.z)
	_chase_yaw(atan2(d.x, d.y), delta)
	if d.length_squared() < PoliceDisplay.WAYPOINT_DIST_SQ:
		_next_zone = PoliceDisplay.next_zone(_pl_zone, _now_zone, _rng.randi_range(0, 1))


func _turn_act(player: Node3D, delta: float) -> void:
	if player == null:
		return
	var want: float = _yaw_to(player.global_position)
	_chase_yaw(want, delta)
	if absf(angle_difference(rotation.y, want)) <= TURN_ONLY:
		_setup(Act.WAIT)


func _update_zones(player: Node3D) -> void:
	_now_zone = PoliceDisplay.zone_for_gx(_gx(global_position))
	if player != null:
		_pl_zone = PoliceDisplay.zone_for_gx(_gx(player.global_position))


## `aNPC_position_move`: chase speed toward the action's max, then step along facing.
func _apply_motion(delta: float) -> void:
	var max_speed: float = 0.0
	var accel: float = 0.0
	var decel: float = 0.0
	match act:
		Act.WALK_SAME, Act.WALK_OTHER:
			max_speed = WALK_SPEED
			accel = WALK_ACCEL
			decel = WALK_DECEL
		Act.RUN_SAME, Act.RUN_OTHER:
			max_speed = RUN_SPEED
			accel = RUN_ACCEL
			decel = RUN_DECEL
	if _pending_msg >= 0 or max_speed <= 0.0:
		## `aPOL2_set_stop_spd` zeroes speed outright.
		_speed = 0.0
	elif _speed < max_speed:
		_speed = minf(max_speed, _speed + accel * delta)
	else:
		_speed = maxf(max_speed, _speed - decel * delta)
	var dir := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	velocity = dir * _speed
	velocity.y = 0.0
	if _speed > 0.0:
		move_and_slide()


func _setup(next: Act) -> void:
	act = next
	_play_act_anim(ACT_ANIM[int(next)])


## `chase_angle`: step toward `want`; true once it is reached.
func _chase_yaw(want: float, delta: float) -> bool:
	var diff: float = angle_difference(rotation.y, want)
	var step: float = TURN_RATE * delta
	if absf(diff) <= step:
		rotation.y = want
		return true
	rotation.y += signf(diff) * step
	return false


func _yaw_to(target: Vector3) -> float:
	var to: Vector3 = target - global_position
	return atan2(to.x, to.z) if to.x * to.x + to.z * to.z > 0.000001 else rotation.y


## World → room GX (`MuseumDisplay.gx_to_world` inverse).
func _gx(world: Vector3) -> Vector3:
	var origin: Vector3 = _grid.origin if _grid != null else Vector3.ZERO
	return (world - origin) / FieldCatalog.GX_TO_METERS


## --- Presentation ------------------------------------------------------------------------


func _ensure_collision() -> void:
	if get_node_or_null("CollisionShape3D") != null:
		return
	var shape := CollisionShape3D.new()
	var capsule := CylinderShape3D.new()
	## `aNPC` pipe collision: radius ~18 GX, height ~40 GX.
	capsule.radius = 18.0 * FieldCatalog.GX_TO_METERS
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(shape)


func _ensure_interact() -> void:
	if get_node_or_null("InteractVolume") != null:
		return
	var volume := Area3D.new()
	volume.name = "InteractVolume"
	volume.collision_layer = 8
	volume.collision_mask = 0
	volume.monitoring = false
	volume.monitorable = true
	volume.set_script(load("res://scenes/world/interact_volume.gd"))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 2.0, 1.6)
	shape.shape = box
	shape.position = Vector3(0.0, 1.0, 0.0)
	volume.add_child(shape)
	add_child(volume)


func _ensure_visual() -> void:
	if get_node_or_null("Model") != null:
		return
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var vis: Node3D = GeneratedVisual.attach_villager(_model, PoliceDisplay.BOOKER_SPECIES)
	if vis == null:
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.35
		capsule.height = 1.4
		mesh.mesh = capsule
		mesh.position.y = 0.9
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.45, 0.7)
		mesh.material_override = mat
		_model.add_child(mesh)
		return
	_body_anim = VisualAnimation.find_animation_player(vis)
	_face.bind(vis, PoliceDisplay.BOOKER_SPECIES)


func _play_act_anim(suffix: String) -> void:
	if _body_anim == null:
		return
	var clip := _resolve_clip(suffix)
	if clip.is_empty():
		return
	if clip == _clip and _body_anim.is_playing():
		return
	_clip = clip
	var animation: Animation = _body_anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR
	_body_anim.speed_scale = 1.0
	_body_anim.play(clip, 0.12)


func _resolve_clip(suffix: String) -> String:
	if _body_anim == null or suffix.is_empty():
		return ""
	if _body_anim.has_animation(suffix):
		return suffix
	for anim_name: String in _body_anim.get_animation_list():
		if anim_name.ends_with(suffix) or suffix in anim_name:
			return anim_name
	return ""
