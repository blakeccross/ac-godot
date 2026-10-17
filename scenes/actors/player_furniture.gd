class_name PlayerFurniture
extends Node

## The player with furniture in a house: gripping a piece to push, pull, turn or tap it
## (`aMR_ManageMoveBottun`), sitting on a chair or lying on a bed and getting off again
## (`aMR_SitDownFurniture` / `aMR_JudgeGoToBed`), and B to pick a piece up. A child of the
## `Player`, which runs it from `_physics_process`; it reads the player's motor, body
## animation and busy flag directly.

## Any stick past this gets you up (`Player_actor_GetController_move_percentX/Y`).
const REST_STAND_STICK := 0.1
## `furniture_push` / `furniture_pull` cKF at half speed: 24 frames of 30 Hz.
const FURNITURE_MOVE_SEC := 0.8
## `aMR_FtrRotate`: 5.6°/tick ellipse over 90° — a little under half a second.
const FURNITURE_TURN_SEC := 0.45
## `Player_actor_Movement_Hold`: the player settles onto the contact point.
const GRIP_SETTLE_RATE := 14.0

## Holding onto a piece of furniture (`mPlayer_INDEX_HOLD` and its push / pull / turn children).
var _grip: FurnitureGrip = FurnitureGrip.new()
var gripping: bool = false
var _grip_nice: Vector3 = Vector3.ZERO
var _grip_move: Dictionary = {}
## Sitting in a chair or lying in a bed: `{ kind, id, pos, yaw_facing, approach, phase, t, dur, from, to }`.
var _seat: FurnitureSeat = FurnitureSeat.new()
var rest: Dictionary = {}

## The Player this belongs to (the parent), found on first use: tests build scenes
## without adding them to the tree.
var _player: Player:
	get:
		if _player == null:
			_player = get_parent() as Player
		return _player


## `aMR_ManageMoveBottun`: A against a piece in your own house grips it. Anything else —
## nothing there, a piece in the pockets to place, another room — falls through to the normal verb.
func try_grip() -> bool:
	if _player._busy or gripping or _player._door_entering or not Game.is_decorating() or Game.held_furniture() != null:
		return false
	var session: IndoorSession = Game.interior_session
	if session == null:
		return false
	var contact: Dictionary = _grip.press(
		session, _player.global_position, WorldGrid.facing_from_player_yaw(_player._motor.facing)
	)
	if contact.is_empty():
		return false
	gripping = true
	_player._busy = true
	_grip_move = {}
	_grip_nice = contact["nice_pos"] as Vector3
	_player._motor.reset(WorldGrid.yaw_for_furniture(_grip.facing))
	_player._mesh.rotation.y = _player._motor.facing
	_player._play_grip_clip(Player.ANIM_HOLD_WAIT1, true)
	return true


func _grip_stick() -> Vector2:
	if _player._menu_open():
		return Vector2.ZERO
	var input_dir: Vector2 = _player.stick_input()
	var wish: Vector3 = _player._camera_wish(input_dir)
	return Vector2(wish.x, wish.z) * clampf(input_dir.length(), 0.0, 1.0)


func tick_grip(delta: float) -> void:
	if Game.interior_session == null:
		_end_grip()
		return
	var held: bool = _player.a_held() and not _player._menu_open()
	var events: Array[Dictionary] = _grip.advance(
		delta, Game.interior_session, held, _grip_stick(), _player.global_position
	)
	if not _grip_move.is_empty():
		_advance_grip_move(delta)
	elif gripping:
		var pos: Vector3 = _player.global_position
		_player.global_position = pos.lerp(Vector3(_grip_nice.x, pos.y, _grip_nice.z), clampf(delta * GRIP_SETTLE_RATE, 0.0, 1.0))
	for event: Dictionary in events:
		if not gripping:
			break
		_on_grip_event(event)
	_player.velocity = Vector3.ZERO


