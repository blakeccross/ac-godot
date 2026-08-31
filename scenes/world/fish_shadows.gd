extends Node3D

## Presents the field's fish shadows and drives their clock. Behavioral analog of
## `Gyoei_Profile`'s move + draw pair: this node owns no decisions, it builds the frame's
## sense snapshot, ticks `FishSchool`, and pushes the results onto quads.
##
## One quad per shadow (`aGYO_MAX_GYOEI` is 2) plus one per escape puff, so a handful of
## nodes rather than the MultiMesh the footprint pool needs.

const SHADER := "res://shaders/fish_shadow.gdshader"
## `aGYO_shadow_scale` is measured to the shadow art's edge, so the quad is padded to give
## the soft rim and the tail sway somewhere to live.
const QUAD_PADDING := 1.45
## `mCoBG_GetWaterHeight` - 8 GX puts the fish under the surface; the quad has to sit just
## above the water plane instead or it z-fights with it.
const SURFACE_LIFT := 0.02

var _school: FishSchool = null
var _material: ShaderMaterial = null
var _mesh: QuadMesh = null
var _shadow_nodes: Array[MeshInstance3D] = []
var _puff_nodes: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("fish_shadows")
	_mesh = QuadMesh.new()
	_mesh.size = Vector2.ONE
	## PlaneMesh would already lie in XZ, but QuadMesh's UVs are the ones the shader's body
	## SDF is written against, so the node is rotated flat instead.
	if ResourceLoader.exists(SHADER):
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER) as Shader
	_bind_school()


func school() -> FishSchool:
	return _school


func _bind_school() -> void:
	var world: Node = get_parent()
	while world != null and not world.is_in_group("world"):
		world = world.get_parent()
	if world == null:
		return
	_school = world.get("fish") as FishSchool


func _process(delta: float) -> void:
	if _school == null:
		_bind_school()
		if _school == null:
			return
	var sense: FishShadow.Sense = _make_sense()
	_school.tick(delta, sense)
	Fishing.tick(delta, _school)
	_sync()


func _make_sense() -> FishShadow.Sense:
	var sense := FishShadow.Sense.new()
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D if get_tree() else null
	if player != null:
		sense.player_position = player.global_position
		if player.has_method("is_dashing"):
			sense.player_dashing = bool(player.call("is_dashing"))
	Fishing.fill_sense(sense)
	return sense


func _sync() -> void:
	_fit(_shadow_nodes, _school.shadows.size())
	for i: int in _school.shadows.size():
		var shadow: FishShadow = _school.shadows[i]
		_place(_shadow_nodes[i], shadow.position, shadow.yaw, shadow.shadow_extent(), 1.0, shadow.body_blend())
	_fit(_puff_nodes, _school.puffs.size())
	for i: int in _school.puffs.size():
		var puff: FishSchool.Puff = _school.puffs[i]
		_place(
			_puff_nodes[i],
			puff.position,
			puff.yaw,
			FishSize.shadow_size(puff.size),
			puff.alpha(),
			FishSize.body_blend(FishSize.anim_frame(puff.age))
		)


func _place(
	node: MeshInstance3D, at: Vector3, yaw: float, extent: Vector2, alpha: float, blend: float
) -> void:
	node.visible = alpha > 0.005
	if not node.visible:
		return
	node.global_position = Vector3(at.x, _school.surface_y + SURFACE_LIFT, at.z)
	## The quad's +Y runs along the fish and the node is laid flat, so yaw stays on Y. The
	## extra half turn is `aGYO_actor_draw_gyoei`'s `rotation.y + DEG2SHORT_ANGLE2(180.0f)`:
	## the shadow art points down its local -Z, so without it the fish swims tail first.
	node.rotation = Vector3(-PI * 0.5, yaw + PI, 0.0)
	node.scale = Vector3(extent.x * QUAD_PADDING, extent.y * QUAD_PADDING, 1.0)
	var mat := node.material_override as ShaderMaterial
	if mat == null:
		return
	## `aGYO_prim_f` runs 0..255 as a cross-fade between two tiles. Remapped to -1..1 it is
	## the sway direction, so one table drives the whole wiggle.
	mat.set_shader_parameter("body_flex", blend * 2.0 - 1.0)
	mat.set_shader_parameter("alpha", alpha)
	mat.set_shader_parameter("aspect", FishSize.SHADOW_ASPECT)


func _fit(pool: Array[MeshInstance3D], want: int) -> void:
	while pool.size() < want:
		var node := MeshInstance3D.new()
		node.mesh = _mesh
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if _material != null:
			node.material_override = _material.duplicate() as ShaderMaterial
		add_child(node)
		pool.append(node)
	for i: int in range(want, pool.size()):
		pool[i].visible = false
