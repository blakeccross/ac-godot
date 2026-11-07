class_name PlayerSequences
extends Node

## The player's scripted body sequences: the mailbox jump, the shrine visit, letting a caught
## creature go, bee and mosquito stings, the radio exercise and falling into a pitfall. Each
## takes the player over (`set_cutscene_driven`) and plays its clips through the `Player`'s
## shared clip helpers. A child of the `Player`.

## `Player_actor_request_proc_index_fromRelease_creature` / `Look_Release_creature` timers.
## `mPlayer_ANIM_SAISEN1` / `OMAIRI_US1`: the New Year coin toss and prayer at the well.
const ANIM_SHRINE_OFFERING := &"ply_1_saisen1"
const ANIM_SHRINE_PRAY := &"ply_1_omairi_us1"
## The step onto the coin spot takes 5 frames at 30 fps; the purse rustles at keyframe 9 and
## the coin flies at 33.
const SHRINE_STEP_SEC := 5.0 / DecompTime.FRAME_HZ
const SHRINE_RUSTLE_SEC := 9.0 / DecompTime.FRAME_HZ
const SHRINE_THROW_SEC := 33.0 / DecompTime.FRAME_HZ
## `mPlayer_ANIM_CONFIRM1`: the mailbox hop and landing.
const ANIM_CONFIRM := &"ply_1_confirm1"
## `cKF_SkeletonInfo_R_AnimationMove_ct_base(…, 8.0f, …)`: 8 frames at 30 fps.
const MAIL_JUMP_SEC := 8.0 / DecompTime.FRAME_HZ
## `main_Release_creature`: 84 ticks of `WAIT1`, the head following for the first 60.
const RELEASE_SECONDS := 84.0 / DecompTime.TICK_HZ
const RELEASE_LOOK_SECONDS := 60.0 / DecompTime.TICK_HZ
## `m_player_main_stung_bee` (`HATI1` → `HATI2`) then `notice_bee` (`HATI3` + the report).
const ANIM_HATI1 := "ply_1_hati1"
const ANIM_HATI2 := "ply_1_hati2"
const ANIM_HATI3 := "ply_1_hati3"
## `Movement_Stung_bee` turns to face the camera after 94 ticks; at 252 → `notice_bee`.
const STUNG_TURN_SEC := 94.0 / DecompTime.TICK_HZ
const STUNG_NOTICE_SEC := 252.0 / DecompTime.TICK_HZ
## `Player_actor_Notice_bee_demo_ct`: `0x17B4` in a lilac report window.
const BEE_NOTICE_MSG := 0x17B4
const BEE_NOTICE_COLOR := Color8(225, 165, 255)
## `READY_PITFALL` → `FALL_PITFALL` → `STRUGGLE_PITFALL` → `CLIMBUP_PITFALL`.
const ANIM_GURATUKU1 := "ply_1_guratuku1"
const ANIM_OTIRU1 := "ply_1_otiru1"
const ANIM_MOGAKU1 := "ply_1_mogaku1"
const ANIM_DERU1 := "ply_1_deru1"
## `ControlAnimationSpeed_Struggle_pitfall`: 20 presses' worth of A and stick wiggling.
const STRUGGLE_PRESSES := 20.0
const STRUGGLE_SPEED_MIN := 0.5
const STRUGGLE_SPEED_DECAY := 0.00435
const STRUGGLE_SPEED_EASE := 0.10875
## `m_player_main_stung_mosquito` (`MOSQUITO1`) → `notice_mosquito` (`MOSQUITO2` + report).
const ANIM_MOSQUITO1 := "ply_1_mosquito1"
const ANIM_MOSQUITO2 := "ply_1_mosquito2"
const MOSQUITO_NOTICE_MSG := 0x3063

## The Player this belongs to (the parent), found on first use: tests build scenes
## without adding them to the tree.
var _player: Player:
	get:
		if _player == null:
			_player = get_parent() as Player
		return _player


## `Player_actor_setup_main_Mail_jump`: `CONFIRM1` while sliding onto `to` and turning to
## `yaw` over its first 8 frames; the clip holds its last frame while the box is open.
func mail_jump(to: Vector3, yaw: float) -> void:
	_player._play_body_once(ANIM_CONFIRM)
	await slide_to(to, yaw, MAIL_JUMP_SEC).finished


