extends EventPresenter

## A festival laid out from its map (`mEvMN_GetEventSetUtInBlock`, `data/events/event_map.json`):
## the props (stalls, mats, tables), residents in their slots (`FestivalCrowd`) and Tortimer at
## his spot. The residents who turn out are hidden from the field until it ends.

const VILLAGER_SCENE := "res://scenes/world/events/festival_villager.tscn"
const TORTIMER_SCENE := "res://scenes/world/events/tortimer_holiday.tscn"
## Map actors that are Tortimer (`SP_NPC_EV_SONCHO2`, the aerobics leader `SP_NPC_SONCHO_D078`).
const TORTIMER_ACTORS: Array[String] = ["SP_NPC_EV_SONCHO2"]
## Event specials that stand at their map unit: actor → scene.
const SPECIALS: Dictionary = {
	"SP_NPC_EV_YOMISE": "res://scenes/world/events/yomise.tscn",
	"SP_NPC_EV_YOMISE2": "res://scenes/world/events/yomise.tscn",
	"SP_NPC_ANGLER": "res://scenes/world/events/angler.tscn",
	"SP_NPC_EV_MIKO": "res://scenes/world/events/miko.tscn",
}
## The props a seated / standing guest faces, if one is this close (cells).
const FACE_PROP_RANGE := 4.0

var _away: Array[StringName] = []


func start() -> bool:
	var entries: Array = mgr.map_actors(id)
	if entries.is_empty():
		return false
	var data: Dictionary = EventManager.event_map(id)
	var props: Array[Vector2i] = []
	for e: Dictionary in entries:
		var actor: String = e["actor"]
		if FestivalCrowd.PROPS.has(actor):
			var prop: Array = FestivalCrowd.PROPS[actor]
			mgr.spawn_structure(id, StringName(prop[0]), e["cell"], &"", "", prop[1], actor)
			props.append(e["cell"])
	var center: Vector2 = Vector2.ZERO
	for e: Dictionary in entries:
		center += Vector2(e["cell"])
	center /= float(entries.size())
	var slots: Array = []
	for e: Dictionary in entries:
		if FestivalCrowd.ACTORS.has(e["actor"]):
			slots.append(e)
	slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return FestivalCrowd.slot_of(a["actor"]) < FestivalCrowd.slot_of(b["actor"]))
	var count: int = mini(slots.size(), int(data.get("joint_npcs", slots.size())))
	var chosen: Array[StringName] = _pick(count)
	var cloth: int = _cloth(str(data.get("cloth", "")))
	for i: int in mini(chosen.size(), slots.size()):
		var e: Dictionary = slots[i]
		var villager: VillagerData = VillagerCatalog.get_villager(chosen[i])
		if villager == null:
			continue
		var node: Node3D = (load(VILLAGER_SCENE) as PackedScene).instantiate() as Node3D
		node.call("assign", villager, FestivalCrowd.family_of(e["actor"]), FestivalCrowd.slot_of(e["actor"]), cloth)
		mgr.add_actor(id, node, e["cell"], _face(e["cell"], props, center), i + 1)
		_away.append(chosen[i])
	for e: Dictionary in entries:
		var actor: String = e["actor"]
		if actor in TORTIMER_ACTORS:
			_add_tortimer(e["cell"], _face(e["cell"], props, center))
		elif SPECIALS.has(actor):
			var special: Node3D = (load(SPECIALS[actor]) as PackedScene).instantiate() as Node3D
			if "anglers" in special:
				special.set("anglers", _names(chosen))
			mgr.add_actor(id, special, e["cell"], _face(e["cell"], props, center), 0)
	_set_away(true)
	return true


func stop() -> void:
	_set_away(false)
	_away.clear()
	super.stop()


## `mEvMN_GetNpcIdxRandom`.
func _pick(count: int) -> Array[StringName]:
	if Game == null or count <= 0:
		return []
	var residents: Array[StringName] = Game.residents.resident_ids()
	var today: String = Game.events.day_key() if Game.events != null else ""
	return FestivalCrowd.pick_villagers(residents, count, "%s:%s" % [id, today], Game.player_met)


func _names(ids: Array[StringName]) -> Array:
	var out: Array = []
	for v: StringName in ids:
		var data: VillagerData = VillagerCatalog.get_villager(v)
		if data != null:
			out.append(data.display_name)
	return out


func _cloth(name: String) -> int:
	if not name.begins_with("ITM_CLOTH"):
		return -1
	return int(name.substr(9))


func _face(cell: Vector2i, props: Array[Vector2i], center: Vector2) -> float:
	var target: Vector2 = center
	var best: float = FACE_PROP_RANGE
	for p: Vector2i in props:
		var d: float = Vector2(p - cell).length()
		if d > 0.0 and d <= best:
			best = d
			target = Vector2(p)
	var to: Vector2 = target - Vector2(cell)
	if to.length_squared() < 0.01:
		return 0.0
	return atan2(to.x, to.y)


func _add_tortimer(cell: Vector2i, yaw: float) -> void:
	var node: Node3D = (load(TORTIMER_SCENE) as PackedScene).instantiate() as Node3D
	node.set("holiday", TortimerHoliday.event_index(soncho_event()))
	mgr.add_actor(id, node, cell, yaw, 0)


## Tortimer's calendar entry for this festival (`mSC_get_soncho_event`).
func soncho_event() -> StringName:
	if String(id).begins_with("sports_fair"):
		return &"soncho_spring_sports_fair" if Clock.month < 7 else &"soncho_fall_sports_fair"
	var own := StringName("soncho_%s" % id)
	if TortimerHoliday.event_index(own) >= 0:
		return own
	return id


func _set_away(away: bool) -> void:
	if mgr == null or mgr.get_tree() == null:
		return
	for node: Node in mgr.get_tree().get_nodes_in_group("villagers"):
		var v := node as Villager
		if v != null and v.data != null and v.data.id in _away:
			v.set_event_away(away)
