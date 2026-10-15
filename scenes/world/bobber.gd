extends Node3D

## Uki (`ac_uki.h`) presentation: a parabola out to the cast point, a slow float bob, a dip
## on every nibble, pulled under while a fish has it and yanked up out of the water once
## struck. `Fishing` owns all the timing and
## the bobber's position once it lands (`aUKI_movement`'s drift), including when this node
## is freed — this script only reads it.

const VISUAL_ID := &"tol_uki_1"

const BOB_AMPLITUDE := 0.03
const BOB_RATE := 2.2
## How far under the surface a nibble pulls it. A fish that has it sets the height itself
## (`Fishing.rise`).
const DIP_DEPTH := 0.075
## `aUKI_color`: more than 3 GX under the surface the float is tinted (100, 100, 128), and
## back above it returns to white. `aUKI_chase_color` moves each channel by half its step
## a tick (the int of 52 * 0.5 and 43 * 0.5): per second, out of 255.
const UNDERWATER := 0.15  ## 3 GX
const UNDERWATER_RGB := Vector3(100, 100, 128) / 255.0
const COLOR_RATE := Vector3(26, 26, 21) * 60.0 / 255.0

## `aUKI_actor_draw` tilts the float on X only, and the model is authored upside down —
## every proc starts from `DEG2SHORT_ANGLE2(180.0f)`. Godot's Y is already up, so the
## flip is the rest pose and the proc targets below are offsets from it.
const REST_PITCH := PI
## Per-proc tilt chases, from the `add_calc_short_angle2` calls (`1 - sqrt(k)` of the gap a
## tick, at most `max_step` short angles a tick): as half-lives and turn rates (rad/s).
const CAST_HALF_LIFE := 0.4504  ## Motion.half_life_from_fraction(1 − √0.95)
const CAST_MAX_RATE := 1024.0 * MathUtil.S16 * 60.0
const SETTLE_HALF_LIFE := 0.1035  ## Motion.half_life_from_fraction(1 − √0.8)
const SETTLE_MAX_RATE := PI * 0.25 * 60.0
## `aUKI_PROC_CAST` / `aUKI_PROC_WAIT` while `cast_timer` runs: the float lies flat.
const PITCH_FLAT := PI * 0.5
## `aUKI_PROC_BITE` with `gyo_status == 4`: yanked over toward the rod. Before the strike
## the bite proc draws no RotateX or RotateY at all — the float stands straight.
const PITCH_PULLED := -PI * 0.5

var _base: Vector3 = Vector3.INF
var _phase: float = 0.0
var _float: Node3D
var _pitch: float = PITCH_FLAT
## `uki->color`, 0–1 a channel.
var _rgb: Vector3 = Vector3.ONE
var _materials: Array[BaseMaterial3D] = []


func _ready() -> void:
	add_to_group("bobber")
	_float = get_node_or_null("Float") as Node3D
	var mesh: Node3D = GeneratedVisual.attach(_float, VISUAL_ID)
	if mesh != null:
		## `_fit_actor` drops a model's lowest vertex onto Y=0, which is right for something
		## standing on the ground and wrong here: `aUKI_actor_draw` puts the authored origin
		## at the actor position, and for the uki that is the waterline. Keep it there so the
		## spindle hangs under the surface and the dome shows above it.
		mesh.position.y = 0.0
		_own_materials(mesh)


func _process(delta: float) -> void:
	if not Fishing.is_active():
		return
	## The landing spot while it flies, then wherever the current has taken it.
	_base = Fishing.anchor()
	_phase += delta
	var offset: Vector3 = Vector3.ZERO
	var progress: float = Fishing.cast_progress()
	if progress < 1.0:
		## `parabola_vec` / `parabola_acc`: the bobber arcs from the rod tip to the cast
		## point. We only have the landing spot, so the arc is drawn from the caster's side.
		var throw: Vector3 = _base - _origin()
		offset = -throw * (1.0 - progress)
		offset.y += throw.length() * Fishing.CAST_ARC * sin(progress * PI)
	else:
		if Fishing.state() == Fishing.State.BITE:
			offset.y = Fishing.rise()
		else:
			offset.y = sin(_phase * BOB_RATE) * BOB_AMPLITUDE - Fishing.dip() * DIP_DEPTH
	if is_inside_tree():
		global_position = _base + offset
	else:
		position = _base + offset
	_tilt(delta, offset.y)


