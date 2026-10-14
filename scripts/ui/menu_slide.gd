class_name MenuSlide
extends Node

## The submenus' shared slide (`m_submenu_ovl.c`): a menu opens from its start position
## (`mSM_set_new_start_data`, 300 units off one edge at speed 75) and glides in, slowing
## past 120 units out (`mSM_move_Move` → `mSM_move_menu`); on closing it speeds away
## the other way, doubling every other tick up to 75, until it is 300 units out.
##
## Those moves take 14 ticks in and 13 out; here they are quadratic eases over the same
## times (fast then slowing in, slowing then fast out), which trace the same path.
## Positions are the menu's `menu_info->position` in screen units, y up; the owner's
## CanvasLayer is offset by them (scaled like a 320x240 screen fitted to the viewport),
## so every layer the menu draws rides along.

enum Dir { OUT_RIGHT, IN_RIGHT, OUT_LEFT, IN_LEFT, OUT_TOP, IN_TOP, OUT_BOTTOM, IN_BOTTOM }

## How far off screen a menu starts and ends (`move_data` targets).
const OFF_SCREEN := 300.0
const IN_SEC := 14.0 / DecompTime.TICK_HZ
const OUT_SEC := 13.0 / DecompTime.TICK_HZ

signal moved(position: Vector2)

var position := Vector2.ZERO

var _dir: int = -1
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _elapsed: float = 0.0
var _done := Callable()
var _layer: CanvasLayer = null


## A slide that offsets `layer`.
static func attach(layer: CanvasLayer) -> MenuSlide:
	var slide := MenuSlide.new()
	slide.name = "MenuSlide"
	slide._layer = layer
	slide.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(slide)
	return slide


## `IN_*` start positions for a direction: the edge the menu comes in from.
static func start_for(dir: int) -> Vector2:
	match dir:
		Dir.IN_RIGHT:
			return Vector2(300.0, 0.0)
		Dir.IN_LEFT:
			return Vector2(-300.0, 0.0)
		Dir.IN_TOP:
			return Vector2(0.0, 300.0)
		Dir.IN_BOTTOM:
			return Vector2(0.0, -300.0)
	return Vector2.ZERO


func _ready() -> void:
	set_process(false)


func is_moving() -> bool:
	return _dir >= 0


## Open: jump to the start position and glide in.
func slide_in(dir: int) -> void:
	position = start_for(dir)
	_begin(dir, Callable())


## Close: speed away; `done` runs once the menu is off screen.
func slide_out(dir: int, done: Callable = Callable()) -> void:
	_begin(dir, done)


## Snap back to rest (e.g. a menu reopened mid-slide).
func settle() -> void:
	_dir = -1
	_done = Callable()
	position = Vector2.ZERO
	_apply()
	set_process(false)


func _begin(dir: int, done: Callable) -> void:
	_dir = dir
	_done = done
	_from = position
	_to = Vector2.ZERO
	if (dir & 1) == 0:
		## An OUT move leaves along its axis, the way its direction points.
		var sgn: float = -1.0 if (dir & 2) != 0 else 1.0
		_to = position
		_to[dir >> 2] = OFF_SCREEN * sgn
	_elapsed = 0.0
	_apply()
	set_process(true)


func _process(delta: float) -> void:
	step(delta)
	_apply()
	if _dir < 0:
		set_process(false)


## `mSM_move_menu` over `delta` seconds; true when the move finished.
func step(delta: float) -> bool:
	if _dir < 0:
		return true
	var going_in: bool = (_dir & 1) == 1
	var duration: float = IN_SEC if going_in else OUT_SEC
	_elapsed = minf(_elapsed + maxf(delta, 0.0), duration)
	## Frame times summed in floats can fall a hair short of the duration.
	if _elapsed > duration - 0.000001:
		_elapsed = duration
	position = Tween.interpolate_value(
		_from, _to - _from, _elapsed, duration, Tween.TRANS_QUAD,
		Tween.EASE_OUT if going_in else Tween.EASE_IN
	)
	var finished: bool = _elapsed >= duration
	if finished:
		position = _to
	if finished:
		var done := _done
		_dir = -1
		_done = Callable()
		if done.is_valid():
			done.call()
	return finished


func _apply() -> void:
	var k: float = 1.0
	if is_inside_tree():
		var vs: Vector2 = get_viewport().get_visible_rect().size
		k = minf(vs.x / 320.0, vs.y / 240.0)
	if _layer != null:
		_layer.offset = Vector2(position.x, -position.y) * k
	moved.emit(position)
