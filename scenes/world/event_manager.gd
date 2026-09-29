class_name EventManager
extends Node

## `ac_event_manager`: turns the calendar's active events into things in town. The calendar
## (`EventCalendar`) says *when*; each event's `EventPresenter` says *what*; this node owns
## the placement rules the presenters share and the actors they spawn.
##
## Placement (`mEv_place_data_c`) is remembered for the day, so leaving a building (which
## reloads the field) finds the visitor where it was — `mEv_reserve_common_place`. The whole
## town is loaded at once here, so the original's "show at the acre edge on wade" procs are
## not needed: an actor exists from its start until its stop.
##
## Block kinds are looked up once (`schedule_init`): pool, station, shrine, the player houses
## and the dock. Random acres never use those five (`search_free_unit_cancel_check`) nor the
## acres around the player (`mFI_CheckBgDma`), so nobody pops in on screen.

const GROUP := &"event_manager"
const UT := 16
## FG acres: x 1..5, z 1..6 (z 6 is the beach row, `FG_BLOCK_Z_NUM`).
const BLOCK_X_MAX := 5
const BLOCK_Z_MAX := 6

## `schedule_event[]` rows that have a presenter here, `id → script`.
const PRESENTERS: Dictionary = {
	&"kabu_peddler": "res://scripts/systems/events/joan_presenter.gd",
	&"kk_slider": "res://scripts/systems/events/kk_presenter.gd",
	&"dozaemon": "res://scripts/systems/events/gulliver_presenter.gd",
	&"broker_sale": "res://scripts/systems/events/redd_presenter.gd",
	&"carpet_peddler": "res://scripts/systems/events/saharah_presenter.gd",
	&"artist": "res://scripts/systems/events/wendell_presenter.gd",
	&"designer": "res://scripts/systems/events/gracie_presenter.gd",
	&"gypsy": "res://scripts/systems/events/katrina_presenter.gd",
	&"soncho_groundhog_day": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_aprilfools_day": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_nature_day": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_spring_cleaning": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_mothers_day": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_graduation_day": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_fathers_day": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_fishing_tourney_1": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_town_day": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_fireworks_show": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_founders_day": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_labor_day": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_explorers_day": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_halloween": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_mayors_day": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_officers_day": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_fishing_tourney_2": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_sale_day": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_snow_day": "res://scripts/systems/events/tortimer_presenter.gd",
	&"soncho_toy_day": "res://scripts/systems/events/tortimer_presenter.gd",
	&"fireworks_show": "res://scripts/systems/events/festival_presenter.gd",
	&"cherry_blossom_festival": "res://scripts/systems/events/festival_presenter.gd",
	&"sports_fair_foot_race": "res://scripts/systems/events/festival_presenter.gd",
	&"sports_fair_aerobics": "res://scripts/systems/events/festival_presenter.gd",
	&"sports_fair_ball_toss": "res://scripts/systems/events/festival_presenter.gd",
	&"sports_fair_tug_of_war": "res://scripts/systems/events/festival_presenter.gd",
	&"new_years_day": "res://scripts/systems/events/festival_presenter.gd",
	&"fishing_tourney_1": "res://scripts/systems/events/festival_presenter.gd",
	&"fishing_tourney_2": "res://scripts/systems/events/festival_presenter.gd",
	&"morning_aerobics": "res://scripts/systems/events/festival_presenter.gd",
	&"harvest_moon_festival": "res://scripts/systems/events/festival_presenter.gd",
	&"harvest_festival": "res://scripts/systems/events/festival_presenter.gd",
	&"new_years_eve_countdown": "res://scripts/systems/events/festival_presenter.gd",
	&"groundhog_day": "res://scripts/systems/events/festival_presenter.gd",
	&"meteor_shower": "res://scripts/systems/events/festival_presenter.gd",
	&"harvest_festival_franklin": "res://scripts/systems/events/franklin_presenter.gd",
	&"halloween": "res://scripts/systems/events/halloween_presenter.gd",
}

## A show owns the music (`mBGMPsComp_make_ps_demo`): the field keeps its hands off.
static var demo_bgm: StringName = &""
static var _places: Dictionary = {}
static var _places_day: String = ""

