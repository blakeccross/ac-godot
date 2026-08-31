extends Node3D

## Uki (`ac_uki.h`) presentation: a parabola out to the cast point, a slow float bob, a dip
## on every nibble, and held under while a fish has it. `Fishing` owns all the timing,
## including when this node is freed — this script only reads it.

const VISUAL_ID := &"tol_uki_1"

const BOB_AMPLITUDE := 0.03
const BOB_RATE := 2.2
## `aUKI_STATUS_VIB`: the bobber shudders while the fish is on.
const VIB_AMPLITUDE := 0.055
const VIB_RATE := 26.0
## How far under the surface a nibble and a hooked fish pull it.
const DIP_DEPTH := 0.075
const HELD_DEPTH := 0.115

## `aUKI_actor_draw` tilts the float on X only, and the model is authored upside down —
## every proc starts from `DEG2SHORT_ANGLE2(180.0f)`. Godot's Y is already up, so the
## flip is the rest pose and the proc targets below are offsets from it.
const REST_PITCH := PI
## The draw runs once per rendered frame at 30 Hz, and `add_calc_short_angle2` steps per
## call, so the tilt is accumulated on a fixed tick rather than scaled by `delta`.
const TILT_HZ := 30.0
## Per-proc `(fraction, max_step)` pairs, straight off the `add_calc_short_angle2` calls.
## Fractions are `1 - sqrt(k)`; steps are short angles (0x10000 = a full turn).
const CAST_FRACTION := 0.025321  # 1 - sqrt(0.95)
const CAST_MAX_STEP := TAU * 1024.0 / 65536.0
const SETTLE_FRACTION := 0.105573  # 1 - sqrt(0.8)
const SETTLE_MAX_STEP := PI * 0.25
## `aUKI_PROC_CAST` / `aUKI_PROC_WAIT` while `cast_timer` runs: the float lies flat.
const PITCH_FLAT := PI * 0.5
## `aUKI_PROC_BITE` with `gyo_status == 4`: yanked nose-down.
const PITCH_PULLED := -PI * 0.5

var _base: Vector3 = Vector3.INF
var _phase: float = 0.0
var _float: Node3D
var _pitch: float = PITCH_FLAT
var _tilt_debt: float = 0.0


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


func _process(delta: float) -> void:
	if _base == Vector3.INF:
		_base = position
	if not Fishing.is_active():
		return
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
		var dip: float = Fishing.dip()
		var held: bool = Fishing.state() == Fishing.State.BITE
		var amplitude: float = VIB_AMPLITUDE if held else BOB_AMPLITUDE
		var rate: float = VIB_RATE if held else BOB_RATE
		offset.y = sin(_phase * rate) * amplitude
		offset.y -= dip * (HELD_DEPTH if held else DIP_DEPTH)
	position = _base + offset
	_tilt(delta)


func _tilt(delta: float) -> void:
	if _float == null:
		return
	var target: float = PITCH_FLAT
	var fraction: float = CAST_FRACTION
	var max_step: float = CAST_MAX_STEP
	match Fishing.state():
		Fishing.State.BITE:
			target = PITCH_PULLED
		Fishing.State.FLOAT:
			## `aUKI_PROC_WAIT` once `cast_timer` has run out: stand upright, and stand up
			## fast — this is the beat that tells you the cast has settled.
			target = 0.0
			fraction = SETTLE_FRACTION
			max_step = SETTLE_MAX_STEP
	_tilt_debt += delta
	var step: float = 1.0 / TILT_HZ
	while _tilt_debt >= step:
		_tilt_debt -= step
		## Every `aUKI_rotate_calc` call passes `minStep == 0`, so the tilt stops where the
		## step rounds away rather than being floored to a minimum turn.
		_pitch = MLib.short_angle2(_pitch, target, fraction, max_step)
	_float.rotation.x = REST_PITCH + _pitch


func _origin() -> Vector3:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D if get_tree() else null
	if player == null:
		return _base
	return Vector3(player.global_position.x, _base.y, player.global_position.z)
