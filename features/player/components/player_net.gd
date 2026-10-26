class_name PlayerNet
extends Node

## The player with the net: ready, walk, swing and stop (`NetSwing`, stepped every
## physics frame while active), and the catch that follows a pull: pulling the insect in,
## showing it off and putting it away (`main_Pull_net` / `main_Notice_net` /
## `main_Putaway_net`). A child of the `Player`; it reads the player's motor, body
## animation and busy flag directly.

## The net's ready / walk / swing / stop states (`NetSwing`), stepped every physics frame
## while active; the catch that follows a pull runs in `_run_net_catch`.
var net_swing := NetSwing.new()
## `player->net_pos` as of the last swing step.
var _net_pos: Vector3 = Vector3.ZERO

## The Player this belongs to (the parent), found on first use: tests build scenes
## without adding them to the tree.
var _player: Player:
	get:
		if _player == null:
			_player = get_parent() as Player
		return _player


## A swing is under way (ready, walk, swing or stop).
func is_active() -> bool:
	return net_swing.is_active()


## `request_main_ready_net` from wait / walk / run, `request_main_slip_net` from a dash.
func begin_net() -> void:
	var from_dash: bool = _player._motor.gait() == PlayerLocomotion.Gait.DASH
	net_swing.begin(from_dash, _player._motor.speed, _player._motor.facing)
	if from_dash:
		_net_events()
	_play_net_clip()


## One physics frame of the net states: a `NetSwing` step, then its speed and facing handed
## back to the mover. Returns the planar velocity for `move_and_slide`.
func tick_net(delta: float, input_dir: Vector2, wish: Vector3, stick: float, menu_open: bool) -> Vector3:
	## `kind != getkind`: the net left the hand (inventory swap, scene change) → back to wait.
	var tool: ToolData = _player.tools.equipped_tool()
	if tool == null or tool.field_verb != Interaction.SWING_NET:
		_end_net()
		return _player._motor.forward() * _player._motor.planar_speed
	var a_held: bool = false
	if _player.scripted_input != null:
		a_held = _player.scripted_input.a_held
	elif not menu_open:
		a_held = Input.is_action_pressed("interact")
	var has_dir: bool = not menu_open and stick > 0.0 and wish.length_squared() > 0.0001
	var wish_yaw: float = atan2(wish.x, wish.z) if has_dir else net_swing.yaw
	var axes: bool = has_dir and (_player.scripted_input != null or _player._axes_active(input_dir))
	if net_swing.is_active():
		var probe: NetSwing.Probe = null
		if net_swing.state == NetSwing.State.SWING:
			probe = _net_probe()
			_net_pos = probe.net_pos
		net_swing.advance(
			delta,
			a_held,
			stick if has_dir else 0.0,
			wish_yaw,
			axes,
			probe,
			_player._motor.over_speed_normalize(_player.global_position),
			_player._motor.wall_ratio
		)
		_net_events()
		if net_swing.state_changed:
			_play_net_clip()
		_sync_net_clip()
	_player._motor.speed = net_swing.speed
	_player._motor.facing = net_swing.yaw
	if net_swing.state == NetSwing.State.PULL:
		_run_net_catch()
	elif net_swing.state == NetSwing.State.NONE:
		_end_net()
	return _player._motor.forward() * _player._motor.planar_speed


func _net_probe() -> NetSwing.Probe:
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_player._mesh)
	var hand := Transform3D.IDENTITY
	var has_hand: bool = false
	if skeleton != null:
		var idx: int = skeleton.find_bone(HeldTool.HAND_BONE)
		if idx >= 0:
			hand = skeleton.global_transform * skeleton.get_bone_global_pose(idx)
			has_hand = true
	return Netting.probe(_player._make_context(), _player.global_position, net_swing.yaw, hand, has_hand)


func _net_events() -> void:
	for event: StringName in net_swing.events:
		match event:
			&"furi":
				PlayerSe.net_furi(_player)
			&"get":
				PlayerSe.net_get(_player)
			&"hit":
				PlayerSe.net_hit(_player)
			&"swing_fx":
				FootstepEffects.swing_net(_player._bg(), _player.global_position, net_swing.yaw)
			&"splash":
				var splash_bg: Array = _player._bg()
				var head: Vector3 = _net_pos
				if splash_bg.size() == 2:
					var surface: float = FieldCollision.ground_y_at(splash_bg[0] as WorldData, splash_bg[1] as WorldGrid, head)
					if FieldCollision.has_floor(surface):
						head.y = surface
				if FootstepEffects.net_splash(splash_bg, head, net_swing.yaw):
					Audio.play_se(&"ami_hit_water", _player)
			&"slip":
				var bg: Array = _player._bg()
				Audio.play_se(Player.SE_SLIP, _player)
				FootstepEffects.turn(bg, _player.global_position, net_swing.yaw, _player._unit_attr(bg), 1)
			&"stop_net":
				## `mPlib_Check_StopNet`: insects near the net panic, fish bolt.
				var ctx: InteractionContext = _player._make_context()
				var field: BugField = Netting.field_of(ctx)
				if field != null:
					field.notify_stop_net(_net_pos)
				var school: FishSchool = Fishing.school_of(ctx)
				if school != null:
					school.notify_tool_swing()
				## `Player_actor_CheckAndSet_UZAI_forNpc`: a villager the net struck.
				var npc := net_swing.hit_actor as Villager
				if npc != null and is_instance_valid(npc):
					npc.register_net_hit()


