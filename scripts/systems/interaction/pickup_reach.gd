class_name PickupReach
extends RefCounted

## Where B can take something from (`Player_actor_Search_putin_item`): it looks at the unit under a
## point 35 GX ahead (only a signboard counts there), then 20 GX ahead, then 10 GX ahead, and the
## thing on that unit has to lie within 15 GX across and 15 GX up or down of the point
## (`Player_actor_CheckItemPosition_forPickup`). Ground items, weeds and signboards opt in by joining
## `GROUP`; a signboard also joins `SIGNBOARD_GROUP`.

const GROUP := &"field_pickup"
const SIGNBOARD_GROUP := &"signboard_pickup"

const SIGNBOARD_PROBE := 35.0 * FieldCatalog.GX_TO_METERS
const ITEM_PROBES: Array[float] = [20.0 * FieldCatalog.GX_TO_METERS, 10.0 * FieldCatalog.GX_TO_METERS]
const RADIUS := 15.0 * FieldCatalog.GX_TO_METERS
const HEIGHT := 15.0 * FieldCatalog.GX_TO_METERS
## Hosts this far from the player can't be reached from any probe.
const CANDIDATE_RANGE := SIGNBOARD_PROBE + RADIUS

var origin: Vector3
## `shape_info.rotation.y`: facing along (sin, cos) on the ground.
var yaw: float
var grid: WorldGrid


func _init(p_origin: Vector3, p_yaw: float, p_grid: WorldGrid) -> void:
	origin = p_origin
	yaw = p_yaw
	grid = p_grid


## `Player_actor_Get_PickupHandPosition`.
func probe(distance: float) -> Vector3:
	return origin + Vector3(sin(yaw), 0.0, cos(yaw)) * distance


## Which look finds `host`: 0 the signboard 35 GX ahead, 1 anything 20 GX ahead, 2 anything 10 GX
## ahead; -1 when none does. Lower wins.
func rank(host: Node3D) -> int:
	if host == null:
		return -1
	if host.is_in_group(SIGNBOARD_GROUP) and _sees(host, SIGNBOARD_PROBE):
		return 0
	for i: int in ITEM_PROBES.size():
		if _sees(host, ITEM_PROBES[i]):
			return 1 + i
	return -1


func _sees(host: Node3D, distance: float) -> bool:
	var at: Vector3 = probe(distance)
	if grid != null and grid.world_to_cell(at) != grid.world_to_cell(host.global_position):
		return false
	var dx: float = host.global_position.x - at.x
	var dz: float = host.global_position.z - at.z
	if dx * dx + dz * dz > RADIUS * RADIUS:
		return false
	return absf(host.global_position.y - at.y) <= HEIGHT