var world: World
var blocks: Dictionary = {}
var _running: Dictionary = {}
var _nodes: Dictionary = {}
var _structures: Dictionary = {}
var _rng := RandomNumberGenerator.new()


static func find(tree: SceneTree) -> EventManager:
	return tree.get_first_node_in_group(GROUP) as EventManager if tree != null else null


func _ready() -> void:
	add_to_group(GROUP)
	_rng.randomize()


## Called by `World` once the field is built.
func setup(p_world: World) -> void:
	world = p_world
	_find_blocks()
	if Game == null or Game.events == null:
		return
	if not Game.events.event_started.is_connected(_on_event_changed):
		Game.events.event_started.connect(_on_event_changed)
		Game.events.event_ended.connect(_on_event_changed)
	if Clock != null and not Clock.hour_changed.is_connected(_on_hour):
		Clock.hour_changed.connect(_on_hour)
	refresh()


func _exit_tree() -> void:
	if Game != null and Game.events != null and Game.events.event_started.is_connected(_on_event_changed):
		Game.events.event_started.disconnect(_on_event_changed)
		Game.events.event_ended.disconnect(_on_event_changed)
	if Clock != null and Clock.hour_changed.is_connected(_on_hour):
		Clock.hour_changed.disconnect(_on_hour)


func _on_event_changed(_id: StringName) -> void:
	refresh()


func _on_hour(_hour: int) -> void:
	refresh()


func _physics_process(delta: float) -> void:
	for id: Variant in _running:
		(_running[id] as EventPresenter).tick(delta)


## `event_at_oclock`: start what went active, stop what ended.
func refresh() -> void:
	if world == null or Game == null or Game.events == null:
		return
	_roll_day()
	for id: Variant in PRESENTERS:
		var sid: StringName = id
		var active: bool = Game.events.is_active(sid)
		if active and not _running.has(sid):
			var presenter: EventPresenter = _make(sid)
			if presenter != null and presenter.start():
				_running[sid] = presenter
		elif not active and _running.has(sid):
			(_running[sid] as EventPresenter).stop()
			_running.erase(sid)


func is_running(id: StringName) -> bool:
	return _running.has(id)


func presenter(id: StringName) -> EventPresenter:
	return _running.get(id) as EventPresenter


func _make(id: StringName) -> EventPresenter:
	var path: String = str(PRESENTERS.get(id, ""))
	if path.is_empty():
		return null
	var script: GDScript = load(path) as GDScript
	if script == null:
		return null
	var p: EventPresenter = script.new() as EventPresenter
	if p == null:
		return null
	p.id = id
	p.mgr = self
	return p


func _roll_day() -> void:
	var key: String = Game.events.day_key()
	if key != _places_day:
		_places_day = key
		_places.clear()


## --- Spawning ------------------------------------------------------------------------------


## Instance `scene_path` at `cell` facing `yaw`, owned by event `id`.
func spawn(id: StringName, scene_path: String, cell: Vector2i, yaw: float = 0.0, index: int = 0) -> Node3D:
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return null
	var node: Node3D = packed.instantiate() as Node3D
	if node == null:
		return null
	return add_actor(id, node, cell, yaw, index)


## Put an already-made node in town for event `id`.
func add_actor(id: StringName, node: Node3D, cell: Vector2i, yaw: float = 0.0, index: int = 0) -> Node3D:
	if "event_id" in node:
		node.set("event_id", id)
	if "place_index" in node:
		node.set("place_index", index)
	if "home_yaw" in node:
		node.set("home_yaw", yaw)
	node.rotation.y = yaw
	node.position = cell_position(cell)
	var parent: Node = world.get_node_or_null("Characters")
	if parent == null:
		parent = world
	parent.add_child(node)
	var list: Array = _nodes.get(id, [])
	list.append(node)
	_nodes[id] = list
	return node


const BUILDING_SCENE := "res://scenes/world/building.tscn"