## Slide onto `to` (XZ) turning to `yaw` over `seconds` (`AnimationMove_ct_base`'s counter).
func slide_to(to: Vector3, yaw: float, seconds: float) -> Tween:
	var from: Vector3 = _player.global_position
	var from_yaw: float = _player._motor.facing
	_player._motor.reset(from_yaw)
	var slide := _player.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	slide.tween_method(
		func(k: float) -> void:
			_player.global_position = Vector3(lerpf(from.x, to.x, k), _player.global_position.y, lerpf(from.z, to.z, k))
			_player.set_facing(lerp_angle(from_yaw, yaw, k)),
		0.0, 1.0, seconds
	)
	slide.tween_callback(_player._motor.reset.bind(yaw))
	return slide


## `Player_actor_setup_main_Throw_money` → `_Pray`: step onto `to` turned to `yaw` over 5
## frames, toss the coin (`SAISEN1`: the purse rustles at keyframe 9, the coin flies at
## 33), then pray (`OMAIRI_US1`). `toss` false is a wish without money: the prayer only.
func shrine_visit(to: Vector3, yaw: float, toss: bool, base_y: float) -> void:
	_player._busy = true
	var from: Vector3 = _player.global_position
	var from_yaw: float = _player._motor.facing
	_player._motor.reset(from_yaw)
	var elapsed: float = 0.0
	if toss:
		_player._play_body_once(ANIM_SHRINE_OFFERING)
	else:
		_player._play_body_once(ANIM_SHRINE_PRAY)
	var rustled: bool = false
	var thrown: bool = false
	while _player.is_inside_tree():
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		var k: float = clampf(elapsed / SHRINE_STEP_SEC, 0.0, 1.0)
		_player.global_position = Vector3(lerpf(from.x, to.x, k), _player.global_position.y, lerpf(from.z, to.z, k))
		_player.set_facing(lerp_angle(from_yaw, yaw, k))
		if toss and not rustled and elapsed >= SHRINE_RUSTLE_SEC:
			rustled = true
			Audio.play_se(&"coin_gasagoso", _player)
		if toss and not thrown and elapsed >= SHRINE_THROW_SEC:
			thrown = true
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			WellCoin.toss(_player.get_parent(), _player.global_position, base_y, rng)
		if _player._anim == null or not _player._anim.is_playing():
			break
	_player._motor.reset(yaw)
	if toss:
		_player._play_body_once(ANIM_SHRINE_PRAY)
		while _player.is_inside_tree() and _player._anim != null and _player._anim.is_playing():
			await get_tree().process_frame
	_player.play_wait_idle()
	_player._busy = false
	_player._gait = PlayerLocomotion.Gait.WAIT


## `Player_actor_setup_main_Mail_land`: `CONFIRM1` again at half speed as the box shuts,
## then the wait.
func mail_land() -> void:
	_player._play_body_once(ANIM_CONFIRM)
	if _player._anim == null:
		return
	_player._anim.speed_scale = 0.5
	var clip: StringName = _player._anim.current_animation
	while _player.is_inside_tree() and _player._anim.is_playing() and _player._anim.current_animation == clip:
		await get_tree().process_frame
	_player._anim.speed_scale = 1.0
	if _player.is_inside_tree() and not _player._anim.is_playing():
		_player.play_wait_idle()


