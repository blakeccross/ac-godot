extends NpcEventPresenter

## Halloween night (`halloween_start`): Jack in a free acre, and the residents who are out
## put on his costume (`mEvMN_GetHalloweenNpcName`, up to five event-NPC slots) where they
## stand; their field copies are hidden until the night ends.

const COSTUME_SCENE := "res://scenes/world/events/halloween_villager.tscn"
const MAX_COSTUMES := 5

const SCAN_INTERVAL := 1.0

var _away: Array[StringName] = []
var _scan: float = 0.0


func _init() -> void:
	scene_path = "res://scenes/world/events/jack.tscn"
	placement = "free"


func start() -> bool:
	return super.start()


## Residents spawn after the event does, and come out later: dress them as they appear.
func tick(delta: float) -> void:
	_scan -= delta
	if _scan > 0.0 or _away.size() >= MAX_COSTUMES or mgr == null or mgr.get_tree() == null:
		return
	_scan = SCAN_INTERVAL
	for node: Node in mgr.get_tree().get_nodes_in_group("villagers"):
		if _away.size() >= MAX_COSTUMES:
			break
		var v := node as Villager
		if v == null or v.data == null or not v.visible or v.indoor_resident or v.data.id in _away:
			continue
		var costume: Node3D = (load(COSTUME_SCENE) as PackedScene).instantiate() as Node3D
		costume.call("assign", v.data)
		var cell: Vector2i = mgr.world.grid.world_to_cell(v.global_position)
		mgr.add_actor(id, costume, cell, v.rotation.y, _away.size() + 1)
		v.set_event_away(true)
		_away.append(v.data.id)


func stop() -> void:
	if mgr != null and mgr.get_tree() != null:
		for node: Node in mgr.get_tree().get_nodes_in_group("villagers"):
			var v := node as Villager
			if v != null and v.data != null and v.data.id in _away:
				v.set_event_away(false)
	_away.clear()
	super.stop()
