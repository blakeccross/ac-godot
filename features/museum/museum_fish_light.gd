class_name MuseumFishLight
extends Node

## The two cyan tank lights (`mfish_point_ligh_pos_get`). They sit on the tank
## the player is standing at and fade over 60 GX. Positions are room GX.


const GLOW_COLOR := Color8(0, 150, 255)
const GLOW_REACH := 60.0
const GLOW_POWER := 55.0
const _TANKS: Array[Vector3] = [
	Vector3(220.0, 40.0, 220.0),
	Vector3(420.0, 40.0, 220.0),
	Vector3(220.0, 40.0, 460.0),
	Vector3(420.0, 40.0, 460.0),
	Vector3(320.0, 40.0, 20.0),
]

var _origin := Vector3.ZERO


func setup(origin: Vector3) -> void:
	_origin = origin
	_publish_color()


func _process(_delta: float) -> void:
	var player := Player.find(get_tree()) as Node3D
	if player == null:
		return
	var gx: Vector3 = (player.global_position - _origin) / FieldCatalog.GX_TO_METERS
	var glows: Array[Dictionary] = glow_gx(gx)
	for i: int in 2:
		var glow: Dictionary = glows[i]
		var world: Vector3 = _origin + (glow["pos"] as Vector3) * FieldCatalog.GX_TO_METERS
		var radius: float = float(glow["power"]) * FieldCatalog.GX_TO_METERS
		RenderingServer.global_shader_parameter_set(StringName("field_glow%d_pos" % i), world)
		RenderingServer.global_shader_parameter_set(StringName("field_glow%d_radius" % i), radius)


## Two lights for a player at `player_gx` (room GX). `power` is the point radius;
## 0 means the player is not in front of a tank.
static func glow_gx(player_gx: Vector3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in 2:
		var tank: int = _tank_for(player_gx.z, i)
		if tank < 0:
			out.append({"pos": player_gx, "power": 0.0})
		else:
			out.append(_one(player_gx, tank, i))
	return out


static func clear_glow() -> void:
	RenderingServer.global_shader_parameter_set(&"field_glow0_radius", 0.0)
	RenderingServer.global_shader_parameter_set(&"field_glow1_radius", 0.0)


static func _publish_color() -> void:
	var c := GLOW_COLOR
	RenderingServer.global_shader_parameter_set(&"field_glow_color", Vector3(c.r, c.g, c.b))


static func _tank_for(player_z: float, index: int) -> int:
	if player_z < 100.0:
		return 4
	if player_z > 100.0 and player_z < 340.0:
		return 0 if index == 0 else 1
	if player_z > 340.0 and player_z < 580.0:
		return 2 if index == 0 else 3
	return -1


static func _one(player: Vector3, tank_index: int, light_index: int) -> Dictionary:
	var tank: Vector3 = _TANKS[tank_index]
	var pos := player
	var left: float
	var right: float
	var down: float
	var up: float
	if tank_index < 4:
		left = 60.0
		right = 60.0
		down = 60.0
		up = 60.0
	else:
		left = 200.0
		right = 200.0
		down = 20.0
		up = 35.0
		pos.x += -down if light_index == 0 else down
	pos.x = clampf(pos.x, tank.x - left, tank.x + right)
	pos.z = clampf(pos.z, tank.z - down, tank.z + up)
	pos.y = player.y
	var dist := Vector2(pos.x - player.x, pos.z - player.z).length()
	var reach := clampf(dist, 0.0, GLOW_REACH)
	var power := (GLOW_REACH - reach) / GLOW_REACH * GLOW_POWER
	return {"pos": pos, "power": power}