## `mTG_release_proc` → `setup_main_Release_creature`: a bug from the pockets is let go
## 7 GX ahead and 13 up and flies off; a fish is thrown at `water` (`ac_gyo_release`).
## Then the player stands and watches it go.
func release_from_pocket(data: ItemData, water: Variant) -> void:
	if data == null or _player._busy:
		return
	var freed: Object = null
	var yaw: float = _player._motor.facing
	if data is BugData:
		var field: BugField = Netting.field_of(_player._make_context())
		var bug := data as BugData
		var habitat: BugData.Habitat = (bug.habitats[0] as BugData.Habitat) if not bug.habitats.is_empty() else BugData.Habitat.FLYING
		var at: Vector3 = _player.global_position + Vector3(
			sin(yaw) * CreatureRelease.BUG_AHEAD, CreatureRelease.BUG_UP, cos(yaw) * CreatureRelease.BUG_AHEAD
		)
		freed = field.spawn(bug, habitat, at, true) if field != null else null
	elif data is FishData and water != null:
		var host: Node = _player.get_parent() if _player.get_parent() != null else _player
		freed = FishRelease.throw(host, data as FishData, _player.global_position, water as Vector3)
	_player._busy = true
	await watch_release(freed, HeldTool.find_skeleton(_player._mesh))
	_player._motor.reset(_player._motor.facing)
	_player._motor.mode_changed = true
	_player._busy = false
	_player._gait = PlayerLocomotion.Gait.WAIT


## `main_Release_creature`: `WAIT1` for 84 ticks while the head follows what was let go
## for the first 60 (`Player_actor_Look_Release_creature`); it snaps back as the wait ends.
func watch_release(target: Object, skeleton: Skeleton3D) -> void:
	var look := PlayerHeadLook.new()
	look.bind(skeleton, _player._anim)
	_player._play_body_loop(StringName(_player.ANIM_WAIT))
	var elapsed: float = 0.0
	while elapsed < RELEASE_SECONDS and _player.is_inside_tree():
		await get_tree().physics_frame
		var delta: float = get_physics_process_delta_time()
		elapsed += delta
		var want := Vector2.ZERO
		var at: Variant = _release_target_pos(target)
		if elapsed <= RELEASE_LOOK_SECONDS and at != null:
			want = PlayerHeadLook.want(_player.global_position + Vector3(0.0, PlayerHeadLook.EYE, 0.0),
				_player._motor.facing, at as Vector3)
		look.body_yaw = _player._motor.facing
		look.step(want, delta)
	look.angle = Vector2.ZERO
	look.unbind()


## Where the released thing is now, or null once it is gone (`insect_flags.destruct`).
static func _release_target_pos(target: Variant) -> Variant:
	## A thrown fish frees itself in the water: test before anything reads its class.
	if not is_instance_valid(target):
		return null
	if target is BugActor:
		return null if (target as BugActor).f_destruct else (target as BugActor).position
	if target is FishRelease:
		var thrown := target as FishRelease
		return thrown.global_position if thrown.exist and thrown.is_inside_tree() else null
	if target is Node3D and (target as Node3D).is_inside_tree():
		return (target as Node3D).global_position
	return null


## `Stung_mosquito` → `Notice_mosquito`: slap at the bite (`MOSQUITO1`), then scratch it
## (`MOSQUITO2`) turning to the camera under the "Yow!" report and the bee-stung jingle.
## Not while busy or in a demo (`Player_actor_Check_is_demo_mode`).
func run_stung_mosquito() -> void:
	if _player._busy or _player.stung or _player.in_pitfall or _player.doors.door_entering or Game.title_demo_active:
		return
	_player.stung = true
	_player._busy = true
	_player.set_cutscene_driven(true)
	var clip: String = _player._start_one_shot(ANIM_MOSQUITO1)
	while _player._clip_running(clip):
		await get_tree().process_frame
	_player._start_one_shot(ANIM_MOSQUITO2)
	var turning := true
	var ui := DialogueOverlay.find(get_tree())
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % MOSQUITO_NOTICE_MSG))
	var prior_bgm: StringName = Game.session.show_bgm
	Game.session.show_bgm = &"bee_stung"
	Audio.play_bgm(&"bee_stung")
	if ui != null and data != null:
		var ctx: DialogueContext = DialogueContext.from_game()
		ctx.speaker_name = ""
		ctx.voice_mode = DialogueVoice.Mode.CLICK
		ctx.window_color = BEE_NOTICE_COLOR
		ui.play(data, ctx)
		while ui.is_open():
			await get_tree().process_frame
			if turning:
				_player._motor.facing = PlayerLocomotion.ease_turn(
					_player._motor.facing, Fishing.SHOW_YAW, get_process_delta_time()
				)
				_player._mesh.rotation.y = _player._motor.facing
	else:
		Game.post_notice("You got bitten by a mosquito!")
	Game.session.show_bgm = prior_bgm if prior_bgm != &"bee_stung" else &""
	var world: World = World.find(get_tree())
	if world != null:
		world.play_outdoor_bgm()
	_player.set_cutscene_driven(false)
	_player.play_wait_idle()
	_player._busy = false
	_player.stung = false


