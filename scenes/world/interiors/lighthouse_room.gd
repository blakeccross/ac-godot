extends "res://scenes/world/interiors/public_room.gd"

## Lighthouse switch room (`SCENE_LIGHTHOUSE`). The machinery is the authored
## `LighthouseSwitch`; this places it on the room's acre and walls off the pit.


func present_exhibits(furniture: Node3D, interior: IndoorSession) -> void:
	if furniture == null or interior == null or interior.grid == null:
		return
	InteriorUnitCollision.add_hulls(
		furniture, interior.grid, "LighthouseRoomCol", LighthouseRoom.blocked_units()
	)
	var machinery: Node3D = furniture.get_node_or_null("LighthouseSwitch") as Node3D
	if machinery != null:
		machinery.position = LighthouseRoom.gx_to_world(interior.grid, LighthouseRoom.SWITCH_GX)
