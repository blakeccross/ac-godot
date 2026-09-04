class_name Villager
extends CharacterBody3D

## One shared villager actor. Looks, schedule, and lines come from VillagerData.
## Spatial: Model, Collision, NavigationAgent3D, InteractionArea, Animation.
## Behavior: VillagerSchedule + VillagerAI + VillagerWalk (goal acres) + VillagerMotor.

const IDLE_SPEED := 0.08
## Fraction of intended XZ step that must stick after BG revise; else front-wall.
## Absolute meters-per-frame thresholds break at 60 Hz (walk ≈ 0.025 m/tick).
const STUCK_FRAC := 0.35
const ANIM_WAIT := "npc_1_wait1"
const ANIM_WALK := "npc_1_walk1"
const ANIM_RUN := "npc_1_run1"
const ANIM_SIT := "npc_1_sit1"
const ANIM_FISH := "npc_1_fish1"

@export var data: VillagerData
## Indoor `ac_npc2` stand-in: always visible while the player is in this house.
@export var indoor_resident: bool = false

var state: VillagerState
var schedule: VillagerSchedule = VillagerSchedule.new()
var ai: VillagerAI = VillagerAI.new()
var _motor: VillagerMotor = VillagerMotor.new()
var _placeholder_bob: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _layer_present: int = 4
var _body_anim: AnimationPlayer
var _clip: String = ""
var _goal_stand: Vector3 = Vector3.ZERO
var _goal_block: Vector2i = Vector2i.ZERO
var _goal_kind: StringName = VillagerWalk.GOAL_MY_HOME
var _stay_elapsed: float = 0.0
## After an avoid hop, wait before re-steering (decomp spends frames in ACT_TURN).
var _avoid_cool: float = 0.0
var _talk_look: Vector3 = Vector3.ZERO
var _face: NpcFace = NpcFace.new()
var _head_look: NpcHeadLook = NpcHeadLook.new()
var _face_mood: int = -1
var _visual: Node3D

@onready var _model: Node3D = $Model
@onready var _placeholder: MeshInstance3D = $Model/PlaceholderMesh
@onready var _collision: CollisionShape3D = $Collision
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _volume: Area3D = $InteractionArea
@onready var _anim: AnimationPlayer = $Animation


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("villagers")
	_layer_present = collision_layer
	_ensure_bound()
	_tint_placeholder()
	Clock.time_changed.connect(_sync_from_clock)
	ai.action_changed.connect(_on_action_changed)
	_motor.reset(global_position, rotation.y)
	var table: ScheduleData = data.schedule_table() if data != null else null
	var first: StringName = table.activity_now() if table != null else VillagerActivity.FIELD
	if not indoor_resident and state != null:
		## Start home when the looks table is IN_HOUSE / SLEEP (`Animal_c.is_home`).
		if first == VillagerActivity.IN_HOUSE or first == VillagerActivity.SLEEP:
			state.is_home = true
	_apply_presence(indoor_resident or VillagerActivity.is_present(first))
	var vis: Node3D = GeneratedVisual.attach_villager(_model, data.species if data else &"")
	_visual = vis
	if vis != null:
		_body_anim = GeneratedVisual.find_animation_player(vis)
		_play_clip(ANIM_WAIT, true)
		_face.bind(vis, data.species if data else &"")
		_head_look.bind(vis, self)
		_sync_face_mood(true)
	if indoor_resident:
		_motor.facing = rotation.y
	else:
		_sync_from_clock()


func _sync_from_clock() -> void:
	if indoor_resident:
		return
	ai.sync(current_activity(), _hints())
	_apply_presence(ai.is_present())


func _exit_tree() -> void:
	if data != null:
		VillagerWalk.release(data.id)
	_unbind_talk()
	if Clock.time_changed.is_connected(_sync_from_clock):
		Clock.time_changed.disconnect(_sync_from_clock)
	if ai.action_changed.is_connected(_on_action_changed):
		ai.action_changed.disconnect(_on_action_changed)


func current_activity() -> StringName:
	_ensure_bound()
	return schedule.tick(Clock.now_sec())