## `m_player_main_wait`: the C-stick is logged while standing (the right stick, or I / J /
## K / L), and a finished pattern starts that exercise.
func poll_radio_exercise(delta: float) -> void:
	if _player.exercising:
		return
	var standing: bool = _player._motor.gait() == PlayerLocomotion.Gait.WAIT
	_player._radio.log_command(
		RadioExercise.direction(_c_stick()) if standing and _radio_able() else -1, delta
	)
	var start: int = _player._radio.step(standing, delta)
	if start >= 0:
		run_radio_exercise(start)


## `Player_actor_Check_AbleRadioExercise`: empty hands, and either the aerobics event on the
## shrine acre or (only when no such event runs) the aerobics radio playing in this room.
func _radio_able() -> bool:
	if Game.inventory.equipment_id != &"":
		return false
	var manager := EventManager.find(get_tree())
	if manager != null and (manager.is_running(&"morning_aerobics") or manager.is_running(&"sports_fair_aerobics")):
		var bg: Array = _player._bg()
		if bg.is_empty():
			return false
		var cell: Vector2i = (bg[1] as WorldGrid).world_to_cell(_player.global_position)
		return FieldCollision.acre_type_at(bg[0] as WorldData, cell) == TownFieldGenerator.T_SHRINE
	var session: IndoorSession = Game.interior_session
	return session != null and session.room != null \
		and FurnitureMusic.active_bgm(session.room) == FurnitureMusic.AEROBICS_BGM


## The GameCube C-stick, y up: the right stick, or I / J / K / L.
func _c_stick() -> Vector2:
	var v := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), -Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	var keys := Vector2(
		float(Input.is_physical_key_pressed(KEY_L)) - float(Input.is_physical_key_pressed(KEY_J)),
		float(Input.is_physical_key_pressed(KEY_I)) - float(Input.is_physical_key_pressed(KEY_K))
	)
	if keys != Vector2.ZERO:
		return keys.normalized()
	return v


## `Radio_exercise`: play the move at its speed, keep logging the stick, and from 24 frames
## before the end pick up the next move; one waiting when the clip ends follows straight on.
func run_radio_exercise(cmd: int) -> void:
	if _player.exercising or cmd < 0 or cmd >= RadioExercise.CLIPS.size():
		return
	_player.exercising = true
	_player._busy = true
	_player.set_cutscene_driven(true)
	while cmd >= 0:
		_player._radio.begin()
		var clip: String = _player._start_one_shot(RadioExercise.CLIPS[cmd], 0.12)
		if clip.is_empty():
			break
		## cKF frames per tick → clip rate (the bake runs at 30 fps = 0.5 per tick).
		_player._anim.speed_scale = RadioExercise.SPEED[cmd] / 0.5
		var length: float = _player._clip_length(clip)
		while _player._clip_running(clip):
			await get_tree().process_frame
			var delta: float = get_process_delta_time()
			var left_frames: float = (length - _player._anim.current_animation_position) * DecompTime.FRAME_HZ
			_player._radio.log_command(RadioExercise.direction(_c_stick()) if _radio_able() else -1, delta)
			## The next exercise can be queued in the last 24 keyframes.
			if left_frames <= 24.0:
				_player._radio.step(false, delta)
		cmd = _player._radio.pending if _player._radio.pending >= 0 and _player._radio.pending_timer <= 0.0 else -1
	_player._anim.speed_scale = 1.0
	_player.set_cutscene_driven(false)
	_player.play_wait_idle()
	_player._busy = false
	_player.exercising = false


