class_name BugField
extends RefCounted

## Live insects on the field. Behavioral analog of `aINS_CTRL_ACTOR` with up to
## `aINS_ACTOR_NUM` (9) slots. Owned by the world scene, not an autoload.
##
## Spawning mirrors `aSOI_insect_set`: one attempt when the player **enters an acre**,
## skipped if that acre already has a live insect (`aINS_chk_live_insect`). Field
## births use slots 0–7 (`aINS_searchRegistSpace` / `aINS_MAKE_NEW`); slot 8 is for
## exist/release paths.

## `aINS_ACTOR_NUM`
const MAX_ACTORS := 9
## `aINS_searchRegistSpace(aINS_MAKE_NEW)` — only indices `< aINS_ACTOR_NUM - 1`.
const MAX_FIELD_SPAWNS := 8
## `aINS_cull_check`: drop when far and in another acre (600 GX).
const CULL_DISTANCE := 600.0 * FieldCatalog.GX_TO_METERS
## Per-type `l_insect_birth_sum` (min, additional_range). Most types birth 1.
const BIRTH_SUM: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0),
	Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0),
	Vector2i(6, 3), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0),
	Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0),
	Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0),
	Vector2i(1, 0), Vector2i(1, 0), Vector2i(6, 3), Vector2i(1, 0), Vector2i(1, 0),
	Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0),
	Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0),
	Vector2i(1, 0),
]

var actors: Array[BugActor] = []
var auto_spawn: bool = true

var _grid: WorldGrid = null
var _layout: WorldData = null
var _tool_swing: float = 0.0
var _net_swing: float = 0.0
var _net_origin: Vector3 = Vector3.ZERO
var _net_dir: Vector3 = Vector3.ZERO
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _spawned_acre: Vector2i = Vector2i(-999, -999)

const TOOL_SWING_SECONDS := 0.25
const NET_SWING_SECONDS := 0.35


func configure(grid: WorldGrid, layout: WorldData) -> void:
	_grid = grid
	_layout = layout
	actors.clear()
	_spawned_acre = Vector2i(-999, -999)


func seed_rng(value: int) -> void:
	_rng.seed = value


func actor_count() -> int:
	return actors.size()


func notify_tool_swing() -> void:
	_tool_swing = TOOL_SWING_SECONDS


func notify_net_swing(origin: Vector3, direction: Vector3) -> void:
	_net_swing = NET_SWING_SECONDS
	_net_origin = origin
	_net_dir = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.FORWARD


func notify_player_action(cell: Vector2i) -> void:
	for actor: BugActor in actors:
		if _grid != null and _grid.world_to_cell(actor.position) == cell:
			actor.release()


func tick(delta: float, sense: BugActor.Sense) -> void:
	if _tool_swing > 0.0:
		sense.player_swung_tool = true
	_tool_swing = maxf(_tool_swing - delta, 0.0)
	if _net_swing > 0.0:
		sense.net_swing_active = true
		sense.net_swing_origin = _net_origin
		sense.net_swing_dir = _net_dir
	_net_swing = maxf(_net_swing - delta, 0.0)
	for actor: BugActor in actors:
		actor.tick(delta, sense)
	_cull_distant(sense)
	var kept: Array[BugActor] = []
	for actor: BugActor in actors:
		if not actor.finished:
			kept.append(actor)
	actors = kept
	_tick_spawn(sense)


func spawn(bug: BugData, habitat: BugData.Habitat, at: Vector3) -> BugActor:
	if bug == null or actors.size() >= MAX_ACTORS:
		return null
	var actor: BugActor = BugActor.create(bug, habitat, at, _rng)
	actors.append(actor)
	return actor


## Place one insect on each tree in the layout (test town and similar).
func seed_trees() -> void:
	if _layout == null or _grid == null:
		return
	var raining: bool = Game.weather == &"rain"
	for site: BugHabitats.Site in BugHabitats.tree_sites(_layout, _grid):
		if actors.size() >= MAX_FIELD_SPAWNS:
			break
		if _occupied_cell(site.cell):
			continue
		var entry: BugSpawnEntry = _roll_tree_entry(raining)
		if entry == null:
			continue
		var bug: BugData = BugCatalog.get_by_type(entry.type_index)
		if bug == null:
			continue
		spawn(bug, BugData.Habitat.TREE, site.anchor)


func find_in_net(origin: Vector3, direction: Vector3) -> BugActor:
	var best: BugActor = null
	var best_dist: float = INF
	for actor: BugActor in actors:
		if actor.finished or actor.caught:
			continue
		if not actor.in_net_volume(origin, direction, Netting.SWING_LENGTH, Netting.SWING_RADIUS):
			continue
		var dist: float = actor.position.distance_to(origin)
		if dist < best_dist:
			best_dist = dist
			best = actor
	return best


func clear() -> void:
	actors.clear()
	_spawned_acre = Vector2i(-999, -999)


func _tick_spawn(sense: BugActor.Sense) -> void:
	if not auto_spawn or _grid == null or _layout == null:
		return
	if not sense.has_player():
		return
	if actors.size() >= MAX_FIELD_SPAWNS:
		return
	var acre: Vector2i = BugHabitats.acre_of_world_pos(_grid, sense.player_position)
	if acre == _spawned_acre:
		return
	_spawned_acre = acre
	## `aSOI_ins_block_check` / `aINS_chk_live_insect`: one attempt per acre entry, and
	## only if that acre does not already host a live insect.
	if _acre_has_insect(acre):
		return
	if not _acre_allows_insects(acre):
		return
	_try_spawn_in_acre(acre)


