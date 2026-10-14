class_name NpcFeelGlyphs
extends Node3D

## Billboard feel glyphs above an NPC (`eEC_EFFECT_WARAU` / `SHOCK` / `HA` / `HIRAMEKI_*`).
## Pipeline cards live under `assets/generated/effects/`; missing packs are a no-op.


const WARAU_VISUALS: Array[StringName] = [
	&"ef_warau01_00",
	&"ef_warau01_01",
	&"ef_warau01_02",
	&"ef_warau01_03",
]
## `eWU_ct` scale 0.0045 on authored verts (pipeline GLB already × `PIPELINE_SCALE`).
const WARAU_MATRIX_SCALE := 0.0045
const WARAU_LIFE_FRAMES := 24
## Continuous laugh while smile manpu holds — a couple of glyph cycles.
const WARAU_CYCLES := 2

const SHOCK_VISUAL := &"ef_shock01_00"
const SHOCK_MATRIX_SCALE := 0.019
const SHOCK_LIFE_FRAMES := 14
const SHOCK_Y_GX := 4.0

const HA_VISUAL := &"ef_ha01_00"
const HA_MATRIX_SCALE := 0.0067
const HA_LIFE_FRAMES := 56
const HA_Y_GX := 12.0
const HA_X_GX := 16.0

## Lightbulb bolt (`ef_hirameki_den`) + brief glow (`ef_hirameki_hikari`).
const HIRAMEKI_DEN_VISUAL := &"ef_hirameki01_den"
const HIRAMEKI_HIKARI_VISUAL := &"ef_hirameki01_hikari"
const HIRAMEKI_DEN_MATRIX_SCALE := 0.007
const HIRAMEKI_HIKARI_MATRIX_SCALE := 0.014
const HIRAMEKI_LIFE_FRAMES := 72
const HIRAMEKI_HIKARI_FRAMES := 12
const HIRAMEKI_Y_GX := 24.0

## `eGM_*` / `eKT_*`: the question and exclamation marks pop in through this squash table
## (two ticks a row, rows past the sixth 1:1), hold to tick 64 and fade by 72.
const POP_SCALE: Array[Vector2] = [
	Vector2(0.5, 0.5), Vector2(0.5, 1.2), Vector2(0.5, 2.0), Vector2(1.2, 1.4), Vector2(2.0, 0.7),
	Vector2(1.5, 0.8),
]
const POP_MATRIX_SCALE := 0.008
const POP_LIFE := 72
const POP_FADE_FROM := 64
const POP_HOLD := 50
const GIMONHU_VISUAL := &"ef_gimonhu01_00"
const KANTANHU_VISUAL := &"ef_kantanhu01_00"
## `eGM_init` / `eKT_init` offsets (GX, NPC frame).
const GIMONHU_AT := Vector3(0.0, 15.0, 7.0)
const KANTANHU_AT := Vector3(0.0, 15.0, -3.0)
## `eAS2_*`: four sweat cards, a new one every four ticks, while the clip runs.
const ASE_VISUALS: Array[StringName] = [&"ef_ase02_00", &"ef_ase02_01", &"ef_ase02_02", &"ef_ase02_03"]
const ASE_MATRIX_SCALE := 0.006
const ASE_LIFE := 52
## `eMK_*`: anger vein beside the head (side picked from the camera), green and red
## draining over 20 ticks, fading out by 41.
const MUKA_VISUAL := &"ef_muka01_00"
const MUKA_MATRIX_SCALE := 0.0075
const MUKA_LIFE := 40
const MUKA_AT := Vector3(10.0, 9.0, 23.0)
## `eLL2_*`: heart that rises (1.0 → 0.1 GX a tick over 28 ticks), grows over 30 and
## wobbles x/y out of phase, fading 96 → 112.
const HEART_VISUAL := &"ef_lovelove02_00"
const HEART_LIFE := 112
const HEART_Y_GX := 16.0
const HEART_SPIN := 10.55
## `eSN_*`: heartbreak card set (0,10,7) in front of the NPC, rising 1.6 GX a tick for 8
## ticks; whole → cracking (tick 60) → split, wobbling like the heart, fading 108 → 128.
const SITUREN_VISUALS: Array[StringName] = [&"ef_situren01_00", &"ef_situren01_01", &"ef_situren01_02"]
const SITUREN_LIFE := 128
const SITUREN_AT := Vector3(0.0, 10.0, 7.0)
const SITUREN_SPIN := 30.94