## `Player_actor_check_pitfall` (walk / run / wait states): standing within 19 GX of the
## centre of a unit holding a buried pitfall springs it.
func poll_pitfall() -> void:
	if _player.in_pitfall:
		return
	var bg: Array = _player._bg()
	if bg.is_empty():
		return
	var grid := bg[1] as WorldGrid
	var cell: Vector2i = grid.world_to_cell(_player.global_position)
	if not grid.is_in_bounds(cell) or not BuriedUse.is_pitfall(grid.occupant_at(cell)):
		return
	var center: Vector3 = grid.cell_corner(cell) + Vector3(grid.cell_size, 0.0, grid.cell_size) * 0.5
	var reach: float = BuriedUse.PITFALL_REACH
	if Vector2(center.x - _player.global_position.x, center.z - _player.global_position.z).length() > reach:
		return
	center.y = _player.global_position.y
	run_pitfall(cell, center)


## The pitfall states. `GURATUKU1` totters onto the pit centre, `OTIRU1` drops in,
## `MOGAKU1` struggles until A presses and stick wiggles add up to 20 (faster struggling
## speeds the clip up), then `DERU1` climbs out as the pit closes behind. The original moves
## the actor by each clip's root (`AnimationMove`); here the drop rides on the mesh pivot.
func run_pitfall(cell: Vector2i, center: Vector3) -> void:
	if _player.in_pitfall:
		return
	_player.in_pitfall = true
	var was_busy: bool = _player._busy
	_player._busy = true
	_player.set_cutscene_driven(true)
	var world := World.find(get_tree())
	var grid: WorldGrid = world.grid if world != null else null
	BuriedUse.spring_pitfall(world, grid, cell)
	var start: Vector3 = _player.global_position
	var clip: String = _player._start_one_shot(ANIM_GURATUKU1)
	var length: float = _player._clip_length(clip)
	var t: float = 0.0
	while _player._clip_running(clip):
		await get_tree().process_frame
		t += get_process_delta_time()
		_player.global_position = start.lerp(center, clampf(t / maxf(length, 0.001), 0.0, 1.0))
	_player.global_position = center
	clip = _player._chain_clip(ANIM_OTIRU1)
	while _player._clip_running(clip):
		await get_tree().process_frame
	_player._chain_clip(ANIM_MOGAKU1, true)
	await _struggle()
	## `setup_main_Climbup_pitfall` → `pit_exit_proc`.
	BuriedUse.close_pit(world, cell)
	clip = _player._chain_clip(ANIM_DERU1)
	while _player._clip_running(clip):
		await get_tree().process_frame
	_player._mesh.position = Vector3.ZERO
	var wait := _player._resolve_clip(_player.ANIM_WAIT)
	if _player._anim != null and not wait.is_empty():
		_player._gait = PlayerLocomotion.Gait.WAIT
		_player._anim.speed_scale = 1.0
		_player._anim.play(wait, 0.0)
	_player.set_cutscene_driven(false)
	_player._busy = was_busy
	_player.in_pitfall = false
	_player.struggle_assist = 0.0


## `Struggle_pitfall`: count A presses and stick motion until 20, easing the clip speed
## toward a target that presses raise and time lowers (0.5–1.0).
func _struggle() -> void:
	var presses: float = 0.0
	var target: float = STRUGGLE_SPEED_MIN
	var speed: float = STRUGGLE_SPEED_MIN
	var old_stick := Vector2.ZERO
	while presses < STRUGGLE_PRESSES:
		await get_tree().process_frame
		var ticks: float = get_process_delta_time() * DecompTime.TICK_HZ
		var stick: Vector2 = _player.stick_input()
		var add: float = 1.0 if _player.a_just_pressed() and not _player._menu_open() else 0.0
		add += absf(old_stick.length() - stick.length()) * 0.5
		if old_stick.length() > 0.0 and stick.length() > 0.0:
			## `s16` move-angle change × 0.00002.
			add += absf(wrapf(stick.angle() - old_stick.angle(), -PI, PI)) * 65536.0 / TAU * 0.00002
		add += _player.struggle_assist * ticks
		old_stick = stick
		presses += add
		## Presses raise the target clip speed; it sags `STRUGGLE_SPEED_DECAY` a tick, and the
		## speed eases `STRUGGLE_SPEED_EASE` of the way to it a tick.
		target = clampf(target + add * 0.25 - STRUGGLE_SPEED_DECAY * ticks, STRUGGLE_SPEED_MIN, 1.0)
		speed = lerpf(speed, target, 1.0 - pow(1.0 - STRUGGLE_SPEED_EASE, ticks))
		if _player._anim != null:
			_player._anim.speed_scale = speed
	if _player._anim != null:
		_player._anim.speed_scale = 1.0


