class_name CarBlight
extends Node3D

## Gracie's washed car glittering (`eEC_EFFECT_CAR_BLIGHT` + `eEC_EFFECT_CAR_LIGHT`,
## `ef_car_blight.c` / `ef_car_light.c`, from `aSCR_actor_move`). For 42 ticks a star
## (`ef_carhosi01_00`) pops up every fourth tick at a fresh one of sixteen spots along a diagonal
## across the car, swelling and shrinking over 24 ticks. A wash done quickly (result 0) also
## sweeps a gleam over the whole body (`ef_car01`).

const GX := FieldCatalog.GX_TO_METERS
const K := GX / FieldCatalog.PIPELINE_SCALE
const SHADER := preload("res://shaders/car_shine.gdshader")
const STAR_VISUAL := &"ef_carhosi01_00"
const GLEAM_VISUAL := &"ef_car01"
const TOTAL_TICKS := 42.0
const STAR_PERIOD := 4.0
const STAR_FIRST := 2.0
const STAR_TICKS := 24.0
const STAR_SIZE := 0.015
const STAR_PRIM := Color.WHITE
const STAR_ENV := Color(1.0, 1.0, 0.0)
## `light_make_pos`, GX from the car's corner (`pos - (50, 0, -50)` is added).
const SPOTS: Array[Vector2] = [
	Vector2(0, 30), Vector2(20, 20), Vector2(40, 10), Vector2(-10, 60), Vector2(10, 50), Vector2(30, 40),
	Vector2(50, 30), Vector2(0, 80), Vector2(20, 70), Vector2(40, 60), Vector2(60, 50), Vector2(30, 90),
	Vector2(50, 80), Vector2(70, 70), Vector2(90, 60), Vector2(100, 80),
]
const CORNER := Vector2(-50.0, 50.0)

var _car: Vector3 = Vector3.ZERO
var _gleam_on: bool = false
var _age: float = 0.0
var _stars_made: int = 0
var _used: int = 0
var _rng := RandomNumberGenerator.new()
## Each star: {card, at, born}.
var _stars: Array[Dictionary] = []
var _gleam: MeshInstance3D
var _gleam_mat: ShaderMaterial


## Glitter over the car standing at `at` (world metres); `gleam` for a quick wash.
static func start(host: Node, at: Vector3, gleam: bool) -> CarBlight:
	if host == null:
		return null
	var fx := CarBlight.new()
	fx.name = "CarBlight"
	fx._car = at
	fx._gleam_on = gleam
	fx._rng.randomize()
	host.add_child(fx)
	fx.global_transform = Transform3D.IDENTITY
	if gleam:
		fx._build_gleam()
	return fx


func _build_gleam() -> void:
	var paths: PackedStringArray = FieldCatalog.mesh_paths(GLEAM_VISUAL)
	var packed: PackedScene = load(paths[0]) as PackedScene if not paths.is_empty() else null
	if packed == null:
		return
	var root: Node = packed.instantiate()
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var src := n as MeshInstance3D
		_gleam = MeshInstance3D.new()
		_gleam.mesh = src.mesh
		_gleam_mat = ShaderMaterial.new()
		_gleam_mat.shader = SHADER
		_gleam_mat.render_priority = 3
		for i: int in src.mesh.get_surface_count():
			_gleam.set_surface_override_material(i, _gleam_mat)
		break
	root.free()
	if _gleam != null:
		_gleam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_gleam.top_level = true
		add_child(_gleam)
		_gleam.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * 0.01 * K), _car)


func _process(delta: float) -> void:
	_age += delta * DecompTime.TICK_HZ
	while STAR_FIRST + float(_stars_made) * STAR_PERIOD <= _age and _stars_made < 11:
		_make_star(STAR_FIRST + float(_stars_made) * STAR_PERIOD)
		_stars_made += 1
	for star: Dictionary in _stars.duplicate():
		var life: float = _age - float(star["born"])
		if life >= STAR_TICKS:
			(star["card"] as Node3D).queue_free()
			_stars.erase(star)
			continue
		var timer: float = STAR_TICKS - life
		var size: float = _adjust(timer, 12.0, 24.0, STAR_SIZE, 0.0) if timer > 12.0 else _adjust(timer, 0.0, 12.0, 0.0, STAR_SIZE)
		EffectCards.face(star["card"] as Node3D, star["at"] as Vector3, size)
	if _gleam_mat != null:
		var t: float = clampf(_age / TOTAL_TICKS, 0.0, 1.0)
		_gleam_mat.set_shader_parameter(&"phase", _age / 60.0)
		_gleam_mat.set_shader_parameter(&"strength", sin(t * PI))
	if _age >= TOTAL_TICKS + STAR_TICKS:
		queue_free()


## `eCar_Blight_light_control`: a spot not used yet.
func _make_star(born: float) -> void:
	var slot: int = _rng.randi_range(0, 15)
	while _used & (1 << slot) != 0:
		slot = (slot + 1) % 16
	_used |= 1 << slot
	var card: Node3D = EffectCards.make(self, STAR_VISUAL, STAR_PRIM, STAR_ENV)
	if card == null:
		return
	var gx := Vector3(SPOTS[slot].x + CORNER.x, SPOTS[slot].y, CORNER.y)
	_stars.append({"card": card, "at": _car + gx * GX, "born": born})


static func _adjust(now: float, start: float, end: float, a: float, b: float) -> float:
	if now <= start:
		return a
	if now >= end:
		return b
	return a + (now - start) * ((b - a) / (end - start))