## Set by the owner before `play`: the NPC is turned toward the camera (`eMK_ct` side).
var faces_camera: bool = true
## The NPC's yaw (radians, Godot +Z forward) for effects placed in front of it (`eSN_init`).
var npc_yaw: float = 0.0
var _kind: StringName = &""
var _frame: float = 0.0
var _cycle: int = 0
var _mesh_host: Node3D
var _glow_host: Node3D
var _active_visual: StringName = &""
var _head_lift: float = 1.15
## The clip-long feel effects (`NpcFeelMoods.KINDS`), stepped at 60 Hz.
var _moods: NpcFeelMoods = null
const MOOD_MAX_TICKS := 600
var _mood_steps := FrameStepper.new()
var _ongen_player: AudioStreamPlayer
## The skeleton bone the clip-long effects start from (`aNPC_set_feel_eff` runs on the
## last joint, at the top of the head). Unset, they start at the glyph point.
var feel_skeleton: Skeleton3D = null
var feel_bone: int = -1
## Mood pose effects (`NpcManpu.MOOD_POSE_EFFECTS`), independent of the reaction glyphs.
var _pose: String = ""
var _pose_counter: float = 0.0
var _pose_steps := FrameStepper.new()
var _ambient: NpcFeelMoods = null


func _ready() -> void:
	_mesh_host = Node3D.new()
	_mesh_host.name = "GlyphMesh"
	add_child(_mesh_host)
	_glow_host = Node3D.new()
	_glow_host.name = "GlyphGlow"
	add_child(_glow_host)


func _process(delta: float) -> void:
	if _kind != &"" or _ambient != null or NpcManpu.MOOD_POSE_EFFECTS.has(_pose):
		_billboard()
	_tick_pose(delta)
	if _kind == &"":
		return
	if _moods != null:
		_tick_moods(delta)
		return
	_frame += delta * DecompTime.TICK_HZ
	match _kind:
		&"warau":
			_tick_warau()
		&"shock":
			_tick_shock()
		&"ha":
			_tick_ha()
		&"hirameki":
			_tick_hirameki()
		&"gimonhu", &"kantanhu":
			_tick_pop()
		&"ase":
			_tick_ase()
		&"muka":
			_tick_muka()
		&"lovelove2":
			_tick_heart()
		&"situren":
			_tick_situren()
		_:
			clear()


