class_name CatchMark
extends Node3D

## `eYajirushi` (`ef_kore`): the red arrow shown beside the left hand while a catch too small to
## see (an ant, a mosquito, a killifish) is held up for the report (`Player_actor_AppearMark_Notice_net`
## / `_rod`). It fades in over three ticks, holds until `finish()`, then fades out over six.
## A billboard that follows the hand.

const SHADER := preload("res://shaders/feel_effect.gdshader")
const MODEL := &"ef_kore"
const TEX := "res://assets/generated/textures/rel/ef_kore_tex.png"
## `ef_net` `type_index` of the ant and the mosquito (`use_mark_insect_type`); the rod's one is
## the killifish (`use_mark_gyoei_type`).
const INSECT_TYPES: Array[int] = [38, 39]
const FISH_ID := &"killifish"
const FADE_IN_TICKS := 3.0
const FADE_OUT_TICKS := 6.0
const SCALE := 0.01

## Where the hand is, in world metres (`Player.left_hand_global`).
var hand: Callable = Callable()
var _mats: Array[ShaderMaterial] = []
var _age: float = 0.0
var _finish_at: float = -1.0


## Whether a net catch of this insect (`BugData.type_index`) gets the arrow.
static func marks_insect(type_index: int) -> bool:
	return INSECT_TYPES.has(type_index)


## Whether a rod catch of this fish gets the arrow.
static func marks_fish(fish_id: StringName) -> bool:
	return fish_id == FISH_ID


## Raise an arrow under `parent` that tracks `hand_at`.
static func appear(parent: Node, hand_at: Callable) -> CatchMark:
	var mark := CatchMark.new()
	mark.hand = hand_at
	mark.name = "CatchMark"
	parent.add_child(mark)
	return mark


## The report is over (`Player_actor_DeleteMark_*` → `effect_kill_proc`): fade out.
func finish() -> void:
	if _finish_at < 0.0:
		_finish_at = _age


func _ready() -> void:
	var paths: PackedStringArray = FieldCatalog.mesh_paths(MODEL)
	var packed: PackedScene = load(paths[0]) as PackedScene if not paths.is_empty() else null
	if packed != null:
		var inst: Node = packed.instantiate()
		add_child(inst)
		_shade(inst)
	var k: float = FieldCatalog.GX_TO_METERS / FieldCatalog.PIPELINE_SCALE * SCALE
	scale = Vector3.ONE * k
	_apply(0.0)


func _process(delta: float) -> void:
	_age += delta * DecompTime.TICK_HZ
	if hand.is_valid():
		global_position = hand.call()
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		global_basis = cam.global_basis.scaled(scale)
	var alpha: float
	if _finish_at >= 0.0:
		alpha = clampf(1.0 - (_age - _finish_at) / FADE_OUT_TICKS, 0.0, 1.0)
		if alpha <= 0.0:
			queue_free()
			return
	else:
		alpha = clampf(_age / FADE_IN_TICKS, 0.0, 1.0)
	_apply(alpha)


func _apply(alpha: float) -> void:
	for m: ShaderMaterial in _mats:
		m.set_shader_parameter(&"prim_color", Color(1.0, 80.0 / 255.0, 30.0 / 255.0, alpha))


func _shade(node: Node) -> void:
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
				sh.set_shader_parameter(&"env_color", Color.WHITE)
				mi.set_surface_override_material(i, sh)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_mats.append(sh)
	for child: Node in node.get_children():
		_shade(child)
