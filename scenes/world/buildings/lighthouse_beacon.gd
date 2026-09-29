extends Node

## The tower lamp (`ac_toudai`: `aTOU_wait` / `aTOU_lighting` / `aTOU_lightout`,
## `aTOU_color_ctrl`, `aTOU_actor_draw_after`). Drives the tower's own generated visual —
## the arm clip baked into `obj_s_toudai.glb` / `obj_w_toudai.glb` and the XLU beam
## surface (`*_light_model`) — so it needs the sibling `GeneratedVisual` the host attaches.
##
## The arm rests on clip frame 51. When the lamp may turn (`LighthouseBook.lamp_on`:
## 18:00–05:00 unless a quest night is still unswitched) it sweeps at cKF speed 0.5; when it
## may not, it keeps sweeping until it is back on frame 51 and stops there. The beam is not
## a light source: it is a translucent cone tinted `(255, 255, b)` whose alpha peaks each
## time the arm passes frame 51 and fades in and out with the lamp.

enum State { WAIT, LIGHTING, LIGHTOUT }

## `aTOU_setup_action(0)`: frames 1–100, repeat, resting on 51.
const FRAME_START := 1.0
const FRAME_END := 100.0
const FRAME_REST := 51
## cKF frames per 60 Hz tick while lit.
const LIT_SPEED := 0.5
## The pipeline samples cKF clips at 30 fps.
const CLIP_FPS := 30.0
const TICK_HZ := 60.0
## `add_calc` fractions: `1 − √0.7` for the beam, `1 − √0.9` for the fade.
const BEAM_DECAY := 1.0 - 0.8366600265340756
const FADE_RATE := 1.0 - 0.9486832980505138
const CALC_MAX := 50.0
const CALC_MIN := 0.5
## Beam prim at the peak (frame 51).
const PEAK_BLUE := 220.0
const PEAK_ALPHA := 240.0
## Per-tick beam ramps by distance from frame 51: [limit, blue step, alpha step].
const RAMPS: Array = [[10, 4.5, 7.0], [30, 1.25, 2.25], [40, 4.0, 0.5]]
const BEAM_SURFACE_SUFFIX := "_light_tex_txt"

## When false the lamp ignores the clock (tests / captures drive `lit` directly).
@export var follow_clock: bool = true
## The lamp may turn. Follows `LighthouseBook.lamp_on_now` while `follow_clock`.
var lit: bool = false

var state: State = State.WAIT
var frame: float = float(FRAME_REST)
## `unk2C8` / `unk2CC` / `unk2D0`: beam blue, beam alpha, fade (0–255).
var beam_blue: float = 0.0
var beam_alpha: float = 0.0
var fade: float = 0.0

var _accum: float = 0.0
var _anim: AnimationPlayer = null
var _clip: StringName = &""
var _beam: Array[StandardMaterial3D] = []


func _ready() -> void:
	## The host attaches its `GeneratedVisual` after its children are ready.
	call_deferred(&"_bind")


func _physics_process(delta: float) -> void:
	_accum += delta
	var ticks: int = 0
	while _accum >= 1.0 / TICK_HZ and ticks < 8:
		_accum -= 1.0 / TICK_HZ
		ticks += 1
		tick()
	if ticks >= 8:
		_accum = 0.0
	_apply()


## One 60 Hz move tick (`aTOU_actor_move`).
func tick() -> void:
	if follow_clock and Game != null and Game.lighthouse != null and Clock != null:
		lit = Game.lighthouse.lamp_on_now()
	if state != State.WAIT:
		frame += LIT_SPEED
		if frame > FRAME_END:
			frame -= FRAME_END - FRAME_START
	match state:
		State.WAIT:
			if lit:
				state = State.LIGHTING
		State.LIGHTING:
			if not lit:
				state = State.LIGHTOUT
		State.LIGHTOUT:
			if int(frame) == FRAME_REST:
				frame = float(FRAME_REST)
				state = State.WAIT
	_color_ctrl()


func is_sweeping() -> bool:
	return state != State.WAIT


