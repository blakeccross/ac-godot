class_name FieldBall
extends Node3D

## The town's ball (`ac_ball`, `ETC_BALL`): one of three (`act_ball_b`, `_d`, `_s`) lies
## somewhere in town and anyone who runs into it kicks it (`aBALL_OBJcheck`) — gently at a
## walk, lofted at a run. It rolls to a stop on the flat, bounces up to three times when it
## lands, glances off walls (`aBALL_BGcheck`), comes to rest in a hole it rolls slowly into,
## and is lost if it lands in water (`NA_SE_27`); a new one turns up somewhere else the next
## time the town loads (`aBALL_Random_pos_set`). Villagers out walking run after it when it
## lies ahead of them (`aNPC_check_ball`). A shovel lifts it out of a hole and an axe knocks
## it away (`aBALL_status_check`). Speeds are GX per 30 fps frame, as in the decomp.
##
## `Game.ball`: `{x, y, z, type}` (metres), empty when a fresh ball is due.

const GROUP := &"field_ball"
const VISUALS: Array[StringName] = [&"act_ball_b", &"act_ball_d", &"act_ball_s"]
## `aBALL_CoInfoData` pipe radius.
const RADIUS_GX := 13.0
const MAX_KICK := 11.0
const GRAVITY := 0.3
const FALL_MAX := -20.0
const ROLL_DECEL := 0.06
const BOUNCES := 3
const BOUNCE_KEEP := 0.7
## `aBALL_calc_axis`: roll angle per frame per unit of speed (s16 → radians).
const ROLL_RATE := 434.81952 * TAU / 65536.0
## `collider` stays the same one for this long (`unk20C`).
const SAME_COLLIDER_FRAMES := 30
## `aNPC_check_ball`: within 200 GX and inside 67.5° of +z of the villager.
const CHASE_GX := 200.0
const CHASE_CONE := deg_to_rad(67.5)
## `aBALL_player_angle_distance_check`.
const TOOL_REACH_GX := 60.0
const TOOL_CONE := PI / 4.0
const SE_KICK := &"25"
const SE_WALL := &"8026"
const SE_DROP := &"43d"
const SE_SPLASH := &"27"
## A lost ball drifts this long before it is gone.
const SINK_SECONDS := 3.0

var type: int = 0
## Horizontal speed (GX / frame), heading (radians, 0 = +z) and vertical speed.
var speed: float = 0.0
var heading: float = 0.0
var vy: float = 0.0
var in_hole: bool = false
var dead: bool = false
var on_ground: bool = true

var _steps := FrameStepper.new(DecompTime.FRAME_HZ, 8.0)
var _bounces: int = BOUNCES
var _collider: Node3D = null
var _collider_left: int = 0
var _last_pos: Dictionary = {}
var _sink: float = 0.0
var _roll: Node3D


static func find(tree: SceneTree) -> FieldBall:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as FieldBall


static func gx() -> float:
	return FieldCatalog.GX_TO_METERS


func _ready() -> void:
	add_to_group(GROUP)
	_roll = Node3D.new()
	_roll.name = "Roll"
	_roll.position.y = RADIUS_GX * gx()
	add_child(_roll)
	## The ball models are centred on their origin; the roll pivot is the centre.
	var visual := Node3D.new()
	visual.name = "Visual"
	_roll.add_child(visual)
	if GeneratedVisual.attach(visual, VISUALS[clampi(type, 0, VISUALS.size() - 1)]) == null:
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = RADIUS_GX * gx()
		sphere.height = sphere.radius * 2.0
		mesh.mesh = sphere
		visual.add_child(mesh)
	_snap_ground()


## `aBALL_actor_dt`: where it is, unless it was lost or is lying in a hole.
func _exit_tree() -> void:
	if Game == null:
		return
	if dead or in_hole:
		Game.ball = {}
	else:
		Game.ball = {"x": global_position.x, "y": global_position.y, "z": global_position.z, "type": type}


func _world() -> World:
	return World.find(get_tree())


func _physics_process(delta: float) -> void:
	_steps.add(delta)
	while _steps.next():
		if not is_inside_tree():
			return
		_frame()


