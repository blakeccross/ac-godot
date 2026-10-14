class_name StatueSparkle
extends Node3D

## `ef_douzou_light`: the glint that twinkles on a statue (`aDOU_setEffect`). A billboarded
## star (`ef_carhosi01_00`) in the statue's colour that a `Tween` swells and shrinks, then
## frees. The statue starts one every `b_timetbl + r_timetbl · rand` ticks at a random point
## over the figure (`offset_tbl` ± `mult_p_tbl` / 2), both by rank.

const VISUAL := &"ef_carhosi01_00"
## Swells over 12 ticks, shrinks over the next 12.
const HALF_LIFE := 12.0 / 60.0
const LIFETIME := 2.0 * HALF_LIFE
## `eDouzou_Light_ct` / `_dw` by rank: peak scale and env colour.
const PEAK: Array[float] = [0.012, 0.011, 0.010, 0.009]
const COLOR: Array[Color] = [
	Color8(255, 255, 0), Color8(200, 255, 255), Color8(255, 100, 100), Color8(100, 255, 100),
]
## `aDOU_setEffect_sub` (GX, from the statue's spot).
const OFFSET: Array[Vector3] = [
	Vector3(1.0, 68.0, 14.0), Vector3(1.0, 62.0, 12.0), Vector3(1.0, 56.0, 10.0), Vector3(1.0, 50.0, 8.0),
]
const SPREAD: Array[Vector3] = [
	Vector3(26.0, 42.0, 0.0), Vector3(23.0, 38.0, 0.0), Vector3(20.0, 34.0, 0.0), Vector3(17.0, 30.0, 0.0),
]
## `aDOU_setEffect`: seconds to the next glint, `b + r · rand` (5 + 10 · rand ticks for gold).
const WAIT_BASE: Array[float] = [5.0 / 60.0, 15.0 / 60.0, 20.0 / 60.0, 30.0 / 60.0]
const WAIT_RAND: Array[float] = [10.0 / 60.0, 30.0 / 60.0, 40.0 / 60.0, 60.0 / 60.0]

var rank: int = 0
## The card's scale, animated by the tween.
var size: float = 0.0:
	set(value):
		size = value
		_redraw()
var _card: Node3D
var _materials: Array[StandardMaterial3D] = []


static func spawn(host: Node, base: Vector3, p_rank: int, rng: RandomNumberGenerator) -> StatueSparkle:
	if host == null:
		return null
	var r: int = clampi(p_rank, 0, 3)
	var fx := StatueSparkle.new()
	fx.rank = r
	host.add_child(fx)
	fx.global_position = base + offset_gx(r, rng) * FieldCatalog.GX_TO_METERS
	return fx


static func offset_gx(r: int, rng: RandomNumberGenerator) -> Vector3:
	var s: Vector3 = SPREAD[r]
	return OFFSET[r] + Vector3(s.x * (rng.randf() - 0.5), s.y * (rng.randf() - 0.5), s.z * (rng.randf() - 0.5))


## Seconds until the next glint.
static func next_wait(r: int, rng: RandomNumberGenerator) -> float:
	return WAIT_BASE[r] + WAIT_RAND[r] * rng.randf()


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
				own.billboard_keep_scale = true
				own.albedo_color = COLOR[rank]
				mi.set_surface_override_material(i, own)
				_materials.append(own)
	_redraw()
	## `eDouzou_Light_mv`: 0 → peak, back to 0.
	var tween := create_tween()
	tween.tween_property(self, "size", PEAK[rank], HALF_LIFE).from(0.0)
	tween.tween_property(self, "size", 0.0, HALF_LIFE)
	tween.tween_callback(queue_free)


func _redraw() -> void:
	if _card != null:
		_card.scale = Vector3.ONE * maxf(size, 0.0001) * FieldCatalog.GX_TO_METERS / FieldCatalog.PIPELINE_SCALE
