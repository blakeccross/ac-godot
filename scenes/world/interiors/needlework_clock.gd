extends Node3D

## The Able Sisters wall clock (`HOUSE_CLOCK` / `aHC_draw_data[aHC_TYPE_TAILORS]`,
## `obj_clock_tailor`). A pendulum wall clock on the back wall; the hands turn on
## Z to the current RTC (`Matrix_RotateZ(90° - rad_hour/min)` in `aHC_DrawClockAfter`).

const VISUAL := &"obj_clock_tailor"
const HOUR_HINTS := ["short", "hour", "hari_s"]
const MIN_HINTS := ["long", "min", "hari_l"]
const FURI_HINTS := ["furi", "pend"]

var _hour: Node3D = null
var _min: Node3D = null
var _furi: Node3D = null
var _hour_rest := 0.0
var _min_rest := 0.0
var _furi_rest := 0.0
var _last_stamp := -1
var _t := 0.0


func _ready() -> void:
	_ensure_visual()
	_bind(self)


func _ensure_visual() -> void:
	if get_node_or_null("GeneratedVisual") != null:
		return
	if FieldCatalog.mesh_paths(VISUAL).is_empty():
		return
	var pivot: Node3D = GeneratedVisual.attach(self, VISUAL)
	if pivot == null:
		return
	## `obj_clock_tailor` verts carry the decomp skeleton root offset — recentre the
	## dial on this node so the wall mount lands where we place it.
	pivot.scale *= 0.62  ## `obj_clock_tailor` verts are oversized for a wall clock
	var aabb: AABB = GeneratedVisual.local_aabb(pivot)
	if aabb.size != Vector3.ZERO:
		var s: float = pivot.scale.x
		pivot.position.x = -(aabb.position.x + aabb.size.x * 0.5) * s
		pivot.position.y = -(aabb.position.y + aabb.size.y * 0.5) * s
		pivot.position.z = -(aabb.position.z + aabb.size.z * 0.5) * s
	GeneratedVisual._disable_shadows(pivot)


func _bind(node: Node) -> void:
	var n := String(node.name).to_lower()
	if node is Node3D and node != self:
		if _hour == null and _has(n, HOUR_HINTS):
			_hour = node
			_hour_rest = node.rotation.z
		elif _min == null and _has(n, MIN_HINTS):
			_min = node
			_min_rest = node.rotation.z
		elif _furi == null and _has(n, FURI_HINTS):
			_furi = node
			_furi_rest = node.rotation.z
	for c in node.get_children():
		_bind(c)


func _process(delta: float) -> void:
	if Clock == null:
		return
	_t += delta
	if _furi != null:
		## Gentle 1 Hz pendulum swing (`obj_clock_tailor_furi` anim).
		_furi.rotation.z = _furi_rest + sin(_t * PI) * 0.18
	var stamp: int = Clock.hour * 60 + Clock.minute
	if stamp == _last_stamp:
		return
	_last_stamp = stamp
	var mf: float = float(Clock.minute) / 60.0
	if _min != null:
		_min.rotation.z = _min_rest - TAU * mf
	if _hour != null:
		_hour.rotation.z = _hour_rest - TAU * (float(posmod(Clock.hour, 12)) + mf) / 12.0


func _has(label: String, hints: Array) -> bool:
	for h: String in hints:
		if h in label:
			return true
	return false
