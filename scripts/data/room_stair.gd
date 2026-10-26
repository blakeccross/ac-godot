class_name RoomStair
extends Resource

## One player-house staircase (`DOOR0` / `DOOR1` unit). The decomp walks onto a sloped unit
## carrying a door item and `goto_next_scene` takes that door index; here the interior does
## the same when the player's own cell is the stair unit, and lands at the `Door_data_c` exit
## position.

enum Dir { DOWN, UP }

@export var cell: Vector2i = Vector2i.ZERO
@export var target_room_id: StringName = &""
## `Door_data_c.exit_position` (metres from the target room's corner).
@export var spawn: Vector3 = Vector3.ZERO
## `Door_data_c.exit_orientation` mapped onto the four grid facings.
@export var spawn_facing: WorldGrid.Facing = WorldGrid.Facing.NORTH
## Where you land in this room when you come up or down these stairs: the other room's
## `Door_data_c.exit_position` back here, in metres. The stair bay is open from here to
## `cell`.
@export var landing: Vector3 = Vector3.ZERO
@export var dir: Dir = Dir.DOWN
@export var label: String = "Stairs"
