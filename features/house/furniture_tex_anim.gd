class_name FurnitureTexAnim
extends Node

## Pieces that bind a different texture to segment 8 each frame (`gSPSegment(…, G_MWO_SEGMENT_8, tex)`):
## the televisions' screens, the slot machine's reels. The pipeline leaves that segment unbound
## (`seg_08`, or the first texture a table lists), so the runtime binds them. The frames come from
## `data/furniture/texture_anims.json` (`tools/gen_furniture_texanim.py`).
##
## A television shows its fixed `off` picture while switched off and steps through `on` while on,
## a frame every `ticks_per_frame` game ticks (the US release counts `tex_animation.frame` a tick
## and reads it `>> 1`). The slot machine's counter runs only while the reels spin, wraps at
## `wrap_frames` and keeps its place between spins.

const DATA_PATH := "res://data/furniture/texture_anims.json"
const TEXTURE_DIR := "res://assets/generated/textures/rel/"

static var _data: Dictionary = {}
static var _loaded: bool = false

var _spec: Dictionary = {}
var _targets: Array[Array] = []
var _placement: StringName = &""
var _spin: FurnitureSwitchAnim = null
var _acc: float = 0.0
var _counter: int = 0
var _shown: String = ""


static func spec_for(visual_id: StringName) -> Dictionary:
	if not _loaded:
		_loaded = true
		var file := FileAccess.open(DATA_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
	return _data.get(String(visual_id), {}) as Dictionary


## The surface whose texture the game binds at draw time: the pipeline's `seg_08` stand-in, or the
## first of a table's textures it picked as the default.
static func is_bound_surface(material_name: String) -> bool:
	return material_name == "seg_08" or material_name.ends_with("_TA_tex_txt")


## Each bound surface's own copy of its material, so another piece of the same model keeps its
## own picture.
static func own_bound_materials(visual: Node) -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for i: int in mesh_instance.mesh.get_surface_count():
			var mat := mesh_instance.get_active_material(i) as StandardMaterial3D
			if mat != null and is_bound_surface(mat.resource_name):
				var own := mat.duplicate() as StandardMaterial3D
				mesh_instance.set_surface_override_material(i, own)
				out.append(own)
	return out


static func texture_named(texture_name: String) -> Texture2D:
	return load(TEXTURE_DIR + texture_name + ".png") as Texture2D


static func attach(piece: Node3D, visual: Node, visual_id: StringName, placement: StringName) -> FurnitureTexAnim:
	var spec: Dictionary = spec_for(visual_id)
	if piece == null or visual == null or spec.is_empty():
		return null
	var fx := FurnitureTexAnim.new()
	fx.name = "FurnitureTexAnim"
	fx._spec = spec
	fx._placement = placement
	for own: StandardMaterial3D in own_bound_materials(visual):
		fx._targets.append([own])
	if fx._targets.is_empty():
		fx.free()
		return null
	fx._spin = piece.get_node_or_null("FurnitureSwitchAnim") as FurnitureSwitchAnim
	piece.add_child(fx)
	fx._show(fx._current())
	return fx


func _process(delta: float) -> void:
	_acc += delta * DecompTime.TICK_HZ
	while _acc >= 1.0:
		_acc -= 1.0
		if _running():
			_counter += 1
			var wrap: int = int(_spec.get("wrap_frames", 0))
			if wrap <= 0:
				wrap = (_spec.get("on", []) as Array).size() * int(_spec.get("ticks_per_frame", 2))
			if _counter >= wrap:
				_counter = 0
	_show(_current())


## Whether the frame counter is moving: a television while it is on, the reels while they spin.
func _running() -> bool:
	if String(_spec.get("kind", "")) == "spin":
		return _spin != null and _spin.is_spinning()
	return _is_on()


func _current() -> String:
	var frames: Array = _spec.get("on", []) as Array
	if frames.is_empty():
		return String(_spec.get("off", ""))
	var spin: bool = String(_spec.get("kind", "")) == "spin"
	if not spin and not _is_on():
		return String(_spec.get("off", ""))
	var step: int = maxi(int(_spec.get("ticks_per_frame", 2)), 1)
	return String(frames[(_counter / step) % frames.size()])


func _show(texture_name: String) -> void:
	if texture_name == _shown or texture_name.is_empty():
		return
	var texture: Texture2D = texture_named(texture_name)
	if texture == null:
		return
	_shown = texture_name
	for target: Array in _targets:
		(target[0] as StandardMaterial3D).albedo_texture = texture


func _is_on() -> bool:
	var session: IndoorSession = Game.interior_session if Game != null else null
	if session == null or session.room == null:
		return true
	var entry: FurniturePlacement = session.room.placement_by_id(_placement)
	return entry == null or entry.on
