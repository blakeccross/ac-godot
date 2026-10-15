class_name Snowball
extends AnimatableBody3D

## A snowman-season snowball (`ac_snowman`). It rolls in m/s on `delta` (the decomp's figures
## are GX per 30 fps frame, noted beside each constant), grows on snow and shrinks off it
## (`SnowmanRules.roll`). Walk into a small one to nudge it; lean on one past a fifth of full
## size for a quarter second and the player starts pushing (`aSMAN_Player_push_Request`,
## `ply_1_push_yuki1`), the ball leading and the player kept behind it. It breaks when it
## hits a wall hard, drops off a cliff or is shoved into a wall for two seconds, and sinks in
## water. Roll the body ball and the head ball into each other while you are in their acre
## and the faster one jumps on top: a snowman (`SnowmanUse.build`).

const GROUP := &"snowball"
const VISUAL := &"act_darumaB"
## `GeneratedVisual` already draws actors at the usual 0.01 (`VisualFit.fit_actor`), so the
## ball's own scale is relative to that.
const VISUAL_PER_SCALE := 100.0
## One GX per 30 fps frame (`ac_snowman`'s speed unit), in m/s.
const FRAME := SnowmanRules.GX * 30.0
## Leaning on it this long (16 ticks) asks to push.
const PUSH_REQUEST_TIME := 16.0 / 60.0
const PUSH_CONE := deg_to_rad(55.0)
## Shoved into a wall this long (120 ticks) and it gives way.
const WALL_PUSH_TIME := 2.0
## Hitting a wall faster than 5 GX a frame breaks it.
const BREAK_WALL_SPEED := 5.0 * FRAME
const BREAK_DROP_GX := 55.0
## The head's jump onto the body (60 ticks).
const COMBINE_TIME := 1.0
## Pushing only starts while it rolls under 3 GX a frame.
const PUSH_START_MAX := 3.0 * FRAME
## `aSMAN_set_speed_relations_norm`: brakes `0.1 − 0.05·n` GX a frame per tick.
const BRAKE := 0.1 * 60.0 * FRAME
const BRAKE_PER_SIZE := 0.05 * 60.0 * FRAME
## A small ball under the player gains `0.16 − 0.14·n` GX a frame per tick of contact.
const NUDGE := 0.16 * 60.0 * FRAME
const NUDGE_PER_SIZE := 0.14 * 60.0 * FRAME
## The push speed eases 0.1 GX a frame per tick toward the stick's.
const PUSH_EASE := 0.1 * 60.0 * FRAME
## `move_dist` gains the speed in GX a frame every tick: per metre rolled, that's 2 / GX.
const GROWTH_PER_METRE := 2.0 / SnowmanRules.GX
## `aSMAN_process_swim`: 0.995× a tick and 0.002 m a tick down.
const SINK_SHRINK_RATE := 0.30075
const SINK_SPEED := 0.12
## The head straightens 0.2 of the way a tick as it jumps.
const ROTATION_SETTLE_HALF_LIFE := 0.0518
## Slack on the 0.9 m player body for "touching".
const CONTACT_SLACK := 0.12
const SE_COMBINE := &"104"
const SE_FALL := &"43d"
const SE_SPLASH := &"27"

@export var part: int = SnowmanRules.PART_BODY
var move_dist: float = 0.0
## Rolling velocity in m/s (x, z).
var vel := Vector2.ZERO
var broken: bool = false
## Taken away with the season: nothing to remember.
var discard: bool = false
var combining: bool = false

var _lean_time: float = 0.0
var _wall_time: float = 0.0
var _pushing: bool = false
var _push_speed: float = 0.0
var _sinking: bool = false
var _pivot: Node3D
var _shape: SphereShape3D
var _col: CollisionShape3D
var _grid: WorldGrid
var _combine: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)
	_pivot = $Roll
	var col := $CollisionShape3D as CollisionShape3D
	## Each ball resizes on its own, so it gets its own shape.
	_shape = (col.shape as SphereShape3D).duplicate() as SphereShape3D
	col.shape = _shape
	_col = col
	GeneratedVisual.attach($Roll/Visual as Node3D, VISUAL)
	var world := _world()
	_grid = world.grid if world != null else null
	_apply_size()
	_snap_ground()


## Leaving the field whole: remember where it is and how big (`mEv` common area).
func _exit_tree() -> void:
	if broken or combining or _sinking or discard:
		return
	var state: Dictionary = save_state()
	if not state.is_empty():
		Game.town.snowballs[part] = state


