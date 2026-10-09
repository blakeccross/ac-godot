class_name NpcFeelMoods
extends RefCounted

## The feel effects that last as long as a villager's reaction clip (`aNPC_set_feel_effect` →
## `ef_pun`, `ef_siawase_hikari`, `ef_kangaeru`, `ef_takurami`, `ef_naku`, `ef_buruburu`,
## `ef_kaze`, `ef_otikomi`, `ef_neboke`). Each kind is an emitter run like the effect
## controller runs it: a `timer` counting down in the NORMAL state, then
## `set_continious_env_proc` re-arming it in CONTINUOUS until the clip ends
## (`effect_kill_proc`, `release`), when the profile's `n_frames` decide whether it vanishes
## at once, fades out over a FINISHED stretch or plays out its own life. Children (puffs,
## tears, petals, leaves, bubbles, sparkles) are `Part`s with their own life.
##
## Positions are GX. The host node is the glyph billboard at the head: +X screen right,
## +Y up, +Z toward the camera, so billboard offsets (`auto_matrix_xlu_offset_proc`,
## `Matrix_translate` after the billboard) are local as they are; world offsets
## (`sMath_RotateY` by the NPC's angle, `pos.y += …`) go through the host's basis.

const KINDS: Array[StringName] = [
	&"pun", &"siawase", &"kangaeru", &"takurami", &"naku", &"buruburu", &"kaze", &"otikomi", &"neboke",
]

const SHADER := preload("res://shaders/feel_effect.gdshader")
const REL_TEX := "res://assets/generated/textures/rel/%s.png"
const GX := FieldCatalog.GX_TO_METERS

enum State { NORMAL, CONTINUOUS, FINISHED }
## `eEC_PROFILE_c.n_frames` specials.
const IMMEDIATE_DEATH := -1
const IGNORE_DEATH := -2

## `ePunYuge_texture_anime_idx` / `ePunYuge_prim_f_table`, one row per two ticks.
const PUN_YUGE_TEX: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2),
	Vector2i(2, 2), Vector2i(2, 3), Vector2i(3, 3), Vector2i(3, 4), Vector2i(4, 4), Vector2i(4, 4),
	Vector2i(4, 4),
]
const PUN_YUGE_PRIM_F: Array[int] = [0, 0, 0, 127, 255, 127, 0, 127, 255, 127, 0, 0, 0]
const PUN_YUGE_SCALE_Y: Array[float] = [0.00595, 0.00833, 0.014161, 0.00833, 0.00595]


class Part:
	var node: Node3D
	var mats: Array[ShaderMaterial] = []
	var t: int = 0
	var life: int = 0
	var step: Callable
	## World GX offset from the head, and billboard GX offset on top of it.
	var pos: Vector3 = Vector3.ZERO
	var ofs: Vector3 = Vector3.ZERO
	var vel: Vector3 = Vector3.ZERO
	var acc: Vector3 = Vector3.ZERO
	var data: Dictionary = {}

	func set_param(name: StringName, value: Variant) -> void:
		for m: ShaderMaterial in mats:
			m.set_shader_parameter(name, value)


var kind: StringName = &""
var state: int = State.NORMAL
var timer: int = 0
## Ticks since the emitter started.
var t: int = 0
var alive: bool = true
var parts: Array[Part] = []
## Level SE (`sAdo_OngenPos`) the emitter holds this tick, or `&""`.
var ongen: StringName = &""
## One-shot SEs (`sAdo_OngenTrgStart`) raised since the host last drained them.
var trg_se: Array[StringName] = []

var _host: Node3D
## The feel joint (`aNPC_set_feel_eff`, joint 25) in the host's frame, metres.
var origin: Vector3 = Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _npc_yaw: float = 0.0
## `angle − (getCamera2AngleY + 0x8000)` as a u16 angle in degrees: 0 facing the camera,
## 90 turned to screen right.
var _view_diff: float = 0.0
var _death: int = IMMEDIATE_DEATH
var _cont: int = 0
var _body: Part = null
var _body2: Part = null
var _es: Dictionary = {}


