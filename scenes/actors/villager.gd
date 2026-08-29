class_name Villager
extends CharacterBody3D

## One shared villager actor. Looks, schedule, and lines come from VillagerData.
## Spatial: Model, Collision, NavigationAgent3D, InteractionArea, Animation.
## Behavior: VillagerSchedule + VillagerAI (reusable actions) + VillagerMotor.

const IDLE_SPEED := 0.08

@export var data: VillagerData

var state: VillagerState
var schedule: VillagerSchedule = VillagerSchedule.new()
var ai: VillagerAI = VillagerAI.new()
var _motor: VillagerMotor = VillagerMotor.new()
var _placeholder_bob: float = 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _layer_present: int = 4

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
	_apply_presence(VillagerActivity.is_present(first))
	_sync_from_clock()
	GeneratedVisual.attach_villager(self, data.species if data else &"")


func _exit_tree() -> void:
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
	ai.sync(current_activity(), _hints())
	if not ai.is_talkable():
		return []
	var who: String = data.display_name if data else "Villager"
	return [Interaction.of(Interaction.TALK, "Talk to %s" % who, 20)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK:
		return false
	ai.sync(current_activity(), _hints())
	if not ai.is_talkable():
		return false
	_ensure_bound()
	if ctx != null and ctx.actor != null:
		_face_towards(ctx.actor.global_position)
	var line: String = VillagerTalk.greeting(data, state)
	if state != null:
		state.record_talk(VillagerTalk.day_key())
	var who: String = data.display_name if data else "Villager"
	Game.post_notice("%s: %s" % [who, line])
	return true


func _physics_process(delta: float) -> void:
	ai.sync(current_activity(), _hints())
	var present: bool = ai.is_present()
	_apply_presence(present)
	if not present:
		velocity = Vector3.ZERO
		ai.step(delta)
		return
	var on_bg: bool = _snap_to_bg()
	if on_bg:
		velocity.y = 0.0
		motion_mode = MOTION_MODE_FLOATING
	elif not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	_steer_ai()
	var next: Vector3 = _next_point()
	var planar: Vector3 = _motor.tick(delta, global_position, next, ai.wants_move())
	ai.consider_arrive(global_position)
	velocity.x = planar.x
	velocity.z = planar.z
	if _model != null:
		_model.rotation.y = _motor.facing
	var before: Vector3 = global_position
	move_and_slide()
	var bg: Array = _bg()
	if bg.size() == 2:
		global_position = FieldCollision.revise_xz(
			bg[0] as WorldData, bg[1] as WorldGrid, before, global_position
		)
	elif on_bg:
		_snap_to_bg()
	_update_placeholder_anim(delta, planar)
	ai.step(delta)


func _ensure_bound() -> void:
	var table: ScheduleData = data.schedule_table() if data != null else null
	if schedule.table != table:
		schedule.bind(table)
	if data != null:
		_motor.configure(data.personality)
		state = Game.villagers.get_or_create(data.id)
	elif state == null:
		state = VillagerState.new()


func _sync_from_clock() -> void:
	ai.sync(current_activity(), _hints())
	_apply_presence(ai.is_present())


func _on_action_changed(kind: StringName) -> void:
	if kind == ActivityKind.LEAVE_HOME:
		global_position = _motor.home
		_motor.reset(_motor.home, _motor.facing)


func _apply_presence(present: bool) -> void:
	visible = present
	collision_layer = _layer_present if present else 0
	if _collision != null:
		_collision.disabled = not present
	if _volume != null:
		_volume.monitorable = present
	if _agent != null:
		_agent.avoidance_enabled = false


func _steer_ai() -> void:
	if ai.is_wandering():
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
	var dest: Vector3 = _walkable_near(_motor.home + _motor.random_offset())
	_motor.set_target(dest)
	if _agent != null and _nav_ready():
		_agent.target_position = dest


func _steer_to(world_pos: Vector3) -> void:
	var dest: Vector3 = _walkable_near(world_pos)
	if not _motor.has_target or _motor.target.distance_to(dest) > 0.35:
		_motor.set_target(dest)
	if _agent != null and _nav_ready():
		_agent.target_position = dest


func _next_point() -> Vector3:
	if _agent != null and _nav_ready() and _motor.has_target:
		if not _agent.is_navigation_finished():
			return _agent.get_next_path_position()
	return _motor.target


func _nav_ready() -> bool:
	if _agent == null or not is_inside_tree():
		return false
	var map: RID = _agent.get_navigation_map()
	return NavigationServer3D.map_get_iteration_id(map) > 0


func _walkable_near(world_pos: Vector3) -> Vector3:
	var bg: Array = _bg()
	if bg.size() != 2:
		return world_pos
	var grid: WorldGrid = bg[1] as WorldGrid
	var cell: Vector2i = grid.world_to_cell(world_pos)
	if grid.is_walkable(cell):
		var pos: Vector3 = grid.cell_to_world(cell)
		pos.y = world_pos.y
		return pos
	return _motor.home


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
	var field_actions: Array[StringName] = []
	if data != null:
		field_actions = data.field_activity_ids()
	return {
		"home": _motor.home,
		"shop": _building_stand(&"acre_shop"),
		"water": _water_stand(),
		"sit": _furniture_stand(),
		"shop_open": Clock.in_hour_window(9, 22),
		"field_actions": field_actions,
		"outdoors": visible and not ActivityKind.hides_actor(ai.kind()),
	}


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
