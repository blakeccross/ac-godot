class_name InteriorLighting
extends RefCounted

## Indoor environment lighting + camera framing for the interior scene root
## (`scenes/world/interior.gd`). Split out so the scene script stays focused
## on node lifecycle.


static func apply(
	host: Node3D, world_env: WorldEnvironment, camera: Camera3D, grid: WorldGrid, room: Room
) -> void:
	var env: Environment = world_env.environment
	var room_color: Color = VisualWindowLight.room_prim_color()
	env.background_mode = Environment.BG_COLOR
	## Void behind gaps in room geometry. `l_mEnv_kcolor_*` (`m_kankyo.c`) keeps a
	## "background color" field crushed to black on the original CRT/composite output —
	## do not derive it from `room_color` like the window fill.
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = room_color
	env.ambient_light_energy = 1.15
	env.fog_enabled = false
	var fill: OmniLight3D = host.get_node_or_null("FillLight") as OmniLight3D
	if fill != null:
		fill.light_color = room_color
		fill.light_energy = 0.55
	if room != null and room.kind == Room.Kind.MUSEUM:
		_apply_museum_mood(env, fill, room)
	VisualWindowLight.refresh_room_prim(host, room_color)
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


## Museum wings read darker and more dramatic than a home — the skylight shafts and
## per-wing tint are the mood, not a flat fill (`ac_museum` baked ceiling shade).
static func _apply_museum_mood(env: Environment, fill: OmniLight3D, room: Room) -> void:
	var tint: Color = Color(0.62, 0.64, 0.70)
	match room.id:
		&"museum_fossil":
			tint = Color(0.55, 0.60, 0.72)
		&"museum_painting":
			tint = Color(0.74, 0.68, 0.58)
		&"museum_fish":
			tint = Color(0.48, 0.62, 0.74)
		&"museum_insect":
			tint = Color(0.56, 0.66, 0.56)
	env.ambient_light_color = tint
	env.ambient_light_energy = 0.72
	## Background stays black (see `apply`) regardless of per-wing tint.
	if fill != null:
		fill.light_color = tint.lightened(0.15)
		fill.light_energy = 0.35


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
