extends Node3D

## Base for an authored public interior (Nook, Able Sisters, police, post).
## Shell GLBs live under `Shell/GeneratedVisual`; `populate()` fits the shell,
## builds collision + doors, places data-driven furniture, then calls
## `present_exhibits()` — which each building's subclass overrides to spawn its
## own shopkeeper / stock / fixtures (mirrors `museum_room.gd`).
## F6 on the `.tscn` alone bootstraps a camera + light; play normally via `interior.tscn`.

@export var room_id: StringName = &""

var _session: Interior = null


func _ready() -> void:
	if get_tree() != null and get_tree().current_scene == self:
		_bootstrap_standalone_preview()


func populate() -> void:
	if room_id == &"" or Game == null:
		return
	var room: Room = Game.interiors.room(room_id)
	if room == null:
		return
	_session = Interior.new()
	_session.bind(room)
	InteriorBuilder.new().populate_authored(self, _session)


## Override per building. `interior.gd` also calls this to refresh shop stock /
## public props after a purchase, so keep it idempotent.
func present_exhibits(_furniture: Node3D, _interior: Interior) -> void:
	pass


func _bootstrap_standalone_preview() -> void:
	## Content fragment: no host camera / `populate()` unless we add them here.
	populate()
	var look := _preview_look_point()
	var cam := Camera3D.new()
	cam.name = "StandalonePreviewCamera"
	cam.position = look + Vector3(0.0, 10.0, 14.0)
	add_child(cam)
	cam.look_at(look)
	cam.current = true
	var light := DirectionalLight3D.new()
	light.name = "StandalonePreviewLight"
	light.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	light.light_energy = 1.1
	add_child(light)
	var world_env := WorldEnvironment.new()
	world_env.name = "StandalonePreviewEnv"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.38, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.82, 0.78)
	env.ambient_light_energy = 1.1
	world_env.environment = env
	add_child(world_env)


func _preview_look_point() -> Vector3:
	if _session == null or _session.room == null or _session.grid == null:
		return Vector3.ZERO
	var room: Room = _session.room
	var grid: WorldGrid = _session.grid
	var nw: Vector3 = grid.cell_corner(room.inner_origin)
	var size := Vector3(
		float(maxi(room.inner_size.x, 1)) * grid.cell_size,
		0.0,
		float(maxi(room.inner_size.y, 1)) * grid.cell_size
	)
	return Vector3(nw.x + size.x * 0.5, 0.0, nw.z + size.z * 0.5)
