class_name IntroKkStage
extends RefCounted

## K.K. opening (`ac_npc_p_sel` / `SCENE_PLAYERSELECT`) before the train.
## Timers are decomp frame counts at 60 Hz.

signal ready_for_talk
signal fade_finished
signal pose_changed(pose: int)

enum Phase { STRUM, TALK, FADE, DONE }
## `aNPS_talk_end_chk` demo orders: 4haku → wait_e1 (253); 255=`TALK1` → default_animation 4haku.
enum Pose { STRUM, LOOK_UP }

## `aNPS_schedule_init_proc`: strum before first talk request.
const STRUM_FRAMES := 440
## After talk ends: `strum_timer = 150`, `bgm_stop_timer = 80`.
const FADE_FRAMES := 150
const BGM_STOP_FRAMES := 80
## Fade alpha ramps while `strum_timer < 70`.
const FADE_RAMP_FRAMES := 70
## Idle on MainNormal / choice before `aNPC_MANPU_CODE_RESET` (255 → TALK1 → 4haku).
const SILENT_FRAMES := 600

const FRAME_HZ := 60.0
## cKF morph_counter −N → |N|/30 s crossfade (same as train Rover).
const MORPH_HZ := 30.0
const MORPH_STRUM := 3.0 / MORPH_HZ
const MORPH_LOOK_UP := 5.0 / MORPH_HZ

## Camera lock from `aNPS_actor_ct`, look-at lowered so KK clears the dialogue box.
const CAM_CENTER_GX := Vector3(100.0, 10.0, 60.0)
const CAM_EYE_GX := Vector3(100.0, 130.0, 210.0)
const CAM_FOV := 40.0
const CAM_NEAR_GX := 100.0
const CAM_FAR_GX := 400.0
## Decomp near=100 GX → 5 m literally; that clips KK's front (body → sliver). ~1 GX.
const CAM_NEAR_METERS := 2.0 * FieldCatalog.GX_TO_METERS
const CAM_FAR_METERS := CAM_FAR_GX * FieldCatalog.GX_TO_METERS

## FG ut (2, 1) center — `player_select_actable` + `mFI_UNIT_BASE_SIZE` 40.
const KK_SPAWN_GX := Vector3(100.0, 0.0, 60.0)
## Camera eye is +Z of spawn. cKF meshes face +Z at yaw 0 (same as villagers).
## `PI` pointed his back at the camera.
const KK_YAW := 0.0

const ANIM_STRUM := "npc_1_4haku_e1"
## `aNPC_MANPU_CODE_RESET_KEKE` (253) → look up, stop strumming.
const ANIM_LOOK_UP := "npc_1_wait_e1"
## Post-staffroll strum rate in `aNPS_actor_move`.
const STRUM_SPEED := 0.5
const FACE_SPECIES := &"end"

const BGM_ID := &"intro_kk"

const ACRE_PATH := "res://assets/generated/environment/acres/grd_player_select.glb"
const KK_PATH := "res://assets/generated/characters/villagers/end_1.glb"
const GUITAR_PATH := "res://assets/generated/furniture/int_sum_guitar01.glb"

## `l_mEnv_kcolor_data_p_sel` (m_kankyo.c) — void stage, warm key light.
const AMBIENT_COLOR := Color(30.0 / 255.0, 30.0 / 255.0, 80.0 / 255.0)
const SUN_COLOR := Color(1.0, 1.0, 200.0 / 255.0)
## GX light direction toward the sun; Godot shines along −Z.
const SUN_DIR_GX := Vector3(0.0, 89.0, 79.0)
const BG_COLOR := Color(0.0, 0.0, 0.0)


static func resolve_clip(anim: AnimationPlayer, suffix: String) -> String:
	## Prefer exact clip name, else shortest animation that ends with `suffix`.
	if anim == null:
		return ""
	if anim.has_animation(suffix):
		return suffix
	var best: String = ""
	for anim_name: String in anim.get_animation_list():
		if not anim_name.ends_with(suffix):
			continue
		if best.is_empty() or anim_name.length() < best.length():
			best = anim_name
	return best


static func anim_for_pose(pose: Pose) -> String:
	match pose:
		Pose.LOOK_UP:
			return ANIM_LOOK_UP
		_:
			return ANIM_STRUM


static func morph_for_pose(pose: Pose) -> float:
	## Destination clip's `morph_counter` magnitude / 30 Hz.
	match pose:
		Pose.LOOK_UP:
			return MORPH_LOOK_UP
		_:
			return MORPH_STRUM


