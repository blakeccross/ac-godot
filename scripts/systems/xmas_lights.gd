class_name XmasLights
extends Node

## `bXI_draw_loop_type1_xtree`: a lit tree's bulbs take one of three tints
## (`gDPSetPrimColor`), stepping every 32 frames (`game_frame & ~0x1F`) from an offset of the
## tree's own (`v0`). Sits under the light model and tints its materials.

const TINTS: Array[Color] = [Color8(255, 255, 100), Color8(100, 255, 255), Color8(255, 100, 255)]
const STEP_FRAMES := 32

var offset: int = 0
var _materials: Array[StandardMaterial3D] = []
var _shown: int = -1


static func attach(lights: Node3D, p_offset: int) -> XmasLights:
	var tint := XmasLights.new()
	tint.name = "Twinkle"
	tint.offset = p_offset
	lights.add_child(tint)
	return tint


## `(frame & ~0x1F) + v0`, mod 3.
static func tint_index(frame: int, p_offset: int) -> int:
	return posmod((frame - posmod(frame, STEP_FRAMES)) + p_offset, TINTS.size())


func _ready() -> void:
	var lights: Node = get_parent()
	for node: Node in lights.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i: int in mi.get_surface_override_material_count():
			var mat := mi.get_active_material(i) as StandardMaterial3D
			if mat == null:
				continue
			var own := mat.duplicate() as StandardMaterial3D
			mi.set_surface_override_material(i, own)
			_materials.append(own)


func _process(_delta: float) -> void:
	var frame: int = int(Time.get_ticks_msec() * DecompTime.FRAME_HZ / 1000.0)
	var idx: int = tint_index(frame, offset)
	if idx == _shown:
		return
	_shown = idx
	for mat: StandardMaterial3D in _materials:
		mat.albedo_color = TINTS[idx]
