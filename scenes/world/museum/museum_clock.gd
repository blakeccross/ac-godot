extends Node3D

## Entrance-hall floor clock (`obj_clock_museum1` / `HOUSE_CLOCK`). Turns whatever hand
## nodes the GLB exposes to the current RTC. Falls back to a silent no-op if the mesh
## has no separable hands.

const HOUR_NAME_HINTS := ["hour", "hari_s", "short", "hr"]
const MIN_NAME_HINTS := ["min", "hari_l", "long"]

## GLB visual is attached at runtime (materials + floor snap) unless already a child.
const VISUAL := &"obj_clock_museum1"

var _hour_hand: Node3D = null
var _min_hand: Node3D = null
var _last_stamp: int = -1


func _ready() -> void:
	_ensure_visual()
	_find_hands(self)


func _ensure_visual() -> void:
	if get_node_or_null("GeneratedVisual") != null:
		return
	if FieldCatalog.mesh_paths(VISUAL).is_empty():
		return
	var pivot: Node3D = GeneratedVisual.attach(self, VISUAL)
	if pivot == null:
		return
	## `obj_clock_museum1` verts carry the decomp skeleton offset (root ~240,150 GX), so
	## `_fit_actor` (which only micro-snaps Y) leaves the dial far off the host. Centre the
	## mesh AABB on this node in XZ, then rest it on the floor.
	var aabb: AABB = GeneratedVisual.local_aabb(pivot)
	if aabb.size != Vector3.ZERO:
		var s: float = pivot.scale.x
		pivot.position.x = -(aabb.position.x + aabb.size.x * 0.5) * s
		pivot.position.z = -(aabb.position.z + aabb.size.z * 0.5) * s
	GeneratedVisual.align_actor_to_height_gx(pivot, 0.0)


func _process(_delta: float) -> void:
	if Clock == null or (_hour_hand == null and _min_hand == null):
		return
	var stamp: int = Clock.hour * 60 + Clock.minute
	if stamp == _last_stamp:
		return
	_last_stamp = stamp
	var minute_frac: float = float(Clock.minute) / 60.0
	if _min_hand != null:
		_min_hand.rotation.y = -TAU * minute_frac
	if _hour_hand != null:
		_hour_hand.rotation.y = -TAU * (float(posmod(Clock.hour, 12)) + minute_frac) / 12.0


func _find_hands(node: Node) -> void:
	var name := String(node.name).to_lower()
	if node is Node3D and node != self:
		if _min_hand == null and _matches(name, MIN_NAME_HINTS):
			_min_hand = node
		elif _hour_hand == null and _matches(name, HOUR_NAME_HINTS):
			_hour_hand = node
	for child in node.get_children():
		_find_hands(child)


func _matches(name: String, hints: Array) -> bool:
	for h: String in hints:
		if h in name:
			return true
	return false
