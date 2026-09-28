class_name InteriorLighting
extends RefCounted

## Indoor environment lighting + camera framing for the interior scene root
## (`scenes/world/interior.gd`). Split out so the scene script stays focused
## on node lifecycle.


static func apply(
	host: Node3D, world_env: WorldEnvironment, camera: Camera3D, grid: WorldGrid, room: Room
) -> void:
	refresh_light(host, world_env, grid, room)
	if camera != null and "offset" in camera:
		## Homes frame the shell (never closer than Camera2 620). Museum / shops /
		## other public rooms keep outdoor focus distance — `Camera2_InDoorCheck`
		## is only NPCROOM0 / ROOM0 / PLAYER0_ROOM.
		if pins_follow_camera(room):
			var bounds: AABB = InteriorShellBuilder.shell_bounds(room, grid)
			var span: float = maxf(bounds.size.x, bounds.size.z)
			if camera.has_method("offset_to_frame_span"):
				camera.set("offset", camera.call("offset_to_frame_span", span))
			elif camera.has_method("offset_for_ground_span"):
				camera.set("offset", camera.call("offset_for_ground_span", span))
			else:
				camera.set("offset", Vector3(0.0, span, span))
		else:
			## Restore Camera2 620 when leaving a framed home for a public room.
			camera.set("offset", preload("res://scenes/world/follow_camera.gd").DEFAULT_OFFSET)
	if pins_follow_camera(room) and camera.has_method("lock_at"):
		camera.call("lock_at", inner_look_point(grid, room))


## Ambient, sun, moon and room lamp for the current time and weather
## (`InteriorLightModel`). Called on entry and on every clock / weather change.
static func refresh_light(host: Node3D, world_env: WorldEnvironment, grid: WorldGrid, room: Room) -> void:
	var tier: int = 0
	if Game.interiors != null and Game.interiors.player_house() != null:
		tier = int(Game.interiors.player_house().size_tier)
	var lit: bool = InteriorLightModel.lamp_on(room, Clock.hour, _owner_home(room))
	var rain: bool = Weather.is_precip(Weather.kind_from_name(Game.weather))
	var light: Dictionary = InteriorLightModel.evaluate(room, Clock.now_sec(), rain, lit, tier)
	var env: Environment = world_env.environment
	env.background_mode = Environment.BG_COLOR
	## Void behind gaps in room geometry. `l_mEnv_kcolor_*` (`m_kankyo.c`) keeps a
	## "background color" field crushed to black on the original CRT/composite output —
	## do not derive it from the room colour like the window fill.
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = light["ambient"] as Color
	env.ambient_light_energy = 1.0
	env.fog_enabled = false
	## Same N64 colour → Godot energy mapping as outdoors (`Clock.outdoor_light`), so the
	## player reads the same stepping through the door.
	var sun: DirectionalLight3D = host.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		_aim(sun, light["sun_dir"] as Vector3)
		sun.light_color = light["sun"] as Color
		sun.light_energy = (light["sun"] as Color).get_luminance() * 1.35
		sun.visible = sun.light_energy > 0.02
	var moon: DirectionalLight3D = host.get_node_or_null("Moon") as DirectionalLight3D
	if moon != null:
		_aim(moon, light["moon_dir"] as Vector3)
		moon.light_color = light["moon"] as Color
		moon.light_energy = (light["moon"] as Color).get_luminance() * 0.9
		moon.visible = moon.light_energy > 0.02
	var lamp: OmniLight3D = host.get_node_or_null("RoomLight") as OmniLight3D
	if lamp != null:
		var units_to_m: float = (grid.cell_size if grid != null else 2.0) / InteriorLightModel.UNITS_PER_CELL
		var nw: Vector3 = grid.cell_corner(Vector2i.ZERO) if grid != null else Vector3.ZERO
		lamp.position = nw + (light["lamp_pos"] as Vector3) * units_to_m
		lamp.omni_range = float(light["lamp_power"]) * units_to_m
		lamp.light_color = light["lamp_color"] as Color
		lamp.light_energy = (light["lamp_color"] as Color).get_luminance() * 1.35
		lamp.visible = lamp.light_energy > 0.01
	var prim: Color = light["room_prim"] as Color
	VisualWindowLight.set_indoor_room_prim(prim)
	VisualWindowLight.refresh_room_prim(host, prim)


static func _owner_home(room: Room) -> bool:
	if room == null or room.kind != Room.Kind.NPC:
		return false
	var house: House = InteriorCatalog.house_template(room.id)
	var occupant: StringName = house.occupant_id if house != null else &""
	if occupant == &"" and String(room.id).begins_with("npc_"):
		occupant = StringName(String(room.id).substr(4))
	return VillagerHome.should_spawn_indoor(occupant)


static func _aim(light: DirectionalLight3D, dir: Vector3) -> void:
	## Decomp dirs point toward the light; Godot shines along −Z.
	if dir.length_squared() < 0.0001:
		return
	var d: Vector3 = dir.normalized()
	var up := Vector3.UP
	if absf(d.dot(up)) > 0.95:
		up = Vector3.RIGHT
	light.basis = Basis.looking_at(-d, up)


## Player and villager homes pin the 3/4 camera to the room (`Camera2` border invert).
static func pins_follow_camera(room: Room) -> bool:
	return room != null and (room.kind == Room.Kind.NPC or room.kind == Room.Kind.PLAYER)


static func inner_look_point(grid: WorldGrid, room: Room) -> Vector3:
	if grid == null or room == null:
		return Vector3.ZERO
	var nw: Vector3 = grid.cell_corner(room.inner_origin)
	var size := Vector3(
		float(maxi(room.inner_size.x, 1)) * grid.cell_size,
		0.0,
		float(maxi(room.inner_size.y, 1)) * grid.cell_size
	)
	return Vector3(nw.x + size.x * 0.5, 0.0, nw.z + size.z * 0.5)
