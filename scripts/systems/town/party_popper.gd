class_name PartyPopper
extends Node3D

## A party popper going off (`eEC_EFFECT_CLACKER`, `ef_clacker.c`, thrown by the New Year's
## Eve countdown neighbours, `ac_countdown_npc1`). The popper itself flies up and out for four
## ticks' wait then 76 ticks, glittering as it goes; four ticks in it bursts into twenty
## pieces of confetti (`ef_kamifubuki`: two paper scraps each, tumbling and drifting down for
## 90 ticks) and three yellow streamers (`ef_tape`, 80 ticks). Run on ticks (60ths of a
## second) fed by `delta`; every number is the decomp's, in GX, kept relative to where it went
## off.

const GX := FieldCatalog.GX_TO_METERS
const K := GX / FieldCatalog.PIPELINE_SCALE
const S16 := MathUtil.S16

## `eClacker_ct`: the body launches 22.5° off vertical at 4.6 GX a tick.
const BODY_LAUNCH := 4.6
const BODY_PITCH := 0x1000 * S16
const BODY_GRAVITY := -0.125
const BODY_TICKS := 80
const BURST_AT := 76
## `eKamifubuki_*`.
const CONFETTI_COUNT := 20
const CONFETTI_TICKS := 90
const CONFETTI_SPEED := 7.0
const CONFETTI_SIZE := 0.003
const CONFETTI_VISUAL := &"ef_kamihubuki01_00"
## Prim colour then env colour per colour index (`rgb_tbl`): red, green, blue, white.
const CONFETTI_COLORS: Array[Color] = [
	Color(0.39, 0.078, 0.078), Color(0.608, 0.118, 0.118),
	Color(0.078, 0.39, 0.078), Color(0.118, 0.608, 0.118),
	Color(0.078, 0.078, 0.39), Color(0.118, 0.118, 0.608),
	Color(0.39, 0.39, 0.39), Color(0.608, 0.608, 0.608),
]
## `eTape_*`.
const TAPE_COUNT := 3
const TAPE_ANGLES: Array[int] = [0x071C, 0x58E3, 0xAAAB]
const TAPE_TICKS := 80
const TAPE_VISUAL := &"ef_tape01_01"
const TAPE_COLOR := Color(1.0, 1.0, 0.0)
## `eKigae_Light` glitter off the flying popper.
const GLITTER_VISUAL := &"ef_takurami01_kira"
const GLITTER_TICKS := 30
const GLITTER_ENV := Color(1.0, 1.0, 0.0)
const DRAG := 0.9486833

var _rng := RandomNumberGenerator.new()
var _origin: Vector3 = Vector3.ZERO
var _ticks: float = 0.0
var _step_acc: float = 0.0
var _timer: int = BODY_TICKS
var _body_pos: Vector3 = Vector3.ZERO
var _body_vel: Vector3 = Vector3.ZERO
var _burst_done: bool = false
## Each scrap: {pos, vel, pos2, vel2, phase, rate, axis, color, timer}.
var _confetti: Array[Dictionary] = []
## Each streamer: {pos, vel, yaw, timer}.
var _tapes: Array[Dictionary] = []
## Each glint: {card, at, age}.
var _glitter: Array[Dictionary] = []
var _confetti_mm: MultiMeshInstance3D
var _tape_mm: MultiMeshInstance3D


## Fire a popper at `at` (world metres), kicking up a puff of dust as it goes.
static func fire(host: Node, at: Vector3) -> PartyPopper:
	if host == null:
		return null
	var popper := PartyPopper.new()
	popper.name = "PartyPopper"
	host.add_child(popper)
	popper.global_transform = Transform3D.IDENTITY
	popper.start(at)
	FootstepEffects.party_puff(host, at)
	return popper


func start(at: Vector3) -> void:
	_rng.randomize()
	_origin = at
	_body_vel = Vector3(0.0, BODY_LAUNCH * cos(BODY_PITCH), BODY_LAUNCH * sin(BODY_PITCH))
	_confetti_mm = _make_multimesh(CONFETTI_VISUAL, CONFETTI_COUNT * 2, true)
	_tape_mm = _make_multimesh(TAPE_VISUAL, TAPE_COUNT, true)


func _process(delta: float) -> void:
	_step_acc += delta * DecompTime.TICK_HZ
	while _step_acc >= 1.0:
		_step_acc -= 1.0
		_tick()
	_draw()
	if _timer <= 0 and _confetti.is_empty() and _tapes.is_empty() and _glitter.is_empty():
		queue_free()


