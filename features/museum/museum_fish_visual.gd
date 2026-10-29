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
	var anim: AnimationPlayer = VisualAnimation.find_animation_player(visual)
	if anim != null:
		var clips: PackedStringArray = anim.get_animation_list()
		if not clips.is_empty():
			var clip: StringName = clips[0]
			var anim_res: Animation = anim.get_animation(clip)
			if anim_res != null:
				anim_res.loop_mode = Animation.LOOP_LINEAR
			anim.play(clip)
		_anim = anim
	return true


var _anim: AnimationPlayer = null


func _process(_delta: float) -> void:
	if actor == null:
		return
	if _anim != null:
		_anim.speed_scale = maxf(actor.anim_speed, 0.0)
	_apply_actor_pose()


## `act_mus_*` cKF uses character stand-up (`ckf_basis` +90° Z):
## length +X→+Y, dorsal +Y→−X. A pure +90° X tip puts the nose on +Z but leaves
## the dorsal on −X (one eye into the floor). This basis maps nose→+Z and dorsal→+Y.
## Crayfish draw adds an extra −180° Y (`mfish_zarigani_dw`).
const SWIM_FROM_STAND := Basis(Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0))


## `mfish_onefish_dw`: turn, pitch and roll about a pivot (`0.25·ofs_y`, `1.5·ofs_z`) and come back
## only `0.5·ofs_z`, so the body sits `ofs_z` along its heading; the roll is half the turn left,
## held to ±20°.
func _apply_actor_pose() -> void:
	if actor == null:
		return
	var gx: float = FieldCatalog.GX_TO_METERS
	var yaw: float = actor.yaw
	if actor.fish_index == 32:
		yaw = wrapf(yaw + PI, -PI, PI)
	var roll: float = clampf(-actor.roll / 2.0, deg_to_rad(-20.0), deg_to_rad(20.0))
	var xf := Transform3D(Basis(Vector3.UP, yaw), actor.world_position())
	xf = xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.25 * actor.ofs_y, 1.5 * actor.ofs_z) * gx)
	xf = xf * Transform3D(Basis(Vector3.RIGHT, actor.pitch) * Basis(Vector3.BACK, roll), Vector3.ZERO)
	xf = xf * Transform3D(Basis.IDENTITY, Vector3(0.0, -0.25 * actor.ofs_y, -0.5 * actor.ofs_z) * gx)
	xf = xf * Transform3D(SWIM_FROM_STAND.scaled(Vector3.ONE * _scale), Vector3.ZERO)
	if is_inside_tree():
		global_transform = xf
	else:
		transform = xf