## Spawn the feel glyph that matches a manpu clip (`NpcManpu.feel_for`).
func play(kind: StringName) -> void:
	clear()
	if kind == &"":
		return
	_kind = kind
	_frame = 0.0
	_cycle = 0
	if NpcFeelMoods.KINDS.has(kind):
		_billboard()
		_moods = NpcFeelMoods.new(self, kind, npc_yaw, view_diff_deg())
		_mood_steps = FrameStepper.new()
		_tick_moods(0.0)
		return
	match kind:
		&"warau":
			_show_warau_frame(0)
		&"shock":
			_set_visual(SHOCK_VISUAL, SHOCK_MATRIX_SCALE)
			_mesh_host.position = Vector3(0.0, SHOCK_Y_GX * FieldCatalog.GX_TO_METERS, 0.0)
			_tint_mesh(Color(1.0, 1.0, 0.0))
		&"ha":
			_set_visual(HA_VISUAL, HA_MATRIX_SCALE)
			_mesh_host.position = Vector3(
				HA_X_GX * FieldCatalog.GX_TO_METERS,
				HA_Y_GX * FieldCatalog.GX_TO_METERS,
				0.0
			)
		&"hirameki":
			_set_visual(HIRAMEKI_DEN_VISUAL, HIRAMEKI_DEN_MATRIX_SCALE)
			_mesh_host.position = Vector3(0.0, HIRAMEKI_Y_GX * FieldCatalog.GX_TO_METERS, 0.0)
			_tint_mesh(Color(1.0, 1.0, 0.39))
			_set_glow_visual(HIRAMEKI_HIKARI_VISUAL, HIRAMEKI_HIKARI_MATRIX_SCALE)
			_glow_host.position = _mesh_host.position
		&"gimonhu", &"kantanhu":
			var question: bool = kind == &"gimonhu"
			_set_visual(GIMONHU_VISUAL if question else KANTANHU_VISUAL, POP_MATRIX_SCALE)
			_mesh_host.position = (GIMONHU_AT if question else KANTANHU_AT) * FieldCatalog.GX_TO_METERS
			Audio.play_se(&"2f" if question else &"14b", self)
			_tick_pop()
		&"ase":
			_set_visual(ASE_VISUALS[0], ASE_MATRIX_SCALE)
		&"muka":
			_set_visual(MUKA_VISUAL, MUKA_MATRIX_SCALE)
			_mesh_host.position = MUKA_AT * FieldCatalog.GX_TO_METERS
			Audio.play_se(&"137", self)
			_tick_muka()
		&"lovelove2":
			_set_visual(HEART_VISUAL, 0.003)
			_mesh_host.position = Vector3(0.0, HEART_Y_GX * FieldCatalog.GX_TO_METERS, 0.0)
			Audio.play_se(&"118", self)
			_tick_heart()
		&"situren":
			_set_visual(SITUREN_VISUALS[0], 0.0)
			Audio.play_se(&"13d", self)
			_tick_situren()
		_:
			_kind = &""


func play_for_manpu(manpu_name: String) -> void:
	play(NpcManpu.feel_for(manpu_name))


## The mood pose now playing (`aNPC_Animation_init` → `draw.feel_effect`): its effects fire
## on the pose's own counter.
func set_pose(clip: String) -> void:
	var key: String = clip.strip_edges().to_lower()
	if key == _pose:
		return
	_pose = key
	_pose_counter = 0.0


func _tick_pose(delta: float) -> void:
	var data: Array = NpcManpu.MOOD_POSE_EFFECTS.get(_pose, [])
	if data.is_empty() and _ambient == null:
		return
	if _ambient == null:
		_ambient = NpcFeelMoods.new(self, &"ambient", npc_yaw, view_diff_deg())
	_ambient.origin = _feel_origin()
	_pose_steps.add(delta)
	while _pose_steps.next():
		if not data.is_empty():
			var top: float = float(data[1])
			for at: Variant in data[2]:
				var gap: float = float(at) - _pose_counter
				if gap >= 0.0 and gap < 0.5:
					_ambient._npc_yaw = npc_yaw
					_ambient.pulse(data[0])
			_pose_counter += 0.5
			while _pose_counter > top:
				_pose_counter -= top
		_ambient.tick()
		for id: StringName in _ambient.trg_se:
			Audio.play_se(id, self)
		_ambient.trg_se.clear()


func _feel_origin() -> Vector3:
	if feel_skeleton != null and is_instance_valid(feel_skeleton) and feel_bone >= 0:
		var at: Vector3 = (feel_skeleton.global_transform * feel_skeleton.get_bone_global_pose(feel_bone)).origin
		return global_transform.affine_inverse() * at
	return Vector3.ZERO


## The reaction clip has ended (`effect_kill_proc`): clip-long effects vanish, fade out or
## play on as their profile says; the one-shot glyphs run their own course.
func release() -> void:
	if _moods != null:
		_moods.release()