func _tick() -> void:
	_ticks += 1.0
	if _timer > 0:
		if _timer & 7 == 0 and _timer < 68:
			_glint()
		if _timer == BURST_AT and not _burst_done:
			_burst()
		if _timer < BURST_AT:
			_body_vel.y += BODY_GRAVITY
			_body_pos += _body_vel
			_body_vel *= DRAG
		_timer -= 1
	for c: Dictionary in _confetti:
		_tick_confetti(c)
	_confetti = _confetti.filter(func(c: Dictionary) -> bool: return int(c["timer"]) > 0)
	for t: Dictionary in _tapes:
		_tick_tape(t)
	_tapes = _tapes.filter(func(t: Dictionary) -> bool: return int(t["timer"]) > 0)
	for g: Dictionary in _glitter:
		g["age"] = float(g["age"]) + 1.0
		var at: Vector3 = g["at"]
		g["vel"] = (g["vel"] as Vector3) + Vector3(0.0, -0.025, 0.0)
		g["at"] = at + (g["vel"] as Vector3)
	for g: Dictionary in _glitter.duplicate():
		if float(g["age"]) >= GLITTER_TICKS:
			(g["card"] as Node3D).queue_free()
			_glitter.erase(g)


## `eKigae_Light` made by the popper every 8 ticks near it.
func _glint() -> void:
	var card: Node3D = EffectCards.make(self, GLITTER_VISUAL, Color.WHITE, GLITTER_ENV)
	if card == null:
		return
	var jitter := Vector3(_rng.randf_range(-100.0, 100.0), _rng.randf_range(-30.0, 30.0), _rng.randf_range(-100.0, 100.0))
	_glitter.append({"card": card, "at": _body_pos + jitter, "vel": Vector3.ZERO, "age": 0.0})


## `eClacker_Make_Effect`: three streamers and twenty scraps from where the popper is.
func _burst() -> void:
	_burst_done = true
	var tilt := Basis(Vector3.RIGHT, BODY_PITCH)
	for i: int in TAPE_COUNT:
		var a1: float = TAPE_ANGLES[i] * S16
		var spread: float = sin(deg_to_rad(20.0)) * 2.0
		var local := Vector3(spread * sin(a1), cos(deg_to_rad(20.0)) * 2.0, spread * cos(a1))
		_tapes.append({"pos": _body_pos, "vel": tilt * local, "yaw": a1, "timer": TAPE_TICKS})
	for i: int in CONFETTI_COUNT:
		var d: float = deg_to_rad(_rng.randf() * 35.0)
		var r: float = _rng.randf() * TAU
		var s: float = sin(d) * CONFETTI_SPEED
		var vel: Vector3 = tilt * Vector3(s * sin(r), cos(d) * CONFETTI_SPEED, s * cos(r))
		d = deg_to_rad(_rng.randf() * 40.0)
		r = _rng.randf() * TAU
		s = sin(d) * CONFETTI_SPEED
		var vel2: Vector3 = tilt * Vector3(s * sin(r), cos(d) * CONFETTI_SPEED, s * cos(r))
		var axis: Vector3 = Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU), EULER_ORDER_ZYX) * Vector3.BACK
		_confetti.append({
			"pos": _body_pos, "vel": vel, "pos2": _body_pos, "vel2": vel2,
			"phase": _rng.randf() * TAU,
			"rate": deg_to_rad(_rng.randf_range(0.0, 30.0)),
			"axis": axis, "color": i / 5,
			"timer": CONFETTI_TICKS - _rng.randi_range(0, 4),
		})


## `eKamifubuki_mv`: both scraps fall, slow, and sway.
func _tick_confetti(c: Dictionary) -> void:
	c["pos"] = (c["pos"] as Vector3) + (c["vel"] as Vector3)
	var vel: Vector3 = c["vel"]
	vel.y -= 0.1
	vel *= DRAG
	c["pos2"] = (c["pos2"] as Vector3) + (c["vel2"] as Vector3)
	var vel2: Vector3 = c["vel2"]
	vel2.y -= 0.1
	vel2 *= DRAG
	var sway: float = sin(float(c["phase"])) * 0.15
	vel.x += _rng.randf() * sway
	vel2.x += _rng.randf() * sway
	c["vel"] = vel
	c["vel2"] = vel2
	c["phase"] = float(c["phase"]) + float(c["rate"])
	c["timer"] = int(c["timer"]) - 1


