class_name ActorPipe
extends RefCounted

## Actor-against-actor collision (`ClObjPipe` OC: `CollisionCheck_OC_Pipe_Vs_Pipe` →
## `CollisionCheck_setOC_HitInfo`). Two overlapping pipes are pushed apart along the line
## between their centres by the overlap, split by weight, and the push lands before the
## terrain check (`Actor_position_move` adds `collision_vec`, then BG). Neither is a wall: a
## walking player and a villager each give way by half.
##
## Each participant joins `GROUP` and answers `pipe_radius()`, `pipe_height()`,
## `pipe_weight()` and `pipe_active()`, then calls `push(self)` once a physics frame and adds
## the result to its position.

const GROUP := &"actor_pipe"
## `status_data.weight` (`m_collision_obj.h`): 0xFF never moves, 0xFE only yields to 0xFF.
const WEIGHT_NORMAL := 50
const WEIGHT_HEAVY := 254
const WEIGHT_IMMOVABLE := 255
## `Player_actor_OcInfoData_forStand` and `aNPC_CoInfoData`: radius 20 GX each; the player's
## pipe is 60 GX tall, an NPC's 30.
const RADIUS := 20.0 * FieldCatalog.GX_TO_METERS
const PLAYER_HEIGHT := 60.0 * FieldCatalog.GX_TO_METERS
const NPC_HEIGHT := 30.0 * FieldCatalog.GX_TO_METERS


## The part of an overlap `self_weight` moves when it meets `other_weight` (`coldis1`).
static func share(self_weight: int, other_weight: int) -> float:
	var self_kind: int = _kind(self_weight)
	var other_kind: int = _kind(other_weight)
	match self_kind:
		WEIGHT_IMMOVABLE:
			return 0.0
		WEIGHT_HEAVY:
			if other_kind == WEIGHT_IMMOVABLE:
				return 1.0
			return 0.5 if other_kind == WEIGHT_HEAVY else 0.0
		_:
			if other_kind != WEIGHT_NORMAL:
				return 1.0
			var total: int = self_weight + other_weight
			return 0.5 if total == 0 else float(other_weight) / float(total)


static func _kind(weight: int) -> int:
	if weight >= WEIGHT_IMMOVABLE:
		return WEIGHT_IMMOVABLE
	if weight == WEIGHT_HEAVY:
		return WEIGHT_HEAVY
	return WEIGHT_NORMAL


## Pushes resolved this physics frame, by instance id (`CollisionCheck_OC` runs every pair, then
## each actor applies its sum): the first actor to ask takes the snapshot, so the split stays
## the same whichever of a pair moves first.
static var _frame: int = -1
static var _pushes: Dictionary = {}


## World-space XZ push for `actor` this physics frame.
static func push(actor: Node3D) -> Vector3:
	if actor == null or not actor.is_inside_tree():
		return Vector3.ZERO
	var frame: int = Engine.get_physics_frames()
	if frame != _frame:
		_frame = frame
		_pushes = resolve(actor.get_tree().get_nodes_in_group(GROUP))
	return _pushes.get(actor.get_instance_id(), Vector3.ZERO)


## Every active pair among `actors`, from their positions now: instance id → summed push.
static func resolve(actors: Array) -> Dictionary:
	var live: Array[Node3D] = []
	for node: Node in actors:
		if node is Node3D and bool(node.call("pipe_active")):
			live.append(node as Node3D)
	var out: Dictionary = {}
	for i: int in live.size():
		var a: Node3D = live[i]
		for j: int in range(i + 1, live.size()):
			var b: Node3D = live[j]
			var pa: Vector3 = a.global_position
			var pb: Vector3 = b.global_position
			## `Math3D_pipeVsPipe_cl`: the heights must overlap, then the circles.
			if pa.y + float(a.call("pipe_height")) < pb.y or pa.y > pb.y + float(b.call("pipe_height")):
				continue
			var reach: float = float(a.call("pipe_radius")) + float(b.call("pipe_radius"))
			var away := Vector2(pa.x - pb.x, pa.z - pb.z)
			var dist: float = away.length()
			if dist > reach:
				continue
			## Stacked exactly: the first of the pair goes -X (`collision_vec.x -= diff`).
			var dir: Vector2 = away / dist if dist > 0.0001 else Vector2(-1.0, 0.0)
			var overlap: Vector2 = dir * (reach - dist)
			var wa: int = int(a.call("pipe_weight"))
			var wb: int = int(b.call("pipe_weight"))
			var da: Vector2 = overlap * share(wa, wb)
			var db: Vector2 = -overlap * share(wb, wa)
			out[a.get_instance_id()] = out.get(a.get_instance_id(), Vector3.ZERO) + Vector3(da.x, 0.0, da.y)
			out[b.get_instance_id()] = out.get(b.get_instance_id(), Vector3.ZERO) + Vector3(db.x, 0.0, db.y)
	return out
