class_name TitleLogoState
extends RefCounted

## The title logo actor (`ac_animal_logo.c`), as a frame-stepped state machine. Everything is
## counted in 60 Hz ticks. The presentation (`title_logo.tscn`) reads the public fields and
## calls `tick()` once per tick; nothing here touches the scene tree.
##
## IN → BACK_FADE_IN → START_KEY_CHK_START → GAME_START → FADE_OUT_START → OUT
##                                              └→ IDLE once the demo has run out
## START or A during IN / BACK_FADE_IN skips straight to START_KEY_CHK_START.

enum Action {
	IN,
	BACK_FADE_IN,
	START_KEY_CHK_START,
	GAME_START,
	FADE_OUT_START,
	OUT,
	IDLE,
}

## `cKF_SkeletonInfo_R_init(..., start 1, end 121, ..., speed 0.5)`: (121 − 1) / 0.5 ticks.
## At 60 Hz that is the 4.0 s the baked `logo_us_*` clips run.
const IN_TICKS := 240
const IN_SECONDS := 4.0
const BACK_FADEIN_RATE := 20
const BACK_FADEIN_MAX := 220
## `aAL_TIMER`: hold after the logo lands before START is accepted.
const TIMER := 60
## `aAL_FADEOUT_TIMER`: solid "PRESS START" while the start chime plays.
const FADEOUT_TIMER := 26
## `aAL_copyright_draw`: the copyright line adds this per draw, but the state init already
## sets 255, so it is on screen at full strength the moment the logo lands.
const COPYRIGHT_ALPHA_RATE := 63
## `aAL_game_start_wait`: phase step (in s16 angle units) — 32768 / 50 while the phase is
## positive, 32768 / 22 otherwise. The negative half therefore runs ~2.3x faster.
const PULSE_STEP_POSITIVE := 655
const PULSE_STEP_NONPOSITIVE := 1489
## `sAdo_SysTrgStart(0x44D)` at FADE_OUT_START.
const START_SE_ID := 0x44D

var action: Action = Action.IN
var back_opacity: int = 0
var copyright_opacity: int = 0
var press_start_opacity: float = 0.0
var title_timer: int = 0
## Ticks the three skeleton clips have played (clamped at `IN_TICKS`).
var in_ticks: int = 0
## True for exactly the tick FADE_OUT_START hands over to OUT
## (`aAL_title_game_data_init_start_select`); the caller fades to black and leaves.
var select_requested: bool = false
## True for exactly the tick FADE_OUT_START begins (the start chime).
var start_chime_requested: bool = false

var _pulse_phase: int = 0


## `start_pressed`: START or A newly pressed this tick.
## `can_start`: land loaded and the fade-in finished (`mLd_CheckStartFlag`, `aAL_wipe_end_check`).
## `button_ok`: `mTD_tdemo_button_ok_check` — false once the demo is nearly over.
## `demo_ended`: the demo has run out (`FADE_TYPE_SELECT_END`).
func tick(
	start_pressed: bool, can_start: bool = true, button_ok: bool = true, demo_ended: bool = false
) -> void:
	select_requested = false
	start_chime_requested = false
	if title_timer > 0:
		title_timer -= 1
	match action:
		Action.IN:
			if start_pressed:
				_set_action(Action.START_KEY_CHK_START)
				return
			in_ticks = mini(in_ticks + 1, IN_TICKS)
			if in_ticks >= IN_TICKS:
				_set_action(Action.BACK_FADE_IN)
		Action.BACK_FADE_IN:
			if start_pressed:
				_set_action(Action.START_KEY_CHK_START)
				return
			back_opacity += BACK_FADEIN_RATE
			if back_opacity > BACK_FADEIN_MAX:
				back_opacity = BACK_FADEIN_MAX
				_set_action(Action.START_KEY_CHK_START)
		Action.START_KEY_CHK_START:
			if title_timer <= 0:
				_set_action(Action.GAME_START)
		Action.GAME_START:
			_pulse()
			if demo_ended:
				_set_action(Action.IDLE)
			elif start_pressed and can_start and button_ok:
				_set_action(Action.FADE_OUT_START)
		Action.FADE_OUT_START:
			if title_timer <= 0:
				select_requested = true
				_set_action(Action.OUT)
		_:
			pass


## Seconds into the 4 s logo clips.
func anim_seconds() -> float:
	return float(in_ticks) / DecompTime.TICK_HZ


func back_visible() -> bool:
	return action >= Action.BACK_FADE_IN


## The copyright line and the TM mark (`action >= aAL_ACTION_START_KEY_CHK_START`).
func copyright_visible() -> bool:
	return action >= Action.START_KEY_CHK_START


func press_start_visible() -> bool:
	return action == Action.GAME_START or action == Action.FADE_OUT_START or action == Action.OUT


func is_leaving() -> bool:
	return action == Action.OUT


func _set_action(next: Action) -> void:
	match next:
		Action.START_KEY_CHK_START:
			## `aAL_start_key_chk_start_wait_init`: snap every clip to its last frame.
			in_ticks = IN_TICKS
			copyright_opacity = 255
			back_opacity = BACK_FADEIN_MAX
			title_timer = TIMER
		Action.FADE_OUT_START:
			press_start_opacity = 255.0
			title_timer = FADEOUT_TIMER
			start_chime_requested = true
	action = next


func _pulse() -> void:
	var step: int = PULSE_STEP_POSITIVE if _pulse_phase > 0 else PULSE_STEP_NONPOSITIVE
	_pulse_phase = MLib.s16_signed(_pulse_phase + step)
	var opacity: float = 127.5 * sin(float(_pulse_phase) * MLib.S16) + 127.5
	press_start_opacity = clampf(opacity, 0.0, 255.0)
