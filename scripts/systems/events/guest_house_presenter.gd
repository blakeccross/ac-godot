class_name GuestHousePresenter
extends EventPresenter

## The snow cabin (`kamakura_start`: `KAMAKURA` on an empty lot, a resident inside —
## `mNpc_AddNpc_inKamakura`) and the summer camper's tent (`summercamp_start`: `TENT` on an
## empty lot, a villager from out of town inside — `mNpc_DecideMaskNpc_summercamp`). Who is
## inside is kept in the event's save area for the season; `Interior` puts them in the room.
## A resident in the cabin is hidden from the field while it stands.

const SCAN_INTERVAL := 1.0

var _away: StringName = &""
var _scan: float = 0.0


static func guest_kind(event: StringName) -> StringName:
	return &"kamakura" if event == &"kamakura" else &"camper"


## The villager inside (`kamakura` / `summer_camper` save area), chosen once per year.
static func guest_of(event: StringName) -> StringName:
	if Game == null or Game.events == null:
		return &""
	var a: Dictionary = Game.events.area(event)
	if int(a.get("year", 0)) == Clock.year and str(a.get("villager", "")) != "":
		return StringName(str(a["villager"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s:%d" % [event, Clock.year]).hash()
	var pick: StringName = &""
	if event == &"kamakura":
		var residents: Array[StringName] = Game.residents.resident_ids()
		if not residents.is_empty():
			pick = residents[rng.randi_range(0, residents.size() - 1)]
	else:
		var strangers: Array[StringName] = []
		for v: VillagerData in VillagerCatalog.all_villagers():
			if not v.islander and not Game.residents.has_resident(v.id):
				strangers.append(v.id)
		if not strangers.is_empty():
			pick = strangers[rng.randi_range(0, strangers.size() - 1)]
	a["year"] = Clock.year
	a["villager"] = String(pick)
	return pick


func start() -> bool:
	var cell: Vector2i = mgr.place_once(id, 0, func() -> Vector2i: return mgr.free_lot(absi(String(id).hash()) % 997))
	if cell.x < 0:
		return false
	var cabin: bool = id == &"kamakura"
	mgr.spawn_structure(
		id, &"obj_w_kamakura" if cabin else &"obj_s_tent", cell,
		&"kamakura" if cabin else &"tent", "Snow Cabin" if cabin else "Tent"
	)
	if cabin:
		_away = guest_of(id)
	else:
		guest_of(id)
	return true


func tick(delta: float) -> void:
	if _away == &"":
		return
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = SCAN_INTERVAL
	_set_away(true)


func stop() -> void:
	_set_away(false)
	_away = &""
	super.stop()


func _set_away(away: bool) -> void:
	if _away == &"" or mgr == null or mgr.get_tree() == null:
		return
	for node: Node in mgr.get_tree().get_nodes_in_group("villagers"):
		var v := node as Villager
		if v != null and v.data != null and v.data.id == _away and not v.indoor_resident:
			v.set_event_away(away)