## `angle − (getCamera2AngleY + 0x8000)` in degrees, 0..360: 0 while the NPC faces the
## camera, 90 turned to screen right.
func view_diff_deg() -> float:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return 0.0
	var to: Vector3 = cam.global_position - global_position
	return fposmod(rad_to_deg(npc_yaw - atan2(to.x, to.z)), 360.0)


func _tick_moods(delta: float) -> void:
	_moods.origin = _feel_origin()
	_mood_steps.add(delta)
	var first: bool = delta == 0.0
	while first or _mood_steps.next():
		first = false
		## A caller that never says the clip ended (the intro's scripted NPCs) still gets
		## its effect back after a long reaction.
		if _moods.t >= MOOD_MAX_TICKS:
			_moods.release()
		if not _moods.tick():
			clear()
			return
		for id: StringName in _moods.trg_se:
			Audio.play_se(id, self)
		_moods.trg_se.clear()
	_hold_ongen(_moods.ongen)


## `sAdo_OngenPos`: the effect's level SE, loud as `Ongen.volume` from the field mic.
func _hold_ongen(id: StringName) -> void:
	if id == &"":
		if _ongen_player != null:
			_ongen_player.stop()
		return
	if _ongen_player == null:
		_ongen_player = AudioStreamPlayer.new()
		_ongen_player.bus = Audio.SFX_BUS
		add_child(_ongen_player)
	if _ongen_player.get_meta(&"se", &"") != id:
		_ongen_player.stop()
		_ongen_player.stream = Ongen.looped(SeCatalog.stream_for(id))
		_ongen_player.set_meta(&"se", id)
	var mic: Vector3 = Ongen.field_mic_gx(get_tree())
	var vol: float = Ongen.BASE_VOLUME
	if mic != Vector3.INF:
		vol = Ongen.volume(mic.distance_to(TownSpace.world_to_gx(global_position)))
	_ongen_player.volume_db = linear_to_db(maxf(vol, 0.0001))
	if _ongen_player.stream != null and not _ongen_player.playing:
		_ongen_player.play()


func clear() -> void:
	if _moods != null:
		_moods.clear()
		_moods = null
	if _ongen_player != null:
		_ongen_player.stop()
	_kind = &""
	_frame = 0.0
	_cycle = 0
	_active_visual = &""
	if _mesh_host != null:
		for child: Node in _mesh_host.get_children():
			child.free()
		_mesh_host.position = Vector3.ZERO
		_mesh_host.scale = Vector3.ONE
	if _glow_host != null:
		for child: Node in _glow_host.get_children():
			child.free()
		_glow_host.position = Vector3.ZERO
		_glow_host.scale = Vector3.ONE


## Follow `skeleton`'s last bone (the NPC feel joint) for the clip-long effects.
func bind_feel_joint(skeleton: Skeleton3D) -> void:
	feel_skeleton = skeleton
	feel_bone = -1
	if skeleton != null:
		feel_bone = skeleton.find_bone("joint_25")
		if feel_bone < 0:
			feel_bone = skeleton.get_bone_count() - 1


func set_head_lift(meters: float) -> void:
	_head_lift = maxf(meters, 0.4)
	position = Vector3(0.0, _head_lift, 0.0)


func _tick_warau() -> void:
	## Disp table advances every 2 effect frames through four cards (`eWU_dw`).
	var slot: int = int(_frame) >> 1
	if slot >= 12:
		_cycle += 1
		if _cycle >= WARAU_CYCLES:
			clear()
			return
		_frame = 0.0
		slot = 0
	## Table: null, null, 00,00, 01,01, 02,02, 03,03, null, null
	var card: int = -1
	if slot >= 2 and slot <= 9:
		card = (slot - 2) >> 1
	if card < 0 or card >= WARAU_VISUALS.size():
		_clear_mesh_only()
		return
	_show_warau_frame(card)


