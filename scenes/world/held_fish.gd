class_name HeldFish
extends Node3D

## The caught fish, held up on the show-off pose.
##
## `aGTT_comeback` pins the hooked fish to `uki->uki_pos` every frame and `aUKI_catch` /
## `aUKI_get` set that to the player's `left_hand_pos` while the bobber itself goes to the
## right hand — so the catch really is in the player's left hand through `GET_T1` / `GET_T2`.
## At the same moment `uki->gyo_status` hits 5 the fish flips to `aGYO_DRAW_TYPE_FISH` and
## `aGYO_actor_draw_fish` takes over from the shadow quad.
##
## That draw does three things this reproduces: it billboards the model into the camera
## (`Matrix_mult(&play->billboard_matrix)`), it nudges the model down by a per-species
## `aGYO_hosei_y`, and it flips between two poses on a per-species cadence.

## `aGYO_anime_ptn` values, as stored in `FishData.model_flap`.
const FLAP_NONE := 0
const FLAP_FAST := 1
const FLAP_SLOW := 2

## `aGYO_frame_ptn1` / `aGYO_frame_ptn2`. `aGYO_anime_frame` walks one entry per drawn frame
## and the draw indexes the display lists with `(int)(frame * 0.5)`, so a 0 or 1 is the `a`
## pose and a 2 is the `b` pose. Baked to pose indices here rather than kept as the raw
## table, since the halving is what makes `dl_c` unreachable.
const FLAP_FAST_POSES: Array[int] = [0, 0, 0, 0, 1, 1, 0, 0]
const FLAP_SLOW_POSES: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0]

## `aGYO_anime_frame` advances once per drawn frame, which on the GameCube is the 30 Hz
## draw. Held on a fixed tick so the flap does not run at the monitor's refresh rate.
const FLAP_HZ := 30.0

var _poses: Array[Node3D] = []
var _pattern: Array[int] = []
var _shown: int = -1
var _tick: float = 0.0
var _index: int = 0
var _scale: float = 1.0
var _lift: float = 0.0


static func create(fish: FishData) -> HeldFish:
	if fish == null or fish.model_base.is_empty():
		return null
	var node := HeldFish.new()
	node.name = "HeldFish"
	if not node._load(fish):
		node.free()
		return null
	return node


func _load(fish: FishData) -> bool:
	for pose: StringName in [&"a", &"b"]:
		var path: String = fish.model_pose(pose)
		if not ResourceLoader.exists(path):
			continue
		var scene: PackedScene = load(path) as PackedScene
		if scene == null:
			continue
		var visual: Node3D = scene.instantiate() as Node3D
		if visual == null:
			continue
		## Same pass every other generated mesh gets. Without it these keep the imported
		## material's backface culling, and the art is flat enough that a billboarded fish
		## can end up showing the side that is not there.
		GeneratedVisual.apply_preview_materials(visual)
		visual.visible = false
		add_child(visual)
		_poses.append(visual)
	if _poses.is_empty():
		return false
	match fish.model_flap:
		FLAP_FAST:
			_pattern = FLAP_FAST_POSES
		FLAP_SLOW:
			_pattern = FLAP_SLOW_POSES
		_:
			_pattern = [0]
	## `aGYO_hosei_y` is subtracted from the draw position, so it lowers the model.
	_lift = fish.model_lift * FieldCatalog.GX_TO_METERS
	## `aGTT_comeback` sets the fish actor's scale to a flat `0.01` for every species, which is
	## the ordinary `aFTR_PROFILE.scale` the pipeline already knows how to convert. Held in
	## world terms because the parent is the rig, whose own space is not the world's.
	_scale = FieldCatalog.actor_uniform_scale()
	position = Vector3(0.0, -_lift, 0.0)
	scale = Vector3.ONE * _scale
	_show(0)
	return true


func _ready() -> void:
	## The hold is written in world terms, so the local scale has to undo the rig's own. Done
	## here as well as in `_billboard` so the first drawn frame is already the right size,
	## rather than the rig's scale showing through until the fish first sees a camera.
	var hand: Node3D = get_parent_node_3d()
	var rig: float = hand.global_transform.basis.get_scale().y if hand != null else 1.0
	if rig > 0.0:
		scale = Vector3.ONE * (_scale / rig)
	_billboard()


func _process(delta: float) -> void:
	_billboard()
	if _pattern.size() <= 1:
		return
	_tick += delta
	var step: float = 1.0 / FLAP_HZ
	while _tick >= step:
		_tick -= step
		_index = (_index + 1) % _pattern.size()
		_show(_pattern[_index])


## The pose index actually on screen. Tests read this rather than poking visibility.
func shown_pose() -> int:
	return _shown


## The art's own bounds, in this node's space and before scaling. Exposed because where the
## origin falls inside the box decides whether the hand holds the fish or goes through it.
func model_bounds() -> AABB:
	## Measured in this node's space, not each mesh's. The converted GLBs nest the mesh under
	## scaled nodes, and reading `get_aabb()` raw ignores that factor -- which is what made
	## every held fish come out a fraction of its size.
	var box := AABB()
	var seen: bool = false
	for mesh: MeshInstance3D in _meshes(self):
		var part: AABB = _to_local_space(mesh) * mesh.get_aabb()
		box = part if not seen else box.merge(part)
		seen = true
	return box if seen else AABB()


func longest_axis() -> float:
	var box: AABB = model_bounds()
	return maxf(box.size.x, maxf(box.size.y, box.size.z))


## Chained by hand rather than through `global_transform`, since the sizing runs before this
## node is in the tree.
func _to_local_space(node: Node3D) -> Transform3D:
	var out := Transform3D.IDENTITY
	var walk: Node = node
	while walk is Node3D and walk != self:
		out = (walk as Node3D).transform * out
		walk = walk.get_parent()
	return out


func _show(pose: int) -> void:
	var want: int = clampi(pose, 0, _poses.size() - 1)
	if want == _shown:
		return
	_shown = want
	for i: int in _poses.size():
		_poses[i].visible = i == want


## `Matrix_mult(&play->billboard_matrix)` — the fish faces the camera, not the hand it is in.
func _billboard() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	## Anchored on the bone rather than on the last frame's own origin, so the hand still
	## carries the fish while the rotation and scale are written in world terms.
	var hand: Node3D = get_parent_node_3d()
	var origin: Vector3 = (
		hand.global_position - Vector3(0.0, _lift, 0.0) if hand != null else global_position
	)
	var to_camera: Vector3 = camera.global_position - origin
	to_camera.y = 0.0
	if to_camera.length_squared() < 0.000001:
		return
	## Built rather than assigned through `global_rotation`: the parent is a bone attachment,
	## and the rig's scale would otherwise ride along into the fish.
	var yaw: float = atan2(to_camera.x, to_camera.z)
	global_transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * _scale), origin)


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out