func _try_spawn_in_acre(acre: Vector2i) -> void:
	var raining: bool = Game.weather == &"rain"
	var entry: BugSpawnEntry = _roll_field_entry(acre, raining)
	if entry == null:
		return
	var bug: BugData = BugCatalog.get_by_type(entry.type_index)
	if bug == null:
		return
	var birth_num: int = _birth_count(entry.type_index)
	for _i: int in birth_num:
		if actors.size() >= MAX_FIELD_SPAWNS:
			return
		if not _spawn_one_in_acre(bug, entry.spawn_area, acre, raining):
			return


func _spawn_one_in_acre(bug: BugData, spawn_area: int, acre: Vector2i, raining: bool) -> bool:
	var resolved_area: int = BugHabitats.resolve_spawn_area(spawn_area, _layout, _grid, acre)
	var sites: Array[BugHabitats.Site] = BugHabitats.sites_for_spawn_area(
		resolved_area, _layout, _grid, acre, Callable(self, "_occupied_cell"), raining
	)
	var site: BugHabitats.Site = BugHabitats.pick_site(sites, _rng)
	if site == null:
		return false
	var prefer_flower: bool = resolved_area == 1
	return (
		spawn(
			bug,
			BugData.habitat_from_spawn_area(resolved_area, prefer_flower),
			site.anchor
		)
		!= null
	)


func _birth_count(type_index: int) -> int:
	if type_index < 0 or type_index >= BIRTH_SUM.size():
		return 1
	var row: Vector2i = BIRTH_SUM[type_index]
	if row.y <= 0:
		return row.x
	return row.x + _rng.randi_range(0, row.y - 1)


func _roll_tree_entry(raining: bool) -> BugSpawnEntry:
	var pool: Array[BugSpawnEntry] = _filtered_entries(
		BugSpawnTable.entries_for(Clock.month, Clock.hour), raining, Vector2i(-1, -1), 0
	)
	return BugCatalog.roll_spawn_entry(pool, _rng, false)


func _roll_field_entry(acre: Vector2i, raining: bool) -> BugSpawnEntry:
	var pool: Array[BugSpawnEntry] = _filtered_entries(
		BugSpawnTable.entries_for(Clock.month, Clock.hour), raining, acre, -1
	)
	return BugCatalog.roll_spawn_entry(pool, _rng, true)


func _filtered_entries(
	source: Array[BugSpawnEntry],
	raining: bool,
	acre: Vector2i,
	only_spawn_area: int
) -> Array[BugSpawnEntry]:
	var out: Array[BugSpawnEntry] = []
	for entry: BugSpawnEntry in source:
		if only_spawn_area >= 0 and entry.spawn_area != only_spawn_area:
			continue
		var resolved: int = BugHabitats.resolve_spawn_area(entry.spawn_area, _layout, _grid, acre)
		if not BugSpawnTable.weather_allows(resolved, raining):
			continue
		if not BugHabitats.has_spawn_area(
			entry.spawn_area, _layout, _grid, acre, Callable(self, "_occupied_cell"), raining
		):
			continue
		out.append(entry)
	return out


func _acre_has_insect(acre: Vector2i) -> bool:
	## `aINS_chk_live_insect`: any live insect whose block matches.
	for actor: BugActor in actors:
		if actor.finished:
			continue
		if BugHabitats.acre_of_world_pos(_grid, actor.position) == acre:
			return true
	return false


func _acre_allows_insects(acre: Vector2i) -> bool:
	## `aSOI_ins_block_check`: no insects on offing / open-ocean border acres.
	if _layout == null or _layout.acre_types.size() != TownFieldGenerator.BLOCK_TOTAL:
		return true
	if acre.x < 0 or acre.x >= TownFieldGenerator.BLOCK_X:
		return false
	if acre.y < 0 or acre.y >= TownFieldGenerator.BLOCK_Z:
		return false
	if not VillagerWalk.is_fg_block(acre):
		return false
	var visual: StringName = &""
	if _layout.acre_visuals.size() == TownFieldGenerator.BLOCK_TOTAL:
		visual = StringName(_layout.acre_visuals[acre.y * TownFieldGenerator.BLOCK_X + acre.x])
	if visual != &"" and FieldCatalog.is_ocean_acre_visual(visual):
		return false
	return true


func _cull_distant(sense: BugActor.Sense) -> void:
	## `aINS_cull_check`: despawn when >600 GX from player and in another acre.
	if not sense.has_player() or _grid == null:
		return
	var player_acre: Vector2i = BugHabitats.acre_of_world_pos(_grid, sense.player_position)
	for actor: BugActor in actors:
		if actor.finished or actor.action == BugActor.Action.FLEE:
			continue
		var dist: float = Vector2(
			actor.position.x - sense.player_position.x, actor.position.z - sense.player_position.z
		).length()
		if dist <= CULL_DISTANCE:
			continue
		if BugHabitats.acre_of_world_pos(_grid, actor.position) != player_acre:
			actor.finished = true


func _occupied_cell(cell: Vector2i) -> bool:
	if _grid == null:
		return false
	for actor: BugActor in actors:
		if _grid.world_to_cell(actor.position) == cell:
			return true
	return false
