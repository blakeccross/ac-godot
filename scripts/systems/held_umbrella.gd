class_name HeldUmbrella
extends RefCounted

## The umbrella in the player's hand (`ac_t_umbrella.c` + `m_player_item_umbrella`). The GLB
## (`tol_umb_NN`, `split_by_gfx`) keeps the handle (`e_umbNN_model*`) and canopy
## (`kasa_umbNN_model*`) apart: the draw rotates −90° about Y off the hand matrix, scales the
## handle, then moves 4500 GX up it and scales the canopy — so the canopy inherits the
## handle's scale. Opening and closing animate those two scales from per-sector tables.
##
## The arm's `ply_1_umbrella1` carry pose is the generic `ToolCarry` overlay (NET part table).

## `aTUMB_ACTION_*` (the tool's `work0`).
enum Action { TAKEOUT_BEFORE, OPENING, PUTAWAY, DESTRUCT, OPEN_NOW }

## `max_anm`: frames each action runs to (0.5 per 60 Hz tick).
const MAX_FRAME: Array[float] = [0.0, 26.0, 30.0, 30.0, 26.0]
const FRAME_STEP := 0.5
## Handle (`e_*`) and canopy (`kasa_*`) keyframes: sector ends, then (x, y) scale per sector
## point. x runs along the handle; y is used for both y and z.
const OPEN_E_SECT: Array[float] = [0.0, 7.0, 11.0, 18.0, 22.0, 26.0]
const OPEN_E_SCALE: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.5, 1.0, 0.5, 1.0, 1.0, 1.0, 1.0, 1.0]
const OPEN_K_SECT: Array[float] = [0.0, 15.0, 22.0, 26.0]
const OPEN_K_SCALE: Array[float] = [3.0, 0.15, 3.0, 0.15, 1.0, 1.0, 0.9, 1.0]
const CLOSE_E_SECT: Array[float] = [0.0, 4.0, 12.0, 15.0, 22.0, 30.0]
const CLOSE_E_SCALE: Array[float] = [1.0, 1.0, 1.0, 1.0, 0.5, 1.0, 0.5, 1.0, 0.0, 0.0, 0.0, 0.0]
const CLOSE_K_SECT: Array[float] = [0.0, 4.0, 12.0, 30.0]
const CLOSE_K_SCALE: Array[float] = [1.0, 1.0, 1.2, 1.0, 3.0, 0.15, 3.0, 0.15]
## `Matrix_translate(4500, 0, 0)` in the GLB's 0.001-scaled units.
const CANOPY_OFFSET := 4.5
## `aTUMB_OngenTrgStart`: opening / putting away.
const SE_OPEN := &"139"
const SE_CLOSE := &"10e"

var action: Action = Action.OPEN_NOW
var frame: float = 0.0
## `opened_fully`: what the rain SE (`mPlib_check_player_open_umbrella`) listens to.
var opened_fully: bool = false
var _handle: Node3D
var _canopy: Node3D
var _at: Node3D


## Split the tool visual into handle / canopy pivots and start in `start` (`aTUMB_setupAction`).
func setup(visual: Node3D, start: Action) -> void:
	_at = visual
	if visual == null:
		set_action(start, false)
		return
	## `Matrix_rotateXYZ(0, -0x4000, 0)` straight after the hand matrix.
	visual.basis = Basis(Vector3.UP, -PI * 0.5)
	_handle = Node3D.new()
	_handle.name = "UmbHandle"
	_canopy = Node3D.new()
	_canopy.name = "UmbCanopy"
	_canopy.position = Vector3(CANOPY_OFFSET, 0.0, 0.0)
	var parts: Array[Node] = []
	_collect(visual, parts)
	visual.add_child(_handle)
	_handle.add_child(_canopy)
	for node: Node in parts:
		var into: Node3D = _canopy if String(node.name).begins_with("kasa_") else _handle
		node.get_parent().remove_child(node)
		into.add_child(node)
	set_action(start, false)


func set_action(next: Action, with_se: bool = true) -> void:
	action = next
	frame = MAX_FRAME[Action.OPEN_NOW] if next == Action.OPEN_NOW else 0.0
	opened_fully = next == Action.OPEN_NOW
	if with_se and _at != null and _at.is_inside_tree():
		if next == Action.OPENING:
			Audio.play_se(SE_OPEN)
		elif next == Action.PUTAWAY:
			Audio.play_se(SE_CLOSE)
	_apply()


## `aTUMB_actor_move` for `delta` seconds: take-out turns into opening straight away; frames
## advance 0.5 per tick up to the action's end.
func tick(delta: float) -> void:
	if action == Action.TAKEOUT_BEFORE:
		set_action(Action.OPENING)
	var last: float = MAX_FRAME[int(action)]
	frame = minf(frame + FRAME_STEP * delta * DecompTime.TICK_HZ, last)
	if action == Action.OPENING:
		opened_fully = frame >= last
	_apply()


func is_closed() -> bool:
	return (action == Action.PUTAWAY or action == Action.DESTRUCT) and frame >= MAX_FRAME[int(action)]


## `aTUMB_calc_model_scale`: (handle, canopy) scales for an action at a frame.
static func scales(for_action: Action, at_frame: float) -> Array[Vector3]:
	var closing: bool = for_action == Action.PUTAWAY or for_action == Action.DESTRUCT
	return [
		_sector_scale(CLOSE_E_SECT if closing else OPEN_E_SECT, CLOSE_E_SCALE if closing else OPEN_E_SCALE, at_frame),
		_sector_scale(CLOSE_K_SECT if closing else OPEN_K_SECT, CLOSE_K_SCALE if closing else OPEN_K_SCALE, at_frame),
	]


## `aTUMB_calc_model_scale_sub`: find the sector holding `(int)frame`, lerp its end points.
static func _sector_scale(sect: Array[float], table: Array[float], at_frame: float) -> Vector3:
	var f: int = int(at_frame)
	var i: int = 1
	var k: int = 0
	while i < sect.size():
		if f <= int(sect[i]):
			f -= int(sect[i - 1])
			break
		i += 1
		k += 1
	i = mini(i, sect.size() - 1)
	k = mini(k, sect.size() - 2)
	var t: float = float(f) / (sect[i] - sect[i - 1])
	var x: float = lerpf(table[k * 2], table[k * 2 + 2], t)
	var y: float = lerpf(table[k * 2 + 1], table[k * 2 + 3], t)
	return Vector3(x, y, y)


func _apply() -> void:
	if _handle == null:
		return
	var s: Array[Vector3] = scales(action, frame)
	_handle.scale = _safe(s[0])
	_canopy.scale = _safe(s[1])
	_handle.visible = s[0].x > 0.001 and s[0].y > 0.001


static func _safe(v: Vector3) -> Vector3:
	return Vector3(maxf(v.x, 0.001), maxf(v.y, 0.001), maxf(v.z, 0.001))


static func _collect(node: Node, out: Array[Node]) -> void:
	for child: Node in node.get_children():
		var n: String = String(child.name)
		if child is MeshInstance3D and (n.begins_with("e_umb") or n.begins_with("kasa_umb")):
			out.append(child)
		else:
			_collect(child, out)