func _on_grip_event(event: Dictionary) -> void:
	match str(event.get("op", "")):
		"tap":
			var side: int = int(event.get("side", -1))
			var tapped_id: StringName = event.get("id", &"") as StringName
			_end_grip()
			_tap_furniture(tapped_id, side)
		"release":
			_end_grip()
		"move":
			_notify_moved(event)
			var pushing: bool = event.get("kind") == &"push"
			_grip_move = {
				"t": 0.0,
				"dur": FURNITURE_MOVE_SEC,
				"from": event["player_from"] as Vector3,
				"to": event["player_to"] as Vector3,
			}
			_grip_nice = event["player_to"] as Vector3
			_player._play_grip_clip(Player.ANIM_PUSH1 if pushing else Player.ANIM_PULL1, false)
			_sync_furniture(FURNITURE_MOVE_SEC)
		"rotate":
			_notify_moved(event)
			_grip_move = {"t": 0.0, "dur": FURNITURE_TURN_SEC, "from": _player.global_position, "to": _player.global_position}
			_player._play_grip_clip(Player.ANIM_LTURN1 if bool(event.get("ccw", true)) else Player.ANIM_RTURN1, false)
			_sync_furniture(FURNITURE_TURN_SEC)
		"bubu":
			## `aMR_SetBubu`: the cross over the player when the piece will not budge.
			FieldEffects.spawn(_effects_host(), FieldEffects.Kind.BUBU, _player.global_position, 0.0)


func _notify_moved(event: Dictionary) -> void:
	var host: Interior = Interior.find(get_tree())
	if host != null:
		host.on_furniture_moved(event.get("vacated", []))


func _advance_grip_move(delta: float) -> void:
	var dur: float = maxf(float(_grip_move["dur"]), 0.001)
	var t: float = minf(float(_grip_move["t"]) + delta, dur)
	_grip_move["t"] = t
	var k: float = smoothstep(0.0, 1.0, t / dur)
	var from: Vector3 = _grip_move["from"] as Vector3
	var to: Vector3 = _grip_move["to"] as Vector3
	_player.global_position = Vector3(lerpf(from.x, to.x, k), _player.global_position.y, lerpf(from.z, to.z, k))
	if t >= dur:
		_grip_move = {}
		_grip.finish_busy()
		_player._play_grip_clip(Player.ANIM_HOLD_WAIT1, true)


func _sync_furniture(duration: float) -> void:
	var host: Interior = Interior.find(get_tree())
	if host != null:
		host.sync_placements(duration)


func _end_grip() -> void:
	gripping = false
	_grip_move = {}
	_grip.reset()
	_player._busy = false
	_player._gait = PlayerLocomotion.Gait.WAIT
	_player.play_wait_idle()


## A short A on a gripped piece is the ordinary use verb (open, switch, put a fish on it).
func _tap_furniture(placement_id: StringName, side: int) -> void:
	var interior: Interior = Interior.find(get_tree())
	var volume: InteractVolume = InteractVolume.of(interior.furniture_node(placement_id) if interior != null else null)
	if volume == null:
		return
	var ctx: InteractionContext = _player._make_context()
	ctx.contact_side = side
	var action: Interaction = Interaction.primary(volume.offers(ctx))
	if action == null:
		return
	await _player._run_interact(InteractionQuery.on(volume, action))


## `aMR_SitDownFurniture` / `aMR_JudgeGoToBed`: walking straight into a chair or a bed.
func poll_rest(delta: float) -> void:
	if _player._menu_open() or Game.interior_session == null or not Game.is_indoors():
		_seat.reset()
		return
	var hit: Dictionary = _seat.poll(
		delta,
		Game.interior_session,
		_player.global_position,
		WorldGrid.facing_from_player_yaw(_player._motor.facing),
		_grip_stick()
	)
	if not hit.is_empty():
		_begin_rest(hit)


func _begin_rest(hit: Dictionary) -> void:
	var lying: bool = int(hit["kind"]) == FurnitureSeat.Rest.LIE
	var leaf: String = Player.ANIM_SITDOWN1
	if lying:
		leaf = Player.ANIM_INBED_L1 if bool(hit.get("from_left", true)) else Player.ANIM_INBED_R1
	rest = hit.duplicate()
	rest["phase"] = &"in"
	rest["t"] = 0.0
	rest["dur"] = _clip_seconds(leaf, 0.8)
	rest["from"] = _player.global_position
	rest["to"] = hit["pos"] as Vector3
	_player._busy = true
	var yaw: float = WorldGrid.yaw_for_furniture(hit["yaw_facing"] as WorldGrid.Facing)
	_player._motor.reset(yaw)
	_player._mesh.rotation.y = yaw
	_player._play_grip_clip(leaf, false)