func _frame() -> void:
	if dead:
		_sink += 1.0 / DecompTime.FRAME_HZ
		global_position += Vector3(sin(heading), 0.0, cos(heading)) * 0.3 * gx()
		_roll.position.y = lerpf(RADIUS_GX * gx(), 0.0, clampf(_sink / SINK_SECONDS, 0.0, 1.0))
		if _sink >= SINK_SECONDS:
			queue_free()
		return
	_contacts()
	if in_hole:
		return
	## `aBALL_position_move`: ease to a stop on the ground, fall under gravity.
	if on_ground:
		speed = move_toward(speed, 0.0, ROLL_DECEL)
	vy = move_toward(vy, FALL_MAX, GRAVITY)
	var step := Vector2(sin(heading), cos(heading)) * speed * gx()
	_move_xz(step)
	global_position.y += vy * gx()
	_land()
	if dead:
		return
	_check_hole()
	_spin()
	if Game != null and (speed > 0.0 or not on_ground):
		Game.ball = {"x": global_position.x, "y": global_position.y, "z": global_position.z, "type": type}


## `aBALL_OBJcheck` against the player and the villagers.
func _contacts() -> void:
	var bodies: Array[Node3D] = []
	var player := Player.find(get_tree())
	if player != null:
		bodies.append(player)
	for node: Node in get_tree().get_nodes_in_group("villagers"):
		if node is Node3D:
			bodies.append(node as Node3D)
	var touched: Node3D = null
	for body: Node3D in bodies:
		var prev: Vector3 = _last_pos.get(body.get_instance_id(), body.global_position)
		_last_pos[body.get_instance_id()] = body.global_position
		if touched != null or in_hole:
			continue
		var d := Vector2(global_position.x - body.global_position.x, global_position.z - body.global_position.z)
		var reach: float = RADIUS_GX * gx() + FieldCollision.ACTOR_RADIUS
		if d.length() >= reach or absf(global_position.y - body.global_position.y) > 1.5:
			continue
		touched = body
		## `mQst_CheckSoccerTarget`: the resident who asked for it keeps it there.
		if body != _collider and body.has_method("take_soccer_ball") and bool(body.call("take_soccer_ball")):
			speed = 0.0
			vy = minf(vy, 0.0)
			_collider = body
			_collider_left = SAME_COLLIDER_FRAMES
			continue
		var moved: Vector3 = body.global_position - prev
		var body_vel := Vector2(moved.x, moved.z) / gx()
		if body != _collider:
			kick(d, body_vel)
			_collider = body
		else:
			## Still against the same one: pushed out along the overlap.
			var push: Vector2 = d.normalized() * (reach - d.length()) / gx() + _velocity()
			speed = minf(push.length(), MAX_KICK)
			if push.length() > 0.0001:
				heading = atan2(push.x, push.y)
		_collider_left = SAME_COLLIDER_FRAMES
	if touched == null:
		if _collider_left <= 0:
			_collider = null
		else:
			_collider_left -= 1


func _velocity() -> Vector2:
	return Vector2(sin(heading), cos(heading)) * speed


## A fresh hit from something moving at `body_vel` (GX / frame) on the side `away` points from.
func kick(away: Vector2, body_vel: Vector2) -> void:
	var dir: Vector2 = away.normalized() if away.length() > 0.0001 else Vector2(sin(heading), cos(heading))
	var own: float = _velocity().dot(dir)
	var fact: float = body_vel.length()
	var pushed: Vector2 = body_vel * ((24.0 / 180.0 * fact) * 0.9 + 0.1)
	var hit: float = absf(own + pushed.dot(dir))
	var after: Vector2 = _velocity() + dir * hit
	var power: float = minf(after.length(), MAX_KICK)
	if on_ground and is_zero_approx(speed):
		## A ball at rest is lifted the harder it's hit.
		var f: float = power / MAX_KICK
		var lift: float = deg_to_rad(f * 90.0 + f * 35.0 * (randf() - 0.5))
		speed = cos(lift) * power
		vy = sin(lift) * power
		if vy > 0.0:
			on_ground = false
			_bounces = 0
	else:
		speed = power * 0.75
	if after.length() > 0.0001:
		heading = atan2(after.x, after.y)
	speed *= 0.9
	if speed > 0.0:
		Audio.play_se(SE_KICK, self)


## Walls and the field's edge (`aBALL_BGcheck`): glance off what it runs into.
func _move_xz(step: Vector2) -> void:
	if step.length() < 0.000001:
		return
	var world := _world()
	var from: Vector3 = global_position
	var to := Vector3(from.x + step.x, from.y, from.z + step.y)
	if world == null or world.layout == null or world.grid == null:
		global_position = to
		return
	var revised: Vector3 = FieldCollision.revise_xz(world.layout, world.grid, from, to, RADIUS_GX * gx())
	var lost := Vector2(to.x - revised.x, to.z - revised.z)
	global_position = Vector3(revised.x, from.y, revised.z)
	if lost.length() > 0.0001:
		_bounce_wall(-lost.normalized())


