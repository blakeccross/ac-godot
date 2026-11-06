class_name FurnitureSwitchAnim
extends Node

## Pieces whose clip follows their switch (`aNogFan_mv`, `aSumKisha_mv`, `aSumSlot_mv`).
##
## The fan and the toy train turn at a speed that eases toward 0.5 (a clip frame a game tick: real
## time) while they are on and toward 0 while off (`add_calc(speed, target, ease, 0.25, 0.0005)`), so
## they spin up and coast down instead of starting and stopping dead. They begin at the speed their
## switch gives them.
## The slot machine stands still until it is used, then plays its clip once.

## Visual id → [ease toward on, ease toward off]: `1 - sqrt(1 - rate)` of the decomp's `CALC_EASE`.
const SPIN := {
	&"int_nog_fan": [0.0253, 0.0253],
	&"int_sum_kisha": [0.0253, 0.0513],
}
const SLOT := &"int_sum_slot"
## A clip frame a game tick is `speed 0.5`: real time at the pipeline's 30 fps.
const FULL_SPEED := 0.5
const MAX_STEP := 0.25
const SNAP := 0.0005

var _visual_id: StringName = &""
var _anim: AnimationPlayer
var _placement: StringName = &""
var _speed: float = 0.0
var _acc: float = 0.0


static func wants(visual_id: StringName) -> bool:
	return SPIN.has(visual_id) or visual_id == SLOT


## `piece` (placed furniture `placement`) drawn from `visual`, or null when its clip doesn't follow a switch.
static func attach(piece: Node3D, visual: Node, visual_id: StringName, placement: StringName) -> FurnitureSwitchAnim:
	if piece == null or visual == null or not wants(visual_id):
		return null
	var anim: AnimationPlayer = VisualAnimation.find_animation_player(visual)
	if anim == null or anim.get_animation_list().is_empty():
		return null
	var fx := FurnitureSwitchAnim.new()
	fx.name = "FurnitureSwitchAnim"
	fx._visual_id = visual_id
	fx._anim = anim
	fx._placement = placement
	fx.process_priority = 100
	piece.add_child(fx)
	if visual_id == SLOT:
		anim.stop()
		anim.seek(0.0, true)
	else:
		fx._speed = FULL_SPEED if fx._is_on() else 0.0
		fx._apply()
	return fx


## One step of `add_calc`: `value` toward `target`, at most `MAX_STEP` a tick, snapping when close.
static func ease_step(value: float, target: float, rate: float) -> float:
	if absf(target - value) < SNAP:
		return target
	return value + clampf((target - value) * rate, -MAX_STEP, MAX_STEP)


## A piece used (`switch_changed_flag`): the slot machine spins once.
func switched() -> void:
	if _visual_id != SLOT or _anim == null:
		return
	_anim.speed_scale = 1.0
	_anim.play(_anim.get_animation_list()[0])


func _process(delta: float) -> void:
	if not SPIN.has(_visual_id) or _anim == null:
		return
	_acc += delta * DecompTime.TICK_HZ
	var rates: Array = SPIN[_visual_id]
	while _acc >= 1.0:
		_acc -= 1.0
		var on: bool = _is_on()
		_speed = ease_step(_speed, FULL_SPEED if on else 0.0, float(rates[0] if on else rates[1]))
	_apply()


func _apply() -> void:
	if _speed <= 0.0:
		if _anim.is_playing():
			_anim.pause()
		return
	_anim.speed_scale = _speed / FULL_SPEED
	if not _anim.is_playing():
		_anim.play(_anim.get_animation_list()[0])


func _is_on() -> bool:
	var session: IndoorSession = Game.interior_session if Game != null else null
	if session == null or session.room == null:
		return true
	var entry: FurniturePlacement = session.room.placement_by_id(_placement)
	return entry == null or entry.on
