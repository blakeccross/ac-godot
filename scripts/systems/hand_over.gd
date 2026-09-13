class_name HandOver
extends RefCounted

## NPC ↔ player item hand-off (`handOverItem` / `aNPC_ANIM_TRANSFER*` / `GET*`).
## Body clips plus the floating `obj_item_*` card (`HandOverItem` / `aHOI_actor_*`).

const NPC_TRANSFER := "npc_1_transfer1"
const NPC_TRANS_WAIT := "npc_1_trans_wait1"
const NPC_GET := "npc_1_get1"
const NPC_GET_PULL := "npc_1_get_pull1"
## `aNPC_ANIM_GET_PULL_WAIT1` (index 30 — `curator->npc_class.talk_info.default_animation
## = 30` in `aCR_get_demo_end_wait`): the "examining" hold once an offered item has been
## pulled in, kept through the identification message before the outcome forks.
const NPC_GET_PULL_WAIT := "npc_1_get_pull_wait1"
const NPC_GET_PUTAWAY := "npc_1_get_putaway1"
## `aNPC_act_get_return` / `aCR_TALK_RETURN_DEMO_*`: an NPC un-taking something it just
## examined (rejections) — a different body clip from `NPC_TRANSFER`'s fresh hand-over.
const NPC_GET_RETURN := "npc_1_get_return1"

const PLY_TRANSFER := "ply_1_transfer1"
const PLY_TRANS_WAIT := "ply_1_trans_wait1"
const PLY_GET := "ply_1_get1"
const PLY_GET_PULL := "ply_1_get_pull1"
const PLY_GET_PUTAWAY := "ply_1_get_putaway1"

## Hold the transferred pose briefly (`aHOI_REQUEST_TRANS_WAIT`).
const TRANS_WAIT_HOLD := 0.35
## `aCR_get_demo_end_wait` → `aCR_msg_win_open_wait`: the examining hold lasts as long as
## the identification message is up. We don't gate on the dialogue's own advance, so this
## is a fixed beat long enough to read the shortest outcome line before the fork.
const EXAMINE_HOLD := 0.6


## Godot raises "previously freed" at the call boundary of a TYPED Node3D argument even
## before a callee's own is_instance_valid guard runs — so this check itself must take
## untyped Variants, or passing a freed node into it would trip the same error.
static func _both_valid(a: Variant, b: Variant) -> bool:
	return is_instance_valid(a) and is_instance_valid(b)


## NPC hands an item to the player (`aNPC_DEMO_GIVE_ITEM` / first-job gifts).
static func npc_gives_to_player(npc: Node3D, player: Node3D, item_id: StringName = &"") -> void:
	if npc == null or player == null:
		return
	var tree: SceneTree = npc.get_tree()
	if tree == null:
		return
	_face_each_other(npc, player)
	var locked: bool = _lock_player(player)
	var prop: HandOverItem = _spawn_prop(npc, item_id)
	if prop != null:
		prop.set_master(npc)
		prop.begin_mode(HandOverItem.Mode.TRANSFER)
	await _play_pair(
		npc,
		[NPC_TRANSFER],
		player,
		[PLY_GET_PULL, PLY_GET],
		tree
	)
	if not _both_valid(npc, player):
		_free_prop(prop)
		return
	## Brief hold while both keep the offer / take pose.
	if prop != null and is_instance_valid(prop):
		prop.begin_mode(HandOverItem.Mode.TRANS_WAIT)
	await _hold_pair(npc, NPC_TRANS_WAIT, player, PLY_GET_PULL, tree, TRANS_WAIT_HOLD)
	if not _both_valid(npc, player):
		_free_prop(prop)
		return
	## Master switches to the player for putaway (`aHOI_chg_master_proc`).
	if prop != null and is_instance_valid(prop):
		prop.set_master(player, true)
		prop.begin_mode(HandOverItem.Mode.PUTAWAY)
	await _play_one(player, [PLY_GET_PUTAWAY], tree)
	_free_prop(prop)
	if _both_valid(npc, player):
		_idle(npc)
		_idle(player)
		_unlock_player(player, locked)


## Player offers an item and the NPC rejects it (`aCR_TALK_GET_DEMO_*` then
## `aCR_TALK_RETURN_DEMO_*`): the same take-and-examine beat as an accepted donation
## (`player_gives_to_npc`'s opening), held through the identification message, then
## handed back instead of filed away — the NPC plays `NPC_GET_RETURN` (un-taking) rather
## than a fresh `NPC_TRANSFER`, and the card returns to the player's own pocket.
static func player_offers_npc_rejects(player: Node3D, npc: Node3D, item_id: StringName = &"") -> void:
	if npc == null or player == null:
		return
	var tree: SceneTree = player.get_tree()
	if tree == null:
		return
	_face_each_other(npc, player)
	var locked: bool = _lock_player(player)
	var prop: HandOverItem = _spawn_prop(player, item_id)
	if prop != null:
		prop.set_master(player)
		prop.begin_mode(HandOverItem.Mode.TRANSFER)
	## GET: player extends the item, the NPC takes it (`aCR_get_demo_start_wait`).
	await _play_pair(player, [PLY_TRANSFER], npc, [NPC_GET_PULL, NPC_GET], tree)
	if not _both_valid(npc, player):
		_free_prop(prop)
		return
	if prop != null and is_instance_valid(prop):
		prop.begin_mode(HandOverItem.Mode.TRANS_WAIT)
	## Examining hold (`default_animation = aNPC_ANIM_GET_PULL_WAIT1`) through the
	## identification message, before the accept/reject fork.
	await _hold_pair(player, PLY_TRANS_WAIT, npc, NPC_GET_PULL_WAIT, tree, EXAMINE_HOLD)
	if not _both_valid(npc, player):
		_free_prop(prop)
		return
	## RETURN: the NPC extends the item back out instead of keeping it.
	if prop != null and is_instance_valid(prop):
		prop.set_master(npc, true)
		prop.begin_mode(HandOverItem.Mode.TRANSFER)
	await _play_pair(npc, [NPC_GET_RETURN, NPC_TRANSFER], player, [PLY_GET_PULL, PLY_GET], tree)
	if not _both_valid(npc, player):
		_free_prop(prop)
		return
	if prop != null and is_instance_valid(prop):
		prop.begin_mode(HandOverItem.Mode.TRANS_WAIT)
	await _hold_pair(npc, NPC_TRANS_WAIT, player, PLY_GET_PULL, tree, TRANS_WAIT_HOLD)
	if not _both_valid(npc, player):
		_free_prop(prop)
		return
	## Back into the player's own pocket.
	if prop != null and is_instance_valid(prop):
		prop.set_master(player, true)
		prop.begin_mode(HandOverItem.Mode.PUTAWAY)
	await _play_one(player, [PLY_GET_PUTAWAY], tree)
	_free_prop(prop)
	if _both_valid(npc, player):
		_idle(npc)
		_idle(player)
		_unlock_player(player, locked)


