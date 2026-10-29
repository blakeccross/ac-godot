extends Node3D

## The lighthouse switch room machinery (`ac_lighthouse_switch`): the lever on the east
## wall (`obj_toudai_switch`), the lens drive in the pit (`obj_toudai_pole`) and the room's
## point light. This node stands at the lever (`LighthouseRoom.SWITCH`) so the player
## faces it; `Lever` / `Pole` sit back on the room datum because both models are authored
## in room GX.
##
## Outside the quest the room runs itself: at night (18:00–05:00) the lever flips on, the
## drive spins up and the light comes on; by day it all winds down. On a quest night only
## the player can throw it (A at the panel, `ply_1_light_on1`), which lights tonight's lamp
## (`LighthouseBook.switch_on`).

const LEVER_VISUAL := &"obj_toudai_switch"
const POLE_VISUAL := &"obj_toudai_pole"
const CLIP_ON := &"obj_toudai_switch"
const CLIP_OFF := &"obj_toudai_switch_off"
const CLIP_POLE := &"obj_toudai_pole"
const PLAYER_ANIM := &"ply_1_light_on1"
## `mPlib_check_player_actor_start_switch_on_lighthouse`: past frame 1 of the player clip.
const PLAYER_EFFECT_FRAME := 2.0
## `aLS_CheckPlayerSwitchPositionAngle`: the player's centre within 33.57 GX of the lever,
## facing strictly between 90° and 180° (east to north).
const PANEL_REACH := 33.5684 * FieldCatalog.GX_TO_METERS
const PANEL_FACING_MIN := PI / 2.0
const PANEL_FACING_MAX := PI
## `aLS_CheckPlayerAction` `nice_pos` {167.27, 40, 112.73} from the lever at {180, 100}, and
## 135°: the clip slides the player there over its 9-frame `AnimationMove` counter.
const PANEL_STAND := Vector3(-12.72792, 0.0, 12.72792) * FieldCatalog.GX_TO_METERS
const PANEL_STAND_YAW := PI * 0.75
const PANEL_STAND_SEC := 9.0 / DecompTime.FRAME_HZ
## `sAdo_OngenTrgStart(SE_ECHO(NA_SE_78))` when the lever passes frame 20 going on.
const LEVER_SE := &"78"
const LEVER_SE_FRAME := 20.0
## cKF clips sampled at 30 fps. Frame speeds below are keyframes a 60th of a second, as the
## decomp writes them; a step advances them by the 60ths it covers.
const CLIP_FPS := 30.0
const TICK_HZ := DecompTime.TICK_HZ
const LEVER_SPEED := 0.5
const POLE_FRAME_START := 1.0
const POLE_FRAME_END := 100.0
const POLE_SPEED_MAX := 0.5
## `aLS_GetNowPoleAnimeSpeed` spin-up: two kicks 30 ticks apart, easing off between, then
## from tick 48 a steady climb.
const POLE_KICK_SEC := 48.0 / TICK_HZ
const POLE_KICK_PERIOD_SEC := 30.0 / TICK_HZ
const POLE_KICK_1 := 0.065
const POLE_KICK_2 := 0.85 * 0.065
const POLE_KICK_DECAY := 0.09
const POLE_CLIMB := 0.0035
## Wind-down: coast to 0.1, ease up by 0.07, then swing back (100 → 1) and settle.
const POLE_COAST := 0.001
const POLE_COAST_FLOOR := 0.1
const POLE_SETTLE_BUMP := 0.07
const POLE_SWING_BACK := 1.7
## The lever drops 49 ticks after the swing back.
const POLE_OFF_SEC := 49.0 / TICK_HZ
## `mEnv_ManagePointLight`: the lighthouse light eases on at 0.02; `RequestChangeLightOFF`
## drops it at 0.002 a tick.
const LIGHT_ON_RATE := 0.02
const LIGHT_ON_MIN := 0.00007
const LIGHT_OFF_RATE := 0.002
const LIGHT_ENERGY := 1.6

enum PoleState { STOPPING, RUNNING }

## `aLS_switch_c.state`: the lever is (or is going) on.
var lever_on: bool = false
var lever_frame: float = 1.0
var lever_clip: StringName = CLIP_ON
var lever_moving: bool = false
var pole_state: PoleState = PoleState.STOPPING
var pole_speed: float = 0.0
var pole_frame: float = POLE_FRAME_START
var pole_reverse: bool = false
## Seconds the drive has been running (the spin-up reads it).
var pole_time: float = 0.0
var pole_phase: int = 2
## Seconds until the lever drops; 0 when not waiting.
var pole_off_left: float = 0.0
## `point_light_percent` for this room (0–1).
var light: float = 0.0
var light_on: bool = false
## When false the room ignores the clock (tests drive `advance()` / modes directly).
@export var follow_clock: bool = true

