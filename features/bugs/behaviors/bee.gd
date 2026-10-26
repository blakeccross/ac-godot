class_name Bee
extends Cicada

## The bee in `ac_ins_semi.c` (type 8): it perches on a trunk and takes off like a cicada,
## but never cries, takes off without the cicada's rattle and buzzes as it flies.


func _item(_a: BugActor) -> int:
	return 8


func _escape_sound(_a: BugActor) -> void:
	pass


func _cry(_a: BugActor, _sense: BugActor.Sense) -> void:
	pass


func _flight_sound(a: BugActor) -> void:
	a.loop_sound = 0x26