func _tick_shock() -> void:
	var t: int = int(_frame)
	if t >= SHOCK_LIFE_FRAMES:
		clear()
		return
	## `eSK_scale_table` / prim fade — approximate with a quick pop then shrink.
	var scales: Array[float] = [0.019, 0.02375, 0.0285, 0.026125, 0.02375, 0.021375, 0.019]
	var idx: int = mini(t, scales.size() - 1)
	var s: float = _node_scale_for(scales[idx])
	_mesh_host.scale = Vector3(s, s, s)
	var fade: float = 1.0 if t < 7 else clampf(1.0 - float(t - 7) / 7.0, 0.0, 1.0)
	_set_mesh_alpha(fade)


func _tick_ha() -> void:
	if int(_frame) >= HA_LIFE_FRAMES:
		clear()
		return
	## Hold full until frame 24, then fade (`eHA_dw` calc_adjust).
	var elapsed: int = int(_frame)
	var fade: float = 1.0
	if elapsed > 24:
		fade = clampf(1.0 - float(elapsed - 24) / float(HA_LIFE_FRAMES - 24), 0.0, 1.0)
	_set_mesh_alpha(fade)


func _tick_hirameki() -> void:
	var t: int = int(_frame)
	if t >= HIRAMEKI_LIFE_FRAMES:
		clear()
		return
	## Den fades from frame 64→72 (`eHiramekiD_dw`); hikari is only the first 12 frames.
	var den_fade: float = 1.0
	if t > 64:
		den_fade = clampf(1.0 - float(t - 64) / 8.0, 0.0, 1.0)
	_set_mesh_alpha(den_fade)
	if _glow_host != null and _glow_host.get_child_count() > 0:
		if t >= HIRAMEKI_HIKARI_FRAMES:
			for child: Node in _glow_host.get_children():
				child.free()
		else:
			## `eHiramekiH_dw`: scale 0.014→0.0175, alpha ramp then fade.
			var hs: float = lerpf(0.014, 0.0175, float(t) / float(HIRAMEKI_HIKARI_FRAMES))
			var g: float = _node_scale_for(hs)
			_glow_host.scale = Vector3(g, g, g)
			var ha: float = 1.0
			if t < 4:
				ha = float(t) * 50.0 / 255.0
			else:
				ha = clampf(1.0 - float(t - 4) / 8.0, 0.0, 1.0)
			_set_mesh_alpha_node(_glow_host, ha)


## `eGM_dw` / `eKT_dw`.
func _tick_pop() -> void:
	var t: int = int(_frame)
	if t >= POP_LIFE:
		clear()
		return
	var row: int = mini(t, POP_HOLD) >> 1
	var sq: Vector2 = POP_SCALE[row] if row < POP_SCALE.size() else Vector2.ONE
	var s: float = _node_scale_for(POP_MATRIX_SCALE)
	_mesh_host.scale = Vector3(sq.x * s, sq.y * s, s)
	_set_mesh_alpha(1.0 - clampf(float(t - POP_FADE_FROM) / float(POP_LIFE - POP_FADE_FROM), 0.0, 1.0))


func _tick_ase() -> void:
	var t: int = int(_frame)
	if t >= ASE_LIFE:
		clear()
		return
	_set_visual(ASE_VISUALS[(t & 12) >> 2], ASE_MATRIX_SCALE)


## Vein tint at tick `t`: prim (255, g, 50) with g 255 → 50 and the env red 255 → 100.
static func muka_color(t: int) -> Color:
	var k: float = clampf(float(t) / 20.0, 0.0, 1.0)
	var a: float = clampf(1.0 - float(t - 20) / 21.0, 0.0, 1.0)
	return Color(1.0, lerpf(255.0, 50.0, k) / 255.0, 50.0 / 255.0, a)


