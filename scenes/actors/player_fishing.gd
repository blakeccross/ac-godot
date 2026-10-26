class_name PlayerFishing
extends Node

## The player at the rod once a cast is out: facing the bobber, the reel-in beats
## (`Fishing.ReelBeat`), waiting on the line, the show-off pose with the catch and putting
## the rod away. A child of the `Player`; it reads the player's motor, body animation and
## busy flag directly.

## `Player_actor_SetPlayerAngle_forUki`'s clamps (per tick).
const UKI_TURN_MAX := 13.73291015625 * PI / 180.0
const UKI_TURN_MIN := 0.274658203125 * PI / 180.0

## `mPlib_check_player_actor_main_index_catch_insect` / `_catch_fish`: pulling in and showing
## a bug or fish — villagers nearby clap (`aNPC_check_clap`).
var catch_showing: bool = false

## The Player this belongs to (the parent), found on first use: tests build scenes
## without adding them to the tree.
var _player: Player:
	get:
		if _player == null:
			_player = get_parent() as Player
		return _player


## The field's line this player last used the rod on (`ToolUse` binds it); null before.
var line: Fishing


## The player has a line out, so is held at the rod.
func holds_line() -> bool:
	return line != null and line.holds(_player)


## `Player_actor_SetPlayerAngle_forUki`: `add_calc_short_angle2(1−√½, 13.73°, 0.27°)` a
## tick toward the bobber while the line is out.
func face_bobber(delta: float) -> void:
	if line == null or not line.faces_bobber(_player):
		return
	var to_uki: Vector3 = line.anchor() - _player.global_position
	if is_zero_approx(to_uki.x) and is_zero_approx(to_uki.z):
		return
	_player._motor.facing = MathUtil.short_angle2(
		_player._motor.facing, atan2(to_uki.x, to_uki.z), MathUtil.HALF_FRACTION, UKI_TURN_MAX, UKI_TURN_MIN,
		delta * DecompTime.TICK_HZ
	)


## The rod's reel-in runs after the action, not through `player_anim`: the hook has to
## resolve on the button frame or the bite window is spent animating. `Fishing` picks the
## beats from what came up on the line.
func play_reel() -> void:
	await _wait_for_line()
	var beats: Array = line.take_reel_beats() if line != null else []
	for beat: Fishing.ReelBeat in beats:
		## `FLY_ROD` → `NOTICE_ROD` → `PUTAWAY_ROD`: a fish is coming out of the water.
		if beat.fish != null:
			catch_showing = true
	for beat: Fishing.ReelBeat in beats:
		if beat.face_camera or beat.hold > 0.0:
			await _play_show(beat)
		else:
			await _player._play_clip(beat.player_anim, beat.tool_anim, beat.start_frame)
	catch_showing = false


## Between A and the line coming up. `relax_rod` holds its pose until the bobber reports
## `aUKI_STATUS_VIB`, and from then `vib_rod` loops `TURI_HIKI1` against the fish for as long
## as the fight lasts (`FIGHT_FRAMES`); an empty line just waits out the bobber's 12 ticks.
func _wait_for_line() -> void:
	## The longest fight is 156 ticks; anything past this means nothing is ticking the line.
	var budget: float = 5.0
	var pulling: bool = false
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_player._mesh)
	if line == null:
		return
	while line.is_reeling() and budget > 0.0:
		if not pulling and line.state() == Fishing.State.BITE:
			pulling = true
			var clip := _player._resolve_clip(String(Fishing.REEL_PULL))
			if _player._anim != null and not clip.is_empty():
				var res: Animation = _player._anim.get_animation(clip)
				if res != null:
					res.loop_mode = Animation.LOOP_LINEAR
				_player._anim.speed_scale = 1.0
				_player._anim.play(clip, 0.08)
			HeldTool.play(skeleton, Fishing.ROD_PULL, true)
		await get_tree().process_frame
		budget -= get_process_delta_time()
	if line.is_reeling():
		line.cancel(Fishing.school_of(_player._make_context()))
	if pulling:
		HeldTool.play(skeleton, _player.tools.tool_hold_anim, true)


## `m_player_main_notice_rod`: hold the catch up and turn square-on to the camera, then put
## the catch report on screen and keep the pose until the player dismisses it. The player
## stays turned to the camera: `putaway_rod` keeps the old `angle_y` only to hand to the
## exchange pockets and never turns them back to the water.
func _play_show(beat: Fishing.ReelBeat) -> void:
	if beat.player_anim == &"":
		return
	var clip := _player._resolve_clip(String(beat.player_anim))
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_player._mesh)
	HeldTool.play(skeleton, beat.tool_anim, false)
	HeldCatch.bind(skeleton, beat.fish)
	var length: float = 0.0
	if _player._anim != null and not clip.is_empty():
		_player._anim.speed_scale = 1.0
		_player._anim.play(clip, 0.08)
		var res: Animation = _player._anim.get_animation(clip)
		if res != null:
			length = res.length
	## `main_notice->timer` counts independently of the animation, so the report opens on
	## frame 42 whether or not the clip has finished — `GET_T2` is longer than that and plays
	## on underneath the text.
	var held: float = 0.0
	while held < beat.hold:
		await get_tree().process_frame
		var delta: float = get_process_delta_time()
		held += delta
		if beat.face_camera:
			## `Player_actor_Movement_Notice_rod`.
			_player._motor.facing = PlayerLocomotion.ease_turn(_player._motor.facing, Fishing.SHOW_YAW, delta)
	if beat.catch_msg == 0:
		## Nothing to hold for, so the pose still has to outlast its own clip: dropping
		## `_busy` early would let the idle animation cut it off mid-hold.
		if held < length:
			await get_tree().create_timer(length - held).timeout
	else:
		await _player._report_catch(beat.catch_msg, beat.pockets_full, beat.fish, beat.completes_record)
	await _play_putaway(skeleton)


## `Player_actor_request_proc_index_fromNotice_rod` hands the dismissed report to
## `putaway_rod`, which plays `PUTAWAY_T1` with a `GASAGOSO` rustle and then falls back to the
## wait. The catch is in the pocket well before this: `setup_main_Notice_rod` banks it with
## `Player_actor_putin_item` before the text ever opens, so this is the visible half of a move
## already made — which is also why a full pocket takes the other branch and throws it back.
func _play_putaway(skeleton: Skeleton3D) -> void:
	## The rod has no putaway clip of its own — `tol_sao_1` carries six and none is one — so it
	## holds the wait pose while the player's hands do the work.
	HeldTool.play(skeleton, _player.tools.tool_hold_anim, true)
	var clip := _player._resolve_clip(String(Fishing.PUTAWAY))
	if _player._anim == null or clip.is_empty():
		HeldCatch.unbind(skeleton)
		return
	_player._anim.speed_scale = 1.0
	_player._anim.play(clip, 0.08)
	## Timed off the clip rather than waited on `animation_finished`, which never arrives if
	## anything else drives the player in the meantime — and then the catch is never released.
	var res: Animation = _player._anim.get_animation(clip)
	if res != null and res.length > 0.0:
		await get_tree().create_timer(res.length).timeout
	## Released at the end, not the start: the fish rides the hand down and goes as the pose
	## closes, rather than blinking out from under a hand still holding it up.
	HeldCatch.unbind(skeleton)
