class_name HandOver
extends RefCounted

## NPC ↔ player item hand-off (`handOverItem` / `aNPC_ANIM_TRANSFER*` / `GET*`).
## Plays body clips; full floating item actor waits. Used by first-job gifts and deliveries.

const NPC_TRANSFER := "npc_1_transfer1"
const NPC_TRANS_WAIT := "npc_1_trans_wait1"
const NPC_GET := "npc_1_get1"
const NPC_GET_PULL := "npc_1_get_pull1"
const NPC_GET_PUTAWAY := "npc_1_get_putaway1"

const PLY_TRANSFER := "ply_1_transfer1"
const PLY_TRANS_WAIT := "ply_1_trans_wait1"
const PLY_GET := "ply_1_get1"
const PLY_GET_PULL := "ply_1_get_pull1"
const PLY_GET_PUTAWAY := "ply_1_get_putaway1"

## Hold the transferred pose briefly (`aHOI_REQUEST_TRANS_WAIT`).
const TRANS_WAIT_HOLD := 0.35


## NPC hands an item to the player (`aNPC_DEMO_GIVE_ITEM` / first-job gifts).
static func npc_gives_to_player(npc: Node3D, player: Node3D, _item_id: StringName = &"") -> void:
	if npc == null or player == null:
		return
	var tree: SceneTree = npc.get_tree()
	if tree == null:
		return
	_face_each_other(npc, player)
	var locked: bool = _lock_player(player)
	await _play_pair(
		npc,
		[NPC_TRANSFER],
		player,
		[PLY_GET_PULL, PLY_GET],
		tree
	)
	## Brief hold while both keep the offer / take pose.
	await _hold_pair(npc, NPC_TRANS_WAIT, player, PLY_GET_PULL, tree, TRANS_WAIT_HOLD)
	await _play_one(player, [PLY_GET_PUTAWAY], tree)
	_idle(npc)
	_idle(player)
	_unlock_player(player, locked)


## Player hands an item to an NPC (first-job QUEST delivery).
static func player_gives_to_npc(player: Node3D, npc: Node3D, _item_id: StringName = &"") -> void:
	if npc == null or player == null:
		return
	var tree: SceneTree = player.get_tree()
	if tree == null:
		return
	_face_each_other(npc, player)
	var locked: bool = _lock_player(player)
	await _play_pair(
		player,
		[PLY_TRANSFER],
		npc,
		[NPC_GET_PULL, NPC_GET],
		tree
	)
	await _hold_pair(player, PLY_TRANS_WAIT, npc, NPC_GET_PULL, tree, TRANS_WAIT_HOLD)
	await _play_one(npc, [NPC_GET_PUTAWAY], tree)
	_idle(npc)
	_idle(player)
	_unlock_player(player, locked)


static func has_npc_transfer(npc: Node3D) -> bool:
	return _resolve(_anim_player(npc), NPC_TRANSFER) != ""


static func has_player_receive(player: Node3D) -> bool:
	var ap: AnimationPlayer = _anim_player(player)
	return _resolve(ap, PLY_GET_PULL) != "" or _resolve(ap, PLY_GET) != ""


static func _play_pair(
	a: Node3D,
	a_clips: Array[String],
	b: Node3D,
	b_clips: Array[String],
	tree: SceneTree
) -> void:
	var a_ap: AnimationPlayer = _anim_player(a)
	var b_ap: AnimationPlayer = _anim_player(b)
	var a_clip := _first_resolved(a_ap, a_clips)
	var b_clip := _first_resolved(b_ap, b_clips)
	var wait_a: float = _start_oneshot(a_ap, a_clip)
	var wait_b: float = _start_oneshot(b_ap, b_clip)
	var wait: float = maxf(wait_a, wait_b)
	if wait <= 0.0:
		await tree.create_timer(0.2).timeout
		return
	await tree.create_timer(wait).timeout


static func _play_one(actor: Node3D, clips: Array[String], tree: SceneTree) -> void:
	var ap: AnimationPlayer = _anim_player(actor)
	var clip := _first_resolved(ap, clips)
	var wait: float = _start_oneshot(ap, clip)
	if wait <= 0.0:
		await tree.create_timer(0.12).timeout
		return
	await tree.create_timer(wait).timeout


static func _hold_pair(
	a: Node3D,
	a_clip_suffix: String,
	b: Node3D,
	b_clip_suffix: String,
	tree: SceneTree,
	seconds: float
) -> void:
	var a_ap: AnimationPlayer = _anim_player(a)
	var b_ap: AnimationPlayer = _anim_player(b)
	_start_oneshot(a_ap, _resolve(a_ap, a_clip_suffix), true)
	_start_oneshot(b_ap, _resolve(b_ap, b_clip_suffix), true)
	await tree.create_timer(maxf(0.05, seconds)).timeout


static func _lock_player(player: Node3D) -> bool:
	if player == null or not player.has_method("set_busy"):
		return false
	if player.has_method("is_busy") and bool(player.call("is_busy")):
		return false
	player.call("set_busy", true)
	return true


static func _unlock_player(player: Node3D, locked: bool) -> void:
	if locked and player != null and player.has_method("set_busy"):
		player.call("set_busy", false)


static func _start_oneshot(ap: AnimationPlayer, clip: String, loop: bool = false) -> float:
	if ap == null or clip.is_empty():
		return 0.0
	var animation: Animation = ap.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	ap.speed_scale = 1.0
	ap.play(clip, 0.08)
	if loop or animation == null:
		return 0.0
	return maxf(0.05, animation.length)


static func _idle(actor: Node3D) -> void:
	if actor == null:
		return
	if actor.has_method("play_wait_anim"):
		actor.call("play_wait_anim")
		return
	var ap: AnimationPlayer = _anim_player(actor)
	var wait := _resolve(ap, "npc_1_wait1")
	if wait.is_empty():
		wait = _resolve(ap, "ply_1_wait1")
	if wait.is_empty() or ap == null:
		return
	var animation: Animation = ap.get_animation(wait)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR
	ap.play(wait, 0.12)


static func _face_each_other(a: Node3D, b: Node3D) -> void:
	_face_toward(a, b.global_position)
	_face_toward(b, a.global_position)


static func _face_toward(actor: Node3D, target: Vector3) -> void:
	if actor == null:
		return
	var to: Vector3 = target - actor.global_position
	to.y = 0.0
	if to.length_squared() <= 0.0001:
		return
	var yaw: float = atan2(to.x, to.z)
	if actor.has_method("set_facing"):
		actor.call("set_facing", yaw)
		return
	actor.rotation.y = yaw


static func _anim_player(actor: Node3D) -> AnimationPlayer:
	if actor == null:
		return null
	if actor.has_method("animation_player"):
		var custom: Variant = actor.call("animation_player")
		if custom is AnimationPlayer:
			return custom as AnimationPlayer
	return GeneratedVisual.find_animation_player(actor)


static func _first_resolved(ap: AnimationPlayer, clips: Array[String]) -> String:
	for suffix: String in clips:
		var hit := _resolve(ap, suffix)
		if not hit.is_empty():
			return hit
	return ""


static func _resolve(ap: AnimationPlayer, suffix: String) -> String:
	if ap == null or suffix.is_empty():
		return ""
	if ap.has_animation(suffix):
		return suffix
	for anim_name: String in ap.get_animation_list():
		if anim_name == suffix or anim_name.ends_with(suffix) or suffix in anim_name:
			return anim_name
	return ""