func normalized() -> float:
	return SnowmanRules.normalized(move_dist)


func radius() -> float:
	return SnowmanRules.radius_m(normalized())


func speed() -> float:
	return vel.length()


func _apply_size() -> void:
	var s: float = SnowmanRules.actor_scale(normalized()) * VISUAL_PER_SCALE
	if _pivot != null:
		_pivot.scale = Vector3.ONE * s
	if _shape != null:
		_shape.radius = radius()
	if _col != null:
		_col.position.y = radius()


func _world() -> World:
	return World.find(get_tree())


func _player() -> Player:
	return Player.find(get_tree())


func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if broken or not is_inside_tree():
		return
	if not _combine.is_empty():
		_combine_step(delta)
	elif _sinking:
		_sink_step(delta)
	elif not _pushing:
		_roll_free(delta)


## ------------------------------------------------------------------ free rolling

func _roll_free(delta: float) -> void:
	var player := _player()
	if player != null and not player.is_busy():
		_touch_player(player, delta)
		if _pushing:
			return
	## `aSMAN_set_speed_relations_norm` on flat ground: ease to a stop, speed averaged over
	## the step.
	var was: float = speed()
	var sp: float = move_toward(was, 0.0, (BRAKE - normalized() * BRAKE_PER_SIZE) * delta)
	var dir: Vector2 = vel.normalized() if was > 0.0001 else Vector2.ZERO
	vel = dir * sp
	if was > 0.0:
		_move(dir * (was + sp) * 0.5, delta)
	if broken:
		return
	_touch_balls()


## `aSMAN_OBJcheck` (the player nudges the ball) and `aSMAN_Player_push_Request`. The player
## body (0.9 m) stops at the ball, so contact is that gap and intent is the stick.
func _touch_player(player: Player, delta: float) -> void:
	var to := Vector2(global_position.x - player.global_position.x, global_position.z - player.global_position.z)
	var dist: float = to.length()
	var want := Vector2(player.move_intent.x, player.move_intent.z)
	var n: float = normalized()
	var touching: bool = dist < radius() + FieldCollision.ACTOR_RADIUS + CONTACT_SLACK
	var leaning: bool = touching and want.length() > 0.05 and absf(angle_difference(atan2(want.x, want.y), atan2(to.x, to.y))) < PUSH_CONE
	if not leaning:
		_lean_time = 0.0
		return
	if n <= SnowmanRules.PUSH_MIN:
		## Too small to push: contact knocks it along.
		vel += want.normalized() * (NUDGE - n * NUDGE_PER_SIZE) * delta
		return
	_lean_time = minf(_lean_time + delta, PUSH_REQUEST_TIME)
	if _lean_time >= PUSH_REQUEST_TIME - 0.0001 and speed() < PUSH_START_MAX and player.snowball.begin_snowball_push(self):
		_pushing = true
		_wall_time = 0.0
		## `aSMAN_process_player_push_init`: start near the player's pace.
		var walk: float = want.length() * PlayerLocomotion.ORIG_WALK
		_push_speed = (1.0 - n) * (3.0 - n * 1.5) * (walk / 7.5) * 1.15 * FRAME


## Ball against ball: combine, or a shove (`aSMAN_snowman_hit_check`).
func _touch_balls() -> void:
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if node == self or not is_instance_valid(node) or node.get("broken") or node.get("combining"):
			continue
		var other := node as Node3D
		var d := Vector2(global_position.x - other.global_position.x, global_position.z - other.global_position.z)
		var reach: float = radius() + float(other.call("radius"))
		if d.length() >= reach:
			continue
		if SnowmanUse.try_combine(self, other):
			return
		## No combine: the faster one hands some of its roll on.
		var ov: Vector2 = other.get("vel")
		if ov.length() > speed():
			vel += ov * (1.0 - normalized()) * 0.4
		var push: Vector2 = d.normalized() * (reach - d.length())
		_move_by(push)


## `delta` seconds of motion at `v` (m/s): walls, cliffs, water, size.
func _move(v: Vector2, delta: float) -> void:
	var step: Vector2 = v * delta
	_move_by(step)
	if broken or _sinking:
		return
	move_dist = SnowmanRules.roll(move_dist, step.length() * GROWTH_PER_METRE, _on_snow())
	_apply_size()
	_spin(step)


