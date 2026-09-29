extends Node3D

## One police box window beam (`ef_room_sunshine_police`, `obj_koban_shine_modelT`).
## The left (west, `actor_specific` 2) beam shows at 00–04 and 12–20, the right (east, 3)
## one at 04–12 and 20–24, each stretched along X by `PoliceDisplay.sunshine_*_x`. Alpha is
## `sunshine_alpha × windowlight_alpha`; colour is the window sun colour 04–20, else moon.
## The police box has no light switch, so `windowlight_alpha` only opens 05:00–18:00.
## The post office beam (`ef_room_sunshine_posthouse`) is the same effect with its own
## model (`visual`), a 0.05 scale and no camera cull; so are the museum's
## (`ef_room_sunshine_museum` / `_minsect`, no cull). The entrance hall's beam is coloured
## by its stained-glass texture (`stained_glass`, `museum_sunshine.gdshader`).

const SHADER := preload("res://shaders/police_sunshine.gdshader")
const STAINED_GLASS_SHADER := preload("res://shaders/museum_sunshine.gdshader")

@export var left: bool = true
@export var visual: StringName = PoliceDisplay.SUNSHINE_VISUAL
@export var cull: bool = true
@export var stained_glass: bool = false

var _pivot: Node3D
var _base_scale: float = 1.0
var _materials: Array[ShaderMaterial] = []
var _window_alpha: float = -1.0


func _ready() -> void:
	_pivot = GeneratedVisual.attach_datum(self, visual)
	if _pivot == null:
		return
	_base_scale = _pivot.scale.y
	_swap_materials(_pivot)
	_tick(0.0)


func _process(delta: float) -> void:
	_tick(delta)


func _tick(delta: float) -> void:
	if _pivot == null or Clock == null:
		return
	var now: int = Clock.now_sec()
	var target: float = PoliceDisplay.window_light_target(now)
	if _window_alpha < 0.0:
		## Scene entry resets the ramp with a step of 1 (`enabled == FALSE`): it lands at once.
		_window_alpha = target
	else:
		_window_alpha = move_toward(_window_alpha, target, PoliceDisplay.WINDOW_LIGHT_RATE * delta)
	var stretch: float = (
		PoliceDisplay.sunshine_left_x(now) if left else PoliceDisplay.sunshine_right_x(now)
	)
	var raining: bool = Game != null and (Game.weather == &"rain" or Game.weather == &"snow")
	var alpha: float = float(PoliceDisplay.sunshine_alpha(now, raining)) / 255.0 * _window_alpha
	var show: bool = _window_alpha >= 0.0001 and stretch != 0.0 and not _culled()
	_pivot.visible = show
	if not show:
		return
	_pivot.scale = Vector3(_base_scale * stretch, _base_scale, _base_scale)
	var palette: Dictionary = Clock.outdoor_light()
	var key: String = "window_sun" if PoliceDisplay.sunshine_uses_sun(now) else "window_moon"
	var tint: Color = palette.get(key, Color.WHITE) as Color
	tint.a = alpha
	for mat: ShaderMaterial in _materials:
		mat.set_shader_parameter("prim", tint)


## `cull_check_from_camera`: the left beam hides once the camera eye is at or west of it,
## the right beam once the eye is at or east of it.
func _culled() -> bool:
	if not cull:
		return false
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return false
	var eye_x: float = cam.global_position.x
	if left:
		return eye_x <= global_position.x
	return eye_x >= global_position.x


func _swap_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 0
		for i: int in count:
			## The imported material: `VisualMaterials` may already have swapped a
			## `ground_spill` patch for a shader that hides its texture.
			var src: Material = mesh_instance.mesh.surface_get_material(i)
			var tex: Texture2D = null
			if src is BaseMaterial3D:
				tex = (src as BaseMaterial3D).albedo_texture
			var mat := ShaderMaterial.new()
			if stained_glass:
				## The shaft's second texture (its fade) comes in as the AO texture on UV2.
				var fade: Texture2D = (src as BaseMaterial3D).ao_texture if src is BaseMaterial3D else null
				mat.shader = STAINED_GLASS_SHADER
				mat.set_shader_parameter("albedo_texture", tex)
				mat.set_shader_parameter("fade_texture", fade)
				mat.set_shader_parameter("shaft", fade != null)
			else:
				mat.shader = SHADER
				mat.set_shader_parameter("albedo_texture", VisualWindowLight.coverage_texture(tex))
			mesh_instance.set_surface_override_material(i, mat)
			_materials.append(mat)
	for child: Node in node.get_children():
		_swap_materials(child)