func tick_rest(delta: float) -> void:
	_player.velocity = Vector3.ZERO
	var lying: bool = int(rest["kind"]) == FurnitureSeat.Rest.LIE
	var phase: StringName = rest["phase"] as StringName
	if phase == &"wait":
		var stick: Vector2 = _grip_stick()
		if not lying:
			if stick.length() > REST_STAND_STICK:
				_begin_stand(false)
			return
		## `wait_bed.flags`: the stick has to come back before the next roll.
		if stick.length() <= 0.5:
			rest["armed"] = true
			return
		if not bool(rest.get("armed", false)):
			return
		var act: Dictionary = FurnitureSeat.bed_action(Game.interior_session, rest, _player.global_position, stick)
		match int(act["action"]):
			FurnitureSeat.BedAction.ROLL:
				_begin_roll(act["side"] as WorldGrid.Facing)
			FurnitureSeat.BedAction.OUT:
				_begin_stand(true, act["side"] as WorldGrid.Facing)
		return
	if phase == &"roll":
		if _player._clip_running(str(rest.get("clip", ""))):
			return
		## `settle_main_Roll_bed` (`AnimationMove_dt`): the clip's sideways travel becomes the
		## player's position, and the bed wait picks up from there without a blend.
		var before: Vector3 = _player._root_joint_position()
		var wait := _player._resolve_clip(Player.ANIM_BED_WAIT1)
		if _player._anim != null and not wait.is_empty():
			_player._ensure_loop(wait)
			_player._anim.play(wait, 0.0)
			_player._anim.seek(0.0, true)
		var after: Vector3 = _player._root_joint_position()
		if before != Vector3.INF and after != Vector3.INF:
			_player.global_position += Vector3(before.x - after.x, 0.0, before.z - after.z)
		rest["pos"] = _player.global_position
		rest["phase"] = &"wait"
		rest["armed"] = false
		return
	var t: float = minf(float(rest["t"]) + delta, float(rest["dur"]))
	rest["t"] = t
	var k: float = smoothstep(0.0, 1.0, t / maxf(float(rest["dur"]), 0.001))
	var from: Vector3 = rest["from"] as Vector3
	var to: Vector3 = rest["to"] as Vector3
	_player.global_position = Vector3(lerpf(from.x, to.x, k), _player.global_position.y, lerpf(from.z, to.z, k))
	if t < float(rest["dur"]):
		return
	if phase == &"in":
		rest["phase"] = &"wait"
		_player._play_grip_clip(Player.ANIM_BED_WAIT1 if lying else Player.ANIM_SITDOWN_WAIT1, true)
	else:
		_end_rest()


func _begin_stand(lying: bool, side: int = -1) -> void:
	var session: IndoorSession = Game.interior_session
	if session == null:
		_end_rest()
		return
	var seat_pos: Vector3 = rest["pos"] as Vector3
	var spot: Dictionary
	var exit_left: bool = bool(rest.get("from_left", true))
	if lying and side >= 0:
		## Out on the side the stick pushed: `OUTBED_L1` undoes `INBED_L1`, whose approach is
		## the side a quarter-turn back from the pillow.
		var grid: WorldGrid = session.grid
		var exit_cell: Vector2i = grid.step(grid.world_to_cell(_player.global_position), side as WorldGrid.Facing)
		spot = FurnitureSeat.bed_exit_spot(session, grid.cell_to_world(exit_cell))
		exit_left = grid.rotate_facing(rest.get("head", WorldGrid.Facing.SOUTH) as WorldGrid.Facing, -1) == side
	elif lying:
		spot = FurnitureSeat.bed_exit_spot(session, rest["approach"] as Vector3)
	else:
		spot = FurnitureSeat.stand_spot(session, seat_pos, rest["yaw_facing"] as WorldGrid.Facing)
	if spot.is_empty():
		return
	var leaf: String = Player.ANIM_STANDUP1
	if lying:
		leaf = Player.ANIM_OUTBED_L1 if exit_left else Player.ANIM_OUTBED_R1
	rest["phase"] = &"out"
	rest["t"] = 0.0
	rest["dur"] = _clip_seconds(leaf, 0.8)
	rest["from"] = _player.global_position
	rest["to"] = spot["pos"] as Vector3
	_player._play_grip_clip(leaf, false)


