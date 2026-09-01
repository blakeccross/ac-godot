class_name BugField
extends RefCounted

## Live insects on the field. Behavioral analog of `aINS_CTRL_ACTOR` with up to
## `aINS_ACTOR_NUM` (9) slots. Owned by the world scene, not an autoload.

## `aINS_ACTOR_NUM`
const MAX_ACTORS := 9
const CULL_DISTANCE := 600.0 * FieldCatalog.GX_TO_METERS
const SPAWN_MIN := 3.0
const SPAWN_MAX := CULL_DISTANCE * 0.75
const SPAWN_INTERVAL := 1.6

var actors: Array[BugActor] = []
var auto_spawn: bool = true

var _grid: WorldGrid = null
var _layout: WorldData = null
var _spawn_timer: float = 0.0
var _tool_swing: float = 0.0
var _net_swing: float = 0.0
var _net_origin: Vector3 = Vector3.ZERO
var _net_dir: Vector3 = Vector3.ZERO
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

const TOOL_SWING_SECONDS := 0.25
const NET_SWING_SECONDS := 0.35


func configure(grid: WorldGrid, layout: WorldData) -> void:
	_grid = grid
	_layout = layout
	actors.clear()
	_spawn_timer = 0.0


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
	var kept: Array[BugActor] = []
	for actor: BugActor in actors:
		if not actor.finished:
			kept.append(actor)
	actors = kept
	_tick_spawn(delta, sense)


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
		if actors.size() >= MAX_ACTORS:
			break
		if _occupied_cell(site.cell):
			continue
		var pool: Array[BugData] = BugCatalog.available(
			Clock.month, Clock.hour, int(BugData.Habitat.TREE), raining
		)
		if pool.is_empty():
			continue
		spawn(BugCatalog.roll(pool), BugData.Habitat.TREE, site.anchor)


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


func _tick_spawn(delta: float, sense: BugActor.Sense) -> void:
	if not auto_spawn or _grid == null or _layout == null or actors.size() >= MAX_ACTORS:
		return
	if not sense.has_player():
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = SPAWN_INTERVAL
	var raining: bool = Game.weather == &"rain"
	var sites: Array[BugHabitats.Site] = BugHabitats.sites_near(
		_layout, _grid, sense.player_position, SPAWN_MAX
	)
	if sites.is_empty():
		return
	var site: BugHabitats.Site = sites[_rng.randi_range(0, sites.size() - 1)]
	var pool: Array[BugData] = BugCatalog.available(
		Clock.month, Clock.hour, int(site.habitat), raining
	)
	if pool.is_empty() and site.habitat == BugData.Habitat.FLYING:
		pool = BugCatalog.available(Clock.month, Clock.hour, -1, raining)
	if pool.is_empty():
		return
	var bug: BugData = BugCatalog.roll(pool)
	var hab: BugData.Habitat = site.habitat
	if not bug.habitats.is_empty():
		for h: int in bug.habitats:
			if h == int(site.habitat):
				hab = h as BugData.Habitat
				break
	spawn(bug, hab, site.anchor)


func _occupied_cell(cell: Vector2i) -> bool:
	if _grid == null:
		return false
	for actor: BugActor in actors:
		if _grid.world_to_cell(actor.position) == cell:
			return true
	return false