func _play_net_clip() -> void:
	net_swing.state_changed = false
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_player._mesh)
	var body: StringName = &""
	var tool_clip: StringName = &""
	var loop: bool = true
	match net_swing.state:
		NetSwing.State.READY:
			body = NetSwing.ANIM_READY
			tool_clip = NetSwing.TOOL_READY
		NetSwing.State.READY_WALK:
			body = NetSwing.ANIM_READY_WALK
			tool_clip = NetSwing.TOOL_READY
		NetSwing.State.SLIP:
			body = NetSwing.ANIM_SLIP
			tool_clip = NetSwing.TOOL_READY
			loop = false
		NetSwing.State.SWING:
			body = NetSwing.ANIM_SWING
			tool_clip = NetSwing.TOOL_SWING
			loop = false
		NetSwing.State.STOP:
			## `setup_main_Stop_net`: the body holds its last pose; only the net moves.
			HeldTool.play(skeleton, NetSwing.TOOL_STOP, false)
			if _player._anim != null:
				_player._anim.speed_scale = 0.0
			return
		_:
			return
	HeldTool.play(skeleton, tool_clip, loop)
	if _player._anim == null:
		return
	var clip := _player._resolve_clip(String(body))
	if clip.is_empty():
		return
	var res: Animation = _player._anim.get_animation(clip)
	if res != null:
		res.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_player._anim.speed_scale = net_swing.frame_speed / NetSwing.FRAME_SPEED
	_player._anim.play(clip, Player.MORPH_5)
	_player._gait = PlayerLocomotion.Gait.WAIT


## Keeps the clip on `NetSwing`'s keyframe: the swing can step back half a keyframe when the
## net strikes something, which a free-running clip would not.
func _sync_net_clip() -> void:
	if _player._anim == null:
		return
	match net_swing.state:
		NetSwing.State.READY_WALK:
			_player._anim.speed_scale = net_swing.frame_speed / NetSwing.FRAME_SPEED
		NetSwing.State.SWING:
			_player._anim.speed_scale = 0.0
			if _player._anim.current_animation != "":
				_player._anim.seek((net_swing.frame - 1.0) / DecompTime.FRAME_HZ, true)


## Back to the wait (`request_main_wait_all`).
func _end_net() -> void:
	net_swing.cancel()
	_player._motor.reset(net_swing.yaw)
	_player._motor.mode_changed = true
	if _player._anim != null:
		_player._anim.speed_scale = 1.0
	HeldTool.play(HeldTool.find_skeleton(_player._mesh), _player.tools.tool_hold_anim, true)


## `pull_net` → `notice_net` → `putaway_net`, from the tick the swing came back full.
func _run_net_catch() -> void:
	var caught: Object = net_swing.caught
	net_swing.cancel()
	_player._busy = true
	var ctx: InteractionContext = _player._make_context()
	var field: BugField = Netting.field_of(ctx)
	var catch_: Netting.Catch = Netting.begin_catch(caught)
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_player._mesh)
	## `PULL_NET` / `NOTICE_NET` / `PUTAWAY_NET`: showing off a bug.
	_player.fishing.catch_showing = catch_ != null
	if catch_ != null:
		var ui: DialogueOverlay = DialogueOverlay.find(get_tree())
		await _net_pull(catch_, skeleton, ui)
		## `setup_main_Notice_net`.
		Netting.bank(catch_, Game.inventory)
		_player._motor.facing = Netting.SHOW_YAW
		_player._mesh.rotation.y = Netting.SHOW_YAW
		await _net_notice(catch_, skeleton, ui)
		## `settle_main_Notice_net`.
		Audio.pop_fanfare(BgmCatalog.id_for_num(Netting.FANFARE_COMPLETE if catch_.completes_record else Netting.FANFARE_CATCH))
		if catch_.banked:
			await _net_putaway(skeleton)
		else:
			## `release_creature`: let it go from the hand, then stand and watch it go.
			var freed: BugActor = Netting.release(catch_, field, _player.left_hand_global())
			HeldCatch.unbind(skeleton)
			await _player._watch_release(freed, skeleton)
	_player._motor.reset(_player._motor.facing)
	_player._motor.mode_changed = true
	if _player._anim != null:
		_player._anim.speed_scale = 1.0
	HeldTool.play(skeleton, _player.tools.tool_hold_anim, true)
	_player.fishing.catch_showing = false
	_player._busy = false
	_player._gait = PlayerLocomotion.Gait.WAIT
	_player._update_focus()


