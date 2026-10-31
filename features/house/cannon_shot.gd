class_name CannonShot
extends Node3D

## The shell the cannon furniture fires (`ac_iku_mario_taihou` → `eEC_EFFECT_KILLER`,
## `ef_killer.c`): it leaves the piece at 2 GX a tick along the way the piece faces (or
## the opposite, when pressed from its front), crosses the room, slows to half as it nears a
## wall, squashes flat into it, and is gone. A piece already against the wall that way does
## not fire.

const VISUAL := &"act_killer"
const GX := FieldCatalog.GX_TO_METERS
const K := GX / FieldCatalog.PIPELINE_SCALE
const SPEED_GX_PER_TICK := 2.0
const SE_SHOT := &"44f"
## Within this many GX of a wall it is slowed, and squashed over the last 16.
const WALL_SLOW := 20.0
const WALL_SQUASH := 16.0
## A piece this close to the wall it would shoot at stays quiet.
const WALL_BLOCK := 21.0
const MAX_TICKS := 360.0

var _dir: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _bounds: Rect2 = Rect2()
var _slowed: bool = false
var _squash: float = 1.0
var _age: float = 0.0
var _model: Node3D


## Fire from `at` along `yaw` inside `bounds` (world x/z, metres). False when the wall is
## too close to shoot at.
static func fire(host: Node, at: Vector3, yaw: float, bounds: Rect2) -> CannonShot:
	if host == null:
		return null
	var dir := Vector3(sin(yaw), 0.0, cos(yaw))
	if absf(dir.z) > absf(dir.x):
		var edge: float = bounds.end.y if dir.z > 0.0 else bounds.position.y
		if absf(at.z - edge) <= WALL_BLOCK * GX:
			return null
	else:
		var edge_x: float = bounds.end.x if dir.x > 0.0 else bounds.position.x
		if absf(at.x - edge_x) <= WALL_BLOCK * GX:
			return null
	var shot := CannonShot.new()
	shot.name = "CannonShot"
	shot._dir = dir
	shot._yaw = yaw
	shot._bounds = bounds
	host.add_child(shot)
	shot.global_position = at
	shot._build()
	Audio.play_se(SE_SHOT, shot)
	return shot


func _build() -> void:
	var paths: PackedStringArray = FieldCatalog.mesh_paths(VISUAL)
	var packed: PackedScene = load(paths[0]) as PackedScene if not paths.is_empty() else null
	if packed != null:
		_model = packed.instantiate() as Node3D
		add_child(_model)
	else:
		GeneratedVisual.mark_missing(self, VISUAL)
	rotation.y = _yaw
	_apply_scale()


func _process(delta: float) -> void:
	var ticks: float = delta * DecompTime.TICK_HZ
	_age += ticks
	var pos: Vector3 = global_position + _dir * SPEED_GX_PER_TICK * GX * ticks * (0.5 if _slowed else 1.0)
	global_position = pos
	if pos.x < _bounds.position.x or pos.z < _bounds.position.y or pos.x > _bounds.end.x or pos.z > _bounds.end.y or _age >= MAX_TICKS:
		queue_free()
		return
	var edge := INF
	edge = minf(edge, pos.x - _bounds.position.x)
	edge = minf(edge, pos.z - _bounds.position.y)
	edge = minf(edge, _bounds.end.x - pos.x)
	edge = minf(edge, _bounds.end.y - pos.z)
	var dist_gx: float = edge / GX
	if dist_gx < WALL_SLOW:
		_squash = dist_gx / WALL_SQUASH
		_slowed = true
	else:
		_squash = 1.0
	_apply_scale()


func _apply_scale() -> void:
	scale = Vector3(1.0, 1.0, maxf(_squash, 0.001)) * 0.01 * K