## `npc_yaw`: the NPC's facing (forward `(sin, cos)`); `view_diff_deg` as `_view_diff`.
func _init(host: Node3D, p_kind: StringName, npc_yaw: float, view_diff_deg: float, seed_value: int = 0) -> void:
	_host = host
	kind = p_kind
	_npc_yaw = npc_yaw
	_view_diff = fposmod(view_diff_deg, 360.0)
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	match kind:
		&"pun":
			_start(24, 44, IMMEDIATE_DEATH)
		&"siawase":
			_start(22, 122, 72)
			_body = _part(&"ef_siawase01_00", Vector3.ZERO, Vector3(0.0, 0.0, -22.0), 0)
			_body.set_param(&"tex0", _rel(&"ef_siawase01_1"))
			_body.set_param(&"tex1", _rel(&"ef_siawase01_2_int_i4"))
			_two_tiles(_body, true, true, true, false, true, 3)
			_body.set_param(&"uv0_scale", Vector2(8.0, 8.0))
			_body.set_param(&"lod_frac", 50.0 / 255.0)
			_body.set_param(&"env_color", _c(255, 255, 0, 230))
		&"kangaeru":
			_start(36, 20, 7)
			var base := Vector3(0.0, 21.0, 0.0)
			_body = _part(&"ef_think_l", base, Vector3(0.0, -6.0, 30.0), 0)
			_body2 = _part(&"ef_think_s", base, Vector3(0.0, -6.0, 30.0), 0)
			for p: Part in [_body, _body2]:
				p.set_param(&"env_color", _c(90, 50, 160, 255))
			_es = {"count": 0, "big": 0, "small": 0}
		&"takurami":
			_start(54, 0, IGNORE_DEATH)
			var ahead := Vector3(sin(_npc_yaw), 0.0, cos(_npc_yaw)) * 6.9
			var side: int = 0 if _view_diff >= 180.0 else 1
			_body = _part(&"ef_takurami01_yoko", ahead + Vector3(0.0, -3.0, 10.0),
				Vector3(15.0 if side == 0 else -15.0, 0.0, 15.0), 0)
			_body.data["mirror"] = side == 1
			_body.set_param(&"env_color", _c(0, 0, 200, 255))
			_es = {"kira_at": ahead}
		&"naku":
			_start(32, 18, IMMEDIATE_DEATH)
			_es = {"at": Vector3(-sin(_npc_yaw), 0.0, -cos(_npc_yaw)) * 6.0, "count": 0}
		&"buruburu":
			_start(8, 8, IMMEDIATE_DEATH)
			_body = _part(&"ef_buruburu01_00", Vector3.ZERO, Vector3(0.0, -10.0, 0.0), 0)
			_body.set_param(&"i4_0", true)
			_body.set_param(&"mirror0", true)
			_body.set_param(&"prim_color", _c(255, 255, 255, 200))
			_body.set_param(&"env_color", _c(0, 100, 100, 255))
		&"kaze":
			_start(100, 0, IGNORE_DEATH)
			var side: int = 1 if _view_diff >= 90.0 and _view_diff <= 270.0 else 0
			_body = _part(&"ef_kaze01", Vector3.ZERO, Vector3(0.0, -3.0, 24.0), 0)
			_body.data["mirror"] = side == 1
			_body.node.rotation.z = deg_to_rad(11.25 if side == 1 else -11.25)
			_body.set_param(&"tex0", _rel(&"ef_kaze01_0_int_i4"))
			_body.set_param(&"tex1", _rel(&"ef_kaze01_1_int_i4"))
			_two_tiles(_body, true, true, true, true, false, 2)
			_body.set_param(&"uv1_scale", Vector2(0.125, 1.0))
			_body.set_param(&"lod_frac", 1.0)
			_body.set_param(&"env_color", _c(0, 255, 255, 255))
			_es = {"side": side}
			trg_se.append(&"kaze")
		&"otikomi":
			_start(22, 100, 10)
			var at := Vector3(0.0, 17.0, 0.0)
			_body = _part(&"ef_doyon01_00", at + Vector3(0.0, 4.0, 0.0), Vector3(0.0, 0.0, 21.0), 0)
			_body.set_param(&"env_color", _c(100, 100, 255, 255))
			_body2 = _part(&"ef_otikomi_us2", at, Vector3(0.0, 0.0, 19.0), 0)
			_body2.set_param(&"tex0", _rel(&"ef_otikomi_us2_int_i4"))
			_body2.set_param(&"tex1", _rel(&"ef_otikomi_us1_int_i4"))
			_two_tiles(_body2, true, true, true, true, false, 2)
			_body2.set_param(&"uv1_scale", Vector2(0.5, 0.5))
			_body2.set_param(&"lod_frac", 1.0)
			_body2.set_param(&"env_color", _c(100, 100, 255, 255))
			_es = {"wobble": 0.4, "speed": 10000.0, "phase": 0}
		&"neboke":
			_start(112, 120, IMMEDIATE_DEATH)
		_:
			alive = false