## `mFI_SetFGStructure_common`: an event structure (Redd's tent, the fortune tent, the
## designer's car, the camper's tent) centred on `cell`, taking a 3×3 block of units, with
## a door into `interior_id` when it has one.
func spawn_structure(
	id: StringName, visual: StringName, cell: Vector2i, interior_id: StringName = &"",
	label: String = "", size: Vector2i = Vector2i(3, 3), tag: String = ""
) -> Node3D:
	var packed: PackedScene = load(BUILDING_SCENE) as PackedScene
	if packed == null:
		return null
	var node: Node3D = packed.instantiate() as Node3D
	## `tag` tells apart the props of one event (`event_fireworks_show_FIREWORKS_STALL1`).
	var occupant := StringName("event_%s" % id if tag.is_empty() else "event_%s_%s" % [id, tag])
	node.name = String(occupant)
	node.set("occupant_id", interior_id if interior_id != &"" else occupant)
	node.set("visual_id", visual)
	node.set("footprint", size)
	node.set("label", label)
	if interior_id == &"":
		var door: Node = node.get_node_or_null("Door")
		if door != null:
			node.remove_child(door)
			door.free()
	var anchor: Vector2i = cell - Vector2i(size.x / 2, size.y / 2)
	var pos: Vector3 = world.grid.footprint_center(anchor, size, WorldGrid.Facing.SOUTH)
	if world.layout != null and world.layout.is_in_bounds(cell):
		pos.y = FieldCollision.ground_y(world.layout, cell)
	node.position = pos
	var parent: Node = world.get_node_or_null("Buildings")
	if parent == null:
		parent = world
	parent.add_child(node)
	world.grid.place(occupant, anchor, size, WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.BUILDING)
	var list: Array = _nodes.get(id, [])
	list.append(node)
	_nodes[id] = list
	var occupants: Array = _structures.get(id, [])
	occupants.append(occupant)
	_structures[id] = occupants
	return node


func actors(id: StringName) -> Array:
	var out: Array = []
	for n: Variant in _nodes.get(id, []):
		if is_instance_valid(n):
			out.append(n)
	return out


## `stop_proc`: remove everything event `id` spawned.
func despawn(id: StringName) -> void:
	for n: Variant in _nodes.get(id, []):
		if is_instance_valid(n):
			## Out of the tree now so a restart can reuse the node name.
			var node := n as Node
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	_nodes.erase(id)
	for occupant: Variant in _structures.get(id, []):
		world.grid.remove(occupant)
	_structures.erase(id)


func cell_position(cell: Vector2i) -> Vector3:
	var pos: Vector3 = world.grid.cell_to_world(cell)
	if world.layout != null and world.layout.is_in_bounds(cell):
		pos.y = FieldCollision.ground_y(world.layout, cell)
	return pos


## --- Blocks and units ---------------------------------------------------------------------


static func block_unit_to_cell(block: Vector2i, unit: Vector2i) -> Vector2i:
	return Vector2i((block.x - 1) * UT + unit.x, (block.y - 1) * UT + unit.y)


static func cell_to_block(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x / UT + 1, cell.y / UT + 1)


func acre_type(block: Vector2i) -> int:
	var data: WorldData = world.layout if world != null else null
	if data == null or data.acre_types.is_empty():
		return -1
	var idx: int = block.y * TownFieldGenerator.BLOCK_X + block.x
	if idx < 0 or idx >= data.acre_types.size():
		return -1
	return int(data.acre_types[idx])


## `schedule_init`: `mFI_BlockKind2BkNum` for the pool, station, shrine, player houses, dock.
func _find_blocks() -> void:
	blocks.clear()
	for bz: int in range(1, BLOCK_Z_MAX + 1):
		for bx: int in range(1, BLOCK_X_MAX + 1):
			var b := Vector2i(bx, bz)
			var t: int = acre_type(b)
			if TownFieldGenerator.is_pool(t) and not blocks.has("pool"):
				blocks["pool"] = b
				blocks["pool_idx"] = t - 69
			elif t == TownFieldGenerator.T_TRACKS_STATION:
				blocks["station"] = b
			elif t == TownFieldGenerator.T_SHRINE:
				blocks["shrine"] = b
			elif t == TownFieldGenerator.T_PLAYER_HOUSE:
				blocks["player"] = b
			elif t == TownFieldGenerator.T_PORT:
				blocks["dock"] = b
	if not blocks.has("player"):
		blocks["player"] = WorldGenerator.PLAYER_HOUSE_BLOCK