func _bounce_wall(normal: Vector2) -> void:
	var v: Vector2 = _velocity()
	var into: float = -v.dot(normal)
	if into <= 0.0:
		return
	if into > 1.0:
		Audio.play_se(SE_WALL, self)
	var f: float = into * 0.07 + 1.2
	v += normal * into * f
	speed = v.length()
	if speed > 0.0001:
		heading = atan2(v.x, v.y)


## On the ground, off a ledge, or landing (up to three bounces at 0.7).
func _land() -> void:
	var world := _world()
	if world == null or world.layout == null or world.grid == null:
		return
	var ground: float = FieldCollision.ground_y_at(world.layout, world.grid, global_position)
	if not FieldCollision.has_floor(ground):
		return
	if global_position.y > ground + 0.001:
		if on_ground and global_position.y - ground > 20.0 * gx():
			Audio.play_se(SE_DROP, self)
		if on_ground:
			_bounces = 0
		on_ground = false
	else:
		global_position.y = ground
		if not on_ground and vy < 0.0 and _bounces < BOUNCES:
			_bounces += 1
			vy = BOUNCE_KEEP * -vy
			on_ground = vy <= 0.5
		else:
			vy = 0.0
			on_ground = true
	if _in_water():
		_lose()


func _in_water() -> bool:
	var world := _world()
	if world == null or world.grid == null:
		return false
	var attr: int = FieldCollision.unit_attr_at(world.layout, world.grid, global_position)
	return attr >= 0 and FieldCatalog.is_water_attr(attr)


## `aBALL_status_check`: a splash, and this ball is gone.
func _lose() -> void:
	dead = true
	Audio.play_se(SE_SPLASH, self)
	speed = minf(speed, 1.0)


## `aBALL_process_ground` over an open hole: once slow it settles in.
func _check_hole() -> void:
	var world := _world()
	if world == null or world.grid == null or not on_ground or speed >= 1.0:
		return
	var cell: Vector2i = world.grid.world_to_cell(global_position)
	if not Game.is_hole(world.grid.occupant_at(cell)):
		return
	var centre: Vector3 = world.grid.cell_to_world(cell)
	global_position = Vector3(centre.x, global_position.y, centre.z)
	in_hole = true
	speed = 0.0
	vy = 0.0
	_roll.position.y = RADIUS_GX * gx() * 0.2


func _spin() -> void:
	if speed <= 0.0001:
		return
	var axis := Vector3(cos(heading), 0.0, -sin(heading))
	_roll.rotate(axis, speed * ROLL_RATE)


func _snap_ground() -> void:
	var world := _world()
	if world == null or world.layout == null or world.grid == null:
		return
	var y: float = FieldCollision.ground_y_at(world.layout, world.grid, global_position)
	if FieldCollision.has_floor(y):
		global_position.y = y


## `aBALL_player_angle_distance_check`: within 60 GX and 45° of the player's facing.
func in_front_of(pos: Vector3, yaw: float) -> bool:
	var to := Vector2(global_position.x - pos.x, global_position.z - pos.z)
	if to.length() >= TOOL_REACH_GX * gx():
		return false
	return absf(angle_difference(yaw, atan2(to.x, to.y))) < TOOL_CONE


## `aBALL_STATE_PLAYER_HIT_SCOOP`: lifted out of a hole or flicked ahead.
func hit_by_shovel(pos: Vector3, yaw: float) -> bool:
	if dead or not (in_front_of(pos, yaw) or is_zero_approx(speed)):
		return false
	heading = yaw
	speed = 2.0
	vy = 4.5
	Audio.play_se(SE_KICK, self)
	on_ground = false
	_bounces = 0
	if in_hole:
		in_hole = false
		_roll.position.y = RADIUS_GX * gx()
	return true


## `aBALL_STATE_PLAYER_HIT_AXE`: knocked off to the side.
func hit_by_axe(pos: Vector3, yaw: float) -> bool:
	if dead or in_hole or not (in_front_of(pos, yaw) or is_zero_approx(speed)):
		return false
	heading = yaw + PI / 4.0
	speed = 4.5
	vy = 3.0
	Audio.play_se(SE_KICK, self)
	on_ground = false
	_bounces = 0
	return true


## `aNPC_check_ball`: lying within 200 GX of a villager, inside 67.5° of +z from it.
static func chase_from(npc_pos: Vector3, ball_pos: Vector3) -> bool:
	var to := Vector2(ball_pos.x - npc_pos.x, ball_pos.z - npc_pos.z)
	if to.length() >= CHASE_GX * gx():
		return false
	return absf(atan2(to.x, to.y)) < CHASE_CONE


func chaseable() -> bool:
	return not dead and not in_hole
