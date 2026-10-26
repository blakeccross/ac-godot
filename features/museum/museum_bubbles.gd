extends Node3D

## Rising aquarium bubbles for the fish wing (`ef_museum5_awa1`). A handful of small
## translucent meshes per tank, each looping up a `Tween` — the buried-shine idiom, since
## the project has no particle system.

const VISUAL := &"ef_museum5_awa1"
const PER_TANK := 4
const RISE_HEIGHT := 1.8
const RISE_TIME := 2.6

## World-space tank centres, injected by `MuseumPresenter`.
var tank_centers: Array = []

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash("museum_bubbles")
	if FieldCatalog.mesh_paths(VISUAL).is_empty():
		return
	for center_v: Variant in tank_centers:
		var center: Vector3 = center_v
		for n: int in PER_TANK:
			_spawn_bubble(center)


func _spawn_bubble(center: Vector3) -> void:
	var host := Node3D.new()
	host.name = "Bubble"
	var jitter := Vector3(
		_rng.randf_range(-0.35, 0.35), 0.0, _rng.randf_range(-0.35, 0.35)
	)
	host.position = center + jitter + Vector3(0.0, 0.2, 0.0)
	add_child(host)
	var pivot: Node3D = GeneratedVisual.attach(host, VISUAL)
	if pivot != null:
		pivot.scale = Vector3.ONE * _rng.randf_range(0.4, 0.9)
		for mi: MeshInstance3D in _mesh_instances(pivot):
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_animate(host)


func _animate(host: Node3D) -> void:
	var base_y: float = host.position.y
	var delay: float = _rng.randf_range(0.0, RISE_TIME)
	var tween := create_tween()
	tween.set_loops()
	tween.tween_interval(delay)
	tween.tween_callback(func() -> void: host.position.y = base_y)
	tween.tween_property(host, "position:y", base_y + RISE_HEIGHT, RISE_TIME).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(host, "scale", host.scale * 1.4, RISE_TIME)


func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_mesh_instances(child))
	return out