func _tilt(delta: float, height: float) -> void:
	if _float == null:
		return
	var target: float = PITCH_FLAT
	var half_life: float = CAST_HALF_LIFE
	var max_rate: float = CAST_MAX_RATE
	var drawn := true
	match Fishing.state():
		Fishing.State.BITE:
			target = PITCH_PULLED
			drawn = Fishing.is_struck()
		Fishing.State.FLOAT:
			## `aUKI_PROC_WAIT` once `cast_timer` has run out: stand upright, and stand up
			## fast — this is the beat that tells you the cast has settled.
			target = 0.0
			half_life = SETTLE_HALF_LIFE
			max_rate = SETTLE_MAX_RATE
	if drawn:
		_pitch = tilt_toward(_pitch, target, half_life, max_rate, delta)
	_rgb = chase_color(_rgb, height < -UNDERWATER, delta)
	## Every proc but an unstruck bite turns the float to face the rod (`uki_angle.y`) and
	## then tips it; an unstruck bite leaves it standing with neither.
	var to_rod: Vector3 = _origin() - global_position if is_inside_tree() else Vector3.ZERO
	var yaw: float = atan2(to_rod.x, to_rod.z) if drawn and to_rod.length_squared() > 0.0 else 0.0
	_float.rotation = Vector3(REST_PITCH + (_pitch if drawn else 0.0), yaw, 0.0)
	_paint()


## The float's pitch eased toward `target` over `delta` seconds, never turning faster than
## `max_rate`.
static func tilt_toward(pitch: float, target: float, half_life: float, max_rate: float, delta: float) -> float:
	var eased: float = Motion.damp_angle(pitch, target, half_life, delta)
	var step: float = clampf(angle_difference(pitch, eased), -max_rate * delta, max_rate * delta)
	return pitch + step


## `aUKI_color` over `delta` seconds: each channel heads toward the underwater tint or back
## to white at its own rate.
static func chase_color(rgb: Vector3, under: bool, delta: float) -> Vector3:
	var goal: Vector3 = UNDERWATER_RGB if under else Vector3.ONE
	return Vector3(
		move_toward(rgb.x, goal.x, COLOR_RATE.x * delta),
		move_toward(rgb.y, goal.y, COLOR_RATE.y * delta),
		move_toward(rgb.z, goal.z, COLOR_RATE.z * delta),
	)


func tint() -> Color:
	return Color(_rgb.x, _rgb.y, _rgb.z)


## `gDPSetPrimColor` on the float: give it its own copies of its materials so tinting one
## bobber does not tint the shared model.
func _own_materials(node: Node) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i) as BaseMaterial3D
			if mat == null:
				continue
			var copy := mat.duplicate() as BaseMaterial3D
			copy.set_meta(&"uki_base_color", mat.albedo_color)
			mi.set_surface_override_material(i, copy)
			_materials.append(copy)
	for child in node.get_children():
		_own_materials(child)


func _paint() -> void:
	var tint_color: Color = tint()
	for mat in _materials:
		var base: Color = mat.get_meta(&"uki_base_color", Color.WHITE)
		mat.albedo_color = Color(base.r * tint_color.r, base.g * tint_color.g, base.b * tint_color.b, base.a)


func _origin() -> Vector3:
	var player := Player.find(get_tree())
	if player == null:
		return _base
	return Vector3(player.global_position.x, _base.y, player.global_position.z)
