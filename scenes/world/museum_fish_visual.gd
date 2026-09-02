class_name MuseumFishVisual
extends Node3D

## Tank fish mesh from `act_mus_*` (not outdoor `act_f*`). Plays the museum cKF loop.

var actor: MuseumFishActor = null

var _scale: float = 1.0


static func create(p_actor: MuseumFishActor) -> MuseumFishVisual:
	if p_actor == null or p_actor.fish == null:
		return null
	var node := MuseumFishVisual.new()
	node.actor = p_actor
	if not node._load(p_actor.fish_index):
		node.free()
		return null
	node._scale = p_actor.render_scale()
	node.scale = Vector3.ONE * node._scale
	return node


func _load(fish_index: int) -> bool:
	var path: String = MuseumDisplay.museum_fish_model_path(fish_index)
	if path.is_empty() or not ResourceLoader.exists(path):
		return false
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return false
	var visual: Node3D = scene.instantiate() as Node3D
	if visual == null:
		return false
	GeneratedVisual.apply_preview_materials(visual)
	add_child(visual)
	var anim: AnimationPlayer = GeneratedVisual.find_animation_player(visual)
	if anim != null:
		var clips: PackedStringArray = anim.get_animation_list()
		if not clips.is_empty():
			var clip: StringName = clips[0]
			var anim_res: Animation = anim.get_animation(clip)
			if anim_res != null:
				anim_res.loop_mode = Animation.LOOP_LINEAR
			anim.play(clip)
	return true


func _process(delta: float) -> void:
	if actor == null:
		return
	actor.tick(delta)
	global_position = actor.position + Vector3(0.0, actor.model_lift, 0.0)
	rotation = Vector3(actor.pitch, actor.yaw, 0.0)
	scale = Vector3.ONE * _scale
