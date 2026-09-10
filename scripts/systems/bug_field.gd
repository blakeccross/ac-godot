class_name BugField
extends RefCounted

## Live insects on the field — the `aINS_CTRL_ACTOR` analog with `aINS_ACTOR_NUM` (9)
## slots. Owned by the world scene, not an autoload. Drives the shared 30 Hz frame
## loop (`aINS_actor_move`) for every slot, then culls and runs one spawn attempt
## per acre the player enters (`aSOI_insect_set`).

## `aINS_ACTOR_NUM`
const MAX_ACTORS := 9
## `aINS_searchRegistSpace(aINS_MAKE_NEW)` — field births take slots 0..7.
const MAX_FIELD_SPAWNS := 8
## `aINS_cull_check`: drop when >600 GX from player and in another acre.
const CULL_DISTANCE := 600.0 * FieldCatalog.GX_TO_METERS
const GAME_FPS := 30.0

## `l_insect_birth_sum` (`ac_set_ovl_insect.c`): (min, additional_range). Only
## RED_DRAGONFLY (10) and FIREFLY (27) birth a swarm of 6–8; everything else is 1.
## Indices are `aINS_INSECT_TYPE_*` / `BugData.type_index`.
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
var _step_acc: float = 0.0
var _field_action: Dictionary = {"kind": 0, "cell": Vector2i(-1, -1)}

const TOOL_SWING_SECONDS := 0.25
const NET_SWING_SECONDS := 0.35


func configure(grid: WorldGrid, layout: WorldData) -> void:
	_grid = grid
	_layout = layout
	actors.clear()
	_spawned_acre = Vector2i(-999, -999)
	_step_acc = 0.0


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


## Generic "player acted on this cell" — releases any bug settled there
## (`aINS_set_pl_act_tim` / dig-up / axe).
func notify_player_action(cell: Vector2i) -> void:
	for actor: BugActor in actors:
		if _grid != null and _grid.world_to_cell(actor.position) == cell:
			actor.release()


## `aINS_set_pl_act_tim(action, ut_x, ut_z)`: latch a field action + its cell for
## the programs (SHAKE_TREE wakes bagworms, DIG_SCOOP wakes mole crickets, REFLECT_*
## wakes pill bugs). Consumed once by `take_field_action`.
func notify_field_action(kind: int, cell: Vector2i) -> void:
	_field_action = {"kind": kind, "cell": cell}


func take_field_action() -> Dictionary:
	var out: Dictionary = _field_action
	_field_action = {"kind": 0, "cell": Vector2i(-1, -1)}
	return out


func tick(delta: float, sense: BugActor.Sense) -> void:
	if _tool_swing > 0.0:
		sense.player_swung_tool = true
	_tool_swing = maxf(_tool_swing - delta, 0.0)
	if _net_swing > 0.0:
		sense.net_swing_active = true
		sense.net_swing_origin = _net_origin
		sense.net_swing_dir = _net_dir
	_net_swing = maxf(_net_swing - delta, 0.0)

	## `aSOI_insect_set` is driven by the set manager on acre transitions, not by
	## the insect frame loop — run it once per call, guarded by `_spawned_acre`.
	_tick_spawn(sense)

	_step_acc += delta
	var budget: int = 8
	while _step_acc >= 1.0 / GAME_FPS and budget > 0:
		_step_acc -= 1.0 / GAME_FPS
		budget -= 1
		_frame(sense)


func _frame(sense: BugActor.Sense) -> void:
	for actor: BugActor in actors:
		if not actor.finished:
			actor.frame(sense)
	_cull_distant(sense)
	var kept: Array[BugActor] = []
	for actor: BugActor in actors:
		if not actor.finished:
			kept.append(actor)
	actors = kept


func spawn(bug: BugData, habitat: BugData.Habitat, at: Vector3, released: bool = false) -> BugActor:
	if bug == null or actors.size() >= MAX_ACTORS:
		return null
	var actor: BugActor = BugActor.create(bug, habitat, at, _rng, released)
	if _grid != null:
		actor.block = BugHabitats.acre_of_world_pos(_grid, at)
		## Tie the HIDE trigger to the cell it spawned on (tree / rock / dig spot).
		var cell: Vector2i = _grid.world_to_cell(at)
		var prog: BugProgram = actor._prog
		if prog.has_method("set_tree_cell"):
			prog.call("set_tree_cell", cell)
		if prog.has_method("set_dig_cell"):
			prog.call("set_dig_cell", cell)
		if prog.has_method("set_rock_cell"):
			prog.call("set_rock_cell", cell)
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
	## `aSOI_ins_block_check` / `aINS_chk_live_insect`: one attempt per acre entry,
	## and only if that acre does not already host a live insect.
	if _acre_has_insect(acre):
		return
	if not _acre_allows_insects(acre):
		return
	_try_spawn_in_acre(acre)


func _try_spawn_in_acre(acre: Vector2i) -> void:
	var raining: bool = Game.weather == &"rain"
	## `aSOI_ins_make_range_data` + `aSOI_ins_decide_insect` + `aSOI_ins_get_idx`.
	var pool: Array[BugSpawnEntry] = BugSpawnScheduler.build_pool(_rng)
	var entry: BugSpawnEntry = BugSpawnScheduler.decide(
		pool, _layout, _grid, acre, raining, Callable(self, "_occupied_cell"), _rng
	)
	if entry == null:
		return
	var bug: BugData = BugCatalog.get_by_type(entry.type_index)
	if bug == null:
		return
	## `aSOI_ins_make`: birth count, each pick a fresh live unit.
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
		spawn(bug, BugData.habitat_from_spawn_area(resolved_area, prefer_flower), site.anchor)
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



func _filtered_entries(
	source: Array[BugSpawnEntry], raining: bool, acre: Vector2i, only_spawn_area: int
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
	## `aINS_cull_check`: destruct flagged actors; despawn the rest when >600 GX from
	## the player and in another acre.
	if _grid == null:
		return
	var player_acre: Vector2i = (
		BugHabitats.acre_of_world_pos(_grid, sense.player_position) if sense.has_player()
		else Vector2i(-999, -999)
	)
	for actor: BugActor in actors:
		if actor.finished:
			continue
		if actor.f_destruct:
			actor.finished = true
			continue
		if not sense.has_player() or actor.caught:
			continue
		if actor.released:
			continue  ## released bugs fade out via alpha_time, not cull
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
