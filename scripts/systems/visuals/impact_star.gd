class_name ImpactStar
extends Node3D

## `ef_impact_star`: a yellow star (`ef_star01_00`, prim 255/255/100) that flies up and out
## from where a shovel strikes something hard, slowing as it goes, shrinking at the start of
## its life and fading at the end. Drawn as a billboard. Two of them per strike
## (`eDig_Scoop_init`, `arg1` 0 and 1).
##
## One `Tween` drives `age`; position, size and opacity are all closed-form functions of it,
## so the flight is identical at any frame rate.

const VISUAL := &"ef_star01_00"
const PRIM := Color8(255, 255, 100)
## 40 ticks.
const LIFETIME := 40.0 * DecompTime.TICK_SEC
## Shrinks from full size over the first 14 ticks…
const SHRINK_TIME := 14.0 * DecompTime.TICK_SEC
## …and fades out over the last 10.
const FADE_TIME := 10.0 * DecompTime.TICK_SEC
## 6 GX a tick at launch.
const LAUNCH_SPEED := 6.0 * 60.0 * FieldCatalog.GX_TO_METERS
## Speed × √0.85 a tick halves it every 8.53 ticks.
const DRAG_HALF_LIFE := 0.14217

## Launch velocity in m/s; the star slows from it with `DRAG_HALF_LIFE`.
var velocity: Vector3 = Vector3.ZERO
## Card scale at launch and once shrunk (`Matrix_scale` units).
var start_size: float = 0.01
var end_size: float = 0.004
## Seconds since launch. The tween animates it; setting it redraws.
var age: float = 0.0:
	set(value):
		age = value
		_redraw()

var _origin: Vector3 = Vector3.ZERO
var _card: Node3D
var _materials: Array[StandardMaterial3D] = []


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
		star.start_size = 0.012
		star.end_size = 0.006
	star.velocity = LAUNCH_SPEED * Vector3(sin(ax) * sin(ay), cos(ax), sin(ax) * cos(ay))
	host.add_child(star)
	star.global_position = pos
	star._origin = star.position
	return star


## How far a star launched at `velocity` has travelled after `t` seconds of drag.
static func offset_at(launch_velocity: Vector3, t: float) -> Vector3:
	var reach: float = DRAG_HALF_LIFE / log(2.0)
	return launch_velocity * reach * (1.0 - pow(0.5, t / DRAG_HALF_LIFE))


## Full size at launch, down to `small` once `SHRINK_TIME` has passed.
static func size_at(t: float, small: float, big: float) -> float:
	return lerpf(big, small, clampf(t / SHRINK_TIME, 0.0, 1.0))


## Opaque until the last `FADE_TIME` of its life.
static func opacity_at(t: float) -> float:
	return clampf((LIFETIME - t) / FADE_TIME, 0.0, 1.0)


func _ready() -> void:
	_origin = position
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
				own.billboard_keep_scale = true
				mi.set_surface_override_material(i, own)
				_materials.append(own)
	_redraw()
	var tween := create_tween()
	tween.tween_property(self, "age", LIFETIME, LIFETIME).from(0.0)
	tween.tween_callback(queue_free)


func _redraw() -> void:
	if not is_inside_tree():
		return
	position = _origin + offset_at(velocity, age)
	if _card == null:
		return
	## Same conversion as `FieldEffects`: `Matrix_scale` over the pipeline's vertex scale.
	_card.scale = Vector3.ONE * size_at(age, end_size, start_size) * FieldCatalog.GX_TO_METERS / FieldCatalog.PIPELINE_SCALE
	var c := PRIM
	c.a = opacity_at(age)
	for mat: StandardMaterial3D in _materials:
		mat.albedo_color = c
