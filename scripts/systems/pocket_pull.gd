class_name PocketPull
extends RefCounted

## `Player_actor_Set_Item_Pickup` frames 20–40: lerp toward `left_hand_pos`, scale → 0.
## Pipeline clips run at 30 fps; the pull lasts the remaining half of PICKUP1 after the
## pocket write at frame 20.

const PULL_FRAMES := 20.0
const ANIM_FPS := 30.0


static func run(node: Node3D, hand_world: Callable) -> void:
	if node == null or not is_instance_valid(node):
		return
	var tree: SceneTree = node.get_tree()
	if tree == null:
		node.scale = Vector3.ZERO
		node.visible = false
		return
	var duration: float = PULL_FRAMES / ANIM_FPS
	var hand0: Vector3 = _safe_hand(hand_world, node.global_position)
	var offset: Vector3 = node.global_position - hand0
	var start_scale: Vector3 = node.scale
	var elapsed: float = 0.0
	while elapsed < duration and is_instance_valid(node):
		await tree.process_frame
		if not is_instance_valid(node):
			return
		elapsed += node.get_process_delta_time()
		var p: float = clampf(1.0 - elapsed / duration, 0.0, 1.0)
		var hand: Vector3 = _safe_hand(hand_world, hand0)
		node.global_position = hand + offset * p
		node.scale = start_scale * p
	if is_instance_valid(node):
		node.scale = Vector3.ZERO
		node.visible = false


static func hand_from_context(ctx: InteractionContext, fallback: Vector3) -> Callable:
	if ctx != null and ctx.actor != null and ctx.actor.has_method("left_hand_global"):
		var actor: Node = ctx.actor
		return func() -> Vector3: return actor.call("left_hand_global") as Vector3
	if ctx != null and ctx.actor is Node3D:
		var body := ctx.actor as Node3D
		return func() -> Vector3: return body.global_position + Vector3(0.0, 0.9, 0.0)
	return func() -> Vector3: return fallback + Vector3(0.0, 0.9, 0.0)


static func _safe_hand(hand_world: Callable, fallback: Vector3) -> Vector3:
	if hand_world.is_null():
		return fallback
	var v: Variant = hand_world.call()
	if typeof(v) != TYPE_VECTOR3:
		return fallback
	return v as Vector3
