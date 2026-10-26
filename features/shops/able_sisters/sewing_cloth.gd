extends Node3D

## The fabric fed through the sewing machine (`aMSN_DustCloth_c` / `aMSN_MoveDustcloth`,
## `ac_misin.c`). Decomp's 138-frame loop, 1:1:
##   target_idx 0→1→2→3→0, one advance per loop
##   frame 0-97  : slide `target_pos` prev→now corner, hold rotation at prev angle
##   frame 98-119: hold
##   frame 120-137: rotate 90° (prev angle → prev angle + 90°)
## Draw is `RotateY(angle) · translate(-target_pos) · model`, so `angle` spins the
## pivot and `-target_pos` slides the cloth under the needle.

const LOOP := 138
## aMSN_dustcloth_target_table (x, z), scaled to metres for a ~1.4 m quad.
const CORNERS: Array[Vector2] = [Vector2(-4, 4), Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4)]
const CORNER_M := 0.055  ## 1 decomp unit → metres
## target_angle_table
const ANGLES: Array[float] = [0.0, 90.0, -180.0, -90.0]
## `obj_misin_cloth`: the quad lies flat on the bed, its local centre lifted back down.
const VISUAL := &"obj_misin_cloth"
const CLOTH_SCALE := 0.34

@onready var _pivot: Node3D = $Pivot

var _base_rot_y: float
var _frame := 0.0
var _target_idx := 0
## `request_dustcloth_stop_proc` / `_move_proc` — held still while Sable talks.
var running := true


func _ready() -> void:
	_base_rot_y = rotation.y
	_attach_cloth()
	_apply()


## The quad under `Pivot`, wearing a checked shop pattern.
func _attach_cloth() -> void:
	var paths: PackedStringArray = FieldCatalog.mesh_paths(VISUAL)
	if paths.is_empty() or _pivot.get_child_count() > 0:
		return
	var packed: PackedScene = load(paths[0]) as PackedScene
	var quad: Node3D = packed.instantiate() as Node3D if packed != null else null
	if quad == null:
		return
	quad.scale = Vector3.ONE * CLOTH_SCALE
	quad.position = Vector3(0.0, -5.3 * CLOTH_SCALE, 0.0)
	_pivot.add_child(quad)
	var tex := DesignTexture.build(DesignPattern.generate(DesignPattern.Motif.CHECK, 8, 2, 15))
	for mi: Node in quad.find_children("*", "MeshInstance3D", true, false):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		(mi as MeshInstance3D).set_surface_override_material(0, mat)
	VisualFit.disable_shadows(quad)


func _process(delta: float) -> void:
	if not running:
		return
	_frame += delta * DecompTime.TICK_HZ
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
