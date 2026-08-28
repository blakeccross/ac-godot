extends Node3D

## Outdoor plot. Lighting follows `m_kankyo` fine-weather terms via Clock.

const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")

@export var data: AcreData

@onready var _sun: DirectionalLight3D = $Sun
@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _spawn: Marker3D = $PlayerSpawn
@onready var _camera: Camera3D = $FollowCamera


func _ready() -> void:
	Game.notify_world_ready()
	Clock.time_changed.connect(_apply_time_of_day)
	_apply_time_of_day()
	_spawn_player()


func _spawn_player() -> void:
	var player: CharacterBody3D = PLAYER_SCENE.instantiate() as CharacterBody3D
	add_child(player)
	var pos := Game.player_position
	if pos.is_equal_approx(Game.DEFAULT_SPAWN):
		pos = _spawn.global_position
	player.apply_spawn(pos, Game.player_yaw)
	if _camera.has_method("set_target"):
		_camera.call("set_target", player)


func _apply_time_of_day() -> void:
	var hour_frac: float = float(Clock.hour) + float(Clock.minute) / 60.0
	var angle: float = deg_to_rad((hour_frac / 24.0) * 360.0 - 90.0)
	_sun.rotation.x = -angle
	_sun.rotation.y = deg_to_rad(-40.0)

	var pal: Dictionary = Clock.outdoor_light()
	_sun.light_energy = float(pal["energy"])
	_sun.light_color = pal["sun"] as Color
	var env: Environment = _world_env.environment
	env.ambient_light_color = pal["ambient"] as Color
	env.ambient_light_energy = float(pal["energy"]) * 0.45 + 0.15