func block_of(kind: String) -> Vector2i:
	return blocks.get(kind, Vector2i(-1, -1)) as Vector2i


func has_block(kind: String) -> bool:
	return blocks.has(kind)


func _reserved_block(block: Vector2i) -> bool:
	for kind: String in ["pool", "station", "shrine", "player", "dock"]:
		if blocks.has(kind) and blocks[kind] == block:
			return true
	return false


## `mFI_CheckBgDma`: acres the player can see — theirs and the neighbours on the near sides.
func is_block_in_view(block: Vector2i) -> bool:
	var p: Node3D = Player.find(get_tree()) as Node3D if get_tree() != null else null
	if p == null or world == null:
		return false
	var cell: Vector2i = world.grid.world_to_cell(p.global_position)
	var pb: Vector2i = cell_to_block(cell)
	var ux: int = posmod(cell.x, UT)
	var uz: int = posmod(cell.y, UT)
	var nx: int = pb.x + (1 if ux >= UT / 2 else -1)
	var nz: int = pb.y + (1 if uz >= UT / 2 else -1)
	return (block.x == pb.x or block.x == nx) and (block.y == pb.y or block.y == nz)


## `mEv_use_block_by_other_event`.
func block_used_by_other(id: StringName, block: Vector2i) -> bool:
	for key: Variant in _places:
		var place: Dictionary = _places[key]
		if StringName(place.get("event", "")) != id and cell_to_block(place["cell"]) == block:
			return true
	return false


## `mNpc_CheckNpcSet` (hard: `_fgcol_hard`, grass / soil / stone only).
func npc_can_stand(cell: Vector2i, hard: bool = false) -> bool:
	if world == null or not world.grid.is_in_bounds(cell):
		return false
	if not world.grid.is_walkable(cell) or world.grid.is_occupied(cell):
		return false
	if hard:
		var t: WorldGrid.Terrain = world.grid.terrain_at(cell)
		if t != WorldGrid.Terrain.GRASS and t != WorldGrid.Terrain.SOIL and t != WorldGrid.Terrain.STONE:
			return false
	return true


## `mNpc_GetMakeUtNuminBlock_area`: a random free unit, `restrict` units in from the edge.
func random_unit_in_block(block: Vector2i, restrict: int = 1, hard: bool = false) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for uz: int in range(restrict, UT - restrict):
		for ux: int in range(restrict, UT - restrict):
			if npc_can_stand(block_unit_to_cell(block, Vector2i(ux, uz)), hard):
				candidates.append(Vector2i(ux, uz))
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


## `mNpc_GetMakeUtNuminBlock_hard_area`: the free hard unit nearest the acre centre.
func central_unit_in_block(block: Vector2i, restrict: int = 1) -> Vector2i:
	var best := Vector2i(-1, -1)
	var min_x: int = UT
	var min_z: int = UT
	for uz: int in range(restrict, UT - restrict):
		for ux: int in range(restrict, UT - restrict):
			if not npc_can_stand(block_unit_to_cell(block, Vector2i(ux, uz)), true):
				continue
			var dx: int = absi(8 - ux)
			var dz: int = absi(8 - uz)
			if min_x > dx and min_z > dz:
				best = Vector2i(ux, uz)
				min_x = dx
				min_z = dz
	return best


func _time_seed() -> Dictionary:
	return {"month": Clock.month, "day": Clock.day, "hour": Clock.hour, "sec": Clock.minute}


## `search_free_unit`: a random acre (not a landmark acre, not in view, not another event's
## on the strict pass) and a free unit in it. `seed` is `type + name + id`.
func search_free_unit(id: StringName, seed_value: int, adjust: int = 0) -> Vector2i:
	var t: Dictionary = _time_seed()
	var x: int = BLOCK_X_MAX
	var z: int = BLOCK_Z_MAX - 1
	var n: int = x * z
	for pass_i: int in [3, 2, 1]:
		for cur: int in range(n, 0, -1):
			var nseed: int = int(t["month"]) * int(t["day"]) + int(t["sec"]) + (int(t["hour"]) + cur) * 3 + seed_value * 9
			nseed = absi(nseed) % n
			var block := Vector2i(1 + nseed % x, 2 + nseed / x)
			if pass_i >= 2 and is_block_in_view(block):
				continue
			if _reserved_block(block):
				continue
			if pass_i >= 3 and block_used_by_other(id, block):
				continue
			var unit: Vector2i = random_unit_in_block(block, 1)
			if unit.x < 0:
				continue
			if unit.x < adjust or unit.x >= UT - adjust or unit.y < adjust or unit.y >= UT - adjust:
				continue
			return block_unit_to_cell(block, unit)
	return Vector2i(-1, -1)