func current_action() -> StringName:
	_ensure_bound()
	ai.sync(current_activity(), _hints())
	return ai.kind()


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if indoor_resident:
		var who: String = data.display_name if data else "Villager"
		return [Interaction.of(Interaction.TALK, "Talk to %s" % who, 20)]
	ai.sync(current_activity(), _hints())
	if not ai.is_talkable():
		return []
	var who_out: String = data.display_name if data else "Villager"
	return [Interaction.of(Interaction.TALK, "Talk to %s" % who_out, 20)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK:
		return false
	if not indoor_resident:
		ai.sync(current_activity(), _hints())
		if not ai.is_talkable():
			return false
	_ensure_bound()
	if ctx != null and ctx.actor != null:
		_talk_look = ctx.actor.global_position
	else:
		_talk_look = global_position
	var talk_ctx: DialogueContext = DialogueContext.from_game(data, state)
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui") if get_tree() != null else null
	if ui != null and ui.has_method("play"):
		if ui.has_method("is_open") and bool(ui.call("is_open")) and ui.has_method("close"):
			ui.call("close")
		ai.begin_talk()
		_bind_talk_end(ui)
		## Decomp `Camera2_request_main_talk(play, player, npc)` — speaker = player.
		var player: Node3D = ctx.actor as Node3D if ctx != null else null
		if player != null:
			TalkCamera.begin(player, self, get_tree())
		ui.call("play", VillagerTalk.conversation(data, state), talk_ctx, state)
	else:
		_face_towards(_talk_look)
		var line: String = VillagerTalk.greeting(data, state)
		var who: String = data.display_name if data else "Villager"
		Game.post_notice("%s: %s" % [who, line])
	if state != null:
		state.record_talk(VillagerTalk.day_key())
	return true


func _physics_process(delta: float) -> void:
	if indoor_resident:
		_tick_indoor(delta)
		return
	ai.sync(current_activity(), _hints())
	var present: bool = ai.is_present()
	_apply_presence(present)
	_tick_face(delta)
	_tick_head_look(delta)
	if not present:
		velocity = Vector3.ZERO
		ai.step(delta)
		_update_animation(delta, Vector3.ZERO)
		return
	if ai.is_talking():
		_hold_talk(delta)
		return
	var on_bg: bool = _snap_to_bg()
	if on_bg:
		velocity.y = 0.0
		motion_mode = MOTION_MODE_FLOATING
	elif not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	if ai.is_wandering():
		_tick_walk_slot(delta)
	_steer_ai()
	var aim: Vector3 = _motor.steer if _motor.has_target else global_position
	var planar: Vector3 = _motor.tick(delta, global_position, aim, ai.wants_move())
	ai.consider_arrive(global_position)
	velocity.x = planar.x
	velocity.z = planar.z
	if _model != null:
		_model.rotation.y = _motor.facing
	var before: Vector3 = global_position
	## Decomp order: position_move → BGcheck → circleRangeRevice → forward/obj → think avoid.
	move_and_slide()
	var bg: Array = _bg()
	if bg.size() == 2:
		global_position = FieldCollision.revise_xz(
			bg[0] as WorldData, bg[1] as WorldGrid, before, global_position
		)
		if ai.is_wandering() and _in_goal_block():
			global_position = VillagerWalk.circle_revise(
				bg[0] as WorldData, _goal_block, global_position
			)
	elif on_bg:
		_snap_to_bg()
	if _avoid_cool > 0.0:
		_avoid_cool = maxf(0.0, _avoid_cool - delta)
	## Avoid only while moving (`speed != 0` in decomp interrupt).
	if planar.length() > IDLE_SPEED:
		_avoid_if_wall(before, planar, delta)
	_update_animation(delta, Vector3(velocity.x, 0.0, velocity.z))
	ai.step(delta)


func _tick_indoor(delta: float) -> void:
	## Indoor resident: always present, stand, head-look, talkable (`ac_npc2` wander wait).
	_apply_presence(true)
	_tick_face(delta)
	_tick_head_look(delta)
	if ai.is_talking():
		_hold_talk(delta)
		return
	velocity = Vector3.ZERO
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()
	_update_animation(delta, Vector3.ZERO)


func _tick_head_look(delta: float) -> void:
	if get_tree() == null:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	var sleepy: bool = (
		state != null and int(state.mood) == int(VillagerState.Mood.SLEEPY)
	) or ai.kind() == ActivityKind.SLEEP
	_head_look.locked = ai.is_talking()
	_head_look.tick(
		delta,
		player as Node3D if player is Node3D else null,
		_motor.facing,
		sleepy
	)


func _ensure_bound() -> void:
	var table: ScheduleData = data.schedule_table() if data != null else null
	if schedule.table != table:
		schedule.bind(table)
	if data != null:
		_motor.configure(data.personality)
		state = Game.villagers.get_or_create(data.id)
	elif state == null:
		state = VillagerState.new()


func _on_action_changed(kind: StringName) -> void:
	if kind == ActivityKind.LEAVE_HOME:
		_set_is_home(false)
		if not visible:
			global_position = _motor.home + ActivityKind.YARD_OFFSET
			_motor.reset(global_position, _motor.facing)
	if kind == ActivityKind.TALK:
		_motor.arrive()
	if kind == ActivityKind.WANDER:
		_motor.arrive()
		_stay_elapsed = 0.0
	if kind == ActivityKind.WAKE or kind == ActivityKind.SLEEP:
		_set_is_home(true)
		if kind == ActivityKind.SLEEP and state != null:
			state.mood = VillagerState.Mood.SLEEPY
	if (
		kind == ActivityKind.GO_HOME
		or kind == ActivityKind.SLEEP
		or kind == ActivityKind.WAKE
	) and data != null:
		VillagerWalk.release(data.id)


func _set_is_home(value: bool) -> void:
	_ensure_bound()
	if state != null:
		state.is_home = value


func _apply_presence(present: bool) -> void:
	visible = present
	collision_layer = _layer_present if present else 0
	if _collision != null:
		_collision.disabled = not present
	if _volume != null:
		_volume.monitorable = present
	if _agent != null:
		_agent.avoidance_enabled = false
	if not present and data != null:
		VillagerWalk.release(data.id)


func _steer_ai() -> void:
	if ai.is_wandering():
		if not _in_goal_block():
			_steer_to(_goal_stand)
			return
		_steer_wander(true)
		return
	if ai.wants_move():
		_steer_to(ai.destination())
		return
	_steer_wander(false)


func _steer_wander(wandering: bool) -> void:
	if not wandering:
		if _agent != null and _nav_ready():
			_agent.target_position = global_position
		return
	if not _motor.needs_new_target():
		return
	var act: StringName = VillagerWalk.pick_act(_looks())
	if act == VillagerWalk.ACT_WAIT:
		_motor.wait_in_place()
		return
	var dest: Vector3 = _roam_point()
	var delta: Vector3 = dest - global_position
	delta.y = 0.0
	if delta.length() < VillagerWalk.MIN_STEP:
		_motor.wait_in_place()
		return
	_avoid_cool = 0.0
	_motor.set_target(dest, act, VillagerWalk.WANDER_ARRIVE, global_position, _motor.facing)
	if _agent != null and _nav_ready():
		_agent.target_position = dest


func _steer_to(world_pos: Vector3) -> void:
	if _motor.wait_left > 0.0:
		return
	var dest: Vector3 = _walkable_near(world_pos)
	if _motor.has_target:
		var to_goal: float = _motor.target.distance_to(dest)
		var to_here: Vector3 = _motor.target - global_position
		to_here.y = 0.0
		if to_goal > 0.35 and to_here.length() > VillagerWalk.WANDER_ARRIVE:
			return
	_avoid_cool = 0.0
	_motor.set_target(
		dest, VillagerWalk.ACT_WALK, VillagerMotor.ARRIVE, global_position, _motor.facing
	)
	if _agent != null and _nav_ready():
		_agent.target_position = dest


func _nav_ready() -> bool:
	if _agent == null or not is_inside_tree():
		return false
	var map: RID = _agent.get_navigation_map()
	return NavigationServer3D.map_get_iteration_id(map) > 0


func _walkable_near(world_pos: Vector3) -> Vector3:
	var bg: Array = _bg()
	if bg.size() != 2:
		return world_pos
	var pos: Vector3 = VillagerWalk.snap_standable(bg[0] as WorldData, world_pos)
	pos.y = world_pos.y
	return pos


func _avoid_if_wall(before: Vector3, planar: Vector3, delta: float) -> void:
	## `aNPC_avoid_obstacle` while speed ≠ 0 and front wall flag set.
	if not _motor.has_target:
		return
	if _avoid_cool > 0.0:
		return
	if not _front_wall_hit(before, planar, delta):
		return
	_steer_around_wall()


func _front_wall_hit(before: Vector3, planar: Vector3, delta: float) -> bool:
	## Analog of `collision_flag` after BG + `aNPC_forward_check`.
	var intended := Vector3(sin(_motor.facing), 0.0, cos(_motor.facing))
	var speed_xz := Vector2(planar.x, planar.z).length()
	if speed_xz > IDLE_SPEED and delta > 0.0:
		var moved: Vector3 = global_position - before
		moved.y = 0.0
		var expected: float = speed_xz * delta
		if moved.dot(intended) < expected * STUCK_FRAC:
			return true
	if get_slide_collision_count() > 0 and _slide_is_front(planar):
		return true
	## `aNPC_forward_check_sub` out of move-range returns a wall hit.
	if ai.is_wandering() and _in_goal_block() and speed_xz > IDLE_SPEED:
		var bg: Array = _bg()
		if bg.size() == 2:
			var probe: Vector3 = before + intended * 1.0
			if not VillagerWalk.in_move_range(bg[0] as WorldData, _goal_block, probe):
				return true
			if _forward_height_wall(bg[0] as WorldData, bg[1] as WorldGrid, before, probe):
				return true
	return false


func _forward_height_wall(
	data: WorldData, grid: WorldGrid, from: Vector3, ahead: Vector3
) -> bool:
	## Forward probe: |Δheight| ≥ half-unit (~1 m) counts as a wall (`forward_check`).
	var ya: float = FieldCollision.ground_y_at(data, grid, from)
	var yb: float = FieldCollision.ground_y_at(data, grid, ahead)
	if not FieldCollision.has_floor(ya):
		return false
	if not FieldCollision.has_floor(yb):
		return true
	return absf(ya - yb) >= 1.0


func _slide_is_front(planar: Vector3) -> bool:
	var move_dir := Vector3(sin(_motor.facing), 0.0, cos(_motor.facing))
	if planar.length_squared() > 0.0001:
		move_dir = Vector3(planar.x, 0.0, planar.z).normalized()
	for i: int in get_slide_collision_count():
		var col: KinematicCollision3D = get_slide_collision(i)
		if col == null:
			continue
		var n: Vector3 = col.get_normal()
		n.y = 0.0
		if n.length_squared() < 0.0001:
			continue
		if move_dir.dot(n.normalized()) < -0.15:
			return true
	return false


func _steer_around_wall() -> void:
	## `aNPC_avoid_obstacle`: flag 3 + side 0 → ±112.5; side 1/2 → `aNPC_avoid_wall`.
	## Never drop `dst_pos` — failed hops fall back to 180° (`turn_to_backward`).
	var bg: Array = _bg()
	if bg.size() != 2:
		_motor.pause()
		return
	var world_data: WorldData = bg[0] as WorldData
	var grid: WorldGrid = bg[1] as WorldGrid
	var here: Vector2i = VillagerWalk.block_from_cell(grid.world_to_cell(global_position))
	if not VillagerWalk.is_fg_block(here):
		here = _goal_block
	var around: Vector3 = global_position
	var side: int = _motor.avoid_direction
	## Front+wall with side 0 → `aNPC_turn_to_backward` (ACT_TURN, then walk).
	## Side 1/2 → `aNPC_avoid_wall` n=0 sets avoid while still moving.
	var turn_first: bool = side == 0
	if side == 0:
		var hop: Dictionary = VillagerWalk.first_avoid_hop(
			world_data, global_position, _motor.facing, here, grid
		)
		if hop.is_empty():
			around = VillagerWalk.avoid_backward(global_position, _motor.facing)
			side = 0
		else:
			around = hop["pos"] as Vector3
			side = int(hop.get("side", 0))
	else:
		around = VillagerWalk.avoid_around(
			world_data, global_position, _motor.facing, here, grid, side
		)
	var delta: Vector3 = around - global_position
	delta.y = 0.0
	if delta.length() < 0.05:
		around = VillagerWalk.avoid_backward(global_position, _motor.facing)
		side = 0
		turn_first = true
	_motor.set_avoid(around, side, turn_first)
	## Roughly one turn clip / think beat before another obstacle interrupt.
	_avoid_cool = 0.25


func _roam_point() -> Vector3:
	var bg: Array = _bg()
	if bg.size() == 2:
		return VillagerWalk.wander_in_block(
			bg[0] as WorldData, _goal_block, global_position, null, bg[1] as WorldGrid
		)
	if _goal_stand != Vector3.INF and _goal_stand != Vector3.ZERO:
		return _goal_stand + _motor.random_offset()
	return _motor.home + _motor.random_offset()


func _hold_talk(delta: float) -> void:
	var on_bg: bool = _snap_to_bg()
	if on_bg:
		velocity.y = 0.0
		motion_mode = MOTION_MODE_FLOATING
	elif not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	_refresh_talk_look()
	_motor.turn_toward(delta, global_position, _talk_look)
	if _model != null:
		_model.rotation.y = _motor.facing
	if _agent != null and _nav_ready():
		_agent.target_position = global_position
	move_and_slide()
	if on_bg:
		_snap_to_bg()
	_update_animation(delta, Vector3.ZERO)
	ai.step(delta)


func _tick_face(delta: float) -> void:
	_sync_face_mood(false)
	_face.tick(delta, _dialogue_uttering())


func _sync_face_mood(force: bool) -> void:
	_ensure_bound()
	var mood: int = int(state.mood) if state != null else int(VillagerState.Mood.NORMAL)
	if not force and mood == _face_mood:
		return
	_face_mood = mood
	_face.set_from_mood(mood)


func _dialogue_uttering() -> bool:
	if not ai.is_talking() or get_tree() == null:
		return false
	var ui: Node = get_tree().get_first_node_in_group("dialogue_ui")
	if ui != null and ui.has_method("is_uttering"):
		return bool(ui.call("is_uttering"))
	return false


func _bind_talk_end(ui: Node) -> void:
	if ui == null or not ui.has_signal("closed"):
		return
	if ui.closed.is_connected(_on_talk_closed):
		ui.closed.disconnect(_on_talk_closed)
	ui.closed.connect(_on_talk_closed, CONNECT_ONE_SHOT)


func _unbind_talk() -> void:
	if get_tree() != null:
		var ui: Node = get_tree().get_first_node_in_group("dialogue_ui")
		if ui != null and ui.has_signal("closed") and ui.closed.is_connected(_on_talk_closed):
			ui.closed.disconnect(_on_talk_closed)
	if ai.is_talking():
		TalkCamera.end(get_tree())
		ai.end_talk()


func _on_talk_closed() -> void:
	TalkCamera.end(get_tree())
	ai.end_talk()


func _refresh_talk_look() -> void:
	if get_tree() == null:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player is Node3D:
		_talk_look = (player as Node3D).global_position


func _face_towards(world_pos: Vector3) -> void:
	var to: Vector3 = world_pos - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	_motor.facing = atan2(to.x, to.z)
	if _model != null:
		_model.rotation.y = _motor.facing


func _tint_placeholder() -> void:
	if _placeholder == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = data.placeholder_color() if data else Color(0.85, 0.55, 0.4, 1)
	_placeholder.material_override = mat


func _update_animation(delta: float, planar: Vector3) -> void:
	if _body_anim == null:
		_update_placeholder_anim(delta, planar)
		return
	var moving: bool = planar.length() > IDLE_SPEED
	var want: String = _clip_for(ai.kind(), moving)
	var clip := _resolve_clip(want)
	if clip.is_empty():
		return
	if clip == _clip and _body_anim.is_playing():
		if moving:
			_body_anim.speed_scale = clampf(
				planar.length() / maxf(_motor.speed_now(), 0.4), 0.75, 1.2
			)
		else:
			_body_anim.speed_scale = 1.0
		return
	_play_clip(want, true)


func _clip_for(_kind: StringName, moving: bool) -> String:
	if moving:
		if _motor.gait == VillagerWalk.ACT_RUN:
			return ANIM_RUN
		return ANIM_WALK
	match _kind:
		ActivityKind.SIT:
			return ANIM_SIT
		ActivityKind.FISH:
			return ANIM_FISH
		_:
			return ANIM_WAIT


func _play_clip(suffix: String, loop: bool) -> void:
	var clip := _resolve_clip(suffix)
	if clip.is_empty() or _body_anim == null:
		return
	_clip = clip
	_ensure_loop(clip, loop)
	_body_anim.speed_scale = 1.0
	_body_anim.play(clip, 0.12)


func _resolve_clip(suffix: String) -> String:
	var player: AnimationPlayer = _body_anim
	if player == null:
		player = _anim
	if player == null or suffix.is_empty():
		return ""
	if player.has_animation(suffix):
		return suffix
	for anim_name: String in player.get_animation_list():
		if anim_name.ends_with(suffix) or suffix in anim_name:
			return anim_name
	if suffix == ANIM_SIT or suffix == ANIM_FISH or suffix == ANIM_RUN:
		return _resolve_clip(ANIM_WAIT) if suffix != ANIM_WAIT else ""
	return ""


func _ensure_loop(clip: String, loop: bool) -> void:
	if _body_anim == null or not _body_anim.has_animation(clip):
		return
	var animation: Animation = _body_anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE


func _update_placeholder_anim(delta: float, planar: Vector3) -> void:
	if _anim != null and _anim.get_animation_list().size() > 0:
		return
	if _placeholder == null or not _placeholder.visible:
		return
	var moving: bool = planar.length() > IDLE_SPEED
	_placeholder_bob += delta * (8.0 if moving else 2.0)
	var amp: float = 0.04 if moving else 0.0
	_placeholder.position.y = 0.75 + sin(_placeholder_bob) * amp


func _hints() -> Dictionary:
	if ai.current == null:
		_refresh_goal()
	var field_actions: Array[StringName] = []
	if data != null:
		field_actions = data.field_activity_ids()
	return {
		"home": _motor.home,
		"goal": _goal_stand,
		"shop": _building_stand(&"acre_shop"),
		"water": _water_stand(),
		"sit": _furniture_stand(),
		"shop_open": Clock.in_hour_window(9, 22),
		"field_actions": field_actions,
		"outdoors": visible and not ActivityKind.hides_actor(ai.kind()),
		"is_home": state != null and state.is_home,
	}


func _tick_walk_slot(delta: float) -> void:
	if not _in_goal_block():
		_stay_elapsed = 0.0
		return
	_stay_elapsed += delta
	if _stay_elapsed < ActivityKind.STAY_SECONDS:
		return
	_stay_elapsed = 0.0
	_refresh_goal()


func _in_goal_block() -> bool:
	var bg: Array = _bg()
	if bg.size() != 2:
		return true
	return VillagerWalk.is_in_block(bg[0] as WorldData, _goal_block, global_position)


func _looks() -> VillagerPersonality.Looks:
	if data != null and data.personality != null:
		return data.personality.looks
	return VillagerPersonality.Looks.LAZY


func _refresh_goal() -> void:
	var looks: VillagerPersonality.Looks = _looks()
	var now: int = Clock.now_sec()
	var want_town: bool = VillagerWalk.can_town_walk(looks, now)
	var who: StringName = data.id if data else &""
	var claimed: bool = VillagerWalk.claim(who, want_town, _field_count())
	if not claimed:
		_goal_kind = VillagerWalk.GOAL_MY_HOME
	else:
		_goal_kind = VillagerWalk.pick_kind(looks, now)
	var bg: Array = _bg()
	var world_data: WorldData = bg[0] as WorldData if bg.size() == 2 else null
	var home_block: Vector2i = VillagerWalk.block_from_cell(_home_cell())
	var shrine: Vector2i = VillagerWalk.shrine_block(world_data)
	var homes: Array[Vector2i] = VillagerWalk.house_blocks(world_data)
	var occupied: Array[Vector2i] = _occupied_blocks()
	_goal_block = VillagerWalk.resolve_block(
		_goal_kind, home_block, shrine, homes, occupied
	)
	if world_data != null:
		_goal_stand = VillagerWalk.stand_in_block(world_data, _goal_block)
	else:
		_goal_stand = _motor.home


func _home_cell() -> Vector2i:
	var bg: Array = _bg()
	if bg.size() != 2:
		return Vector2i.ZERO
	return (bg[1] as WorldGrid).world_to_cell(_motor.home)


func _occupied_blocks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if get_tree() == null:
		return out
	for node: Node in get_tree().get_nodes_in_group("villagers"):
		if not (node is Node3D) or not (node as Node3D).visible:
			continue
		var block: Vector2i = VillagerWalk.block_from_cell(_home_cell_of(node as Node3D))
		if not out.has(block):
			out.append(block)
	return out


func _home_cell_of(node: Node3D) -> Vector2i:
	var bg: Array = _bg()
	if bg.size() != 2:
		return Vector2i.ZERO
	return (bg[1] as WorldGrid).world_to_cell(node.global_position)


func _field_count() -> int:
	if get_tree() == null:
		return 1
	var n: int = 0
	for node: Node in get_tree().get_nodes_in_group("villagers"):
		if node is Villager and (node as Villager).visible:
			n += 1
	return maxi(n, 1)


func _building_stand(building_id: StringName) -> Vector3:
	var bg: Array = _bg()
	if bg.size() != 2:
		return Vector3.INF
	var world_data: WorldData = bg[0] as WorldData
	var grid: WorldGrid = bg[1] as WorldGrid
	for b: BuildingPlacement in world_data.buildings:
		if b == null or b.id != building_id:
			continue
		var cell := Vector2i(b.cell.x + b.footprint.x / 2, b.cell.y + b.footprint.y)
		return grid.cell_to_world(cell)
	return Vector3.INF


func _furniture_stand() -> Vector3:
	var bg: Array = _bg()
	if bg.size() != 2:
		return _motor.home
	var world_data: WorldData = bg[0] as WorldData
	var grid: WorldGrid = bg[1] as WorldGrid
	for o: ObjectPlacement in world_data.objects:
		if o != null and o.kind == &"furniture":
			return grid.cell_to_world(o.cell)
	return _motor.home


func _water_stand() -> Vector3:
	var bg: Array = _bg()
	if bg.size() != 2:
		return Vector3.INF
	var world_data: WorldData = bg[0] as WorldData
	var grid: WorldGrid = bg[1] as WorldGrid
	var from: Vector2i = grid.world_to_cell(_motor.home)
	var stand: Vector2i = VillagerPlan.nearest_water_stand(world_data, from)
	if stand == Vector2i(-1, -1):
		return Vector3.INF
	return grid.cell_to_world(stand)


func _bg() -> Array:
	if get_tree() == null:
		return []
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		return []
	var world_data: Variant = world.get("layout")
	var grid: Variant = world.get("grid")
	if not (world_data is WorldData) or not (grid is WorldGrid):
		return []
	return [world_data, grid]


func _snap_to_bg() -> bool:
	var bg: Array = _bg()
	if bg.is_empty():
		return false
	var y: float = FieldCollision.ground_y_at(bg[0] as WorldData, bg[1] as WorldGrid, global_position)
	if not FieldCollision.has_floor(y):
		return false
	floor_snap_length = 0.0
	floor_block_on_wall = false
	global_position.y = y
	return true
