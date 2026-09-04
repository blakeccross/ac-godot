class_name NpcFeelGlyphs
extends Node3D

## Billboard feel glyphs above an NPC (`eEC_EFFECT_WARAU` / `SHOCK` / `HA` / `HIRAMEKI_*`).
## Pipeline cards live under `assets/generated/effects/`; missing packs are a no-op.

const EFFECT_HZ := 60.0

const WARAU_VISUALS: Array[StringName] = [
	&"ef_warau01_00",
	&"ef_warau01_01",
	&"ef_warau01_02",
	&"ef_warau01_03",
]
## `eWU_ct` scale 0.0045 on authored verts (pipeline GLB already × `PIPELINE_SCALE`).
const WARAU_MATRIX_SCALE := 0.0045
const WARAU_LIFE_FRAMES := 24
## Continuous laugh while smile manpu holds — a couple of glyph cycles.
const WARAU_CYCLES := 2

const SHOCK_VISUAL := &"ef_shock01_00"
const SHOCK_MATRIX_SCALE := 0.019
const SHOCK_LIFE_FRAMES := 14
const SHOCK_Y_GX := 4.0

const HA_VISUAL := &"ef_ha01_00"
const HA_MATRIX_SCALE := 0.0067
const HA_LIFE_FRAMES := 56
const HA_Y_GX := 12.0
const HA_X_GX := 16.0

## Lightbulb bolt (`ef_hirameki_den`) + brief glow (`ef_hirameki_hikari`).
const HIRAMEKI_DEN_VISUAL := &"ef_hirameki01_den"
const HIRAMEKI_HIKARI_VISUAL := &"ef_hirameki01_hikari"
const HIRAMEKI_DEN_MATRIX_SCALE := 0.007
const HIRAMEKI_HIKARI_MATRIX_SCALE := 0.014
const HIRAMEKI_LIFE_FRAMES := 72
const HIRAMEKI_HIKARI_FRAMES := 12
const HIRAMEKI_Y_GX := 24.0

var _kind: StringName = &""
var _frame: float = 0.0
var _cycle: int = 0
var _mesh_host: Node3D
var _glow_host: Node3D
var _active_visual: StringName = &""
var _head_lift: float = 1.15


func _ready() -> void:
	_mesh_host = Node3D.new()
	_mesh_host.name = "GlyphMesh"
	add_child(_mesh_host)
	_glow_host = Node3D.new()
	_glow_host.name = "GlyphGlow"
	add_child(_glow_host)


func _process(delta: float) -> void:
	if _kind == &"":
		return
	_billboard()
	_frame += delta * EFFECT_HZ
	match _kind:
		&"warau":
			_tick_warau()
		&"shock":
			_tick_shock()
		&"ha":
			_tick_ha()
		&"hirameki":
			_tick_hirameki()
		_:
			clear()


## Spawn the feel glyph that matches a manpu clip (`NpcManpu.feel_for`).
func play(kind: StringName) -> void:
	clear()
	if kind == &"":
		return
	_kind = kind
	_frame = 0.0
	_cycle = 0
	match kind:
		&"warau":
			_show_warau_frame(0)
		&"shock":
			_set_visual(SHOCK_VISUAL, SHOCK_MATRIX_SCALE)
			_mesh_host.position = Vector3(0.0, SHOCK_Y_GX * FieldCatalog.GX_TO_METERS, 0.0)
			_tint_mesh(Color(1.0, 1.0, 0.0))
		&"ha":
			_set_visual(HA_VISUAL, HA_MATRIX_SCALE)
			_mesh_host.position = Vector3(
				HA_X_GX * FieldCatalog.GX_TO_METERS,
				HA_Y_GX * FieldCatalog.GX_TO_METERS,
				0.0
			)
		&"hirameki":
			_set_visual(HIRAMEKI_DEN_VISUAL, HIRAMEKI_DEN_MATRIX_SCALE)
			_mesh_host.position = Vector3(0.0, HIRAMEKI_Y_GX * FieldCatalog.GX_TO_METERS, 0.0)
			_tint_mesh(Color(1.0, 1.0, 0.39))
			_set_glow_visual(HIRAMEKI_HIKARI_VISUAL, HIRAMEKI_HIKARI_MATRIX_SCALE)
			_glow_host.position = _mesh_host.position
		_:
			_kind = &""


