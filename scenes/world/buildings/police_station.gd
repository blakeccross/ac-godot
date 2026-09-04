extends StaticBody3D

## Police box outdoor shell. Enter loads `police_box`.

@export var occupant_id: StringName = &"police"
@export var footprint: Vector2i = Vector2i(3, 3)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.BUILDING
@export var visual_id: StringName = &"obj_s_kouban"
@export var label: String = "Police Station"
@export var door_verb: StringName = &"enter"


func _ready() -> void:
	GeneratedVisual.attach(self, visual_id)
	HostCollision.apply_building(self, visual_id, footprint, HostCollision.CELL)
	var door: Node = get_node_or_null("Door")
	if door != null:
		if "label" in door:
			door.set("label", label)
		if "verb" in door:
			door.set("verb", door_verb)
		if "closed_notice" in door:
			door.set("closed_notice", "The %s is locked." % label)


func apply_grid_yaw(facing: WorldGrid.Facing) -> void:
	rotation.y = WorldGrid.yaw_for_facing(facing)


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, visual_id)
