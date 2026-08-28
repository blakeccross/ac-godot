class_name DialogueData
extends Resource

## One conversation. A UI scene plays `lines`; this resource does not run dialogue.

@export var id: StringName = &""
@export var speaker_id: StringName = &""
@export var lines: PackedStringArray = PackedStringArray()
