class_name SpiritGlow
extends Node3D

## The glow the wishing well's spirit comes and goes in (`eEC_EFFECT_MAKE_HEM`,
## `ef_make_hem.c`, from `aSHR_make_hem`). A light sphere swells and brightens for 120 ticks, holds
## until tick 150 - the moment the spirit shows (or hides) - and sixteen glints are shaken
## loose, falling slowly and twinkling on a 16-tick beat, then the sphere fades out by 196.
## The spirit's own visibility is the owner's: it listens for `swapped`.

signal swapped

const SHADER := preload("res://shaders/spirit_glow.gdshader")
const SPHERE_VISUAL := &"ef_sphere_light"
const GLINT_VISUAL := &"ef_takurami01_kira"
const GX := FieldCatalog.GX_TO_METERS
const K := GX / FieldCatalog.PIPELINE_SCALE
const SE_APPEAR := &"468"
const SE_VANISH := &"469"
## Where the sphere hangs over the spirit's feet.
const HEIGHT_APPEAR := 30.0
const HEIGHT_VANISH := 20.0
const SWAP_TICK := 150.0
const END_TICK := 196.0
const GLINT_COUNT := 16
const GLINT_RADIUS := 20.0
const GLINT_SIZE := 0.0065
const GLINT_PRIM := Color(1.0, 1.0, 1.0, 200.0 / 255.0)
const SPHERE_SCALE := 0.575
## `add_calc(&scale, 0.575, 0.05, 0.1, 0.001)`.
const SCALE_EASE := 0.05
const SCALE_MAX_STEP := 0.1
const SCALE_MIN_STEP := 0.001

var _appearing: bool = true
var _at: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _sphere_scale: float = 0.0
var _sphere: MeshInstance3D
var _mats: Array[ShaderMaterial] = []
var _swapped: bool = false
var _rng := RandomNumberGenerator.new()
var _glints: Array[Dictionary] = []


## Glow over `feet` (world metres): the spirit arriving or leaving.
static func play(host: Node, feet: Vector3, appearing: bool) -> SpiritGlow:
	if host == null:
		return null
	var glow := SpiritGlow.new()
	glow.name = "SpiritGlow"
	glow._appearing = appearing
	glow._at = feet + Vector3(0.0, (HEIGHT_APPEAR if appearing else HEIGHT_VANISH) * GX, 0.0)
	glow._rng.randomize()
	host.add_child(glow)
	glow.global_position = Vector3.ZERO
	glow._build()
	Audio.play_se(SE_APPEAR if appearing else SE_VANISH, glow)
	return glow


func _build() -> void:
	var paths: PackedStringArray = FieldCatalog.mesh_paths(SPHERE_VISUAL)
	var packed: PackedScene = load(paths[0]) as PackedScene if not paths.is_empty() else null
	if packed == null:
		return
	var root: Node = packed.instantiate()
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var src := n as MeshInstance3D
		_sphere = MeshInstance3D.new()
		_sphere.mesh = src.mesh
		for i: int in src.mesh.get_surface_count():
			var mat := ShaderMaterial.new()
			mat.shader = SHADER
			mat.render_priority = 3
			mat.set_shader_parameter(&"strength", 0.0)
			_sphere.set_surface_override_material(i, mat)
			_mats.append(mat)
		break
	root.free()
	if _sphere != null:
		_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sphere.top_level = true
		add_child(_sphere)
		_sphere.global_position = _at


func _process(delta: float) -> void:
	var step: float = delta * DecompTime.TICK_HZ
	var from: float = _age
	_age += step
	var ticks: int = int(floor(_age)) - int(floor(from))
	for _i: int in ticks:
		_sphere_scale = _ease(_sphere_scale)
	var alpha: float = _sphere_alpha(_age)
	for mat: ShaderMaterial in _mats:
		mat.set_shader_parameter(&"strength", alpha)
	if _sphere != null:
		var s: float = _sphere_scale * 0.01 * K
		_sphere.scale = Vector3.ONE * maxf(s, 0.00001)
		_sphere.global_position = _at
	if not _swapped and _age >= SWAP_TICK:
		_swapped = true
		_shed_glints()
		swapped.emit()
	_move_glints(step)
	if _age >= END_TICK:
		for g: Dictionary in _glints:
			(g["card"] as Node3D).queue_free()
		queue_free()


## `eMH_mv`: the sphere's opacity by tick.
static func _sphere_alpha(age: float) -> float:
	if age <= 120.0:
		return age / 120.0
	if age <= SWAP_TICK:
		return 1.0
	return clampf(1.0 - (age - 151.0) / (195.0 - 151.0), 0.0, 1.0)


static func _ease(value: float) -> float:
	var step: float = (SPHERE_SCALE - value) * SCALE_EASE
	step = clampf(step, -SCALE_MAX_STEP, SCALE_MAX_STEP)
	if absf(SPHERE_SCALE - value) < SCALE_MIN_STEP:
		return SPHERE_SCALE
	if absf(step) < SCALE_MIN_STEP:
		step = SCALE_MIN_STEP * signf(step)
	return value + step


## `eMHK_*`: a twinkle that drifts down 0.2-0.3 GX a tick on a 16-tick beat.
func _shed_glints() -> void:
	for _i: int in GLINT_COUNT:
		var card: Node3D = EffectCards.make(self, GLINT_VISUAL, GLINT_PRIM, Color.WHITE)
		if card == null:
			continue
		var a: float = _rng.randf() * TAU
		_glints.append({
			"card": card,
			"at": Vector3(GLINT_RADIUS * sin(a), -10.0 + _rng.randf() * 25.0, GLINT_RADIUS * cos(a)),
			"fall": 0.2 + _rng.randf() * 0.1,
			"beat": _rng.randi_range(0, 31),
			"age": 0.0,
		})


func _move_glints(step: float) -> void:
	for g: Dictionary in _glints:
		var at: Vector3 = g["at"]
		at.y -= float(g["fall"]) * step
		g["at"] = at
		g["age"] = float(g["age"]) + step
		var beat: int = (int(g["age"]) + int(g["beat"])) & 15
		var size: float = _adjust(float(beat), 0.0, 7.0, 0.0, GLINT_SIZE) if beat <= 7 else _adjust(float(beat), 8.0, 15.0, GLINT_SIZE, 0.0)
		EffectCards.face(g["card"] as Node3D, _at + at * GX, size)


static func _adjust(now: float, start: float, end: float, a: float, b: float) -> float:
	if now <= start:
		return a
	if now >= end:
		return b
	return a + (now - start) * ((b - a) / (end - start))