@onready var _lever: Node3D = $Lever
@onready var _pole: Node3D = $Pole
@onready var _light: OmniLight3D = $RoomLight
var _lever_anim: AnimationPlayer = null
var _pole_anim: AnimationPlayer = null


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("authored_fixture")
	if not FieldCatalog.mesh_paths(LEVER_VISUAL).is_empty():
		GeneratedVisual.attach_datum(_lever, LEVER_VISUAL)
		_lever_anim = _find_anim(_lever)
	if not FieldCatalog.mesh_paths(POLE_VISUAL).is_empty():
		GeneratedVisual.attach_datum(_pole, POLE_VISUAL)
		_pole_anim = _find_anim(_pole)
	_light.light_color = LighthouseRoom.LIGHT_COLOR
	enter(_mode())


## `Lighthouse_Switch_Actor_ct`: the room as it stands when the player walks in.
func enter(mode: LighthouseBook.SwitchMode) -> void:
	var on: bool = false
	match mode:
		LighthouseBook.SwitchMode.AUTO_ON:
			on = true
		LighthouseBook.SwitchMode.MANUAL:
			on = Game != null and Game.lighthouse != null and Game.lighthouse.is_night_lit(
				EventDates.ordinal(Clock.year, Clock.month, Clock.day)
			)
	lever_on = on
	## The lever rests on the first frame of the clip that would move it away.
	lever_clip = CLIP_OFF if on else CLIP_ON
	lever_frame = 1.0
	lever_moving = false
	pole_phase = 2
	pole_frame = POLE_FRAME_START
	pole_reverse = false
	if on:
		pole_state = PoleState.RUNNING
		pole_speed = POLE_SPEED_MAX
		pole_time = POLE_KICK_SEC
	else:
		pole_state = PoleState.STOPPING
		pole_speed = 0.0
		pole_time = 0.0
	light_on = on
	light = 1.0 if on else 0.0
	_apply()


func _physics_process(delta: float) -> void:
	advance(_mode(), delta)
	_apply()


## `Lighthouse_Switch_Actor_move` (minus the player check) over `delta` seconds.
func advance(mode: LighthouseBook.SwitchMode, delta: float) -> void:
	_auto_switch(mode)
	_pole_move(delta)
	_lever_move(delta)
	_light_move(delta)


func get_interactions(ctx: InteractionContext) -> Array[Interaction]:
	if not can_throw():
		return []
	var actor: Node3D = ctx.actor as Node3D if ctx != null else null
	if actor != null and not at_panel(actor):
		return []
	var action := Interaction.of(Interaction.TOGGLE, "Turn on the light", 20, PLAYER_ANIM, PLAYER_EFFECT_FRAME)
	var face: Vector3 = global_basis * Vector3(sin(PANEL_STAND_YAW), 0.0, cos(PANEL_STAND_YAW))
	return [action.with_stand(to_global(PANEL_STAND), atan2(face.x, face.z), PANEL_STAND_SEC)]


## `aLS_CheckPlayerSwitchPositionAngle`, in this room's axes.
func at_panel(actor: Node3D) -> bool:
	var local: Vector3 = to_local(actor.global_position)
	if Vector2(local.x, local.z).length() >= PANEL_REACH:
		return false
	if not actor.has_method("facing_yaw"):
		return true
	var yaw: float = float(actor.call("facing_yaw"))
	var dir: Vector3 = global_basis.inverse() * Vector3(sin(yaw), 0.0, cos(yaw))
	var local_yaw: float = atan2(dir.x, dir.z)
	return local_yaw > PANEL_FACING_MIN and local_yaw < PANEL_FACING_MAX


## `aLS_CheckPlayerAction`: A at the panel on a quest night while the lever is off.
func can_throw() -> bool:
	return _mode() == LighthouseBook.SwitchMode.MANUAL and not lever_on


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TOGGLE or not can_throw():
		return false
	if Game != null and Game.lighthouse != null:
		Game.lighthouse.switch_on_now()
	request_lever_on()
	return true


## `aLS_RequestSwitchON`.
func request_lever_on() -> void:
	lever_on = true
	lever_clip = CLIP_ON
	lever_frame = 1.0
	lever_moving = true


## `aLS_RequestPoleToStop`: the drive winds down and the light goes out; the lever follows.
func request_pole_stop() -> void:
	pole_state = PoleState.STOPPING
	pole_phase = 0
	light_on = false


func _auto_switch(mode: LighthouseBook.SwitchMode) -> void:
	match mode:
		LighthouseBook.SwitchMode.OFF:
			if lever_on and pole_state == PoleState.RUNNING:
				request_pole_stop()
		LighthouseBook.SwitchMode.AUTO_ON:
			if not lever_on:
				request_lever_on()


