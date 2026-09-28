extends Node3D

## The lighthouse switch room machinery (`ac_lighthouse_switch`): the lever on the east
## wall (`obj_toudai_switch`), the lens drive in the pit (`obj_toudai_pole`) and the room's
## point light. This node stands at the lever (`LighthouseRoom.SWITCH_GX`) so the player
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
## `sAdo_OngenTrgStart(SE_ECHO(NA_SE_78))` when the lever passes frame 20 going on.
const LEVER_SE := &"78"
const LEVER_SE_FRAME := 20.0
## cKF clips sampled at 30 fps; the move tick is 60 Hz.
const CLIP_FPS := 30.0
const TICK_HZ := 60.0
const LEVER_SPEED := 0.5
const POLE_FRAME_START := 1.0
const POLE_FRAME_END := 100.0
const POLE_SPEED_MAX := 0.5
## `aLS_GetNowPoleAnimeSpeed` spin-up: two kicks 30 ticks apart, then a steady climb.
const POLE_KICK_TICKS := 48
const POLE_KICK_PERIOD := 30
const POLE_KICK_1 := 0.065
const POLE_KICK_2 := 0.85 * 0.065
const POLE_KICK_DECAY := 0.09
const POLE_CLIMB := 0.0035
## Wind-down: coast to 0.1, ease up by 0.07, then swing back (100 → 1) and settle.
const POLE_COAST := 0.001
const POLE_COAST_FLOOR := 0.1
const POLE_SETTLE_BUMP := 0.07
const POLE_SWING_BACK := 1.7
const POLE_OFF_DELAY := 49
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
var pole_timer: int = 0
var pole_phase: int = 2
var pole_off_timer: int = 0
## `point_light_percent` for this room (0–1).
var light: float = 0.0
var light_on: bool = false
## When false the room ignores the clock (tests drive `tick()` / modes directly).
@export var follow_clock: bool = true

var _accum: float = 0.0
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
		pole_timer = POLE_KICK_TICKS
	else:
		pole_state = PoleState.STOPPING
		pole_speed = 0.0
		pole_timer = 0
	light_on = on
	light = 1.0 if on else 0.0
	_apply()


func _physics_process(delta: float) -> void:
	_accum += delta
	var ticks: int = 0
	while _accum >= 1.0 / TICK_HZ and ticks < 8:
		_accum -= 1.0 / TICK_HZ
		ticks += 1
		tick(_mode())
	if ticks >= 8:
		_accum = 0.0
	_apply()


## One 60 Hz move (`Lighthouse_Switch_Actor_move` minus the player check).
func tick(mode: LighthouseBook.SwitchMode) -> void:
	_auto_switch(mode)
	_pole_move()
	_lever_move()
	_light_move()


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if not can_throw():
		return []
	return [Interaction.of(Interaction.TOGGLE, "Turn on the light", 20, PLAYER_ANIM, PLAYER_EFFECT_FRAME)]


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


func _lever_move() -> void:
	if not lever_moving:
		return
	var before: float = lever_frame
	lever_frame += LEVER_SPEED
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
			pole_timer = 0
			pole_speed = 0.0
			pole_reverse = false
			light_on = true


func _pole_move() -> void:
	if pole_state == PoleState.RUNNING:
		if pole_timer < POLE_KICK_TICKS:
			if pole_timer % POLE_KICK_PERIOD == 0:
				pole_speed = POLE_KICK_1 if pole_timer < POLE_KICK_PERIOD else POLE_KICK_2
			else:
				pole_speed = _add_calc(pole_speed, 0.0, POLE_KICK_DECAY, POLE_KICK_DECAY * 0.065, 0.00001)
			pole_timer += 1
		else:
			pole_speed += POLE_CLIMB
	else:
		match pole_phase:
			0:
				pole_speed -= POLE_COAST
				if pole_speed < POLE_COAST_FLOOR:
					pole_phase = 1
			1:
				var goal: float = POLE_COAST_FLOOR + POLE_SETTLE_BUMP
				pole_speed = _add_calc(pole_speed, goal, 0.4, 1.0, 0.001)
				if absf(pole_speed - goal) < 0.001:
					pole_phase = 2
					pole_reverse = true
					pole_speed = POLE_COAST_FLOOR * POLE_SWING_BACK
					pole_off_timer = POLE_OFF_DELAY
			_:
				pole_speed = _add_calc(pole_speed, 0.0, 0.4, 1.0, 0.001)
				if pole_off_timer > 1:
					pole_off_timer -= 1
				elif pole_off_timer == 1:
					pole_off_timer = 0
					## `aLS_RequestSwitchOFF`.
					lever_on = false
					lever_clip = CLIP_OFF
					lever_frame = 1.0
					lever_moving = true
	pole_speed = clampf(pole_speed, 0.0, POLE_SPEED_MAX)
	if pole_speed > 0.0:
		pole_frame += -pole_speed if pole_reverse else pole_speed
		var span: float = POLE_FRAME_END - POLE_FRAME_START
		while pole_frame > POLE_FRAME_END:
			pole_frame -= span
		while pole_frame < POLE_FRAME_START:
			pole_frame += span


func _light_move() -> void:
	if light_on:
		light = _add_calc(light, 1.0, LIGHT_ON_RATE, LIGHT_ON_RATE, LIGHT_ON_MIN)
	else:
		light = maxf(0.0, light - LIGHT_OFF_RATE)


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


## `add_calc(value, target, fraction, max_step, min_step)`.
static func _add_calc(value: float, target: float, fraction: float, max_step: float, min_step: float) -> float:
	var diff: float = target - value
	if diff == 0.0:
		return value
	var mag: float = clampf(absf(diff * fraction), min_step, max_step)
	if absf(diff) <= mag:
		return target
	return value + signf(diff) * mag


static func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c: Node in n.get_children():
		var found: AnimationPlayer = _find_anim(c)
		if found != null:
			return found
	return null
