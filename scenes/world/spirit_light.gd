class_name SpiritLight
extends Node3D

## The pale circle on the ground under the well spirit (`eEC_EFFECT_MAKE_HEM_LIGHT`, `ef_make_hem.c`).
## Arriving it starts at 170 (of 255), fades out as the glow builds, is gone while the spirit
## swaps in, comes back to 50 by tick 175 and stays until the spirit leaves; then `finish` plays the
## other half: 50 down to nothing over 120 ticks, dark until 150, and up to 170 by 195.

const SHADER := preload("res://shaders/spirit_ground_light.gdshader")
const VISUAL := &"ef_circle_light"
const GX := FieldCatalog.GX_TO_METERS
const K := GX / FieldCatalog.PIPELINE_SCALE
const LIFT_GX := 0.1
const SIZE := 0.01
const END_TICK := 195.0

var _age: float = 0.0
var _finishing: bool = false
var _mat: ShaderMaterial


## Under the spirit at `feet` (world metres).
static func start(host: Node, feet: Vector3) -> SpiritLight:
	if host == null:
		return null
	var light := SpiritLight.new()
	light.name = "SpiritLight"
	host.add_child(light)
	light.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * SIZE * K), feet + Vector3(0.0, LIFT_GX * GX, 0.0))
	light._build()
	return light


## The spirit is leaving.
func finish() -> void:
	_finishing = true
	_age = 0.0


func _build() -> void:
	var paths: PackedStringArray = FieldCatalog.mesh_paths(VISUAL)
	var packed: PackedScene = load(paths[0]) as PackedScene if not paths.is_empty() else null
	if packed == null:
		return
	var root: Node = packed.instantiate()
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var src := n as MeshInstance3D
		var mi := MeshInstance3D.new()
		mi.mesh = src.mesh
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_mat.render_priority = 1
		var std := src.get_active_material(0) as StandardMaterial3D
		if std != null:
			_mat.set_shader_parameter(&"tex0", std.albedo_texture)
		for i: int in src.mesh.get_surface_count():
			mi.set_surface_override_material(i, _mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		break
	root.free()


func _process(delta: float) -> void:
	_age += delta * DecompTime.TICK_HZ
	if _mat != null:
		_mat.set_shader_parameter(&"strength", alpha_at(_age, _finishing) / 255.0)
	if _finishing and _age >= END_TICK:
		queue_free()


## `eMHL_mv`: the circle's alpha (0–255) `age` ticks into arriving or leaving.
static func alpha_at(age: float, leaving: bool) -> float:
	if age < 120.0:
		return _adjust(age, 0.0, 119.0, 50.0, 0.0) if leaving else _adjust(age, 0.0, 119.0, 170.0, 0.0)
	if age < 150.0:
		return 0.0
	return _adjust(age, 151.0, 195.0, 0.0, 170.0) if leaving else _adjust(age, 151.0, 175.0, 0.0, 50.0)


static func _adjust(now: float, start: float, end: float, a: float, b: float) -> float:
	if now <= start:
		return a
	if now >= end:
		return b
	return a + (now - start) * ((b - a) / (end - start))