func play_for_manpu(manpu_name: String) -> void:
	play(NpcManpu.feel_for(manpu_name))


func clear() -> void:
	_kind = &""
	_frame = 0.0
	_cycle = 0
	_active_visual = &""
	if _mesh_host != null:
		for child: Node in _mesh_host.get_children():
			child.free()
		_mesh_host.position = Vector3.ZERO
		_mesh_host.scale = Vector3.ONE
	if _glow_host != null:
		for child: Node in _glow_host.get_children():
			child.free()
		_glow_host.position = Vector3.ZERO
		_glow_host.scale = Vector3.ONE


func set_head_lift(meters: float) -> void:
	_head_lift = maxf(meters, 0.4)
	position = Vector3(0.0, _head_lift, 0.0)


func _tick_warau() -> void:
	## Disp table advances every 2 effect frames through four cards (`eWU_dw`).
	var slot: int = int(_frame) >> 1
	if slot >= 12:
		_cycle += 1
		if _cycle >= WARAU_CYCLES:
			clear()
			return
		_frame = 0.0
		slot = 0
	## Table: null, null, 00,00, 01,01, 02,02, 03,03, null, null
	var card: int = -1
	if slot >= 2 and slot <= 9:
		card = (slot - 2) >> 1
	if card < 0 or card >= WARAU_VISUALS.size():
		_clear_mesh_only()
		return
	_show_warau_frame(card)


func _tick_shock() -> void:
	var t: int = int(_frame)
	if t >= SHOCK_LIFE_FRAMES:
		clear()
		return
	## `eSK_scale_table` / prim fade — approximate with a quick pop then shrink.
	var scales: Array[float] = [0.019, 0.02375, 0.0285, 0.026125, 0.02375, 0.021375, 0.019]
	var idx: int = mini(t, scales.size() - 1)
	var s: float = _node_scale_for(scales[idx])
	_mesh_host.scale = Vector3(s, s, s)
	var fade: float = 1.0 if t < 7 else clampf(1.0 - float(t - 7) / 7.0, 0.0, 1.0)
	_set_mesh_alpha(fade)


func _tick_ha() -> void:
	if int(_frame) >= HA_LIFE_FRAMES:
		clear()
		return
	## Hold full until frame 24, then fade (`eHA_dw` calc_adjust).
	var elapsed: int = int(_frame)
	var fade: float = 1.0
	if elapsed > 24:
		fade = clampf(1.0 - float(elapsed - 24) / float(HA_LIFE_FRAMES - 24), 0.0, 1.0)
	_set_mesh_alpha(fade)


func _tick_hirameki() -> void:
	var t: int = int(_frame)
	if t >= HIRAMEKI_LIFE_FRAMES:
		clear()
		return
	## Den fades from frame 64→72 (`eHiramekiD_dw`); hikari is only the first 12 frames.
	var den_fade: float = 1.0
	if t > 64:
		den_fade = clampf(1.0 - float(t - 64) / 8.0, 0.0, 1.0)
	_set_mesh_alpha(den_fade)
	if _glow_host != null and _glow_host.get_child_count() > 0:
		if t >= HIRAMEKI_HIKARI_FRAMES:
			for child: Node in _glow_host.get_children():
				child.free()
		else:
			## `eHiramekiH_dw`: scale 0.014→0.0175, alpha ramp then fade.
			var hs: float = lerpf(0.014, 0.0175, float(t) / float(HIRAMEKI_HIKARI_FRAMES))
			var g: float = _node_scale_for(hs)
			_glow_host.scale = Vector3(g, g, g)
			var ha: float = 1.0
			if t < 4:
				ha = float(t) * 50.0 / 255.0
			else:
				ha = clampf(1.0 - float(t - 4) / 8.0, 0.0, 1.0)
			_set_mesh_alpha_node(_glow_host, ha)


