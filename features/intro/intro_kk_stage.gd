class_name IntroKkStage
extends RefCounted

## K.K. opening (`ac_npc_p_sel` / `SCENE_PLAYERSELECT`) before the train: the stage's
## numbers. The timing lives on the scene's nodes (`intro_kk.tscn`: `TalkDelay`,
## `SilentTimer`, the `Outro` clip), each citing its decomp count.

## `aNPS_talk_end_chk` demo orders: 4haku → wait_e1 (253); 255=`TALK1` → default_animation 4haku.
enum Pose { STRUM, LOOK_UP }

## cKF morph_counter −N → |N|/30 s crossfade (same as train Rover).
const MORPH_STRUM := 3.0 / DecompTime.FRAME_HZ
const MORPH_LOOK_UP := 5.0 / DecompTime.FRAME_HZ

## The player-select floor is y 40 in the decomp (K.K.'s actor y in a GAFE01 savestate);
## our acre floor is y 0, so decomp heights drop by this much.
const DECOMP_FLOOR_Y_GX := 40.0
## Camera lock from `aNPS_actor_ct`: look (100, 60, 60), eye (100, 130, 210), FOV 40, the
## same values as the live View in that savestate, kept floor-relative.
const CAM_CENTER_GX := Vector3(100.0, 60.0 - DECOMP_FLOOR_Y_GX, 60.0)
const CAM_EYE_GX := Vector3(100.0, 130.0 - DECOMP_FLOOR_Y_GX, 210.0)
const CAM_FOV := 40.0
const CAM_NEAR_GX := 100.0
const CAM_FAR_GX := 400.0
## Decomp near=100 GX → 5 m literally; that clips KK's front (body → sliver). ~1 GX.
const CAM_NEAR_METERS := 0.1  ## 2 GX
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

const ACRE_PATH := "res://scenes/world/acres/grd_player_select.tscn"
const KK_PATH := "res://assets/generated/characters/villagers/end_1.glb"

## `l_mEnv_kcolor_data_p_sel` (m_kankyo.c) — void stage, warm key light.
const AMBIENT_COLOR := Color(30.0 / 255.0, 30.0 / 255.0, 80.0 / 255.0)
const SUN_COLOR := Color(1.0, 1.0, 200.0 / 255.0)
## GX light direction toward the sun; Godot shines along −Z.
const SUN_DIR_GX := Vector3(0.0, 89.0, 79.0)
## Same plane as the table, tipped toward overhead. (0, 89, 79) lights the cheeks
## almost as hard as the crown, so the face stays one flat white. This puts the
## clamped hit on the top of the head.
const CHARACTER_SUN_DIR := Vector3(0.0, 115.0, 55.0)
## GC captures show a black void; decomp clear `(22,27,94)` is unused with fog off.
## Atmosphere is the scrolling spot2 fog texture on the XLU cone, not clear color.
const BG_COLOR := Color(0.0, 0.0, 0.0)
const FOG_COLOR := Color(100.0 / 255.0, 100.0 / 255.0, 120.0 / 255.0)


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
