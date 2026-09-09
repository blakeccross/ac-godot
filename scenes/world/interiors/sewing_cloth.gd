extends Node3D

## The fabric fed through the sewing machine (`aMSN_DustCloth_c` / `aMSN_MoveDustcloth`,
## `ac_misin.c`). Decomp's 138-frame loop, 1:1:
##   target_idx 0→1→2→3→0, one advance per loop
##   frame 0-97  : slide `target_pos` prev→now corner, hold rotation at prev angle
##   frame 98-119: hold
##   frame 120-137: rotate 90° (prev angle → prev angle + 90°)
## Draw is `RotateY(angle) · translate(-target_pos) · model`, so `angle` spins the
## pivot and `-target_pos` slides the cloth under the needle.

const FPS := 60.0
const LOOP := 138
## aMSN_dustcloth_target_table (x, z), scaled to metres for a ~1.4 m quad.
const CORNERS: Array[Vector2] = [Vector2(-4, 4), Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4)]
const CORNER_M := 0.055  ## 1 decomp unit → metres
## target_angle_table
const ANGLES: Array[float] = [0.0, 90.0, -180.0, -90.0]

@onready var _pivot: Node3D = $Pivot

var _base_rot_y: float
var _frame := 0.0
var _target_idx := 0


func _ready() -> void:
	_base_rot_y = rotation.y
	_apply()


func _process(delta: float) -> void:
	_frame += delta * FPS
	if _frame >= LOOP:
		_frame -= LOOP
		_target_idx = (_target_idx + 1) % 4
	_apply()


func _apply() -> void:
	var prev := (_target_idx - 1) & 3
	var offset: Vector2
	var angle_deg: float
	if _frame < 98.0:
		var p := _frame / 97.0
		offset = CORNERS[prev].lerp(CORNERS[_target_idx], p)
		angle_deg = ANGLES[prev]
	elif _frame < 120.0:
		offset = CORNERS[_target_idx]
		angle_deg = ANGLES[prev]
	else:
		var p := (_frame - 120.0) / 18.0
		offset = CORNERS[_target_idx]
		angle_deg = ANGLES[prev] + p * 90.0
	rotation.y = _base_rot_y + deg_to_rad(angle_deg)
	if _pivot != null:
		_pivot.position.x = -offset.x * CORNER_M
		_pivot.position.z = -offset.y * CORNER_M