## The clip has ended (`effect_kill_proc`): vanish, fade out, or play on.
func release() -> void:
	if not alive or state == State.FINISHED:
		return
	if _death == IMMEDIATE_DEATH:
		_kill_body()
		alive = false
	elif _death > 0:
		state = State.FINISHED
		timer = _death


## One 60 Hz tick. False once the emitter and all its parts are gone.
func tick() -> bool:
	ongen = &""
	if alive:
		_emitter_step()
		timer -= 1
		if timer <= 0 and alive:
			_kill_body()
			alive = false
	for p: Part in parts.duplicate():
		if p == _body or p == _body2:
			continue
		p.step.call(p)
		p.t += 1
		if p.t >= p.life:
			_free(p)
		else:
			_place(p)
	if _body != null:
		_place(_body)
	if _body2 != null:
		_place(_body2)
	t += 1
	return alive or not parts.is_empty()


func clear() -> void:
	for p: Part in parts.duplicate():
		_free(p)
	_body = null
	_body2 = null
	alive = false


# ---- emitters ------------------------------------------------------

func _start(normal: int, cont: int, death: int) -> void:
	timer = normal
	_cont = cont
	_death = death


## `eEL_SetContiniousEnv`.
func _continuous() -> void:
	if _cont <= 0:
		return
	if (state == State.NORMAL or state == State.CONTINUOUS) and timer <= 1:
		state = State.CONTINUOUS
		timer = _cont


func _emitter_step() -> void:
	match kind:
		&"pun":
			_continuous()
			if state == State.CONTINUOUS:
				var left: int = 44 - timer
				if left == 8:
					_spawn_pun_yuge()
					_spawn_pun_sekimen()
		&"siawase":
			ongen = &"lev_e"
			_continuous()
			var alpha: float = 150.0
			var s: float = 0.015
			if state == State.NORMAL:
				s = _adjust(22 - timer, 0, 21, 0.0, 0.015)
			elif state == State.FINISHED:
				alpha = _adjust(72 - timer, 0, 72, 150.0, 0.0)
			_scale(_body, s, s, s)
			_body.set_param(&"prim_color", _c(255, 255, 200, int(alpha)))
			## `Evw_Anime` SCROLL2 {1, −4}: passed to the scroll as (1, 4), ÷ 8 texels a tick.
			_body.set_param(&"scroll0", Vector2(1.0, 4.0) * float(t) / 8.0)
			## `eSSHN_mv`: a petal every fourth tick while the clip plays.
			if state != State.FINISHED and (timer & 3) == 0:
				_spawn_petal()
		&"kangaeru":
			_continuous()
			_tick_think()
		&"takurami":
			var e: int = 54 - timer
			if e == 0:
				trg_se.append(&"117")
			if e == 10:
				_spawn_kira(_es["kira_at"])
			_scale(_body, _adjust(e, 0, 8, 0.0, 0.017), 0.02, 0.017)
			_body.set_param(&"prim_color", _c(0, 0, 0, int(_adjust(e, 46, 54, 200.0, 0.0))))
		&"naku":
			_continuous()
			ongen = &"lev_2e"
			if (timer & 1) == 1:
				_spawn_tear(int(_es["count"]) & 1)
				_es["count"] = int(_es["count"]) + 1
		&"buruburu":
			_continuous()
			ongen = &"lev_2d"
			var idx: int = (timer >> 1) & 1
			_scale(_body, [0.015, 0.016][idx], 0.01, [0.01, 0.011][idx])
			_body.set_param(&"tex0", _rel(StringName("ef_buruburu01_%d_int_i4" % idx)))
		&"kaze":
			var e: int = 100 - timer
			if timer == 64:
				_spawn_leaf(int(_es["side"]))
			var a: float = 150.0
			if e <= 9:
				a = _adjust(e, 0, 18, 0.0, 150.0)
			elif e >= 80:
				a = _adjust(e, 80, 98, 150.0, 0.0)
			_scale(_body, 0.063, 0.021, 0.021)
			_body.set_param(&"prim_color", _c(255, 255, 255, int(a)))
			_body.set_param(&"scroll1", Vector2(3.0, 2.0) * float(t) / 8.0)
		&"otikomi":
			_tick_gloom()
		&"neboke":
			_continuous()
			if state == State.NORMAL:
				var e: int = 112 - timer
				if e == 16:
					_spawn_yawn(0)
				elif e == 44:
					_spawn_yawn(1)
			elif state == State.CONTINUOUS:
				var e2: int = 120 - timer
				if e2 == 46 or e2 == 74:
					_spawn_zzz()


