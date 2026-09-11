extends Node3D

## Rotating warning light at the top of the lighthouse (`ac_toudai`'s glow effect,
## `aTOU_color_ctrl` / `obj_s_toudai_light_model`). The converted `obj_s_toudai.glb` already
## carries the real decomp-sourced sweep: an `AnimationPlayer` rotating the
## `obj_s_toudai_arm_model` bone, which the `obj_s_toudai_blend` mesh is skinned to.
## `GeneratedVisual.attach` stops autoplay on every import (nothing plays baked clips by
## default), which left that arm frozen in its bind pose — off-center rather than sweeping,
## since a rest frame of a rotation track is not the same as "no rotation". Playing the real
## clip is both more faithful than a hand-rolled spin and fixes the frozen look.
##
## The `GeneratedVisual` (and its `AnimationPlayer`) is attached by the sibling `Lighthouse`
## root in its own `_ready`, which — as the parent — runs *after* this node's `_ready`. The
## lookup is deferred so it runs once that attach has actually happened.
##
## On/off (including the night-hours window) is owned by the sibling `LighthouseSwitch` —
## this node just reflects whatever `on` it's given. A supplementary glow (not in decomp's
## separated form — see the header above) still spins on its own simple loop; it does not
## need bone-perfect sync to read as "the light is sweeping."

const ANIMATION_NAME := &"obj_s_toudai"
const SPIN_SPEED := 1.6 ## rad/s, supplementary glow orbit — independent of the real clip's rate.

var on: bool = false:
	set(value):
		on = value
		_apply_light()
		_apply_animation()

@onready var _head: Node3D = $Head
@onready var _light: SpotLight3D = $Head/SpotLight3D
var _anim: AnimationPlayer = null


func _ready() -> void:
	_apply_light()
	call_deferred(&"_late_ready")


func _late_ready() -> void:
	_anim = _find_animation_player()
	_apply_animation()


func _process(delta: float) -> void:
	if on:
		_head.rotate_y(SPIN_SPEED * delta)


func _apply_light() -> void:
	if _light != null:
		_light.visible = on


func _apply_animation() -> void:
	if _anim == null or not _anim.has_animation(ANIMATION_NAME):
		return
	if on:
		_anim.get_animation(ANIMATION_NAME).loop_mode = Animation.LOOP_LINEAR
		if _anim.current_animation != ANIMATION_NAME or not _anim.is_playing():
			_anim.play(ANIMATION_NAME)
	else:
		_anim.stop()
		_anim.seek(0.0, true) ## Rest pose, not wherever the sweep happened to stop.


func _find_animation_player() -> AnimationPlayer:
	var host: Node = get_parent()
	if host == null:
		return null
	var visual: Node = host.get_node_or_null("GeneratedVisual")
	if visual == null:
		return null
	return _find_animation_player_in(visual)


func _find_animation_player_in(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found: AnimationPlayer = _find_animation_player_in(c)
		if found != null:
			return found
	return null
