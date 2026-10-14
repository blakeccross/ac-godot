class_name NpcEventPresenter
extends EventPresenter

## One visitor NPC at one spot (`make_actor_in_*_block` + the actor's `ct`). Subclasses pick
## the scene and the spot; the spot is remembered for the day (`mEv_reserve_common_place`).

## `EventNpc` scene to instance.
var scene_path: String = ""
## Where to stand: "free" (`make_actor_in_free_block`), "empty" (`make_move_actor_in_free_block`),
## "seaside", "lot" (an empty house lot), or "fixed" (`block_kind` + `unit`).
var placement: String = "free"
var block_kind: String = ""
var unit: Vector2i = Vector2i(7, 7)
## `adjust` for `search_free_unit` (units kept clear of the acre edge).
var adjust: int = 1
var yaw: float = 0.0
var npc: EventNpc


func start() -> bool:
	var cell: Vector2i = mgr.place_once(id, 0, pick_cell)
	if cell.x < 0:
		return false
	var packed: PackedScene = load(scene_path) as PackedScene
	var node: Node3D = packed.instantiate() as Node3D if packed != null else null
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
		"free":
			return mgr.search_free_unit(id, place_seed(), adjust)
		"empty":
			return mgr.search_empty_unit(id, place_seed())
		"seaside":
			return mgr.search_seaside_unit(place_seed())
		"lot":
			return mgr.free_lot(place_seed())
		"fixed":
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