## `eKG_mv` / `eKG_dw`: the big bubble nods 2.5° and the small one −3.75° a tick for ten
## ticks of every 25, both reset when the big one comes round.
func _tick_think() -> void:
	var before: int = MLib.s16_signed(int(_es["big"]))
	if int(_es["count"]) < 10:
		_es["big"] = MLib.s16_signed(int(_es["big"]) + 455)
		_es["small"] = MLib.s16_signed(int(_es["small"]) - 682)
	if int(_es["big"]) >= 0 and before < 0:
		_es["big"] = 0
		_es["small"] = 0
	_es["count"] = int(_es["count"]) + 1
	if int(_es["count"]) >= 25:
		_es["count"] = 0
	var alpha: int = 255
	if state == State.FINISHED:
		alpha = int(_adjust(7 - timer, 0, 6, 255.0, 0.0))
	else:
		ongen = &"lev_58"
	var s: float = 0.008
	var sz: float = 0.8
	if state == State.NORMAL:
		s = _adjust(36 - timer, 0, 7, 0.0, 0.008)
		sz = 1.0
	_scale(_body, s, s, sz)
	_scale(_body2, s, s, sz)
	_body.data["shift"] = Vector3(-475.0 * s, 950.0 * s, 0.0)
	_body2.data["shift"] = Vector3(475.0 * s, 0.0, 0.0)
	_body.node.rotation.z = MLib.s16_to_rad(int(_es["big"]))
	_body2.node.rotation.z = MLib.s16_to_rad(int(_es["small"]))
	for p: Part in [_body, _body2]:
		p.set_param(&"prim_color", _c(255, 255, 255, alpha))


## `eOMN_mv` / `eOMN_dw`: a dark cloud squashing and stretching ever more gently over
## falling lines of gloom.
func _tick_gloom() -> void:
	var phase: int = int(_es["phase"]) + int(float(_es["speed"]))
	_es["phase"] = phase
	var w: float = float(_es["wobble"]) * sin(MLib.s16_to_rad(phase))
	_es["wobble"] = AcreCamera.add_calc(float(_es["wobble"]), 0.025, 0.022, 0.1, 0.001)
	_es["speed"] = AcreCamera.add_calc(float(_es["speed"]), 2000.0, 0.022, 6000.0, 0.01)
	_continuous()
	var alpha: float = 255.0
	var alpha2: float = 100.0
	var lines_y: float = 0.0135
	if state == State.NORMAL:
		lines_y = _adjust(22 - timer, 10, 21, 0.0, 0.0135)
		ongen = &"lev_59"
	elif state == State.CONTINUOUS:
		ongen = &"lev_59"
	else:
		alpha = _adjust(10 - timer, 0, 9, 255.0, 0.0)
		alpha2 = _adjust(10 - timer, 0, 9, 100.0, 0.0)
	_scale(_body, 0.01 * (1.0 + w) * 1.3, 0.01 * (1.0 - w), 0.01)
	_body.set_param(&"prim_color", _c(40, 30, 40, int(alpha)))
	_scale(_body2, 0.015, lines_y, 0.01)
	_body2.set_param(&"prim_color", _c(0, 255, 255, int(alpha2)))
	_body2.set_param(&"scroll1", Vector2(0.0, 25.0) * float(t) / 8.0)


