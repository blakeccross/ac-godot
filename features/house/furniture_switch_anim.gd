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
## `fan_kurukuru_data`: game ticks per blade-picture step, by how fast the fan turns (`idx = 9 − 2 ×
## 9 × speed`); −1 holds the picture. The blade is three pictures, each held for two steps.
const FAN_STEP_TICKS: Array[int] = [1, 1, 1, 2, 2, 2, 2, 2, 3, -1]
const FAN_BLADES: Array[String] = [
	"int_nog_fan_fan1_TA_tex_txt", "int_nog_fan_fan2_TA_tex_txt", "int_nog_fan_fan3_TA_tex_txt"
]
## A clip frame a game tick is `speed 0.5`: real time at the pipeline's 30 fps.
const FULL_SPEED := 0.5
const MAX_STEP := 0.25
const SNAP := 0.0005

var _visual_id: StringName = &""
var _anim: AnimationPlayer
var _placement: StringName = &""
var _speed: float = 0.0
var _acc: float = 0.0
var _blades: Array[StandardMaterial3D] = []
var _blade_wait: int = 0
var _blade_frame: int = 0


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
	if visual_id == &"int_nog_fan":
		fx._blades = FurnitureTexAnim.own_bound_materials(visual)
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


## Whether the slot machine's reels are turning (`dynamic_work_s[0]`).
func is_spinning() -> bool:
	return _visual_id == SLOT and _anim != null and _anim.is_playing()


## A piece used (`switch_changed_flag`): the slot machine spins once.
func switched() -> void:
	if _visual_id != SLOT or _anim == null:
		return
	_anim.speed_scale = 1.0
	_anim.play(_anim.get_animation_list()[0])
	_set_spinning(true)
	if not _anim.animation_finished.is_connected(_on_spin_finished):
		_anim.animation_finished.connect(_on_spin_finished)


func _on_spin_finished(_name: StringName) -> void:
	_set_spinning(false)


func _set_spinning(on: bool) -> void:
	var session: IndoorSession = Game.interior_session if Game != null else null
	if session == null or session.room == null:
		return
	var entry: FurniturePlacement = session.room.placement_by_id(_placement)
	if entry != null:
		entry.spinning = on


func _process(delta: float) -> void:
	if not SPIN.has(_visual_id) or _anim == null:
		return
	_acc += delta * DecompTime.TICK_HZ
	var rates: Array = SPIN[_visual_id]
	while _acc >= 1.0:
		_acc -= 1.0
		var on: bool = _is_on()
		_speed = ease_step(_speed, FULL_SPEED if on else 0.0, float(rates[0] if on else rates[1]))
		if not _blades.is_empty():
			_blur_tick()
	_apply()


## `aNogFan_mv`: the blade's picture steps faster the faster it turns, and holds when it has stopped.
func _blur_tick() -> void:
	var idx: int = clampi(int(9.0 - 2.0 * (_speed * 9.0)), 0, FAN_STEP_TICKS.size() - 1)
	var ticks: int = FAN_STEP_TICKS[idx]
	if ticks < 0:
		return
	_blade_wait += 1
	if _blade_wait < ticks:
		return
	_blade_wait = 0
	_blade_frame = (_blade_frame + 1) % (FAN_BLADES.size() * 2)
	var texture: Texture2D = FurnitureTexAnim.texture_named(FAN_BLADES[_blade_frame / 2])
	if texture == null:
		return
	for blade: StandardMaterial3D in _blades:
		blade.albedo_texture = texture


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