var phase: Phase = Phase.STRUM
var pose: Pose = Pose.STRUM
var fade_alpha: float = 0.0

var _strum_left: float = float(STRUM_FRAMES) / FRAME_HZ
var _fade_left: float = float(FADE_FRAMES) / FRAME_HZ
var _bgm_stop_left: float = -1.0
var _silent_frames: float = 0.0
var _talk_signaled: bool = false
var _fade_done: bool = false


static func gx_to_meters(gx: Vector3) -> Vector3:
	return gx * FieldCatalog.GX_TO_METERS


static func required_asset_paths() -> PackedStringArray:
	return PackedStringArray([ACRE_PATH, KK_PATH])


static func missing_assets() -> PackedStringArray:
	var out := PackedStringArray()
	for path: String in required_asset_paths():
		if not ResourceLoader.exists(path):
			out.append(path)
	return out


static func sun_basis() -> Basis:
	## Light travels opposite the decomp “toward sun” vector.
	var travel := -SUN_DIR_GX.normalized()
	return Basis.looking_at(travel, Vector3.RIGHT if absf(travel.y) > 0.95 else Vector3.UP)


func reset() -> void:
	phase = Phase.STRUM
	pose = Pose.STRUM
	fade_alpha = 0.0
	_strum_left = float(STRUM_FRAMES) / FRAME_HZ
	_fade_left = float(FADE_FRAMES) / FRAME_HZ
	_bgm_stop_left = -1.0
	_silent_frames = 0.0
	_talk_signaled = false
	_fade_done = false


func begin_fade() -> void:
	if phase == Phase.FADE or phase == Phase.DONE:
		return
	phase = Phase.FADE
	_fade_left = float(FADE_FRAMES) / FRAME_HZ
	_bgm_stop_left = float(BGM_STOP_FRAMES) / FRAME_HZ
	fade_alpha = 0.0
	_set_pose(Pose.STRUM)


func tick(delta: float, awaiting_input: bool = false) -> void:
	match phase:
		Phase.STRUM:
			_strum_left = maxf(_strum_left - delta, 0.0)
			if _strum_left <= 0.0 and not _talk_signaled:
				_talk_signaled = true
				phase = Phase.TALK
				## `aNPS_talk_end_chk`: leave 4haku → wait_e1 as soon as talk runs.
				_set_pose(Pose.LOOK_UP)
				ready_for_talk.emit()
		Phase.TALK:
			_tick_talk_idle(delta, awaiting_input)
		Phase.FADE:
			_tick_fade(delta)
		_:
			pass


func _tick_talk_idle(delta: float, awaiting_input: bool) -> void:
	## `silent_counter` only climbs on MainNormal / choice; resets while text lays in.
	if awaiting_input:
		_silent_frames = minf(_silent_frames + delta * FRAME_HZ, float(SILENT_FRAMES))
	else:
		_silent_frames = 0.0
	## Mirrors `aNPS_talk_end_chk` order 253 / 255:
	## silent < 600 + 4haku → wait_e1; silent >= 600 + not 4haku → TALK1 → default 4haku.
	if _silent_frames >= float(SILENT_FRAMES):
		if pose != Pose.STRUM:
			_set_pose(Pose.STRUM)
	elif pose == Pose.STRUM:
		_set_pose(Pose.LOOK_UP)


func _set_pose(next: Pose) -> void:
	if pose == next:
		return
	pose = next
	pose_changed.emit(pose)


func request_strum() -> void:
	_set_pose(Pose.STRUM)


func request_look_up() -> void:
	_set_pose(Pose.LOOK_UP)


func _tick_fade(delta: float) -> void:
	if _bgm_stop_left > 0.0:
		_bgm_stop_left -= delta
		if _bgm_stop_left <= 0.0:
			_bgm_stop_left = -1.0
			## `mBGMPsComp_make_ps_wipe(0x421C)` — crossfade out intro_kk.
			Audio.stop_bgm()
	_fade_left = maxf(_fade_left - delta, 0.0)
	var frames_left: float = _fade_left * FRAME_HZ
	if frames_left < float(FADE_RAMP_FRAMES):
		fade_alpha = clampf(1.0 - frames_left / float(FADE_RAMP_FRAMES), 0.0, 1.0)
	else:
		fade_alpha = 0.0
	if _fade_left <= 0.0 and not _fade_done:
		_fade_done = true
		fade_alpha = 1.0
		phase = Phase.DONE
		fade_finished.emit()
