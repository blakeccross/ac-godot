extends Node3D

## Rising bubbles for the fish wing (`ef_suisou_awa` / `ef_museum5_awa1`).
## Twenty vents burp a short run, then rest. Each bubble pops in over four ticks,
## climbs to the water line, and shrinks there. A large one in a small tank leaves
## a ring (`ef_turi_hamon` arg 6).

const VISUAL := &"ef_museum5_awa1"
const SHADER := preload("res://shaders/museum_bubble.gdshader")
const BUBBLE_TEX := preload("res://assets/generated/textures/rel/ef_museum5_awa1.png")
const GX := FieldCatalog.GX_TO_METERS
## Pipeline mesh is `vertex × 0.001`. Effect scale is the draw matrix on the raw vertex.
const NODE_PER_EFFECT := GX / FieldCatalog.PIPELINE_SCALE
const SURFACE_GX := 115.0
const LIFE_TICKS := 80.0
const POP_END := 76.0
const RISE_KEEP := 0.916515138991168  # sqrt(0.84), per tick
const RISE_PUSH := 0.075
const DRAG := 0.1
const TANK2 := 2
const SEA_TANK := 4
const BIG_SCALE := 0.0025
const SCALE_LO := 0.00125  # (0.25) × 0.005
const SCALE_SPAN := 0.00375  # (0.75) × 0.005
const WOBBLE_POS := deg_to_rad(25.0)
const WOBBLE_SCALE := deg_to_rad(12.5)
const SURFACE_FRAC := 0.2928932188134524  # 1 − sqrt(0.5)
const CLAMP_GX := 50.0

## Room origin (metres). Vents are absolute GX, placed with `tank_world_y`.
var room_origin: Vector3 = Vector3.ZERO

var _rng := RandomNumberGenerator.new()
var _scene: PackedScene = null
var _mat: ShaderMaterial = null
var _vents: Array[Vent] = []
var _live: Array[Bubble] = []
var _debt := 0.0
var _frame := 0


class Vent:
	var pos := Vector3.ZERO
	var tank := 0
	var wait := 0.0
	var burst := 0


class Bubble:
	var host: Node3D
	var pivot: Node3D
	var mat: ShaderMaterial
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var accel := Vector3.ZERO
	var target_scale := 0.0
	var scale := 0.0
	var life := 0.0
	var pos_angle := 0.0
	var scale_angle := 0.0
	var tank := 0
	var ripples := false
	var rippled := false


## Godot node scale for an `ef_suisou_awa` matrix scale. The quad is 0.8 pipeline
## units across, so 0.005 (the largest bubble) is 0.2 m.
static func node_scale_for(effect_scale: float) -> float:
	return effect_scale * NODE_PER_EFFECT


func _ready() -> void:
	_rng.seed = hash("museum_bubbles")
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("bubble_tex", _mask_texture())
	## After the tank glass (1), water (2) and caustic (3).
	_mat.render_priority = 4
	var paths := FieldCatalog.mesh_paths(VISUAL)
	if paths.is_empty():
		return
	_scene = load(paths[0]) as PackedScene
	if _scene == null:
		return
	for i: int in MuseumDisplay.BUBBLE_POS.size():
		var vent := Vent.new()
		vent.pos = MuseumDisplay.BUBBLE_POS[i]
		vent.tank = MuseumDisplay.BUBBLE_TANK[i]
		vent.wait = float(_rng.randi_range(40, 120))
		vent.burst = _rng.randi_range(2, 5)
		_vents.append(vent)


func _process(delta: float) -> void:
	if _scene == null:
		return
	_debt += delta * DecompTime.TICK_HZ
	var steps := mini(int(_debt), 8)
	_debt -= float(steps)
	for _i: int in steps:
		_step_vents()
		_step_bubbles()
		_frame += 1


func _step_vents() -> void:
	for vent: Vent in _vents:
		vent.wait -= 1.0
		if vent.wait >= 0.0:
			continue
		_spawn(vent)
		if vent.burst > 0:
			vent.burst -= 1
			vent.wait = float(_rng.randi_range(2, 10))
		else:
			vent.wait = float(_rng.randi_range(80, 240))
			vent.burst = _rng.randi_range(2, 5)


func _spawn(vent: Vent) -> void:
	var host := Node3D.new()
	host.name = "Bubble"
	add_child(host)
	var pivot := Node3D.new()
	pivot.name = "GeneratedVisual"
	var inst := _scene.instantiate() as Node3D
	if inst == null:
		host.queue_free()
		return
	pivot.add_child(inst)
	host.add_child(pivot)
	var mat := _mat.duplicate() as ShaderMaterial
	for mi: MeshInstance3D in _meshes(pivot):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bubble := Bubble.new()
	_apply_material(pivot, mat)
	bubble.host = host
	bubble.pivot = pivot
	bubble.mat = mat
	bubble.pos = vent.pos
	bubble.vel = Vector3(_rng.randf_range(-0.8, 0.8), 0.0, _rng.randf_range(-0.8, 0.8))
	bubble.accel = Vector3(0.0, RISE_PUSH, 0.0)
	bubble.target_scale = SCALE_LO + _rng.randf() * SCALE_SPAN
	bubble.life = LIFE_TICKS
	bubble.pos_angle = _rng.randf() * TAU
	bubble.scale_angle = _rng.randf() * TAU
	bubble.tank = vent.tank
	bubble.ripples = bubble.target_scale > BIG_SCALE and vent.tank != SEA_TANK
	_live.append(bubble)
	_place(bubble)