func _move_by(step: Vector2) -> void:
	var world := _world()
	var from: Vector3 = global_position
	var to := Vector3(from.x + step.x, from.y, from.z + step.y)
	if world != null and world.layout != null and world.grid != null:
		var revised: Vector3 = FieldCollision.revise_xz(world.layout, world.grid, from, to, radius())
		var blocked: float = Vector2(to.x - revised.x, to.z - revised.z).length()
		if blocked > 0.0001 or _hits_body(revised):
			if _hits_body(revised):
				revised = from
			_hit_wall(step, Vector2(revised.x - from.x, revised.z - from.z))
		to = revised
	global_position = Vector3(to.x, global_position.y, to.z)
	var before_y: float = from.y
	_snap_ground()
	if before_y - global_position.y >= BREAK_DROP_GX * SnowmanRules.GX:
		Audio.play_se(SE_FALL, self)
		smash()
		return
	if _in_water():
		_start_sink()


## `aSMAN_BGcheck` wall response: a hard knock breaks it, otherwise it glances off.
func _hit_wall(step: Vector2, moved: Vector2) -> void:
	if step.length() < 0.00001:
		return
	var lost: Vector2 = step - moved
	var normal: Vector2 = -lost.normalized() if lost.length() > 0.00001 else -step.normalized()
	var into: float = -vel.dot(normal)
	if into > BREAK_WALL_SPEED:
		smash()
		return
	if into > 0.0:
		vel += normal * into * 1.7
		vel *= 0.7


func _hits_body(at: Vector3) -> bool:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return false
	var probe := SphereShape3D.new()
	probe.radius = radius() * 0.9
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.transform = Transform3D(Basis.IDENTITY, at + Vector3(0.0, radius(), 0.0))
	q.collision_mask = 1
	var skip: Array[RID] = [get_rid()]
	var player := _player()
	if player != null:
		skip.append(player.get_rid())
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		if node is CollisionObject3D:
			skip.append((node as CollisionObject3D).get_rid())
	q.exclude = skip
	return not space.intersect_shape(q, 1).is_empty()


func _spin(step: Vector2) -> void:
	if _pivot == null or step.length() < 0.00001:
		return
	var axis := Vector3(step.y, 0.0, -step.x).normalized()
	_pivot.global_rotate(axis, step.length() / maxf(radius(), 0.01))


func _snap_ground() -> void:
	var world := _world()
	if world == null or world.layout == null or world.grid == null:
		return
	var y: float = FieldCollision.ground_y_at(world.layout, world.grid, global_position)
	if FieldCollision.has_floor(y):
		global_position.y = y
	if _pivot != null:
		_pivot.position.y = radius()


func _on_snow() -> bool:
	var world := _world()
	if world == null or world.grid == null:
		return true
	var attr: int = FieldCollision.unit_attr_at(world.layout, world.grid, global_position)
	if attr >= 0:
		return attr <= 3
	return world.grid.terrain_at(world.grid.world_to_cell(global_position)) == WorldGrid.Terrain.GRASS


func _in_water() -> bool:
	var world := _world()
	if world == null or world.grid == null:
		return false
	var attr: int = FieldCollision.unit_attr_at(world.layout, world.grid, global_position)
	return attr >= 0 and FieldCatalog.is_water_attr(attr)


## ------------------------------------------------------------------ pushing

