class_name EffectCards
extends RefCounted

## Camera-facing cards of the effect models (`ef_takurami01_kira`, …) for effects that live in the
## world rather than at a villager's head (`auto_matrix_xlu_proc` → the play scene's billboard
## matrix). Each is drawn with the feel-effect combiner: the texel's intensity blends ENV → PRIM,
## alpha is the texel's alpha × PRIM.a. The owner steps its own timing and calls `face` each frame.

const SHADER := preload("res://shaders/feel_effect.gdshader")
const GX := FieldCatalog.GX_TO_METERS
const META_MATS := &"effect_card_mats"


## A card of `visual` under `parent`, hidden until the owner places it. Null without the model.
static func make(parent: Node, visual: StringName, prim: Color = Color.WHITE, env: Color = Color.WHITE) -> Node3D:
	var paths: PackedStringArray = FieldCatalog.mesh_paths(visual)
	var packed: PackedScene = load(paths[0]) as PackedScene if not paths.is_empty() else null
	if packed == null:
		return null
	var card := Node3D.new()
	card.name = String(visual)
	var mats: Array[ShaderMaterial] = []
	var inst: Node = packed.instantiate()
	card.add_child(inst)
	_shade(inst, mats)
	card.set_meta(META_MATS, mats)
	parent.add_child(card)
	tint(card, prim, env)
	return card


static func tint(card: Node3D, prim: Color, env: Color = Color.WHITE) -> void:
	if card == null or not card.has_meta(META_MATS):
		return
	for mat: ShaderMaterial in card.get_meta(META_MATS):
		mat.set_shader_parameter(&"prim_color", prim)
		mat.set_shader_parameter(&"env_color", env)


## Turn `card` to the camera at `at` (world metres) with the decomp's matrix `scale`.
static func face(card: Node3D, at: Vector3, scale: float) -> void:
	if card == null or not card.is_inside_tree():
		return
	var cam: Camera3D = card.get_viewport().get_camera_3d()
	var basis: Basis = cam.global_basis.orthonormalized() if cam != null else Basis.IDENTITY
	var k: float = maxf(scale, 0.00001) * GX / FieldCatalog.PIPELINE_SCALE
	card.global_transform = Transform3D(basis * Basis.from_scale(Vector3.ONE * k), at)


static func _shade(node: Node, mats: Array[ShaderMaterial]) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i: int in mi.mesh.get_surface_count():
				var std := mi.get_active_material(i) as StandardMaterial3D
				var sh := ShaderMaterial.new()
				sh.shader = SHADER
				sh.render_priority = 3
				if std != null:
					sh.set_shader_parameter(&"tex0", std.albedo_texture)
				sh.set_shader_parameter(&"mirror0", true)
				mi.set_surface_override_material(i, sh)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mats.append(sh)
	for child: Node in node.get_children():
		_shade(child, mats)
