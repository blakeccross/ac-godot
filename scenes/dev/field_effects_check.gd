extends Node3D

## A row of every field effect, re-spawned on a timer, for before/after captures:
##
##   tools/capture.sh scene=res://scenes/dev/field_effects_check.tscn wait=40 name=fx
##
## Effects run left to right in `ROW` order, 1.2 m apart, over a flat grey ground lit like
## noon, seen from a fixed camera (authored in the scene). The hot-food steam uses the
## stew's warm puff.

const ROW: Array = [
	[FieldEffects.Kind.DUST, 0, 8],
	[FieldEffects.Kind.DUST, 0, 4],
	[FieldEffects.Kind.TUMBLE_DUST, 0, 5],
	[FieldEffects.Kind.STEAM, 0, 0],
	[FieldEffects.Kind.SOBA_YUGE, 6, 1],
	[FieldEffects.Kind.KISHA_KEMURI, 0, 0],
	[FieldEffects.Kind.SAND, 1, 0],
	[FieldEffects.Kind.SIBUKI, 0, 1],
	[FieldEffects.Kind.YUKIHANE, 0, 0],
	[FieldEffects.Kind.MIZUTAMA, 0, 0x5000],
	[FieldEffects.Kind.YUKIDAMA, 0, 0x1000],
	[FieldEffects.Kind.PETAL, 3, 2],
	[FieldEffects.Kind.HAMON, 2, 0],
]
const SPACING := 1.2
## Seconds between waves; a wave spawns every effect once.
const WAVE := 0.25

@onready var _effects: Node3D = $Effects
var _wait: float = 0.0


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = WAVE
	for i: int in ROW.size():
		var row: Array = ROW[i]
		var at := Vector3((float(i) - (ROW.size() - 1) * 0.5) * SPACING, 0.0, 0.0)
		FieldEffects.spawn(_effects, row[0] as FieldEffects.Kind, at, 0.0, int(row[1]), int(row[2]), _flat)


static func _flat(_at: Vector3) -> float:
	return 0.0
