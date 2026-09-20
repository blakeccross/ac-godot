class_name RoomStair
extends Resource

## One player-house staircase (`DOOR0` / `DOOR1` unit). The decomp walks onto a sloped unit
## carrying a door item and `goto_next_scene` takes that door index; here a sensor at the
## unit does the same and lands at the `Door_data_c` exit position.

enum Dir { DOWN, UP }

@export var cell: Vector2i = Vector2i.ZERO
@export var target_room_id: StringName = &""
## `Door_data_c.exit_position` in disc GX units.
@export var spawn_gx: Vector3 = Vector3.ZERO
## `Door_data_c.exit_orientation` mapped onto the four grid facings.
@export var spawn_facing: WorldGrid.Facing = WorldGrid.Facing.NORTH
@export var dir: Dir = Dir.DOWN
@export var label: String = "Stairs"
