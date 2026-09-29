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
## a tick (the int of 52 * 0.5 and 43 * 0.5).
const UNDERWATER_GX := 3.0
const UNDERWATER_RGB := Vector3i(100, 100, 128)
const COLOR_STEP := Vector3i(26, 26, 21)

## `aUKI_actor_draw` tilts the float on X only, and the model is authored upside down —
## every proc starts from `DEG2SHORT_ANGLE2(180.0f)`. Godot's Y is already up, so the
## flip is the rest pose and the proc targets below are offsets from it.
const REST_PITCH := PI
## Per-proc `(fraction, max_step)` pairs, straight off the `add_calc_short_angle2` calls.
## Fractions are `1 - sqrt(k)`; steps are short angles (0x10000 = a full turn).
const CAST_FRACTION := 1.0 - sqrt(0.95)
const CAST_MAX_STEP := 1024.0 * MLib.S16
const SETTLE_FRACTION := 1.0 - sqrt(0.8)
const SETTLE_MAX_STEP := PI * 0.25
## `aUKI_PROC_CAST` / `aUKI_PROC_WAIT` while `cast_timer` runs: the float lies flat.
const PITCH_FLAT := PI * 0.5
## `aUKI_PROC_BITE` with `gyo_status == 4`: yanked over toward the rod. Before the strike
## the bite proc draws no RotateX or RotateY at all — the float stands straight.
const PITCH_PULLED := -PI * 0.5

var _base: Vector3 = Vector3.INF
var _phase: float = 0.0
var _float: Node3D
var _pitch: float = PITCH_FLAT
var _tilt_steps := FrameStepper.new()
## `uki->color`, 0–255 a channel.
var _rgb: Vector3i = Vector3i(255, 255, 255)
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
	var fraction: float = CAST_FRACTION
	var max_step: float = CAST_MAX_STEP
	var drawn := true
	match Fishing.state():
		Fishing.State.BITE:
			target = PITCH_PULLED
			drawn = Fishing.is_struck()
		Fishing.State.FLOAT:
			## `aUKI_PROC_WAIT` once `cast_timer` has run out: stand upright, and stand up
			## fast — this is the beat that tells you the cast has settled.
			target = 0.0
			fraction = SETTLE_FRACTION
			max_step = SETTLE_MAX_STEP
	## The draw runs once per tick and `add_calc_short_angle2` steps per call, so the tilt
	## runs on fixed ticks rather than being scaled by `delta`.
	_tilt_steps.add(delta)
	while _tilt_steps.next():
		## Every `aUKI_rotate_calc` call passes `minStep == 0`, so the tilt stops where the
		## step rounds away rather than being floored to a minimum turn.
		if drawn:
			_pitch = MLib.short_angle2(_pitch, target, fraction, max_step)
		_rgb = chase_color(_rgb, height < -UNDERWATER_GX * FieldCatalog.GX_TO_METERS)
	## Every proc but an unstruck bite turns the float to face the rod (`uki_angle.y`) and
	## then tips it; an unstruck bite leaves it standing with neither.
	var to_rod: Vector3 = _origin() - global_position if is_inside_tree() else Vector3.ZERO
	var yaw: float = atan2(to_rod.x, to_rod.z) if drawn and to_rod.length_squared() > 0.0 else 0.0
	_float.rotation = Vector3(REST_PITCH + (_pitch if drawn else 0.0), yaw, 0.0)
	_paint()


## One tick of `aUKI_color`: each channel steps toward the underwater tint or back to white.
static func chase_color(rgb: Vector3i, under: bool) -> Vector3i:
	var goal: Vector3i = UNDERWATER_RGB if under else Vector3i(255, 255, 255)
	return Vector3i(
		int(move_toward(rgb.x, goal.x, COLOR_STEP.x)),
		int(move_toward(rgb.y, goal.y, COLOR_STEP.y)),
		int(move_toward(rgb.z, goal.z, COLOR_STEP.z)),
	)


func tint() -> Color:
	return Color8(_rgb.x, _rgb.y, _rgb.z)


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