# ---- children ------------------------------------------------------

## `ePunYuge`: a puff of steam over the head, swelling as its frames cross-fade.
func _spawn_pun_yuge() -> void:
	var p := _part(&"ef_pun01_00", Vector3(0.0, 23.0, 0.0), Vector3(0.0, 0.0, 10.0), 26)
	_two_tiles(p, true, true, true, true, true, 1)
	p.set_param(&"color_t0", true)
	p.step = func(q: Part) -> void:
		var e: int = q.t
		if e < 4:
			q.ofs.y += 1.5
		var frame: int = clampi(e >> 1, 0, 12)
		q.set_param(&"tex0", _rel(StringName("ef_pun01_%d_int_i4" % PUN_YUGE_TEX[frame].x)))
		q.set_param(&"tex1", _rel(StringName("ef_pun01_%d_int_i4" % PUN_YUGE_TEX[frame].y)))
		q.set_param(&"lod_frac", float(PUN_YUGE_PRIM_F[frame]) / 255.0)
		var gb: float = _adjust(e, 0, 8, 200.0, 255.0)
		q.set_param(&"prim_color", _c(255, int(gb), int(gb), int(_adjust(e, 12, 26, 255.0, 0.0))))
		var env_gb: int = int(_adjust(e, 0, 8, 0.0, 255.0))
		q.set_param(&"env_color", _c(255, env_gb, env_gb, 255))
		if frame <= 4:
			_scale(q, 0.00595, PUN_YUGE_SCALE_Y[frame], 0.00595)
		else:
			var s: float = _adjust(e, 10, 26, 0.00595, 0.0119)
			_scale(q, s, s, s)
	trg_se.append(&"pun_yuge")


## `ePunRed`: the red flush across the face.
func _spawn_pun_sekimen() -> void:
	var p := _part(&"ef_pun01_01", Vector3.ZERO, Vector3(0.0, -2.0, 25.0), 16)
	p.set_param(&"tex0", _rel(&"ef_pun01_5_int_i4"))
	p.set_param(&"i4_0", true)
	p.set_param(&"env_color", _c(255, 100, 100, 255))
	p.step = func(q: Part) -> void:
		var s: float = _adjust(q.t, 0, 16, 0.0105, 0.0189)
		_scale(q, s, s, s)
		q.set_param(&"prim_color", _c(255, 0, 0, int(_adjust(q.t, 8, 16, 150.0, 0.0))))


## `eSSHNC`: a pink or yellow petal drifting out, then floating up and fading.
func _spawn_petal() -> void:
	var p := _part(&"ef_siawase01_01", Vector3(0.0, -15.0, 0.0), Vector3.ZERO, 92)
	var a: float = deg_to_rad(_rng.randf() * 180.0 - 90.0)
	p.vel = Vector3(-0.4 * sin(a), 0.4 * cos(a), 0.0)
	p.data["spin"] = 0.0
	p.data["turn"] = deg_to_rad(6.96 if p.vel.x > 0.0 else -6.96)
	var yellow: bool = (_rng.randi_range(0, 9) & 1) == 1
	p.data["prim"] = Vector3(255, 255, 0) if yellow else Vector3(255, 255, 255)
	p.set_param(&"env_color", _c(255, 0, 0, 255) if yellow else _c(255, 0, 255, 255))
	p.step = func(q: Part) -> void:
		var e: int = q.t
		q.acc.y = 0.01 if e >= 58 else _adjust(e, 40, 58, 0.0, 0.01)
		q.vel += q.acc
		q.pos += q.vel
		q.data["spin"] = float(q.data["spin"]) + float(q.data["turn"])
		q.node.rotation.z = float(q.data["spin"])
		var s: float = _adjust(e, 40, 58, 0.0, 0.005)
		_scale(q, s, s, s)
		var rgb: Vector3 = q.data["prim"]
		var alpha: float = _adjust(e, 66, 92, 255.0, 0.0) if e >= 66 else 255.0
		q.set_param(&"prim_color", _c(int(rgb.x), int(rgb.y), int(rgb.z), int(alpha)))


