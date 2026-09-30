class_name HandCursor
extends Control

## `m_hand_ovl`'s pointing hand (`cKF_bs_r_hnd`, `hnd_sasu` loop) for menus that point
## at a slot. The skinned model renders into `Host/Viewport`; `point_at` places the
## fingertip. Same framing as the pockets hand in `inventory_overlay.gd`.

const HND_GLB := "res://assets/generated/characters/other/hnd.glb"
## Fingertip inside the card, as a fraction of `size`.
const TIP := Vector2(0.3, 0.55)

@onready var _viewport: SubViewport = $Host/Viewport
@onready var _world: Node3D = $Host/Viewport/World
@onready var _camera: Camera3D = $Host/Viewport/World/Camera

var _anim: AnimationPlayer = null
var _tween: Tween = null


func _ready() -> void:
	_camera.look_at(Vector3(0.05, 0.28, 0.0), Vector3.UP)
	visibility_changed.connect(_sync_update)
	_sync_update()
	if not ResourceLoader.exists(HND_GLB):
		return
	var packed := load(HND_GLB) as PackedScene
	var body: Node = packed.instantiate() if packed != null else null
	if not (body is Node3D):
		if body != null:
			body.queue_free()
		return
	var pivot := body as Node3D
	_world.add_child(pivot)
	VisualFit.apply_actor_scale(pivot, &"hnd")
	GeneratedVisual.apply_preview_materials(pivot)
	VisualAnimation.stop_autoplay_keep_rest(pivot)
	pivot.rotation_degrees = Vector3(-30.0, -113.0, 0.0)
	_anim = VisualAnimation.find_animation_player(pivot)
	_play("hnd_sasu")


## Move the fingertip to `tip` (parent-local).
func point_at(tip: Vector2, animate: bool = true) -> void:
	var target := tip - size * TIP
	if _tween != null:
		_tween.kill()
	if not animate or not is_visible_in_tree():
		position = target
		return
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "position", target, 0.12)


func _sync_update() -> void:
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED)


func _play(suffix: String) -> void:
	if _anim == null:
		return
	for clip: String in _anim.get_animation_list():
		if clip == suffix or clip.ends_with(suffix):
			var a := _anim.get_animation(clip)
			if a != null:
				a.loop_mode = Animation.LOOP_LINEAR
			_anim.play(clip)
			return
