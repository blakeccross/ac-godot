class_name IntroTrainSleepNpc
extends RefCounted

## Background passenger (`SP_NPC_SLEEP_OBABA`) — decomp `aNSO_*` + `aNPC_think_in_block`.

const ANIM_KOKKURI_D1 := "npc_1_kokkuri_d1"
const ANIM_KOKKURI_D2 := "npc_1_kokkuri_d2"
## `start_demo1` ut (4,4) center + `aNSO_actor_ct` birth offset (−6 GX, −24 GX).
const SPAWN_GX := Vector3(174.0, 0.0, 156.0)
## `aNPC_think_in_block_init_proc` appear index 0 (`appear_rotation` default for SPNPC).
const APPEAR_ROTATION := 0
## `mv_posZ[0]` from think-in-block (−120 GX walk target offset; final bench Z if walk completes).
const THINK_BLOCK_OFFSET_GX := Vector3(0.0, 0.0, -120.0)
## Bench cushion height GX (`rom_train_in` seat surface).
const SEAT_CUSHION_Y_GX := 40.0

var _host: Node3D
var _anim: AnimationPlayer
var _clip: String = ""
var _loops_left: int = 0
var _pending: bool = false


static func decomp_appear_yaw(appear: int) -> float:
	## `angle_table[]` in `ac_npc_think_in_block.c_inc` → `WorldGrid` / `aMR_angle_table`.
	var decomp_deg: PackedFloat32Array = PackedFloat32Array([180.0, 0.0, -90.0, 90.0])
	var idx: int = clampi(appear, 0, decomp_deg.size() - 1)
	return deg_to_rad(decomp_deg[idx])


static func spawn_yaw() -> float:
	return decomp_appear_yaw(APPEAR_ROTATION)


func bind(host: Node3D, anim: AnimationPlayer) -> void:
	_host = host
	_anim = anim
	if _host != null:
		_host.global_position = IntroTrainStage.gx_to_meters(SPAWN_GX)
		_host.rotation = Vector3.ZERO
		_host.rotation.y = spawn_yaw()
	_start_sleep()


func tick(_delta: float) -> void:
	if _pending:
		_flush_pending()


func _start_sleep() -> void:
	## Decomp `aNSO_setupAction(aNSO_ACT_SLEEP)` → `aNPC_ANIM_KOKKURI_D1` only.
	_loops_left = 2 + randi() % 3
	_play(ANIM_KOKKURI_D1, false, true)


func _align_to_seat() -> void:
	if _host == null:
		return
	var vis: Node3D = _host.get_node_or_null("GeneratedVisual") as Node3D
	if vis == null:
		return
	GeneratedVisual.align_actor_to_height_gx(vis, SEAT_CUSHION_Y_GX)


func _play(suffix: String, loop: bool, snap: bool = false) -> void:
	if _anim == null:
		_clip = suffix
		_pending = true
		return
	var clip: String = IntroTrainStage.resolve_rover_clip(_anim, suffix)
	if clip.is_empty():
		return
	if _clip == clip and _anim.is_playing() and not snap:
		return
	_clip = clip
	var animation: Animation = _anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var blend: float = 0.0 if snap else IntroTrainStage.ANIM_MORPH_BLEND
	_anim.play(clip, blend)
	if snap:
		_anim.advance(0.0)
		_align_to_seat()
	if _anim.animation_finished.is_connected(_on_anim_finished):
		_anim.animation_finished.disconnect(_on_anim_finished)
	if not loop:
		_anim.animation_finished.connect(_on_anim_finished)


func _on_anim_finished(anim_name: StringName) -> void:
	if _clip != "" and String(anim_name) != _clip:
		return
	if _anim != null and _anim.animation_finished.is_connected(_on_anim_finished):
		_anim.animation_finished.disconnect(_on_anim_finished)
	_pending = true


func _flush_pending() -> void:
	_pending = false
	if _clip == ANIM_KOKKURI_D1:
		_loops_left -= 1
		if _loops_left <= 0:
			_loops_left = 2 + randi() % 3
			_play(ANIM_KOKKURI_D2, false)
		else:
			_play(ANIM_KOKKURI_D1, false)
	elif _clip == ANIM_KOKKURI_D2:
		_start_sleep()
	else:
		_start_sleep()