func _tick_muka() -> void:
	var t: int = int(_frame)
	if t >= MUKA_LIFE:
		clear()
		return
	## `eMK_ct`: screen right of the head while the NPC faces the camera, left otherwise.
	var side: float = 1.0 if faces_camera else -1.0
	_mesh_host.position = Vector3(MUKA_AT.x * side, MUKA_AT.y, MUKA_AT.z) * FieldCatalog.GX_TO_METERS
	var c: Color = muka_color(t)
	_tint_mesh(c)
	_set_mesh_alpha(c.a)


## Heart (x, y) matrix scale at tick `t` (`eLL2_dw`).
static func heart_scale(t: int) -> Vector2:
	var k: float = clampf(float(t) / 30.0, 0.0, 1.0)
	var base: float = lerpf(0.003, 0.014, k)
	var hi: float = lerpf(1.0125, 0.6375, k)
	var lo: float = lerpf(0.037499964, 0.412499964, k)
	var angle: float = deg_to_rad(HEART_SPIN) * float(t + 1)
	return Vector2(
		base * (lo + (sin(angle) + 1.0) * 0.5 * (hi - lo)),
		base * (lo + (cos(angle) + 1.0) * 0.5 * (hi - lo))
	)


## Total GX the heart has risen by tick `t`.
static func heart_rise(t: int) -> float:
	var y: float = 0.0
	for i: int in t:
		y += lerpf(1.0, 0.1, clampf(float(i) / 28.0, 0.0, 1.0))
	return y


func _tick_heart() -> void:
	var t: int = int(_frame)
	if t >= HEART_LIFE:
		clear()
		return
	var sc: Vector2 = heart_scale(t)
	var unit: float = _node_scale_for(1.0)
	_mesh_host.scale = Vector3(sc.x * unit, sc.y * unit, lerpf(0.003, 0.014, clampf(float(t) / 30.0, 0.0, 1.0)) * unit)
	_mesh_host.position.y = (HEART_Y_GX + heart_rise(t)) * FieldCatalog.GX_TO_METERS
	_set_mesh_alpha(1.0 - clampf(float(t - 96) / 16.0, 0.0, 1.0))


## Heartbreak card (0 whole, 1 cracking, 2 split) at tick `t`.
static func situren_card(t: int) -> int:
	if t == 60:
		return 1
	return 2 if t > 60 else 0


## Heartbreak (x, y) matrix scale at tick `t` (`eSN_dw`).
static func situren_scale(t: int) -> Vector2:
	var base: float = lerpf(0.0, 0.0075, clampf(float(t) / 6.0, 0.0, 1.0))
	var k: float = clampf(float(t) / 42.0, 0.0, 1.0)
	var hi: float = lerpf(1.4, 1.0, k)
	var lo: float = lerpf(0.6, 1.0, k)
	var angle: float = deg_to_rad(SITUREN_SPIN) * float(t + 1)
	return Vector2(
		base * (lo + (sin(angle) + 1.0) * 0.5 * (hi - lo)),
		base * (lo + (cos(angle) + 1.0) * 0.5 * (hi - lo))
	)


func _tick_situren() -> void:
	var t: int = int(_frame)
	if t >= SITUREN_LIFE:
		clear()
		return
	_set_visual(SITUREN_VISUALS[situren_card(t)], 0.0075)
	var sc: Vector2 = situren_scale(t)
	var unit: float = _node_scale_for(1.0)
	_mesh_host.scale = Vector3(sc.x * unit, sc.y * unit, 0.0075 * unit)
	## World-space offset in front of the NPC, carried into the billboard's frame.
	var rise: float = 1.6 * float(mini(t, 8))
	var world := Vector3(
		sin(npc_yaw) * SITUREN_AT.z, SITUREN_AT.y + rise, cos(npc_yaw) * SITUREN_AT.z
	) * FieldCatalog.GX_TO_METERS
	_mesh_host.position = global_basis.orthonormalized().inverse() * world
	_tint_mesh(Color(1.0, 200.0 / 255.0, 1.0))
	_set_mesh_alpha(1.0 - clampf(float(t - 108) / 20.0, 0.0, 1.0))