func _step_bubbles() -> void:
	var sway := sin(float(_frame) * PI * 0.5)
	var kept: Array[Bubble] = []
	for bubble: Bubble in _live:
		if bubble.life <= 0.0 or not is_instance_valid(bubble.host):
			if is_instance_valid(bubble.host):
				bubble.host.queue_free()
			continue
		if bubble.pos.y >= SURFACE_GX:
			if bubble.ripples and not bubble.rippled:
				bubble.rippled = true
				_ripple(bubble)
			bubble.vel.y = _approach(bubble.vel.y, 0.0, SURFACE_FRAC, 0.5, 0.05)
			bubble.scale = _approach(bubble.scale, 0.0, SURFACE_FRAC, 0.001, 0.00005)
		else:
			bubble.scale = FieldEffects.calc_adjust(
				bubble.life, POP_END, LIFE_TICKS, bubble.target_scale, 0.0
			)
			bubble.vel.y *= RISE_KEEP
			bubble.pos_angle += WOBBLE_POS
			bubble.scale_angle += WOBBLE_SCALE
			if bubble.tank == TANK2:
				bubble.accel.x = sway * 0.05 - 0.04
			bubble.vel.x = _drag_to_zero(bubble.vel.x)
			bubble.vel.z = _drag_to_zero(bubble.vel.z)
			bubble.vel += bubble.accel
			bubble.pos += bubble.vel
			if bubble.tank == TANK2:
				_clamp_tank2(bubble)
			if bubble.pos.y >= SURFACE_GX:
				bubble.pos.y = SURFACE_GX
		bubble.life -= 1.0
		if bubble.life <= 0.0:
			bubble.host.queue_free()
			continue
		_place(bubble)
		kept.append(bubble)
	_live = kept


func _place(bubble: Bubble) -> void:
	var drawn := bubble.pos
	drawn.x += cos(bubble.pos_angle)
	drawn.z += sin(bubble.pos_angle)
	bubble.host.position = room_origin + Vector3(
		drawn.x * GX, MuseumDisplay.tank_world_y(drawn.y), drawn.z * GX
	)
	## `BILLBOARD_ENABLED` draws the raw quad and drops this node's scale, so the
	## draw size goes in as a vertex multiplier. The node stays at 1.
	var xz := node_scale_for(bubble.scale) * (sin(bubble.scale_angle) * 0.1 + 1.0)
	var y := node_scale_for(bubble.scale) * (cos(bubble.scale_angle) * 0.1 + 1.0)
	bubble.pivot.scale = Vector3.ONE
	if bubble.mat != null:
		bubble.mat.set_shader_parameter("card_scale", Vector2(xz, y))
	bubble.host.visible = bubble.scale > 0.00005


func _ripple(bubble: Bubble) -> void:
	var at := room_origin + Vector3(
		bubble.pos.x * GX, MuseumDisplay.tank_world_y(SURFACE_GX), bubble.pos.z * GX
	)
	FieldEffects.spawn(self, FieldEffects.Kind.HAMON, at, 0.0, 6, 0)


func _clamp_tank2(bubble: Bubble) -> void:
	var center := MuseumDisplay.TANK_POS[TANK2] / GX
	bubble.pos.x = clampf(bubble.pos.x, center.x - CLAMP_GX, center.x + CLAMP_GX)
	bubble.pos.z = clampf(bubble.pos.z, center.z - CLAMP_GX, center.z + CLAMP_GX)


## The loose PNG keeps the I4 mask in RGB and leaves alpha at 255, so a normal
## albedo draw is an opaque black square. Bake the combiner into alpha:
## colour is cyan in the dark of the mask and white in the highlight, and
## alpha is the mask times ENV alpha 150.
static func _mask_texture() -> Texture2D:
	var image := BUBBLE_TEX.get_image()
	if image == null:
		return BUBBLE_TEX
	image = image.duplicate()
	image.convert(Image.FORMAT_RGBA8)
	var env := Color(0.0, 1.0, 1.0)
	for y: int in image.get_height():
		for x: int in image.get_width():
			var mask := image.get_pixel(x, y).r
			var color := env.lerp(Color.WHITE, mask)
			color.a = mask * (150.0 / 255.0)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


func _apply_material(pivot: Node3D, mat: ShaderMaterial) -> void:
	for mi: MeshInstance3D in _meshes(pivot):
		if mi.mesh == null:
			continue
		## The card is flat. The margin keeps it in the frustum; the shader faces it.
		mi.extra_cull_margin = 1.0
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node)
	for child: Node in node.get_children():
		out.append_array(_meshes(child))
	return out


static func _approach(current: float, target: float, fraction: float, max_step: float, min_step: float) -> float:
	var step := fraction * (target - current)
	if absf(step) < min_step:
		step = min_step if target > current else -min_step
	else:
		step = clampf(step, -max_step, max_step)
	var next := current + step
	if (step > 0.0 and next > target) or (step < 0.0 and next < target):
		return target
	return next


static func _drag_to_zero(value: float) -> float:
	var step := clampf(value * DRAG, -DRAG, DRAG)
	return value - step
