class_name WindowSunshine
extends RefCounted

## Window beams (`ef_room_sunshine`, `ROOM_SUNSHINE`) for the rooms that spawn them: Able
## Sisters, every player-house floor with windows, and villager homes. Each scene lists
## two actors, arg 2 (west window, `room_lightL`) and arg 3 (east, `room_lightR`); the
## positions below are the scenes' own actor tables. Timing, alpha and colour are the
## police box beam's (`PoliceDisplay.sunshine_*`, the same formulas in both effects).
##
## The post office, museum entrance and insect wing use their own effects and models
## (`ef_room_sunshine_posthouse` / `_museum` / `_minsect`), so they are not listed here.

const SCENE := preload("res://scenes/world/interiors/room_sunshine.tscn")
const VISUAL_L := &"room_lightL"
const VISUAL_R := &"room_lightR"

## `NEEDLEWORK` / `npc_room01` / `player_room_{s,m,l,ll1,ll2}` actor positions (GX).
const NEEDLEWORK: Array[Vector3] = [Vector3(40, 0, 160), Vector3(360, 0, 160)]
const NPC_ROOM: Array[Vector3] = [Vector3(40, 0, 160), Vector3(282, 0, 160)]
const PLAYER_MAIN: Array[Array] = [
	[Vector3(40, 0, 120), Vector3(200, 0, 120)],
	[Vector3(40, 0, 160), Vector3(280, 0, 160)],
	[Vector3(40, 0, 200), Vector3(360, 0, 200)],
	[Vector3(40, 0, 200), Vector3(360, 0, 200)],
]
const PLAYER_UPPER: Array[Vector3] = [Vector3(40, 0, 160), Vector3(280, 0, 160)]

## `mEnv_NPC_LIGHTS_OFF_TIME` / `_ON_TIME`, and the default switch state the player's
## rooms start in (`mRmTp_SetDefaultLightSwitchData(0)`): lights on 18:00–05:00.
const LIGHTS_OFF_SEC := 5 * 3600
const LIGHTS_ON_SEC := 18 * 3600
## `point_light_min`: the room light's share when the switch is off.
const POINT_LIGHT_MIN := 0.14


## The two actor positions for a room, west first; empty when the scene has none
## (basement, shops, …).
static func actors_for(room: Room, house: House = null) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if room == null:
		return out
	match room.kind:
		Room.Kind.NEEDLEWORK:
			out.assign(NEEDLEWORK)
		Room.Kind.NPC:
			out.assign(NPC_ROOM)
		Room.Kind.PLAYER:
			if room.id == PlayerHouse.MAIN:
				out.assign(PLAYER_MAIN[PlayerHouse.tier_of(house)])
			elif room.id == PlayerHouse.UPPER:
				out.assign(PLAYER_UPPER)
	return out


## Whether the room has a light switch (`mRmTp_GetNowSceneLightSwitchIndex` ≠ −1): the
## player's rooms and villager homes. It changes how far the window light opens.
static func has_light_switch(room: Room) -> bool:
	return room != null and (room.kind == Room.Kind.PLAYER or room.kind == Room.Kind.NPC)


## `Ef_Room_Sunshine_actor_ct`: every non-zero `actor_specific` first steps −1 X, then
## case 2 nets −1 more and case 3 nets +1. Y is `1 + BgY` and the draw adds 0.1.
static func anchor_gx(actor_gx: Vector3, left: bool) -> Vector3:
	var x: float = actor_gx.x - 1.0 + (-1.0 if left else 1.0)
	return Vector3(x, actor_gx.y + 1.1, actor_gx.z)


## X stretch of a beam; 0 hides it. The west beam shows at night 00–04 and in the
## afternoon 12–20, the east one in the morning 04–12 and evening 20–24. Both models
## already point into the room, so unlike the police box the east beam is not mirrored.
static func stretch(now_sec: int, left: bool) -> float:
	if left:
		return PoliceDisplay.sunshine_left_x(now_sec)
	return absf(PoliceDisplay.sunshine_right_x(now_sec))


## `mEnv_MakeWindowLightAlpha` target. Rooms without a switch open only 05:00–18:00
## (`PoliceDisplay.window_light_target`). With one, the target is
## `(1 − point_light_percent) · 0.78 + 0.22` at any hour: 0.22 with the lights on,
## about 0.89 with them off. Both close for ±120 s around the `s16`-cast marks.
static func window_light_target(now_sec: int, light_switch: bool) -> float:
	if not light_switch:
		return PoliceDisplay.window_light_target(now_sec)
	for mark: int in [0, 86400, 43200]:
		if absi(PoliceDisplay._s16(now_sec - mark)) < 120:
			return 0.0
	var percent: float = 1.0 if lights_on(now_sec) else POINT_LIGHT_MIN
	return (1.0 - percent) * 0.78 + 0.22


static func lights_on(now_sec: int) -> bool:
	return now_sec >= LIGHTS_ON_SEC or now_sec < LIGHTS_OFF_SEC


## Adds `SunshineL` / `SunshineR` under `root` for the room's actors. Idempotent.
static func add(root: Node3D, grid: WorldGrid, room: Room, house: House = null) -> void:
	if root == null or grid == null:
		return
	var actors: Array[Vector3] = actors_for(room, house)
	if actors.size() != 2:
		return
	for i: int in 2:
		var left: bool = i == 0
		var node_name: String = "SunshineL" if left else "SunshineR"
		var node: Node3D = root.get_node_or_null(node_name) as Node3D
		if node == null:
			node = SCENE.instantiate() as Node3D
			node.name = node_name
			node.set("left", left)
			node.set("light_switch", has_light_switch(room))
			root.add_child(node)
		node.position = MuseumDisplay.gx_to_world(grid, anchor_gx(actors[i], left))
