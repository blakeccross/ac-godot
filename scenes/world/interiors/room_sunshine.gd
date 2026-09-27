extends Node3D

## One window beam (`ef_room_sunshine`): `room_lightL` for the west window
## (`actor_specific` 2), `room_lightR` for the east one (3). Placed by `WindowSunshine`,
## which also holds the timing. Unlike the police box beam, each side has its own model,
## both stretch along +X, and there is no camera cull. `light_switch` rooms (homes) keep
## the window light partly open at every hour.

const SHADER := preload("res://shaders/room_sunshine.gdshader")

@export var left: bool = true
@export var light_switch: bool = false

var _pivot: Node3D
var _base_scale: float = 1.0
var _materials: Array[ShaderMaterial] = []
var _window_alpha: float = -1.0


func _ready() -> void:
	_pivot = GeneratedVisual.attach_datum(
		self, WindowSunshine.VISUAL_L if left else WindowSunshine.VISUAL_R
	)
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
	var target: float = WindowSunshine.window_light_target(now, light_switch)
	if _window_alpha < 0.0:
		## Scene entry resets the ramp with a step of 1 (`enabled == FALSE`): it lands at once.
		_window_alpha = target
	else:
		_window_alpha = move_toward(_window_alpha, target, PoliceDisplay.WINDOW_LIGHT_RATE * delta)
	var stretch: float = WindowSunshine.stretch(now, left)
	var raining: bool = Game != null and (Game.weather == &"rain" or Game.weather == &"snow")
	var alpha: float = float(PoliceDisplay.sunshine_alpha(now, raining)) / 255.0 * _window_alpha
	var show: bool = _window_alpha >= 0.0001 and stretch != 0.0
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
			mat.shader = SHADER
			## The shaft has no texture: its coverage is the vertex alpha.
			mat.set_shader_parameter("shade_alpha", tex == null)
			mat.set_shader_parameter("albedo_texture", VisualWindowLight.coverage_texture(tex))
			mesh_instance.set_surface_override_material(i, mat)
			_materials.append(mat)
	for child: Node in node.get_children():
		_swap_materials(child)