## Beam prim colour as drawn, alpha already multiplied by the fade (`PRIM_LOD_FRAC`).
## Alpha 0 when `aTOU_actor_draw_after` would skip the beam.
func beam_color() -> Color:
	if int(beam_alpha) == 0:
		return Color(1.0, 1.0, beam_blue / 255.0, 0.0)
	var prim_a: float = minf(beam_alpha, float(int(fade)))
	return Color(1.0, 1.0, clampf(beam_blue, 0.0, 255.0) / 255.0, prim_a / 255.0 * int(fade) / 255.0)


## Clip time for the current cKF frame.
func clip_time() -> float:
	return (frame - FRAME_START) / CLIP_FPS


func _color_ctrl() -> void:
	if state == State.WAIT:
		beam_blue = _add_calc(beam_blue, 0.0, BEAM_DECAY)
		beam_alpha = _add_calc(beam_alpha, 0.0, BEAM_DECAY)
		fade = _add_calc(fade, 0.0, FADE_RATE)
		return
	var offset: int = int(frame) - FRAME_REST
	var toward: float = 1.0 if offset < 0 else -1.0
	var dist: int = absi(offset)
	if dist == 0:
		beam_blue = PEAK_BLUE
		beam_alpha = PEAK_ALPHA
	elif dist >= int(RAMPS[RAMPS.size() - 1][0]):
		beam_blue = _add_calc(beam_blue, 0.0, BEAM_DECAY)
		beam_alpha = _add_calc(beam_alpha, 0.0, BEAM_DECAY)
	else:
		for ramp: Array in RAMPS:
			if dist < int(ramp[0]):
				beam_blue += float(ramp[1]) * toward
				beam_alpha += float(ramp[2]) * toward
				break
	fade = _add_calc(fade, 255.0, FADE_RATE)


## `add_calc(value, target, fraction, max_step, min_step)`.
static func _add_calc(value: float, target: float, fraction: float) -> float:
	var diff: float = target - value
	if diff == 0.0:
		return value
	var step: float = diff * fraction
	var mag: float = clampf(absf(step), CALC_MIN, CALC_MAX)
	if absf(diff) <= mag:
		return target
	return value + signf(diff) * mag


func _apply() -> void:
	if _anim == null or not is_instance_valid(_anim):
		_bind()
	if _anim != null and _clip != &"" and _anim.has_animation(_clip):
		if _anim.current_animation != _clip:
			_anim.play(_clip)
		_anim.pause()
		_anim.seek(clip_time(), true)
	var color: Color = beam_color()
	for mat: StandardMaterial3D in _beam:
		if is_instance_valid(mat):
			mat.albedo_color = color


func _bind() -> void:
	_anim = null
	_clip = &""
	_beam.clear()
	var host: Node = get_parent()
	var visual: Node = host.get_node_or_null("GeneratedVisual") if host != null else null
	if visual == null:
		return
	_anim = _find_animation_player(visual)
	if _anim != null:
		for clip_name: StringName in _anim.get_animation_list():
			if clip_name != &"RESET":
				_clip = clip_name
				break
	_bind_beam(visual)


## The `*_light_model` joint's XLU surface: `G_CC` prim colour × texel alpha × prim alpha,
## then × `PRIM_LOD_FRAC` — unlit, not written to depth. `aTOU_actor_draw_before` hides
## it; `draw_after` redraws it only with the lamp's prim, so it starts invisible.
func _bind_beam(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
		for i: int in count:
			var mat: Material = mi.get_active_material(i)
			if not (mat is StandardMaterial3D):
				continue
			if not String(mat.resource_name).ends_with(BEAM_SURFACE_SUFFIX):
				continue
			var beam := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			beam.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			beam.cull_mode = BaseMaterial3D.CULL_DISABLED
			beam.vertex_color_use_as_albedo = false
			beam.albedo_texture = VisualWindowLight.coverage_texture(beam.albedo_texture)
			beam.albedo_color = beam_color()
			mi.set_surface_override_material(i, beam)
			_beam.append(beam)
	for child: Node in n.get_children():
		_bind_beam(child)


static func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c: Node in n.get_children():
		var found: AnimationPlayer = _find_animation_player(c)
		if found != null:
			return found
	return null