## `search_empty_unit`: like `search_free_unit` but the unit is the hard, flat one nearest
## the acre centre (walking visitors: artist, carpet peddler).
func search_empty_unit(id: StringName, seed_value: int) -> Vector2i:
	var t: Dictionary = _time_seed()
	var x: int = BLOCK_X_MAX
	var z: int = BLOCK_Z_MAX - 1
	var n: int = x * z
	for pass_i: int in [3, 2, 1]:
		for cur: int in range(n, 0, -1):
			var nseed: int = int(t["month"]) * int(t["day"]) + int(t["sec"]) + (int(t["hour"]) + cur) * 7 - seed_value
			nseed = absi(nseed) % n
			var block := Vector2i(1 + nseed % x, 2 + nseed / x)
			if pass_i >= 2 and is_block_in_view(block):
				continue
			if _reserved_block(block):
				continue
			if pass_i >= 3 and block_used_by_other(id, block):
				continue
			var unit: Vector2i = central_unit_in_block(block, pass_i)
			if unit.x < 0:
				continue
			return block_unit_to_cell(block, unit)
	return Vector2i(-1, -1)


## `search_seaside_unit`: an acre on the beach row and a unit at the waves.
func search_seaside_unit(seed_value: int) -> Vector2i:
	var n: int = BLOCK_X_MAX
	var bx: int = 1 + posmod(seed_value + Clock.day + Clock.minute, n)
	var dock: Vector2i = block_of("dock")
	if Vector2i(bx, BLOCK_Z_MAX) == dock:
		bx = bx - 1 if bx > (BLOCK_X_MAX + 2) / 2 else bx + 1
	if is_block_in_view(Vector2i(bx, BLOCK_Z_MAX)):
		bx = bx - 2 if bx > (BLOCK_X_MAX + 2) / 2 else bx + 2
	bx = clampi(bx, 1, BLOCK_X_MAX)
	var unit: Vector2i = wave_unit(Vector2i(bx, BLOCK_Z_MAX))
	if unit.x >= 0:
		return block_unit_to_cell(Vector2i(bx, BLOCK_Z_MAX), unit)
	for i: int in range(BLOCK_X_MAX + 1, 0, -1):
		bx = 1 + posmod(bx + i, BLOCK_X_MAX)
		var b := Vector2i(bx, BLOCK_Z_MAX)
		if is_block_in_view(b):
			continue
		unit = wave_unit(b)
		if unit.x >= 0:
			return block_unit_to_cell(b, unit)
	return Vector2i(-1, -1)


## `mFI_GetWaveUtinBlock`: a sand unit with the sea directly south of it.
func wave_unit(block: Vector2i) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for uz: int in range(1, UT - 1):
		for ux: int in range(1, UT - 1):
			var cell: Vector2i = block_unit_to_cell(block, Vector2i(ux, uz))
			if not npc_can_stand(cell):
				continue
			if world.grid.terrain_at(cell) != WorldGrid.Terrain.SAND:
				continue
			var south: Vector2i = cell + Vector2i(0, 1)
			if world.grid.is_in_bounds(south) and world.grid.terrain_at(south) == WorldGrid.Terrain.WATER:
				candidates.append(Vector2i(ux, uz))
	if candidates.is_empty():
		return Vector2i(-1, -1)
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


## `neighbor_check`: `cell` or the first free neighbour from `neighbor_adjust`.
const NEIGHBOR_ADJUST: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(1, 1),
	Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(0, 2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(2, 0),
	Vector2i(-1, 2), Vector2i(2, 1), Vector2i(-2, -1), Vector2i(-1, -2),
]