func _lever_move(delta: float) -> void:
	if not lever_moving:
		return
	var before: float = lever_frame
	lever_frame += LEVER_SPEED * delta * TICK_HZ
	if lever_on and (before - LEVER_SE_FRAME) * (lever_frame - LEVER_SE_FRAME) <= 0.0 and before != lever_frame:
		if Audio != null:
			Audio.play_se(LEVER_SE, self)
	var last: float = _clip_frames(_lever_anim, lever_clip)
	if lever_frame >= last:
		lever_frame = last
		lever_moving = false
		if lever_on:
			## `aLS_SwitchMove`: once the lever is home the drive starts and the light comes on.
			pole_state = PoleState.RUNNING
			pole_time = -1.0
			pole_speed = 0.0
			pole_reverse = false
			light_on = true


func _pole_move(delta: float) -> void:
	if pole_state == PoleState.RUNNING:
		## The first step after the lever lands kicks (`pole_time` −1 marks it).
		var before: float = pole_time
		pole_time = maxf(pole_time, 0.0)
		if pole_time < POLE_KICK_SEC:
			if before < 0.0:
				pole_speed = POLE_KICK_1
			elif before < POLE_KICK_PERIOD_SEC and pole_time + delta >= POLE_KICK_PERIOD_SEC:
				pole_speed = POLE_KICK_2
			else:
				pole_speed = _approach(
					pole_speed, 0.0, POLE_KICK_DECAY, POLE_KICK_DECAY * 0.065, 0.00001, delta
				)
			pole_time += delta
		else:
			pole_speed += POLE_CLIMB * TICK_HZ * delta
	else:
		match pole_phase:
			0:
				pole_speed -= POLE_COAST * TICK_HZ * delta
				if pole_speed < POLE_COAST_FLOOR:
					pole_phase = 1
			1:
				var goal: float = POLE_COAST_FLOOR + POLE_SETTLE_BUMP
				pole_speed = _approach(pole_speed, goal, 0.4, 1.0, 0.001, delta)
				if absf(pole_speed - goal) < 0.001:
					pole_phase = 2
					pole_reverse = true
					pole_speed = POLE_COAST_FLOOR * POLE_SWING_BACK
					pole_off_left = POLE_OFF_SEC
			_:
				pole_speed = _approach(pole_speed, 0.0, 0.4, 1.0, 0.001, delta)
				if pole_off_left > 0.0:
					pole_off_left -= delta
					if pole_off_left <= 0.0:
						pole_off_left = 0.0
						## `aLS_RequestSwitchOFF`.
						lever_on = false
						lever_clip = CLIP_OFF
						lever_frame = 1.0
						lever_moving = true
	_turn_pole(delta)


func _turn_pole(delta: float) -> void:
	pole_speed = clampf(pole_speed, 0.0, POLE_SPEED_MAX)
	if pole_speed > 0.0:
		var step: float = pole_speed * TICK_HZ * delta
		pole_frame += -step if pole_reverse else step
		var span: float = POLE_FRAME_END - POLE_FRAME_START
		while pole_frame > POLE_FRAME_END:
			pole_frame -= span
		while pole_frame < POLE_FRAME_START:
			pole_frame += span


func _light_move(delta: float) -> void:
	if light_on:
		light = _approach(light, 1.0, LIGHT_ON_RATE, LIGHT_ON_RATE, LIGHT_ON_MIN, delta)
	else:
		light = maxf(0.0, light - LIGHT_OFF_RATE * TICK_HZ * delta)


func _apply() -> void:
	_seek(_lever_anim, lever_clip, lever_frame)
	_seek(_pole_anim, CLIP_POLE, pole_frame)
	if _light != null:
		_light.light_energy = LIGHT_ENERGY * light
		_light.visible = light > 0.0


func _mode() -> LighthouseBook.SwitchMode:
	if not follow_clock or Game == null or Game.lighthouse == null or Clock == null:
		return LighthouseBook.SwitchMode.OFF if not lever_on else LighthouseBook.SwitchMode.AUTO_ON
	return Game.lighthouse.switch_mode_now()


static func _seek(anim: AnimationPlayer, clip: StringName, cfr: float) -> void:
	if anim == null or not is_instance_valid(anim) or not anim.has_animation(clip):
		return
	if anim.current_animation != clip:
		anim.play(clip)
	anim.pause()
	anim.seek((cfr - 1.0) / CLIP_FPS, true)


## Last cKF frame of a clip (`cKF_FRAMECONTROL_STOP` end), from the baked length.
static func _clip_frames(anim: AnimationPlayer, clip: StringName) -> float:
	if anim == null or not is_instance_valid(anim) or not anim.has_animation(clip):
		return 48.0
	return 1.0 + anim.get_animation(clip).length * CLIP_FPS


## `add_calc(value, target, fraction, max_step, min_step)` a tick, over `delta` seconds.
static func _approach(
	value: float, target: float, fraction: float, max_step: float, min_step: float, delta: float
) -> float:
	return Motion.approach(
		value, target, Motion.half_life_from_fraction(fraction), max_step * TICK_HZ,
		min_step * TICK_HZ, delta
	)


static func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c: Node in n.get_children():
		var found: AnimationPlayer = _find_anim(c)
		if found != null:
			return found
	return null
