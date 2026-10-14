extends Node3D

## A row of every field effect, re-spawned on a timer, for before/after captures:
##
##   tools/capture.sh scene=res://scenes/dev/field_fx_check.tscn wait=40 name=fx
##
## Effects run left to right in `ROW` order, 1.2 m apart, over a flat grey ground lit like
## noon, seen from a fixed camera (authored in the scene). The hot-food steam uses the
## stew's warm puff.

const ROW: Array = [
	[FieldFx.Kind.DUST, 0, 8],
	[FieldFx.Kind.DUST, 0, 4],
	[FieldFx.Kind.TUMBLE_DUST, 0, 5],
	[FieldFx.Kind.STEAM, 0, 0],
	[FieldFx.Kind.SOBA_YUGE, 6, 1],
	[FieldFx.Kind.KISHA_KEMURI, 0, 0],
	[FieldFx.Kind.SAND, 1, 0],
	[FieldFx.Kind.SIBUKI, 0, 1],
	[FieldFx.Kind.YUKIHANE, 0, 0],
	[FieldFx.Kind.MIZUTAMA, 0, 0x5000],
	[FieldFx.Kind.YUKIDAMA, 0, 0x1000],
	[FieldFx.Kind.PETAL, 3, 2],
	[FieldFx.Kind.HAMON, 2, 0],
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
		FieldFx.spawn(_effects, row[0] as FieldFx.Kind, at, 0.0, int(row[1]), int(row[2]), _flat)


static func _flat(_at: Vector3) -> float:
	return 0.0