## `Stung_bee` → `Notice_bee`. The music goes quiet, `HATI1` flinches into `HATI2`, whose
## frame 21 swells the face; from tick 94 the player turns their back to the camera (angle
## 0x8000), and at tick 252 `HATI3` spins round to show the face under the "stung by a bee"
## report with the bee-stung jingle.
func run_stung_bee() -> void:
	if _player.stung:
		return
	_player.stung = true
	var was_busy: bool = _player._busy
	_player._busy = true
	## Holds `HATI2`'s last frame between clips rather than dropping to the wait.
	_player.set_cutscene_driven(true)
	## `mBGMPsComp_make_ps_quiet` (and the chase music goes with it).
	Game.session.show_bgm = &"_quiet"
	Audio.stop_bgm()
	## `HATI1` flinches into `HATI2`, whose `sting_swell` clip event swells the face.
	_player._sting_swelled = false
	var clip: String = _player._start_one_shot(ANIM_HATI1)
	if clip.is_empty():
		_player._start_one_shot(ANIM_HATI2)
	else:
		## Whatever ends first (`HATI1`, or whatever cut it off) hands over, as before.
		_player._anim.animation_finished.connect(func(_done: StringName) -> void: _player._start_one_shot(ANIM_HATI2), CONNECT_ONE_SHOT)
	await get_tree().create_timer(STUNG_TURN_SEC, false).timeout
	## Then the back to the camera, easing round until the notice.
	var turn_left: float = STUNG_NOTICE_SEC - STUNG_TURN_SEC
	while turn_left >= 0.0:
		await get_tree().process_frame
		var delta: float = get_process_delta_time()
		turn_left -= delta
		_player._motor.facing = PlayerLocomotion.ease_turn(_player._motor.facing, Fishing.SHOW_YAW + PI, delta)
		_player._mesh.rotation.y = _player._motor.facing
	if not _player._sting_swelled:
		_player._sting_swelled = true
		Game.bees.sting()
	await _notice_bee()
	_player.stung = false
	Game.session.show_bgm = &""
	var world: World = World.find(get_tree())
	if world != null:
		world.play_outdoor_bgm()
	_player.set_cutscene_driven(false)
	_player._busy = was_busy


## `Notice_bee`: `HATI3` and the report; both have to finish before the wait.
func _notice_bee() -> void:
	var clip: String = _player._start_one_shot(ANIM_HATI3)
	Game.session.show_bgm = &"bee_stung"
	Audio.play_bgm(&"bee_stung")
	var ui := DialogueOverlay.find(get_tree())
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % BEE_NOTICE_MSG))
	if ui != null and data != null:
		var ctx: DialogueContext = DialogueContext.from_game()
		ctx.speaker_name = ""
		ctx.voice_mode = DialogueVoice.Mode.CLICK
		ctx.window_color = BEE_NOTICE_COLOR
		ui.play(data, ctx)
		await ui.closed
	else:
		Game.post_notice("You've been stung by bees!")
	while not clip.is_empty() and _player._anim != null and _player._anim.is_playing() and _player._anim.current_animation == clip:
		await _player._anim.animation_finished
	## `settle_main_Notice_bee`: `HATI3`'s half-turn lives on joint_0 here (the original moves
	## it onto the actor with `AnimationMove` ROT_Y), so hand it to the facing and cut to the
	## wait without a blend — the pose reads the same either side of the swap.
	_player._motor.reset(Fishing.SHOW_YAW)
	_player._mesh.rotation.y = _player._motor.facing
	var wait := _player._resolve_clip(_player.ANIM_WAIT)
	if _player._anim != null and not wait.is_empty():
		_player._gait = PlayerLocomotion.Gait.WAIT
		_player._anim.play(wait, 0.0)
