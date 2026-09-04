extends Node3D

## Base museum wing scene. Subclasses own exhibits + any extra collision.
## Instanced by `museum_complete.tscn` and by `interior.tscn` via catalog scene paths.

@export var room_id: StringName = &""

var _wing: Interior = null


func _ready() -> void:
	size_authored_doors()


## Fill Terrain collision + this room's exhibits (`MuseumBook`).
func populate() -> void:
	if room_id == &"" or Game == null:
		return
	var room: Room = Game.interiors.room(room_id)
	if room == null:
		return
	_wing = Interior.new()
	_wing.bind(room)
	InteriorBuilder.new().populate_authored(self, _wing)
	size_authored_doors()


## Override in each wing script.
func present_exhibits(_furniture: Node3D, _session: Interior) -> void:
	pass


func size_authored_doors() -> void:
	var doors: Node = get_node_or_null("Doors")
	if doors == null:
		return
	match room_id:
		&"museum_entrance":
			for link: Dictionary in MuseumDisplay.ENTRANCE_WING_DOORS:
				var door: Node3D = doors.get_node_or_null("Link_%s" % String(link["room"])) as Node3D
				if door != null:
					_size_door(door, link["sensor"] as Vector3)
			var exit_door: Node3D = doors.get_node_or_null("Exit") as Node3D
			if exit_door != null:
				_size_door(exit_door, MuseumDisplay.ENTRANCE_EXIT_SENSOR_GX)
		_:
			if not MuseumDisplay.WING_EXIT_DOORS.has(room_id):
				return
			var link: Dictionary = MuseumDisplay.WING_EXIT_DOORS[room_id] as Dictionary
			var exit_door: Node3D = doors.get_node_or_null("Exit") as Node3D
			if exit_door != null:
				_size_door(exit_door, link["sensor"] as Vector3)


func _size_door(door: Node3D, sensor_gx: Vector3) -> void:
	HostCollision.resize_interact_box(door, InteriorBuilder.museum_door_box(sensor_gx))
