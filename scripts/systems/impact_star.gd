class_name ImpactStar
extends Node3D

## `ef_impact_star`: a yellow star (`ef_star01_00`, prim 255/255/100) that flies up and out
## from where a shovel strikes something hard, slowing by √0.85 a tick, shrinking over its
## first 14 ticks and fading over its last 10 (40 ticks in all). Drawn as a billboard. Two of them per strike
## (`eDig_Scoop_init`, `arg1` 0 and 1). State is GX at the controller's 60 Hz.

const VISUAL := &"ef_star01_00"
const LIFE := 40
const SLOW := 0.9219544
const PRIM := Color8(255, 255, 100)

var timer: int = LIFE
var vel_gx: Vector3 = Vector3.ZERO
var scale_from: float = 0.01
var scale_to: float = 0.004
var _card: Node3D
var _materials: Array[StandardMaterial3D] = []
var _steps := FrameStepper.new(DecompTime.TICK_HZ, 8.0)


## `eImpact_Star_ct`: star 0 rises steeply near `yaw`, star 1 a little wider and bigger.
static func spawn(host: Node, pos: Vector3, yaw: float, which: int, rng: RandomNumberGenerator) -> ImpactStar:
	if host == null:
		return null
	var star := ImpactStar.new()
	var ay: float = yaw
	var ax: float
	if which == 0:
		ax = deg_to_rad(-70.0) + deg_to_rad(rng.randf_range(0.0, 20.0))
		ay += deg_to_rad(rng.randf_range(0.0, 20.0))
	else:
		ax = deg_to_rad(-60.0) - deg_to_rad(rng.randf_range(0.0, 20.0))
		ay += deg_to_rad(10.0) - deg_to_rad(rng.randf_range(0.0, 20.0))
		star.scale_from = 0.012
		star.scale_to = 0.006
	var mul := 6.0
	star.vel_gx = Vector3(mul * sin(ax) * sin(ay), mul * cos(ax), mul * sin(ax) * cos(ay))
	host.add_child(star)
	star.global_position = pos
	return star


## `calc_adjust_proc(timer, 26, 40, small, big)`: full size at 40, small from 26 down.
static func scale_at(t: int, small: float, big: float) -> float:
	return lerpf(small, big, clampf(float(t - 26) / 14.0, 0.0, 1.0))


## `calc_adjust_proc(timer, 0, 10, 0, 255)`.
static func alpha_at(t: int) -> float:
	return clampf(float(t) / 10.0, 0.0, 1.0)


func _ready() -> void:
	_card = GeneratedVisual.instantiate_raw(VISUAL)
	if _card != null:
		add_child(_card)
		for node: Node in _card.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			for i: int in mi.get_surface_override_material_count():
				var mat := mi.get_active_material(i) as StandardMaterial3D
				if mat == null:
					continue
				var own := mat.duplicate() as StandardMaterial3D
				own.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				own.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				own.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
				mi.set_surface_override_material(i, own)
				_materials.append(own)
	_draw()


func _process(delta: float) -> void:
	_steps.add(delta)
	while _steps.next():
		global_position += vel_gx * FieldCatalog.GX_TO_METERS
		vel_gx *= SLOW
		timer -= 1
		if timer <= 0:
			queue_free()
			return
	_draw()


func _draw() -> void:
	if _card == null:
		return
	## Same conversion as `FieldFx`: `Matrix_scale` over the pipeline's vertex scale.
	_card.scale = Vector3.ONE * scale_at(timer, scale_to, scale_from) * FieldCatalog.GX_TO_METERS / FieldCatalog.PIPELINE_SCALE
	var c := PRIM
	c.a = alpha_at(timer)
	for mat: StandardMaterial3D in _materials:
		mat.albedo_color = c
