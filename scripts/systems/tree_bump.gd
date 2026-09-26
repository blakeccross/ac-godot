class_name TreeBump
extends RefCounted

## Walking up to a tree shakes it a little (`Player_actor_check_little_shake_tree`).
## Every player frame, in any state but the shake itself: among the 8 units around the
## player's own, the collideable tree whose centre is under one unit away, within 10 GX
## of the feet in height, and closest to straight ahead (inside ±45°) is the target. It
## fires once, then the player's 3-entry table (`shake_tree_*`) holds that tree until its
## timer runs out and the player is no longer aimed at it — so pushing on a tree does
## not shake it again and again.

## Target must be inside ±45° of the player's facing (`min_angle = 45°`).
const CONE := deg_to_rad(45.0)
## `dy > 10.0` GX between the unit-centre ground and the player's feet.
const MAX_DY := 10.0 * FieldCatalog.GX_TO_METERS
## `*shake_timer_p = 16.0f` / `84.0f` (little / button shake), in 60 Hz frames.
const LITTLE_TICKS := 16.0
const BIG_TICKS := 84.0
const SLOTS := 3
const NONE := Vector2i(-1, -1)

var _cells: Array[Vector2i] = [NONE, NONE, NONE]
var _timers: Array[float] = [0.0, 0.0, 0.0]
var _little: Array[bool] = [false, false, false]


## `Player_actor_Get_shake_tree_position_and_itemNo`: the tree the player is aimed at.
static func pick(
	pos: Vector3, yaw: float, data: WorldData, grid: WorldGrid, trees: Array[Node3D]
) -> Node3D:
	var here: Vector2i = grid.world_to_cell(pos)
	var reach_sq: float = grid.cell_size * grid.cell_size
	var best: Node3D = null
	var best_angle: float = CONE
	for tree: Node3D in trees:
		var cell: Vector2i = grid.world_to_cell(_at(tree))
		var off: Vector2i = cell - here
		if maxi(absi(off.x), absi(off.y)) != 1:
			continue
		var centre: Vector3 = grid.cell_to_world(cell)
		var ground: float = FieldCollision.ground_y_at(data, grid, centre)
		if FieldCollision.has_floor(ground) and absf(ground - pos.y) > MAX_DY:
			continue
		var dx: float = centre.x - pos.x
		var dz: float = centre.z - pos.z
		if dx * dx + dz * dz >= reach_sq:
			continue
		var angle: float = absf(angle_difference(yaw, atan2(dx, dz)))
		if angle < best_angle:
			best_angle = angle
			best = tree
	return best


## One player frame. Returns the tree that just started its little shake, else null.
func tick(
	delta: float, pos: Vector3, yaw: float, data: WorldData, grid: WorldGrid, trees: Array[Node3D]
) -> Node3D:
	var target: Node3D = pick(pos, yaw, data, grid, trees)
	var target_cell: Vector2i = NONE
	var fired: Node3D = null
	if target != null:
		target_cell = grid.world_to_cell(_at(target))
		if _set_little(target_cell):
			fired = target
	## Entries whose timer ran out are dropped once the player is aimed elsewhere.
	for i: int in SLOTS:
		if _timers[i] <= 0.0 and _used(i) and _cells[i] != target_cell:
			_cells[i] = NONE
	for i: int in SLOTS:
		_timers[i] = maxf(_timers[i] - delta / DecompTime.TICK_SEC, 0.0)
	return fired


## `Player_actor_Set_shake_tree_table(little = FALSE)`: the button shake claims the tree
## for 84 frames, so walking up to it right after doesn't shake it a second time.
func note_big_shake(cell: Vector2i) -> void:
	for i: int in SLOTS:
		if _cells[i] == cell:
			_timers[i] = BIG_TICKS
			_little[i] = false
			return
	var slot: int = _free_slot()
	if slot >= 0:
		_cells[slot] = cell
		_timers[slot] = BIG_TICKS
		_little[slot] = false


## `Get_tree_shaken_table_index`: trees whose entry is still running (timer > 0), little or
## button. `mPlib_Check_tree_shaken` reads exactly this, for insects clinging to a trunk.
func active_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i: int in SLOTS:
		if _timers[i] > 0.0 and _used(i):
			out.append(_cells[i])
	return out


func has_entry(cell: Vector2i) -> bool:
	return _cells.has(cell)


static func _at(node: Node3D) -> Vector3:
	return node.global_position if node.is_inside_tree() else node.position


func _set_little(cell: Vector2i) -> bool:
	## `Check_able_shake_tree_table`: a tree already in the table never re-triggers.
	if _cells.has(cell):
		return false
	var slot: int = _free_slot()
	if slot < 0:
		return false
	_cells[slot] = cell
	_timers[slot] = LITTLE_TICKS
	_little[slot] = true
	return true


func _free_slot() -> int:
	for i: int in SLOTS:
		if not _used(i):
			return i
	return -1


func _used(i: int) -> bool:
	return _cells[i].x >= 0 and _cells[i].y >= 0