func _show_warau_frame(card: int) -> void:
	_set_visual(WARAU_VISUALS[card], WARAU_MATRIX_SCALE)
	_mesh_host.position = Vector3.ZERO


func _set_visual(visual_id: StringName, matrix_scale: float) -> void:
	if visual_id == _active_visual and _mesh_host.get_child_count() > 0:
		var s: float = _node_scale_for(matrix_scale)
		_mesh_host.scale = Vector3(s, s, s)
		return
	_clear_mesh_only()
	_active_visual = visual_id
	var paths: PackedStringArray = FieldCatalog.mesh_paths(visual_id)
	if paths.is_empty():
		return
	var packed: PackedScene = load(paths[0]) as PackedScene
	if packed == null:
		return
	var inst: Node = packed.instantiate()
	_mesh_host.add_child(inst)
	_make_unshaded(_mesh_host)
	var s2: float = _node_scale_for(matrix_scale)
	_mesh_host.scale = Vector3(s2, s2, s2)


func _set_glow_visual(visual_id: StringName, matrix_scale: float) -> void:
	if _glow_host == null:
		return
	for child: Node in _glow_host.get_children():
		child.free()
	var paths: PackedStringArray = FieldCatalog.mesh_paths(visual_id)
	if paths.is_empty():
		return
	var packed: PackedScene = load(paths[0]) as PackedScene
	if packed == null:
		return
	var inst: Node = packed.instantiate()
	_glow_host.add_child(inst)
	_make_unshaded(_glow_host)
	_tint_mesh_node(_glow_host, Color(1.0, 1.0, 0.39))
	var s: float = _node_scale_for(matrix_scale)
	_glow_host.scale = Vector3(s, s, s)


func _clear_mesh_only() -> void:
	_active_visual = &""
	if _mesh_host == null:
		return
	for child: Node in _mesh_host.get_children():
		child.free()


func _node_scale_for(matrix_scale: float) -> float:
	## Authored × matrix_scale → GX; GLB already × PIPELINE_SCALE.
	return matrix_scale * FieldCatalog.GX_TO_METERS / FieldCatalog.PIPELINE_SCALE


func _billboard() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to: Vector3 = cam.global_position - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	## +Z toward the camera and +X screen right, as the GX billboard matrix: offsets and
	## cards read the right way round.
	look_at(global_position - to.normalized(), Vector3.UP)


func _make_unshaded(root: Node) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.mesh != null:
			for i: int in mi.mesh.get_surface_count():
				var mat: Material = mi.get_active_material(i)
				if mat is StandardMaterial3D:
					var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					std.cull_mode = BaseMaterial3D.CULL_DISABLED
					std.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
					mi.set_surface_override_material(i, std)
	for child: Node in root.get_children():
		_make_unshaded(child)


func _tint_mesh(color: Color) -> void:
	_tint_mesh_node(_mesh_host, color)


func _tint_mesh_node(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i: int in mi.mesh.get_surface_count():
				var mat: Material = mi.get_active_material(i)
				if mat is StandardMaterial3D:
					var std := mat as StandardMaterial3D
					var c: Color = color
					c.a = std.albedo_color.a
					std.albedo_color = c
	for child: Node in node.get_children():
		_tint_mesh_node(child, color)


func _set_mesh_alpha(alpha: float) -> void:
	_set_mesh_alpha_node(_mesh_host, clampf(alpha, 0.0, 1.0))


func _set_mesh_alpha_node(node: Node, alpha: float) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i: int in mi.mesh.get_surface_count():
				var mat: Material = mi.get_active_material(i)
				if mat is StandardMaterial3D:
					var std := mat as StandardMaterial3D
					var c: Color = std.albedo_color
					c.a = alpha
					std.albedo_color = c
	for child: Node in node.get_children():
		_set_mesh_alpha_node(child, alpha)