## `eTMK`: the sparkle at the corner of a scheming grin.
func _spawn_kira(at: Vector3) -> void:
	var d: float = _view_diff
	var off := Vector3(7.0, -8.0, 14.0)
	if d <= 60.0:
		off = Vector3(6.0, -8.0, 14.0)
	elif d <= 120.005:
		off = Vector3(13.0, -8.0, 14.0)
	elif d <= 180.0:
		off = Vector3(13.0, -3.0, -14.0)
	elif d <= 240.0:
		off = Vector3(-13.0, -3.0, -14.0)
	elif d <= 300.005:
		off = Vector3(-13.0, -8.0, 14.0)
	var p := _part(&"ef_takurami01_kira", at, off, 30)
	p.set_param(&"prim_color", _c(255, 255, 255, 255))
	p.set_param(&"env_color", _c(255, 255, 0, 255))
	p.step = func(q: Part) -> void:
		var s: float = _adjust(q.t, 0, 10, 0.0, 0.009) if q.t < 10 else _adjust(q.t, 11, 29, 0.009, 0.0)
		_scale(q, s, s, s)


## `eNamida`: a tear flung out to one side, arcing down.
func _spawn_tear(side: int) -> void:
	var p := _part(&"ef_namida01", _es["at"], Vector3.ZERO, 30)
	var v := Vector3(0.0, 1.85, 0.0)
	v = _rot_z(v, deg_to_rad(_rng.randf() * 40.0 - 20.0))
	v = _rot_x(v, deg_to_rad(_rng.randf() * 40.0 - 20.0))
	v = _rot_z(v, deg_to_rad(55.0 if side == 0 else -55.0))
	p.vel = v
	p.acc = Vector3(0.0, -0.0675, 0.0)
	p.data["local"] = Vector3(0.0, 0.0, 10.0)
	p.data["base"] = p.pos
	p.set_param(&"prim_color", _c(0, 255, 255, 155))
	p.set_param(&"env_color", _c(255, 255, 255, 255))
	p.step = func(q: Part) -> void:
		q.vel += q.acc
		var local: Vector3 = Vector3(q.data["local"]) + q.vel
		q.data["local"] = local
		q.pos = Vector3(q.data["base"]) + _rot_y(local, _npc_yaw)
		var s: float = _adjust(q.t, 0, 18, 0.0, 0.0027) if q.t < 20 else _adjust(q.t, 20, 30, 0.0027, 0.0)
		_scale(q, s, s, s)


## `eKZH`: a leaf caught in the gust, tumbling across.
func _spawn_leaf(side: int) -> void:
	var p := _part(&"ef_kaze01_happa", Vector3(0.0, -10.0, 10.0),
		Vector3(40.0 if side == 1 else -40.0, 14.0, 15.0), 60)
	p.set_param(&"prim_color", _c(200, 150, 0, 255))
	p.set_param(&"env_color", _c(100, 0, 0, 255))
	var dir: float = -1.0 if side == 1 else 1.0
	p.step = func(q: Part) -> void:
		var e: int = q.t
		var spin: float = 0.0
		if e < 20:
			q.vel += Vector3(dir * 0.095, -0.02875, 0.0)
		elif e < 40:
			spin = _adjust(e, 20, 39, 0.0, 360.0)
		else:
			spin = _adjust(e, 40, 59, 360.0, 450.0)
			q.vel += Vector3(dir * 0.095, -0.02875, 0.0)
		q.ofs += q.vel
		q.node.rotation.z = deg_to_rad(spin) * (-1.0 if side == 1 else 1.0)
		var s: float = 0.0048
		if e <= 10:
			s = _adjust(e, 0, 10, 0.0, 0.0048)
		elif e > 50:
			s = _adjust(e, 52, 60, 0.0048, 0.0)
		_scale(q, s, s, s)


