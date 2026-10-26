class_name MouthFlap
extends SkeletonModifier3D

## Skeletal mouths: heads drawn with `talk_type` 1 (`npc_draw_data.c` — Blathers, Nook,
## ducks, birds, …) have no mouth texture; joints 22–23 (`aNPC_part_tbl01`, the jaw and the
## `mouth_*_model` bone) always take their rotation from the `kutipaku` clip instead of the
## body clip. While a line is uttering it plays (`speed` 0.5 a tick = the clip's own 30 fps),
## runs on briefly after, then parks on the first (shut) frame (`aNPC_tex_anm_ctrl`).

const CLIP_DEFAULT := "npc_1_kutipaku1"
const CLIP_ALT := "npc_1_kutipaku2"
## Skeletons drawn with `talk_type` 1. A `mouth_*_model` bone alone does not tell: goats,
## mice and moles carry one but talk with a mouth texture.
const SKELETAL_MOUTHS: Array[StringName] = [
	&"ant", &"bev", &"boa", &"bpt", &"brd", &"chn", &"cml", &"crd", &"duk", &"elp", &"fob",
	&"fox", &"gor", &"grf", &"hgh", &"hgs", &"hip", &"hrs", &"kab", &"kgr", &"lrc", &"oct",
	&"ost", &"owl", &"pbr", &"pga", &"pgb", &"pgn", &"pkn", &"plb", &"rcc", &"rcd", &"rcf",
	&"rcn", &"rcs", &"rhn", &"seg", &"tig", &"ttl", &"tuk", &"wls", &"wol",
]
## `aNPC_set_anime`: shape banks 107 / 148 / 191 / 253 / 286 / 291 / 330 / 401 flap with
## `KUTIPAKU2`.
const ALT_CLIP_SKELETONS: Array[StringName] = [
	&"chn", &"duk", &"kgr", &"ost", &"owl", &"pbr", &"pgn", &"rhn",
]
const JOINTS: Array[int] = [22, 23]
## `kutipaku_timer = 8`: ticks the flap keeps going once the text stops.
const TAIL_SECONDS := 8.0 / DecompTime.TICK_HZ

var _clip: Animation
## [bone index, rotation track index] for each joint the clip animates.
var _tracks: Array[Vector2i] = []
var _time: float = 0.0
var _tail: float = 0.0


## The `kutipaku` clip a skeleton code (`owl`, `rcn`) talks with, or "" for mouth textures.
static func clip_for(skeleton_code: StringName) -> String:
	if skeleton_code not in SKELETAL_MOUTHS:
		return ""
	return CLIP_ALT if skeleton_code in ALT_CLIP_SKELETONS else CLIP_DEFAULT


## Adds the modifier to `visual`'s skeleton (or returns the one already there) for the
## skeleton code's clip. Null when that skeleton talks with a mouth texture instead.
static func attach(visual: Node, skeleton_code: StringName) -> MouthFlap:
	var clip_name: String = clip_for(skeleton_code)
	if visual == null or clip_name.is_empty():
		return null
	var anim_player: AnimationPlayer = VisualAnimation.find_animation_player(visual)
	if anim_player == null or not anim_player.has_animation(clip_name):
		return null
	var skels: Array[Node] = visual.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return null
	var skel := skels[0] as Skeleton3D
	for child: Node in skel.get_children():
		if child is MouthFlap:
			return child as MouthFlap
	var flap := MouthFlap.new()
	flap.name = "MouthFlap"
	flap._clip = anim_player.get_animation(clip_name)
	flap._bind_tracks(skel)
	if flap._tracks.is_empty():
		flap.free()
		return null
	skel.add_child(flap)
	return flap


func tick(delta: float, uttering: bool) -> void:
	if uttering:
		_tail = TAIL_SECONDS
	elif _tail > 0.0:
		_tail = maxf(0.0, _tail - delta)
	else:
		_time = 0.0
		return
	_time = fposmod(_time + delta, maxf(_clip.length, 0.001))


## Test-only: no in-game callers; kept for tests.
func is_flapping() -> bool:
	return _time > 0.0 or _tail > 0.0


func _bind_tracks(skel: Skeleton3D) -> void:
	_tracks.clear()
	for joint: int in JOINTS:
		if joint >= skel.get_bone_count():
			continue
		var bone_name: String = skel.get_bone_name(joint)
		for track: int in _clip.get_track_count():
			if _clip.track_get_type(track) != Animation.TYPE_ROTATION_3D:
				continue
			if String(_clip.track_get_path(track)).get_slice(":", 1) == bone_name:
				_tracks.append(Vector2i(joint, track))
				break


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or _clip == null:
		return
	for entry: Vector2i in _tracks:
		skel.set_bone_pose_rotation(entry.x, _clip.rotation_track_interpolate(entry.y, _time))
