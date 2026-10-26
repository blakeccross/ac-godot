class_name PlayerSnowball
extends Node

## The player rolling a snowball: leaning on it starts a push (`Snowball.push`), the
## player follows it each physics step, and it lets go at an acre border it may not cross.
## A child of the `Player`; it reads the player's motor directly.

const ANIM_PUSH_YUKI1 := "ply_1_push_yuki1"

## The Player this belongs to (the parent), found on first use: tests build scenes
## without adding them to the tree.
var _player: Player:
	get:
		if _player == null:
			_player = get_parent() as Player
		return _player


## `mPlib_request_main_push_snowball_type1`: the ball leads, the player keeps behind it.
func begin_snowball_push(ball: Node3D) -> bool:
	if _player._busy or _player.furniture.gripping or _player._snowball != null or not _player._wade.is_empty() or _player._menu_open():
		return false
	_player._snowball = ball
	if ball is PhysicsBody3D:
		_player.add_collision_exception_with(ball)
	_player._play_grip_clip(ANIM_PUSH_YUKI1, true)
	return true


## `mPlib_request_main_push_snowball_end_type1`.
func end_snowball_push() -> void:
	var ball: Node3D = _player._snowball
	_player._snowball = null
	if is_instance_valid(ball):
		if ball is PhysicsBody3D:
			_player.remove_collision_exception_with(ball)
		if ball.has_method("end_push"):
			ball.call("end_push")
	_player.velocity = Vector3.ZERO


## `Player_actor_main_Push_snowball`: the ball moves each step and hands back where the
## player stands (`mPlib_SetParam_for_push_snowball`).
func push_snowball(
	delta: float, wish: Vector3, stick: float, dash: bool, input_dir: Vector2 = Vector2.ZERO, bg: Array = []
) -> void:
	if not is_instance_valid(_player._snowball):
		end_snowball_push()
		return
	var last: Dictionary = _player._snowball.call("push", delta, wish, stick, dash, _player)
	if last.is_empty():
		end_snowball_push()
		return
	var aim: Vector3 = last["aim"]
	var before: Vector3 = _player.global_position
	_player.global_position = Vector3(aim.x, _player.global_position.y, aim.z)
	_player._snap_to_bg()
	_player.set_facing(float(last["yaw"]))
	_player._motor.body_yaw = _player._motor.facing
	_player.velocity = Vector3.ZERO
	if bg.size() == 2 and TownSpace.is_outdoor_town() and _snowball_border(before, input_dir, bg):
		return
	if _player._anim != null:
		_player._anim.speed_scale = clampf(float(last["speed"]) / (1.5 * Snowball.FRAME), 0.2, 2.0)


## `aSMAN_player_push_scroll_request`: pushing, the player is walled in the acre too
## (`mCoBG_UniqueWallCheck`). At the wall with the stick across and the body within 5°,
## the player and the ball wade together (`WADE_SNOWBALL`); otherwise the push lets go.
func _snowball_border(before: Vector3, input_dir: Vector2, bg: Array) -> bool:
	var old_gx: Vector3 = TownSpace.world_to_gx(before)
	var now_gx: Vector3 = TownSpace.world_to_gx(_player.global_position)
	var held: Vector3 = AcreWade.confine(old_gx, now_gx)
	if held.x == now_gx.x and held.z == now_gx.z:
		return false
	var back: Vector3 = TownSpace.gx_to_world(held)
	_player.global_position.x = back.x
	_player.global_position.z = back.z
	_player._snap_to_bg()
	var pos_gx: Vector3 = TownSpace.world_to_gx(_player.global_position)
	var dir: AcreWade.Dir = AcreWade.direction(
		pos_gx, _player._motor.facing, Vector2(input_dir.x, -input_dir.y),
		func(d: AcreWade.Dir) -> bool: return _player._can_land(pos_gx, d, bg),
		0.0, _player.unable_wade, AcreWade.SNOWBALL_ANGLE_RANGE,
	)
	if dir == AcreWade.Dir.NONE or _player.unable_wade:
		end_snowball_push()
		return true
	var ball: Node3D = _player._snowball
	var ofs: Vector3 = ball.global_position - _player.global_position
	_player._begin_wade(pos_gx, dir)
	_player._wade["ball"] = ball
	_player._wade["ball_ofs"] = ofs
	## Still leaning on it through the scroll (`Wade_snowball` keeps the push pose).
	_player._play_grip_clip(ANIM_PUSH_YUKI1, true)
	return true
