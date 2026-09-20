class_name PlayerSe
extends RefCounted

## Player action SE on animation frames (`m_player_main_*` / `m_player_sound.c_inc`).
## Schedules one-shots via `Audio.play_se`. Outcome-specific hits also call helpers.

const ANIM_FPS := 30.0

## Clip basename → [[frame, se_id], …] always played for that clip.
const CLIP_MARKS: Dictionary = {
	&"ply_1_axe_swing1": [[10.0, &"tool_furi"]],
	## `Player_actor_SetSound_AXE_FURI_axe_common`: same whoosh, frame 10, for the open-air swing.
	&"ply_1_axe_suka1": [[10.0, &"tool_furi"]],
	## Dig scoop1 is outcome-driven (`HoleUse.dig` / flower dig), not every dig1 clip —
	## stump dig uses the same clip with kiribasu SE instead.
	&"ply_1_fill_up1": [[11.0, &"scoop_umeru"]],
	&"ply_1_fill_up_i1": [[18.0, &"scoop_umeru"]],
	## `aMR_SetOpenFtrDemoData`: the piece opens as the player reaches for it.
	&"ply_1_kagu_open_h1": [[0.0, &"drawer_open"]],
	&"ply_1_kagu_open_k1": [[0.0, &"ftr_door_open"]],
	&"ply_1_kagu_open_d1": [[0.0, &"ftr_door_open"]],
	&"ply_1_kagu_close_h1": [[6.0, &"drawer_close"]],
	&"ply_1_kagu_close_k1": [[6.0, &"ftr_door_close"]],
	&"ply_1_kagu_close_d1": [[6.0, &"ftr_door_close"]],
	&"ply_1_pickup1": [[10.0, &"item_get"], [20.0, &"gasagoso"]],
	&"ply_1_sao_swing1": [[20.0, &"rod_stroke"]],
	&"ply_1_net_swing1": [[0.0, &"tool_furi"]],
	## `Player_actor_sound_JUMP` at setup, `Player_actor_sound_SIT` at frame 18 (`SetSound_Sitdown`).
	&"ply_1_sitdown1": [[0.0, &"jump"], [18.0, &"hard_chair_sit"]],
	&"ply_1_inbed_L1": [[0.0, &"bed_in"]],
	&"ply_1_inbed_R1": [[0.0, &"bed_in"]],
	&"ply_1_turi_hiki1": [[0.0, &"10c"]],
	&"ply_1_get_t1": [[0.0, &"rod_back"]],
	&"ply_1_not_get_t1": [[0.0, &"rod_back"]],
	## `Player_actor_sound_GASAGOSO` at `setup_main_Putin_item` / `Takeout_item`.
	&"ply_1_putaway1": [[0.0, &"gasagoso"]],
	&"ply_1_putaway_t1": [[0.0, &"gasagoso"]],
	&"ply_1_get_putaway1": [[0.0, &"gasagoso"]],
	&"ply_1_get_m1": [[0.0, &"ami_hit"]],
}


static func schedule_clip(at: Node, clip_name: StringName, extra: Array = []) -> void:
	## Fire SE at decomp frame marks. `extra` is [[frame, id], …] for outcome overlays.
	if at == null or not is_instance_valid(at):
		return
	var tree: SceneTree = at.get_tree()
	if tree == null:
		return
	var base: StringName = _basename(clip_name)
	var marks: Array = []
	if CLIP_MARKS.has(base):
		marks.append_array(CLIP_MARKS[base])
	marks.append_array(extra)
	for mark: Variant in marks:
		if typeof(mark) != TYPE_ARRAY or (mark as Array).size() < 2:
			continue
		var frame: float = float((mark as Array)[0])
		var se_id: StringName = (mark as Array)[1] as StringName
		if se_id == &"":
			continue
		var delay: float = maxf(0.0, frame / ANIM_FPS)
		if delay <= 0.001:
			Audio.play_se(se_id, at)
			continue
		var timer: SceneTreeTimer = tree.create_timer(delay)
		timer.timeout.connect(_play.bind(at, se_id), CONNECT_ONE_SHOT)


static func axe_cut(at: Node) -> void:
	## Called from tree chop at effect frame 15.
	_play_now(at, &"axe_cut")


static func axe_hit(at: Node) -> void:
	_play_now(at, &"axe_hit")


static func tree_touch(at: Node) -> void:
	## `Player_actor_sound_tree_touch`: walking into a shakeable tree.
	_play_now(at, &"tree_touch")


static func tree_yurasu(at: Node) -> void:
	## Shake effect frame 10.
	_play_now(at, &"tree_yurasu")


static func scoop_rock(at: Node) -> void:
	_play_now(at, &"scoop_hit")


static func scoop_tree(at: Node) -> void:
	_play_now(at, &"scoop_tree_hit")


static func scoop_dig(at: Node) -> void:
	## Dig effect frame 15 — play immediately when interact fires.
	_play_now(at, &"scoop1")


static func stump_dig(at: Node) -> void:
	## Effect @15 → kiribasu_scoop now; kiribasu_out @20 (= +5 frames).
	_play_now(at, &"kiribasu_scoop")
	_play_at_frame(at, 5.0, &"kiribasu_out")


static func buried_dig(at: Node) -> void:
	## Effect @21.
	_play_now(at, &"item_horidashi")


static func net_get(at: Node) -> void:
	_play_now(at, &"tool_get")


static func bobber_splash(at: Node) -> void:
	_play_now(at, &"10b")


static func karaburi(at: Node) -> void:
	_play_now(at, &"karaburi")


static func bee_sting(at: Node) -> void:
	_play_now(at, &"hachi_sasareru")


static func drawer_open(at: Node) -> void:
	_play_now(at, &"drawer_open")


static func furniture_door_open(at: Node) -> void:
	_play_now(at, &"ftr_door_open")


static func _play_now(at: Node, se_id: StringName) -> void:
	if at != null and is_instance_valid(at):
		Audio.play_se(se_id, at)
	else:
		Audio.play_se(se_id)


static func _play_at_frame(at: Node, frame: float, se_id: StringName) -> void:
	if at == null or not is_instance_valid(at):
		return
	var tree: SceneTree = at.get_tree()
	if tree == null:
		Audio.play_se(se_id, at)
		return
	var delay: float = maxf(0.0, frame / ANIM_FPS)
	if delay <= 0.001:
		Audio.play_se(se_id, at)
		return
	tree.create_timer(delay).timeout.connect(_play.bind(at, se_id), CONNECT_ONE_SHOT)


static func _play(at: Node, se_id: StringName) -> void:
	if at == null or not is_instance_valid(at):
		return
	Audio.play_se(se_id, at)


static func _basename(clip_name: StringName) -> StringName:
	var s := String(clip_name)
	var slash: int = s.rfind("/")
	if slash >= 0:
		s = s.substr(slash + 1)
	return StringName(s)
