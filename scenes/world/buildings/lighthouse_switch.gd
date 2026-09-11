extends StaticBody3D

## Lighthouse on/off switch (`ac_lighthouse_switch`). Decomp gates manual toggling behind a
## scripted multi-day mayor's-quest "lighthouse period" that also locks island boat travel —
## that whole system is out of scope (`docs/scope.md`: "Island boat logistics and
## island-exclusive systems"). This keeps only the switch itself: auto on/off at
## `aLS_NiceSwitchOnTime`'s night window (18:00-05:00 — decomp's own hours, not this engine's
## broader ambient-lighting `Clock.TimeOfDay.NIGHT`), toggleable at any time by the player,
## with the manual choice sticking until the next window boundary resets it
## (`aLS_AutoSwitch`).

const NIGHT_START_HOUR := 18
const NIGHT_END_HOUR := 5

@export var footprint: Vector2i = Vector2i(1, 1)
@export var visual_id: StringName = &"obj_toudai_switch"
@export var beacon_path: NodePath = ^"../Beacon"

var _on := false
var _manual_override := false
@onready var _beacon: Node = get_node_or_null(beacon_path)


func _ready() -> void:
	add_to_group("interactable")
	GeneratedVisual.attach(self, visual_id)
	HostCollision.apply_box(self, footprint, HostCollision.CELL, 0.8)
	Clock.hour_changed.connect(_on_hour_changed)
	_sync_beacon()


func _exit_tree() -> void:
	if Clock.hour_changed.is_connected(_on_hour_changed):
		Clock.hour_changed.disconnect(_on_hour_changed)


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, visual_id)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	var verb := "Turn off the light" if is_on() else "Turn on the light"
	return [Interaction.of(Interaction.TOGGLE, verb, 6)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TOGGLE:
		return false
	_manual_override = true
	_on = not is_on()
	_sync_beacon()
	return true


func _on_hour_changed(hour: int) -> void:
	if hour == NIGHT_START_HOUR or hour == NIGHT_END_HOUR:
		_manual_override = false
		recheck()


## Re-evaluate on/off from the current clock and push it to the beacon. Called on the
## `18:00`/`05:00` boundaries; exposed for tests and for a post-load/scene-enter refresh.
func recheck() -> void:
	_sync_beacon()


func is_on() -> bool:
	return _on if _manual_override else _auto_on()


func _auto_on() -> bool:
	return Clock.hour >= NIGHT_START_HOUR or Clock.hour < NIGHT_END_HOUR


func _sync_beacon() -> void:
	if _beacon != null and "on" in _beacon:
		_beacon.set("on", is_on())