## Player hands an item to an NPC (first-job QUEST delivery).
static func player_gives_to_npc(player: Node3D, npc: Node3D, item_id: StringName = &"") -> void:
	if npc == null or player == null:
		return
	var tree: SceneTree = player.get_tree()
	if tree == null:
		return
	_face_each_other(npc, player)
	var locked: bool = _lock_player(player)
	var prop: HandOverItem = _spawn_prop(player, item_id)
	if prop != null:
		prop.set_master(player)
		prop.begin_mode(HandOverItem.Mode.TRANSFER)
	await _play_pair(
		player,
		[PLY_TRANSFER],
		npc,
		[NPC_GET_PULL, NPC_GET],
		tree
	)
	if not _both_valid(npc, player):
		_free_prop(prop)
		return
	if prop != null and is_instance_valid(prop):
		prop.begin_mode(HandOverItem.Mode.TRANS_WAIT)
	await _hold_pair(player, PLY_TRANS_WAIT, npc, NPC_GET_PULL, tree, TRANS_WAIT_HOLD)
	if not _both_valid(npc, player):
		_free_prop(prop)
		return
	if prop != null and is_instance_valid(prop):
		prop.set_master(npc, true)
		prop.begin_mode(HandOverItem.Mode.PUTAWAY)
	await _play_one(npc, [NPC_GET_PUTAWAY], tree)
	_free_prop(prop)
	if _both_valid(npc, player):
		_idle(npc)
		_idle(player)
		_unlock_player(player, locked)


static func has_npc_transfer(npc: Node3D) -> bool:
	return _resolve(_anim_player(npc), NPC_TRANSFER) != ""


static func has_player_receive(player: Node3D) -> bool:
	var ap: AnimationPlayer = _anim_player(player)
	return _resolve(ap, PLY_GET_PULL) != "" or _resolve(ap, PLY_GET) != ""


static func _spawn_prop(host: Node3D, item_id: StringName) -> HandOverItem:
	if host == null or item_id == &"":
		return null
	var parent: Node = host.get_tree().current_scene if host.get_tree() != null else host
	if parent == null:
		parent = host
	return HandOverItem.spawn(parent, item_id)


static func _free_prop(prop: Variant) -> void:
	if prop != null and is_instance_valid(prop):
		(prop as HandOverItem).finish()


static func _play_pair(
	a: Node3D,
	a_clips: Array[String],
	b: Node3D,
	b_clips: Array[String],
	tree: SceneTree
) -> void:
	## Multi-phase sequences (`player_offers_npc_rejects` especially) span several
	## seconds of real time across many awaits — either actor can be freed mid-sequence
	## (scene change, the node despawning) before the next phase runs.
	var a_ap: AnimationPlayer = _anim_player(a) if is_instance_valid(a) else null
	var b_ap: AnimationPlayer = _anim_player(b) if is_instance_valid(b) else null
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
	var ap: AnimationPlayer = _anim_player(actor) if is_instance_valid(actor) else null
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
	var a_ap: AnimationPlayer = _anim_player(a) if is_instance_valid(a) else null
	var b_ap: AnimationPlayer = _anim_player(b) if is_instance_valid(b) else null
	_start_oneshot(a_ap, _resolve(a_ap, a_clip_suffix), true)
	_start_oneshot(b_ap, _resolve(b_ap, b_clip_suffix), true)
	await tree.create_timer(maxf(0.05, seconds)).timeout


static func _lock_player(player: Node3D) -> bool:
	if not is_instance_valid(player) or not player.has_method("set_busy"):
		return false
	if player.has_method("is_busy") and bool(player.call("is_busy")):
		return false
	player.call("set_busy", true)
	return true


static func _unlock_player(player: Node3D, locked: bool) -> void:
	if locked and is_instance_valid(player) and player.has_method("set_busy"):
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
	if not is_instance_valid(actor):
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
	if not is_instance_valid(a) or not is_instance_valid(b):
		return
	_face_toward(a, b.global_position)
	_face_toward(b, a.global_position)


static func _face_toward(actor: Node3D, target: Vector3) -> void:
	if not is_instance_valid(actor):
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
	if not is_instance_valid(actor):
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
