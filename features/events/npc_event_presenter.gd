class_name NpcEventPresenter
extends EventPresenter

## One visitor NPC at one spot (`make_actor_in_*_block` + the actor's `ct`). Each visitor's
## `.tres` picks the scene and the spot; subclasses add the visitor's own start rules. The
## spot is remembered for the day (`mEv_reserve_common_place`).

enum Placement {
	## A random acre (`make_actor_in_free_block`).
	FREE,
	## `make_move_actor_in_free_block`.
	EMPTY,
	## A beach acre at the waves (`make_actor_in_seaside_block`).
	SEASIDE,
	## An empty house lot.
	LOT,
	## `block_kind` + `unit` (`make_actor_in_fixed_block`).
	FIXED,
}

## `EventNpc` scene to instance.
@export var scene: PackedScene
@export var placement: Placement = Placement.FREE
## The acre for `FIXED`.
@export var block_kind: EventManager.BlockKind = EventManager.BlockKind.STATION
@export var unit: Vector2i = Vector2i(7, 7)
## `adjust` for `search_free_unit` (units kept clear of the acre edge).
@export_range(0, 7) var adjust: int = 1
@export var yaw: float = 0.0

var npc: EventNpc


func start() -> bool:
	var cell: Vector2i = mgr.place_once(id, 0, pick_cell)
	if cell.x < 0:
		return false
	var node: Node3D = scene.instantiate() as Node3D if scene != null else null
	if node == null:
		return false
	configure(node)
	mgr.add_actor(id, node, cell, face_yaw(cell), 0)
	npc = node as EventNpc
	placed(node)
	return true


## Seed stand-in for `ctrl->type + ev_name + id` (the acre roll also mixes in the clock).
func place_seed() -> int:
	return absi(String(id).hash()) % 997


func pick_cell() -> Vector2i:
	match placement:
		Placement.FREE:
			return mgr.search_free_unit(id, place_seed(), adjust)
		Placement.EMPTY:
			return mgr.search_empty_unit(id, place_seed())
		Placement.SEASIDE:
			return mgr.search_seaside_unit(place_seed())
		Placement.LOT:
			return mgr.free_lot(place_seed())
		Placement.FIXED:
			var block: Vector2i = mgr.block_of(block_kind)
			if block.x < 0:
				return Vector2i(-1, -1)
			return mgr.fixed_cell(block, unit)
	return Vector2i(-1, -1)


func face_yaw(_cell: Vector2i) -> float:
	return yaw


## Before the node enters the tree (species, flags `_ready` reads).
func configure(_node: Node3D) -> void:
	pass


## After the node is in town.
func placed(_node: Node3D) -> void:
	pass