## `eNeboke_Akubi`: a yawn bubble wobbling up from the mouth.
func _spawn_yawn(size: int) -> void:
	var jitter := Vector3(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 3.0))
	var p := _part(&"ef_neboke_awa01", _rot_y(Vector3(0.0, 7.0, 13.5), _npc_yaw) + jitter, Vector3.ZERO, 80)
	var v := _rot_z(Vector3(0.0, 0.15, 0.0), deg_to_rad(_rng.randf() * 30.0 - 15.0))
	p.vel = _rot_y(_rot_x(v, deg_to_rad(20.0)), _npc_yaw)
	p.acc = Vector3(0.0, 0.003425, 0.0)
	p.data["phase"] = _rng.randf() * TAU
	p.data["base"] = [0.005, 0.0015][size]
	p.set_param(&"alpha_from_env", true)
	p.set_param(&"prim_color", _c(255, 255, 255, 255))
	p.set_param(&"env_color", _c(255, 255, 150, 255))
	p.step = func(q: Part) -> void:
		q.vel += q.acc
		q.pos += q.vel
		q.data["phase"] = float(q.data["phase"]) + deg_to_rad(11.25)
		var s: float = _adjust(q.t, 0, 4, 0.0, float(q.data["base"]))
		if q.t == 79:
			s *= 1.2
		var ph: float = q.data["phase"]
		_scale(q, s * (sin(ph) * 0.2 + 1.0), s * (cos(ph) * 0.2 + 1.0), s)


## `eSleep`: a "z" rising beside the head, swaying and leaning into its path.
func _spawn_zzz() -> void:
	var side: float = 5.0 if fposmod(rad_to_deg(_npc_yaw), 360.0) < 180.0 else -5.0
	var p := _part(&"ef_sleep01", _rot_y(Vector3(side, 10.0, 13.0), _npc_yaw), Vector3.ZERO, 64)
	p.vel = Vector3(0.0, 0.18, 0.0)
	p.acc = Vector3(0.0, 0.008, 0.0)
	p.data["sway"] = 0.0
	p.data["wobble"] = 0.0
	p.data["drawn"] = p.pos
	p.data["anchor"] = p.pos
	p.set_param(&"env_color", _c(120, 50, 255, 255))
	p.step = func(q: Part) -> void:
		q.data["wobble"] = float(q.data["wobble"]) + deg_to_rad(11.25)
		q.data["sway"] = float(q.data["sway"]) + deg_to_rad(6.33)
		q.vel += q.acc
		q.data["anchor"] = Vector3(q.data["anchor"]) + q.vel
		var s: float = 0.0036
		var alpha: int = 200
		if q.t < 62:
			s = _adjust(q.t, 0, 40, 0.0, 0.003)
			alpha = 255
		var wob: float = q.data["wobble"]
		var sx: float = s * (sin(wob) * 0.3 + 1.0) * (cos(wob) * 0.3 + 1.0)
		_scale(q, sx, s, s)
		var at: Vector3 = Vector3(q.data["anchor"]) + Vector3(sin(float(q.data["sway"])) * 2.7, 0.0, 0.0)
		var prev: Vector3 = q.data["drawn"]
		## `atans_table(dy, dx)` is the angle of (dx, dy) from +Y.
		q.node.rotation.z = -(atan2(at.x - prev.x, at.y - prev.y) + PI)
		q.data["drawn"] = at
		q.pos = at
		q.set_param(&"prim_color", _c(255, 255, 255, alpha))


# ---- parts ---------------------------------------------------------