func fixed_cell(block: Vector2i, unit: Vector2i, checked: bool = true) -> Vector2i:
	var cell: Vector2i = block_unit_to_cell(block, unit)
	if not checked or npc_can_stand(cell):
		return cell
	for off: Vector2i in NEIGHBOR_ADJUST:
		var u: Vector2i = Vector2i(clampi(unit.x + off.x, 0, UT - 1), clampi(unit.y + off.y, 0, UT - 1))
		var c: Vector2i = block_unit_to_cell(block, u)
		if npc_can_stand(c):
			return c
	return Vector2i(-1, -1)


## `get_unit_lot4sale`: an empty house lot (a SIGN reserve with no resident on it).
func free_lot(seed_value: int) -> Vector2i:
	var data: WorldData = world.layout if world != null else null
	if data == null:
		return Vector2i(-1, -1)
	var lots: Array[Vector2i] = []
	for r: Vector2i in data.reserve_cells:
		if not world.grid.is_occupied(r):
			lots.append(r)
	if lots.is_empty():
		return Vector2i(-1, -1)
	var t: Dictionary = _time_seed()
	for i: int in range(lots.size(), 0, -1):
		var nseed: int = int(t["sec"]) + int(t["month"]) * int(t["hour"]) + int(t["day"]) + (lots.size() - i) + seed_value * 3
		nseed = absi(nseed) % lots.size()
		if not is_block_in_view(cell_to_block(lots[nseed])):
			return lots[nseed]
	return lots[0]


## --- Remembered places (`mEv_place_data_c`) ---------------------------------------------


func place(id: StringName, index: int = 0) -> Dictionary:
	return _places.get("%s:%d" % [id, index], {})


func remember(id: StringName, index: int, cell: Vector2i, extra: Dictionary = {}) -> Dictionary:
	var rec: Dictionary = extra.duplicate()
	rec["event"] = String(id)
	rec["cell"] = cell
	_places["%s:%d" % [id, index]] = rec
	return rec


func forget(id: StringName, index: int = 0) -> void:
	_places.erase("%s:%d" % [id, index])


## `mEv_get_event_place`: the block an event's actor is in (Copper's hint), or (-1, -1).
static func event_block(id: StringName) -> Vector2i:
	var rec: Dictionary = _places.get("%s:0" % id, {})
	if rec.is_empty():
		return Vector2i(-1, -1)
	return cell_to_block(rec["cell"])


## The remembered cell for `(id, index)`, or `pick` evaluated once and remembered.
func place_once(id: StringName, index: int, pick: Callable) -> Vector2i:
	var rec: Dictionary = place(id, index)
	if not rec.is_empty():
		return rec["cell"]
	var cell: Vector2i = pick.call()
	if cell.x < 0:
		return cell
	remember(id, index, cell)
	return cell


## --- Festival map data (`m_event_map_npc`) ------------------------------------------------


static var _map_cache: Dictionary = {}


static func event_map(id: StringName) -> Dictionary:
	if _map_cache.is_empty():
		var f := FileAccess.open("res://data/events/event_map.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_map_cache = (parsed as Dictionary).get("events", {})
	return _map_cache.get(String(id), {})


## `mEvMN_GetEventSetUtInBlock`: `[{actor, cell}]` for the event's acre (pond variant picked
## by the pond acre's type, `mFI_GetPuleIdx`).
func map_actors(id: StringName) -> Array:
	var data: Dictionary = event_map(id)
	if data.is_empty():
		return []
	var kind: String = str(data.get("block_kind", "none"))
	var block: Vector2i = block_of(kind) if kind != "none" else Vector2i(-1, -1)
	if block.x < 0:
		return []
	var maps: Array = data.get("maps", [])
	var variant: int = int(blocks.get("pool_idx", 0)) if kind == "pool" else 0
	var entries: Array = maps[clampi(variant, 0, maps.size() - 1)]
	var out: Array = []
	for e: Variant in entries:
		var unit: Array = (e as Dictionary)["unit"]
		out.append({"actor": str((e as Dictionary)["actor"]), "cell": block_unit_to_cell(block, Vector2i(int(unit[0]), int(unit[1])))})
	return out
