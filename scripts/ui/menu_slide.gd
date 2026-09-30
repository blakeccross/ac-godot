class_name MenuSlide
extends Node

## The submenus' shared slide (`m_submenu_ovl.c`): a menu opens from its start position
## (`mSM_set_new_start_data`, 300 units off one edge at speed 75) and glides in, slowing
## past 120 units out (`mSM_move_Move` → `mSM_move_menu`); on closing it speeds away
## the other way, doubling every other frame up to 75, until it is 300 units out.
## Positions are the menu's `menu_info->position` in screen units, y up; the owner's
## CanvasLayer is offset by them (scaled like a 320x240 screen fitted to the viewport),
## so every layer the menu draws rides along.

enum Dir { OUT_RIGHT, IN_RIGHT, OUT_LEFT, IN_LEFT, OUT_TOP, IN_TOP, OUT_BOTTOM, IN_BOTTOM }

## `mSM_move_Move` `move_data`: {speed multiplier, where the multiplier starts, target,
## direction}, for out (even) and in (odd) moves.
const OUT_MOVE := [2.0, 0.0, 300.0, 1.0]
const IN_MOVE := [0.5, 120.0, 0.0, -1.0]
const START_SPEED := 75.0

signal moved(position: Vector2)

var position := Vector2.ZERO

var _speed := Vector2.ZERO
var _dir: int = -1
var _flag: bool = false
var _accum: float = 0.0
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
	_speed = Vector2(START_SPEED, START_SPEED)
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
	_flag = false
	_done = done
	_accum = 0.0
	_apply()
	set_process(true)


func _process(delta: float) -> void:
	_accum += delta * DecompTime.TICK_HZ
	var steps: int = 0
	while _accum >= 1.0 and _dir >= 0 and steps < 8:
		_accum -= 1.0
		steps += 1
		step()
	_apply()
	if _dir < 0:
		set_process(false)


## One decomp frame of `mSM_move_menu`; true when the move finished.
func step() -> bool:
	if _dir < 0:
		return true
	var axis: int = _dir >> 2
	var data: Array = IN_MOVE if (_dir & 1) == 1 else OUT_MOVE
	var sgn: float = -1.0 if (_dir & 2) != 0 else 1.0
	var p0: float = float(data[1]) * sgn
	var p1: float = float(data[2]) * sgn
	var p2: float = float(data[3]) * sgn
	var pos: float = position[axis]
	var speed: float = _speed[axis]
	if not _flag:
		if p2 * (pos - p0) >= 0.0:
			speed = clampf(speed * float(data[0]), 1.0, START_SPEED)
		_flag = true
	else:
		_flag = false
	pos += speed * p2 * 0.5
	var finished: bool = p2 * (pos - p1) > 0.0
	if finished:
		_flag = false
		pos = p1
	position[axis] = float(int(pos))
	_speed[axis] = speed
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