## `Roll_bed`: `NEGAERI_L1` / `R1`, whichever carries the body toward `side` (the original
## picks it from the facing and stick quadrant; the clip's own root travel says the same).
func _begin_roll(side: WorldGrid.Facing) -> void:
	var session: IndoorSession = Game.interior_session
	if session == null:
		return
	var step: Vector2i = session.grid.step(Vector2i.ZERO, side)
	var want := Vector3(float(step.x), 0.0, float(step.y))
	var leaf: String = Player.ANIM_NEGAERI_R1
	var travel: Vector3 = _clip_root_travel(Player.ANIM_NEGAERI_R1)
	if travel != Vector3.ZERO and travel.dot(want) < 0.0:
		leaf = Player.ANIM_NEGAERI_L1
	var clip: String = _player._start_one_shot(leaf, 0.0)
	Audio.play_se(&"bed_negaeri", _player)
	rest["phase"] = &"roll"
	rest["clip"] = clip
	rest["armed"] = false


## World-space XZ the clip's joint_0 travels from first to last key, turned by the facing.
func _clip_root_travel(leaf: String) -> Vector3:
	var clip: String = _player._resolve_clip(leaf)
	if clip.is_empty() or _player._anim == null:
		return Vector3.ZERO
	var res: Animation = _player._anim.get_animation(clip)
	var track: int = _player._find_joint0_position_track(res) if res != null else -1
	if track < 0 or res.track_get_key_count(track) < 2:
		return Vector3.ZERO
	var a: Vector3 = res.track_get_key_value(track, 0) as Vector3
	var b: Vector3 = res.track_get_key_value(track, res.track_get_key_count(track) - 1) as Vector3
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	return d.rotated(Vector3.UP, _player._motor.facing)


func _end_rest() -> void:
	rest = {}
	_seat.reset()
	_player._busy = false
	_player._gait = PlayerLocomotion.Gait.WAIT
	_player.play_wait_idle()


func _clip_seconds(leaf: String, fallback: float) -> float:
	var clip: String = _player._resolve_clip(leaf)
	if _player._anim == null or clip.is_empty():
		return fallback
	var animation: Animation = _player._anim.get_animation(clip)
	return animation.length if animation != null and animation.length > 0.0 else fallback


## Shut the dresser / wardrobe / closet again once the last message has closed.
func play_storage_close(storage_type: int) -> void:
	var leaf: StringName = FurnitureStorage.CLOSE_CLIPS.get(storage_type, &"") as StringName
	if leaf == &"" or _player._anim == null:
		return
	var clip: String = _player._resolve_clip(String(leaf))
	if clip.is_empty():
		return
	var animation: Animation = _player._anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_NONE
	_player._anim.speed_scale = 1.0
	_player._anim.play(clip, 0.08)
	await _player._anim.animation_finished


## `Player_actor_CheckAndRequest_main_pickup_all`: B facing a piece in your own house picks it up.
func poll_furniture_pickup() -> void:
	if not Input.is_action_just_pressed("sprint") or _player._menu_open() or _player._door_entering:
		return
	if not Game.is_decorating() or Game.interior_session == null:
		return
	var id: StringName = FurnitureGrip.find_pickup(
		Game.interior_session, _player.global_position, WorldGrid.facing_from_player_yaw(_player._motor.facing)
	)
	if id == &"":
		return
	_player._busy = true
	var tail: float = await _player._play_action(&"ply_1_pickup1", 20.0)
	Game.pick_up_furniture(id)
	await _player._finish_action(tail)
	_player._busy = false
	_player._gait = PlayerLocomotion.Gait.WAIT


## The room's `Effects` node, or the room itself.
func _effects_host() -> Node:
	var room: Node = Interior.find(get_tree())
	if room == null:
		return _player.get_parent()
	var effects: Node = room.get_node_or_null("Effects")
	return effects if effects != null else room