func _show_warau_frame(card: int) -> void:
	_set_visual(WARAU_VISUALS[card], WARAU_MATRIX_SCALE)
	_mesh_host.position = Vector3.ZERO


func _set_visual(visual_id: StringName, matrix_scale: float) -> void:
	if visual_id == _active_visual and _mesh_host.get_child_count() > 0:
		var s: float = _node_scale_for(matrix_scale)
		_mesh_host.scale = Vector3(s, s, s)
		return
	_clear_mesh_only()
	_active_visual = visual_id
	var paths: PackedStringArray = FieldCatalog.mesh_paths(visual_id)
	if paths.is_empty():
		return
	var packed: PackedScene = load(paths[0]) as PackedScene
	if packed == null:
		return
	var inst: Node = packed.instantiate()
	_mesh_host.add_child(inst)
	_make_unshaded(_mesh_host)
	var s2: float = _node_scale_for(matrix_scale)
	_mesh_host.scale = Vector3(s2, s2, s2)


func _set_glow_visual(visual_id: StringName, matrix_scale: float) -> void:
	if _glow_host == null:
		return
	for child: Node in _glow_host.get_children():
		child.free()
	var paths: PackedStringArray = FieldCatalog.mesh_paths(visual_id)
	if paths.is_empty():
		return
	var packed: PackedScene = load(paths[0]) as PackedScene
	if packed == null:
		return
	var inst: Node = packed.instantiate()
	_glow_host.add_child(inst)
	_make_unshaded(_glow_host)
	_tint_mesh_node(_glow_host, Color(1.0, 1.0, 0.39))
	var s: float = _node_scale_for(matrix_scale)
	_glow_host.scale = Vector3(s, s, s)


func _clear_mesh_only() -> void:
	_active_visual = &""
	if _mesh_host == null:
		return
	for child: Node in _mesh_host.get_children():
		child.free()


func _node_scale_for(matrix_scale: float) -> float:
	## Authored × matrix_scale → GX; GLB already × PIPELINE_SCALE.
	return matrix_scale * FieldCatalog.GX_TO_METERS / FieldCatalog.PIPELINE_SCALE


func _billboard() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to: Vector3 = cam.global_position - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	look_at(global_position + to.normalized(), Vector3.UP)


func _make_unshaded(root: Node) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.mesh != null:
			for i: int in mi.mesh.get_surface_count():
				var mat: Material = mi.get_active_material(i)
				if mat is StandardMaterial3D:
					var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					std.cull_mode = BaseMaterial3D.CULL_DISABLED
					std.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
					mi.set_surface_override_material(i, std)
	for child: Node in root.get_children():
		_make_unshaded(child)


func _tint_mesh(color: Color) -> void:
	_tint_mesh_node(_mesh_host, color)


func _tint_mesh_node(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i: int in mi.mesh.get_surface_count():
				var mat: Material = mi.get_active_material(i)
				if mat is StandardMaterial3D:
					var std := mat as StandardMaterial3D
					var c: Color = color
					c.a = std.albedo_color.a
					std.albedo_color = c
	for child: Node in node.get_children():
		_tint_mesh_node(child, color)


func _set_mesh_alpha(alpha: float) -> void:
	_set_mesh_alpha_node(_mesh_host, clampf(alpha, 0.0, 1.0))


func _set_mesh_alpha_node(node: Node, alpha: float) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i: int in mi.mesh.get_surface_count():
				var mat: Material = mi.get_active_material(i)
				if mat is StandardMaterial3D:
					var std := mat as StandardMaterial3D
					var c: Color = std.albedo_color
					c.a = alpha
					std.albedo_color = c
	for child: Node in node.get_children():
		_set_mesh_alpha_node(child, alpha)
