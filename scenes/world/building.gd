class_name Building
extends StaticBody3D

## Simple outdoor building shell (museum, Able Sisters, post office, …).
## Interaction lives on the child Door — composition, not a special player case.

const LEVEL_SOUND := preload("res://scenes/world/level_sound.tscn")

@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(2, 2)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.BUILDING
@export var visual_id: StringName = &""
@export var label: String = "Building"
@export var door_verb: StringName = &"enter"


func _ready() -> void:
	GeneratedVisual.attach(self, visual_id)
	HostCollision.apply_building(self, visual_id, footprint, HostCollision.CELL)
	## `ac_shrine_move`: the wishing well hums (level SE 0x5A) whenever it is out.
	if String(visual_id).contains("shrine"):
		var hum := LEVEL_SOUND.instantiate() as LevelSound
		hum.level_id = 0x5A
		add_child(hum)
	## Station is outdoor-only (`ac_station` + acre collision; Porter at ut 5,4). No Door.
	if HostCollision.is_station(visual_id):
		return
	var door := get_node_or_null("Door") as Door
	if door != null:
		door.label = label
		door.verb = door_verb
		door.closed_notice = "The %s is locked." % label
		## Museum: walk-in enter (`aMsm_check_player` has no A button); lighthouse too
		## (`aTOU_actor_move` requests the door with no A button).
		if HostCollision.is_museum(visual_id) or HostCollision.is_lighthouse(visual_id):
			door.auto_enter = true


func apply_grid_yaw(facing: WorldGrid.Facing) -> void:
	rotation.y = WorldGrid.yaw_for_facing(facing)


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, visual_id)