## `eTape_mv`: a streamer coasts for the first six ticks, then flies on and slows.
func _tick_tape(t: Dictionary) -> void:
	if int(t["timer"]) < TAPE_TICKS - 6:
		var vel: Vector3 = t["vel"]
		vel.y -= 0.025
		t["pos"] = (t["pos"] as Vector3) + vel
		t["vel"] = vel * DRAG
	t["timer"] = int(t["timer"]) - 1


func _draw() -> void:
	var i: int = 0
	var mm: MultiMesh = _confetti_mm.multimesh if _confetti_mm != null else null
	if mm != null:
		for c: Dictionary in _confetti:
			var alpha: float = _adjust(float(c["timer"]), 0.0, 10.0, 0.0, 1.0)
			var rgb: Color = CONFETTI_COLORS[int(c["color"]) * 2]
			var env: Color = CONFETTI_COLORS[int(c["color"]) * 2 + 1]
			var tint := Color(minf(rgb.r + env.r, 1.0), minf(rgb.g + env.g, 1.0), minf(rgb.b + env.b, 1.0), alpha)
			var rot := Basis(c["axis"] as Vector3, float(c["phase"]))
			var size: Vector3 = Vector3.ONE * CONFETTI_SIZE * K
			for key: String in ["pos", "pos2"]:
				if i < mm.instance_count:
					mm.set_instance_transform(i, Transform3D(rot * Basis.from_scale(size), _origin + (c[key] as Vector3) * GX))
					mm.set_instance_color(i, tint)
					i += 1
		mm.visible_instance_count = i
	var j: int = 0
	var tm: MultiMesh = _tape_mm.multimesh if _tape_mm != null else null
	if tm != null:
		for t: Dictionary in _tapes:
			var timer: float = float(t["timer"])
			var sy: float
			var sz: float
			if timer > 68.0:
				sy = _adjust(timer, 68.0, 80.0, 1.0, 0.0) * 0.01
				sz = 0.0
			elif timer > 56.0:
				sy = 0.01
				sz = 0.0
			else:
				sy = _adjust(timer, 0.0, 56.0, 0.7, 1.0) * 0.01
				sz = _adjust(timer, 0.0, 56.0, 1.0, 0.0) * 0.01
			var alpha: float = 1.0 if timer > 14.0 else _adjust(timer, 0.0, 28.0, 0.0, 1.0)
			var basis := Basis(Vector3.RIGHT, BODY_PITCH) * Basis.from_euler(Vector3(deg_to_rad(20.0), float(t["yaw"]), 0.0), EULER_ORDER_ZYX)
			basis = basis * Basis.from_scale(Vector3(0.01, maxf(sy, 0.00001), maxf(sz, 0.00001)) * K)
			tm.set_instance_transform(j, Transform3D(basis, _origin + (t["pos"] as Vector3) * GX))
			tm.set_instance_color(j, Color(TAPE_COLOR, alpha))
			j += 1
		tm.visible_instance_count = j
	for g: Dictionary in _glitter:
		var age: float = float(g["age"])
		var timer: float = float(GLITTER_TICKS) - age
		var size: float = _adjust(timer, 20.0, 30.0, 0.009, 0.0) if timer > 20.0 else _adjust(timer, 0.0, 20.0, 0.0, 0.009)
		EffectCards.face(g["card"] as Node3D, _origin + (g["at"] as Vector3) * GX, size)


func _make_multimesh(visual: StringName, count: int, colored: bool) -> MultiMeshInstance3D:
	var paths: PackedStringArray = FieldCatalog.mesh_paths(visual)
	var packed: PackedScene = load(paths[0]) as PackedScene if not paths.is_empty() else null
	if packed == null:
		return null
	var root: Node = packed.instantiate()
	var mesh: Mesh = null
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		mesh = (n as MeshInstance3D).mesh
		break
	root.free()
	if mesh == null:
		return null
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colored
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.top_level = true
	add_child(inst)
	return inst


## `eEL_CalcAdjust`.
static func _adjust(now: float, start: float, end: float, a: float, b: float) -> float:
	if now <= start:
		return a
	if now >= end:
		return b
	return a + (now - start) * ((b - a) / (end - start))