## `aSMAN_process_player_push`, called by the player every physics step while pushing.
## Returns {aim, yaw, speed} for the player, or {} when the push ends.
func push(delta: float, wish: Vector3, stick: float, dash: bool, player: Node3D) -> Dictionary:
	if broken or not _combine.is_empty():
		return {}
	var n: float = normalized()
	var to := Vector2(global_position.x - player.global_position.x, global_position.z - player.global_position.z)
	var player_angle: float = atan2(to.x, to.y)
	var move := Vector2(wish.x, wish.z)
	if stick <= 0.0 or move.length() < 0.001 or n <= SnowmanRules.PUSH_MIN:
		return _release()
	var move_angle: float = atan2(move.x, move.y)
	var diff: float = angle_difference(move_angle, player_angle)
	if absf(diff) > PUSH_CONE:
		return _release()
	var base: float = stick * (3.0 - n * 1.5) * cos(diff) * FRAME
	if dash:
		base *= 1.5
	var was: float = _push_speed
	_push_speed = move_toward(_push_speed, base, PUSH_EASE * delta)
	vel = move.normalized() * _push_speed
	var before: Vector3 = global_position
	_move(move.normalized() * (was + _push_speed) * 0.5, delta)
	if broken:
		return {}
	if _sinking:
		return _release()
	## Shoved into a wall for two seconds: it gives way (`timer > 120`).
	if Vector2(global_position.x - before.x, global_position.z - before.z).length() < 0.25 * vel.length() * delta:
		_wall_time += delta
		if _wall_time > WALL_PUSH_TIME:
			smash()
			return {}
	else:
		_wall_time = 0.0
	_touch_balls()
	if not _combine.is_empty() or broken:
		return {}
	var back: float = (SnowmanRules.radius_gx(n) + 10.0) * SnowmanRules.GX
	var aim := Vector3(global_position.x - sin(player_angle) * back, player.global_position.y, global_position.z - cos(player_angle) * back)
	return {"aim": aim, "yaw": player_angle, "speed": _push_speed}


## `aSMAN_process_player_push_scroll`: carried across an acre border at the player's side
## (`mPlib_GetSnowballPos_forWadeSnowball`), rolling as it goes.
func carry_to(at: Vector3) -> void:
	var step := Vector2(at.x - global_position.x, at.z - global_position.z)
	global_position = Vector3(at.x, global_position.y, at.z)
	_snap_ground()
	_spin(step)


func _release() -> Dictionary:
	_pushing = false
	_lean_time = 0.0
	return {}


func end_push() -> void:
	_pushing = false
	_lean_time = 0.0


## ------------------------------------------------------------------ endings

func _start_sink() -> void:
	_sinking = true
	Audio.play_se(SE_SPLASH, self)
	SnowmanUse.ball_gone(part)


## `aSMAN_process_swim`: it shrinks away in the water.
func _sink_step(delta: float) -> void:
	if _pivot == null:
		queue_free()
		return
	_pivot.scale *= exp(-SINK_SHRINK_RATE * delta)
	global_position.y -= SINK_SPEED * delta
	if _pivot.scale.x < 0.05:
		broken = true
		queue_free()


## `aSMAN_MakeBreakEffect`: it bursts.
func smash() -> void:
	if broken:
		return
	broken = true
	_release_player()
	SnowmanUse.ball_gone(part)
	if _pivot != null:
		var t := create_tween()
		t.tween_property(_pivot, "scale", _pivot.scale * 1.3, 0.08)
		t.tween_property(_pivot, "scale", Vector3.ONE * 0.001, 0.18)
		t.tween_callback(queue_free)
	else:
		queue_free()


func _release_player() -> void:
	if _pushing:
		var player := _player()
		if player != null:
			player.snowball.end_snowball_push()
	_pushing = false


## ------------------------------------------------------------------ combining

## `aSMAN_process_combine_head_jump` / `_combine_body`: over a second the body slides to its
## unit centre and the head arcs up onto it.
func begin_combine(as_head: bool, target: Vector3, top_y: float, done: Callable) -> void:
	_release_player()
	combining = true
	vel = Vector2.ZERO
	_combine = {"head": as_head, "from": global_position, "to": target, "top": top_y, "t": 0.0, "done": done}
	if as_head:
		Audio.play_se(SE_COMBINE, self)


func _combine_step(delta: float) -> void:
	var t: float = minf(float(_combine["t"]) + delta, COMBINE_TIME)
	_combine["t"] = t
	var k: float = t / COMBINE_TIME
	var from: Vector3 = _combine["from"]
	var to: Vector3 = _combine["to"]
	var pos: Vector3 = from.lerp(to, k)
	if bool(_combine["head"]):
		pos.y = lerpf(from.y, float(_combine["top"]), k) + 4.0 * k * (1.0 - k) * 1.5
		if _pivot != null:
			_pivot.rotation = Motion.damp_vec3(_pivot.rotation, Vector3.ZERO, ROTATION_SETTLE_HALF_LIFE, delta)
	global_position = pos
	if t >= COMBINE_TIME:
		var done: Callable = _combine["done"]
		_combine = {}
		if done.is_valid():
			done.call()


func save_state() -> Dictionary:
	if _grid == null:
		return {}
	var cell: Vector2i = _grid.world_to_cell(global_position)
	return {"cell": [cell.x, cell.y], "dist": move_dist}
