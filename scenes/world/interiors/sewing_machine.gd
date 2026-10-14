extends Node3D

## Sable's sewing machine (`ac_misin.c`): the animated `obj_misin` overlay (needle bob
## and belt scroll) on the machine body baked into the `rom_tailor` shell. Its verts are
## drawn `Matrix_translate(0) * Matrix_scale(0.01)` from the block's NW corner, so the
## model loads raw at actor scale (no foot-snap) and this node sits at the room's grid
## origin, nudged onto the baked machine head in `needlework.tscn`.

const VISUAL := &"obj_misin"

## `request_misin_stop_proc` / `_move_proc`: Sable stops sewing to talk.
var running := true:
	set(value):
		running = value
		if _anim != null:
			_anim.speed_scale = 1.0 if running else 0.0

var _anim: AnimationPlayer


func _ready() -> void:
	var pivot: Node3D = GeneratedVisual.attach_datum(self, VISUAL)
	if pivot == null:
		return
	VisualFit.disable_shadows(pivot)
	_anim = VisualAnimation.find_animation_player(pivot)
	if _anim == null or _anim.get_animation_list().is_empty():
		return
	var clip: String = _anim.get_animation_list()[0]
	_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_anim.play(clip)
	running = running
