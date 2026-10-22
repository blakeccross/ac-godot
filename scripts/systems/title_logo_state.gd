class_name TitleLogoState
extends RefCounted

## The title logo actor (`ac_animal_logo.c`) as a state machine, run on `delta` in seconds.
## The presentation (`title_logo.tscn`) calls `update()` every frame and reads the public
## fields; nothing here touches the scene tree.
##
## IN → BACK_FADE_IN → START_KEY_CHK_START → GAME_START → FADE_OUT_START → OUT
##                                              └→ IDLE once the demo has run out
## START or A during IN / BACK_FADE_IN skips straight to START_KEY_CHK_START.

## FADE_OUT_START begins (`sAdo_SysTrgStart(0x44D)`, the start chime).
signal start_chime
## FADE_OUT_START hands over to OUT (`aAL_title_game_data_init_start_select`): the owner
## fades to black and leaves.
signal start_selected

enum Action {
	IN,
	BACK_FADE_IN,
	START_KEY_CHK_START,
	GAME_START,
	FADE_OUT_START,
	OUT,
	IDLE,
}

## `cKF_SkeletonInfo_R_init(..., start 1, end 121, ..., speed 0.5)`: the 4 s the baked
## `logo_us_*` clips run.
const IN_SECONDS := 4.0
## The backdrop fades in at 20/255 a tick, up to 220/255.
const BACK_FADEIN_RATE := 20.0 / 255.0 * 60.0
const BACK_FADEIN_MAX := 220.0 / 255.0
## `aAL_TIMER`: 60 ticks' hold after the logo lands before START is accepted.
const HOLD_TIME := 1.0
## `aAL_FADEOUT_TIMER`: 26 ticks of solid "PRESS START" while the start chime plays.
const FADEOUT_TIME := 26.0 / 60.0
## `aAL_game_start_wait`: the pulse phase turns 32768/50 s16 a tick while positive and
## 32768/22 otherwise, so the dim half runs ~2.3× faster. In rad/s.
const PULSE_RATE_POSITIVE := 655.0 * MathUtil.S16 * 60.0
const PULSE_RATE_NONPOSITIVE := 1489.0 * MathUtil.S16 * 60.0

var action: Action = Action.IN
## 0–1.
var back_opacity: float = 0.0
var copyright_opacity: float = 0.0
var press_start_opacity: float = 0.0
## Seconds left on the current hold (START_KEY_CHK_START / FADE_OUT_START).
var hold_left: float = 0.0
## Seconds the three skeleton clips have played (up to `IN_SECONDS`).
var in_time: float = 0.0

## Radians, in (−π, π].
var _pulse_phase: float = 0.0


## `start_pressed`: START or A newly pressed since the last update.
## `can_start`: land loaded and the fade-in finished (`mLd_CheckStartFlag`, `aAL_wipe_end_check`).
## `button_ok`: `mTD_tdemo_button_ok_check` — false once the demo is nearly over.
## `demo_ended`: the demo has run out (`FADE_TYPE_SELECT_END`).
func update(
	delta: float, start_pressed: bool, can_start: bool = true, button_ok: bool = true,
	demo_ended: bool = false
) -> void:
	hold_left = maxf(hold_left - delta, 0.0)
	if hold_left < 1e-4:
		hold_left = 0.0
	match action:
		Action.IN:
			if start_pressed:
				_set_action(Action.START_KEY_CHK_START)
				return
			in_time = minf(in_time + delta, IN_SECONDS)
			## A hair of slack so frame sums like 240 × 1/60 land on time.
			if in_time >= IN_SECONDS - 1e-4:
				in_time = IN_SECONDS
				_set_action(Action.BACK_FADE_IN)
		Action.BACK_FADE_IN:
			if start_pressed:
				_set_action(Action.START_KEY_CHK_START)
				return
			back_opacity = minf(back_opacity + BACK_FADEIN_RATE * delta, BACK_FADEIN_MAX)
			if back_opacity >= BACK_FADEIN_MAX:
				_set_action(Action.START_KEY_CHK_START)
		Action.START_KEY_CHK_START:
			if hold_left <= 0.0:
				_set_action(Action.GAME_START)
		Action.GAME_START:
			_pulse(delta)
			if demo_ended:
				_set_action(Action.IDLE)
			elif start_pressed and can_start and button_ok:
				_set_action(Action.FADE_OUT_START)
		Action.FADE_OUT_START:
			if hold_left <= 0.0:
				_set_action(Action.OUT)
				start_selected.emit()
		_:
			pass


## Seconds into the 4 s logo clips.
func anim_seconds() -> float:
	return in_time


func back_visible() -> bool:
	return action >= Action.BACK_FADE_IN


## When the TM mark (and originally the copyright line) would show
## (`action >= aAL_ACTION_START_KEY_CHK_START`). Presentation skips the copyright text.
func copyright_visible() -> bool:
	return action >= Action.START_KEY_CHK_START


func press_start_visible() -> bool:
	return action == Action.GAME_START or action == Action.FADE_OUT_START or action == Action.OUT


## Test-only: no in-game callers; kept for tests.
func is_leaving() -> bool:
	return action == Action.OUT


func _set_action(next: Action) -> void:
	match next:
		Action.START_KEY_CHK_START:
			## `aAL_start_key_chk_start_wait_init`: snap every clip to its last frame.
			in_time = IN_SECONDS
			copyright_opacity = 1.0
			back_opacity = BACK_FADEIN_MAX
			hold_left = HOLD_TIME
		Action.FADE_OUT_START:
			press_start_opacity = 1.0
			hold_left = FADEOUT_TIME
	action = next
	if next == Action.FADE_OUT_START:
		start_chime.emit()


## Turns the pulse phase by `delta`, switching speed exactly where it crosses 0 and ±π.
func _pulse(delta: float) -> void:
	var left: float = delta
	while left > 0.0:
		if _pulse_phase > 0.0:
			## Bright half: slow, up to π, which wraps round to −π.
			var to_wrap: float = (PI - _pulse_phase) / PULSE_RATE_POSITIVE
			if left < to_wrap:
				_pulse_phase += PULSE_RATE_POSITIVE * left
				break
			_pulse_phase = -PI
			left -= to_wrap
		else:
			## Dim half: fast, up to 0, where the bright half takes over.
			var to_zero: float = -_pulse_phase / PULSE_RATE_NONPOSITIVE
			if left < to_zero:
				_pulse_phase += PULSE_RATE_NONPOSITIVE * left
				break
			left -= to_zero
			_pulse_phase = 1e-6
	press_start_opacity = clampf(0.5 * sin(_pulse_phase) + 0.5, 0.0, 1.0)