## `main_Pull_net`: `GET_M1` plays out; the insect shows in the left hand past keyframe 15,
## the player turns to the camera past 17, and the report opens 50 ticks in. The pull hands
## on once the clip has ended and the report is up.
func _net_pull(catch_: Netting.Catch, skeleton: Skeleton3D, ui: DialogueOverlay) -> void:
	HeldTool.play(skeleton, Netting.TOOL_PULL, false)
	_player._play_body_once(Netting.ANIM_PULL)
	var elapsed: float = 0.0
	var shown: bool = false
	var reported: bool = false
	while true:
		await get_tree().physics_frame
		var delta: float = get_physics_process_delta_time()
		var frame: float = _keyframe_at(elapsed)
		if frame > Netting.PULL_TURN_FRAME:
			_player._motor.facing = PlayerLocomotion.ease_turn(_player._motor.facing, Netting.SHOW_YAW, delta)
			_player._mesh.rotation.y = _player._motor.facing
		if frame > Netting.PULL_TO_HAND_FRAME and not shown:
			HeldCatch.bind_bug(skeleton, catch_.bug)
			shown = true
		elapsed += delta
		if elapsed >= Netting.PULL_REPORT_SEC and not reported:
			_player.reports.report_camera(true)
			_player.reports.say_net_catch(ui, catch_.report_msg(), catch_.bug)
			Audio.push_fanfare(BgmCatalog.id_for_num(Netting.FANFARE_CATCH))
			reported = true
		if _clip_ended(elapsed, Netting.PULL_FRAMES) and reported:
			return


## `main_Notice_net`'s message states: the collection-complete follow-up with `YATTA2`, or the
## pockets-full swap question, then wait for the report to close.
func _net_notice(catch_: Netting.Catch, skeleton: Skeleton3D, ui: DialogueOverlay) -> void:
	await _player.reports.wait_closed(ui)
	if catch_.completes_record:
		HeldTool.play(skeleton, Netting.TOOL_YATTA, false)
		_player._play_body_once(Netting.ANIM_YATTA)
		Audio.pop_fanfare(BgmCatalog.id_for_num(Netting.FANFARE_CATCH))
		Audio.push_fanfare(BgmCatalog.id_for_num(Netting.FANFARE_COMPLETE))
		_player.reports.say_net_catch(ui, Netting.LAST_GET_CONTINUE_MSG, catch_.bug)
		await _player.reports.wait_closed(ui)
	if not catch_.banked and catch_.bug != null:
		## 0xA4D: "Swap" trades a pocket for it (`mSM_IV_OPEN_EXCHANGE`), else it goes.
		if await _player.reports.ask_swap(Netting.POCKETS_FULL_MSG) and await _player.reports.exchange_into_pockets(catch_.bug.id):
			catch_.banked = true
	_player.reports.report_camera(false)


## `main_Putaway_net`: `PUTAWAY_M1` with `GASAGOSO`; the insect shrinks each tick until
## keyframe 17 and is gone from the hand there.
func _net_putaway(skeleton: Skeleton3D) -> void:
	HeldTool.play(skeleton, Netting.TOOL_PUTAWAY, false)
	_player._play_body_once(Netting.ANIM_PUTAWAY)
	PlayerSe.gasagoso(_player)
	var elapsed: float = 0.0
	## Shrinks until keyframe 17, then leaves the hand.
	var shrink_sec: float = (Netting.PUTAWAY_GONE_FRAME - 1.0) / DecompTime.FRAME_HZ
	while not _clip_ended(elapsed, Netting.PUTAWAY_FRAMES):
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if elapsed < shrink_sec:
			var held: Node3D = HeldCatch.held_creature(skeleton)
			if held != null:
				held.scale = Vector3.ONE * pow(Netting.PUTAWAY_SHRINK, elapsed * DecompTime.TICK_HZ)
		elif HeldCatch.is_held(skeleton):
			HeldCatch.unbind(skeleton)
	HeldCatch.unbind(skeleton)


## The keyframe (1-based, 30 a second) a clip started `elapsed` seconds ago is showing.
static func _keyframe_at(elapsed: float) -> float:
	return 1.0 + elapsed * DecompTime.FRAME_HZ


## `CulcAnimation_Base2` end detection for a stop-mode clip: it reports the end one tick
## after the clip reaches `end_frame`.
static func _clip_ended(elapsed: float, end_frame: float) -> bool:
	return elapsed >= (end_frame - 1.0) / DecompTime.FRAME_HZ + DecompTime.TICK_SEC - 0.0001