func _part(visual: StringName, pos: Vector3, ofs: Vector3, life: int) -> Part:
	var p := Part.new()
	p.life = life
	p.pos = pos
	p.ofs = ofs
	p.step = func(_q: Part) -> void: pass
	p.node = Node3D.new()
	p.node.name = String(visual)
	var paths: PackedStringArray = FieldCatalog.mesh_paths(visual)
	var packed: PackedScene = load(paths[0]) as PackedScene if not paths.is_empty() else null
	if packed != null:
		var inst: Node = packed.instantiate()
		p.node.add_child(inst)
		_shade(inst, p)
	if _host != null:
		_host.add_child(p.node)
	p.node.scale = Vector3.ZERO
	parts.append(p)
	_place(p)
	return p


func _shade(node: Node, p: Part) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i: int in mi.mesh.get_surface_count():
				var std := mi.get_active_material(i) as StandardMaterial3D
				var sh := ShaderMaterial.new()
				sh.shader = SHADER
				sh.render_priority = 3
				if std != null:
					sh.set_shader_parameter(&"tex0", std.albedo_texture)
					sh.set_shader_parameter(&"tex1", VisualWaterMaterials._layer1_texture(std))
				## The baked atlases cover 0..1; mirroring there is the identity and keeps
				## the edge texels from wrapping.
				sh.set_shader_parameter(&"mirror0", true)
				mi.set_surface_override_material(i, sh)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				p.mats.append(sh)
	for child: Node in node.get_children():
		_shade(child, p)


func _two_tiles(p: Part, on: bool, i4_0: bool, i4_1: bool, mirror0: bool, mirror1: bool, alpha_mode: int) -> void:
	p.set_param(&"two_tiles", on)
	p.set_param(&"i4_0", i4_0)
	p.set_param(&"i4_1", i4_1)
	p.set_param(&"mirror0", mirror0)
	p.set_param(&"mirror1", mirror1)
	p.set_param(&"alpha_mode", alpha_mode)


## GX matrix scale → node scale (the GLBs carry the pipeline's scale already).
func _scale(p: Part, x: float, y: float, z: float) -> void:
	var k: float = GX / FieldCatalog.PIPELINE_SCALE
	var mx: float = -1.0 if bool(p.data.get("mirror", false)) else 1.0
	p.node.scale = Vector3(maxf(x, 0.00001) * k * mx, maxf(y, 0.00001) * k, maxf(z, 0.00001) * k)


func _place(p: Part) -> void:
	if p.node == null or _host == null or not _host.is_inside_tree():
		return
	var to_local: Basis = _host.global_basis.orthonormalized().inverse()
	var shift: Vector3 = p.data.get("shift", Vector3.ZERO)
	p.node.position = origin + (to_local * p.pos + p.ofs + shift) * GX


func _free(p: Part) -> void:
	parts.erase(p)
	if p.node != null and is_instance_valid(p.node):
		p.node.queue_free()
	p.node = null


func _kill_body() -> void:
	for p: Part in [_body, _body2]:
		if p != null:
			_free(p)
	_body = null
	_body2 = null


func _rel(name: StringName) -> Texture2D:
	var path: String = REL_TEX % name
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


# ---- decomp math ---------------------------------------------------

## `eEL_CalcAdjust`.
static func _adjust(now: int, start: int, end: int, from: float, to: float) -> float:
	if start == end or now <= start:
		return from
	if now >= end:
		return to
	return from + float(now - start) * ((to - from) / float(end - start))


static func _c(r: int, g: int, b: int, a: int) -> Color:
	return Color(r / 255.0, g / 255.0, b / 255.0, clampi(a, 0, 255) / 255.0)


static func _rot_x(v: Vector3, a: float) -> Vector3:
	return Vector3(v.x, v.y * cos(a) - v.z * sin(a), v.y * sin(a) + v.z * cos(a))


## `sMath_RotateY`: +Z turns to the NPC's facing `(sin, cos)`.
static func _rot_y(v: Vector3, a: float) -> Vector3:
	return Vector3(v.x * cos(a) + v.z * sin(a), v.y, -v.x * sin(a) + v.z * cos(a))


static func _rot_z(v: Vector3, a: float) -> Vector3:
	return Vector3(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a), v.z)
