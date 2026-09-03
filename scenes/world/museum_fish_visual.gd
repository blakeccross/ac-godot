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
	_apply_actor_pose()


## `act_mus_*` cKF uses character stand-up (`ckf_basis` +90° Z):
## length +X→+Y, dorsal +Y→−X. A pure +90° X tip puts the nose on +Z but leaves
## the dorsal on −X (one eye into the floor). This basis maps nose→+Z and dorsal→+Y.
## Crayfish draw adds an extra −180° Y (`mfish_zarigani_dw`).
const SWIM_FROM_STAND := Basis(Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0))


func _apply_actor_pose() -> void:
	if actor == null:
		return
	var lift := Vector3(0.0, actor.model_lift, 0.0)
	var origin: Vector3 = actor.position + lift
	var yaw: float = actor.yaw
	if actor.fish_index == 32:
		yaw = wrapf(yaw + PI, -PI, PI)
	var face := Basis.from_euler(Vector3(actor.pitch, yaw, 0.0))
	var posed := Transform3D((face * SWIM_FROM_STAND).scaled(Vector3.ONE * _scale), origin)
	if is_inside_tree():
		global_transform = posed
	else:
		transform = posed
