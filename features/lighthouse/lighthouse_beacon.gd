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
##
## The decomp ramps the beam a step a tick by how far the arm is from frame 51 — down after
## the peak, up before it — and eases it to nothing 40 or more frames away. Summed, the ramps
## trace a fixed curve over the arm's frame, so inside 40 frames the beam is read off that
## curve; outside it eases as the decomp does.

enum State { WAIT, LIGHTING, LIGHTOUT }

## `aTOU_setup_action(0)`: frames 1–100, repeat, resting on 51.
const FRAME_START := 1.0
const FRAME_END := 100.0
const FRAME_REST := 51
## The pipeline samples cKF clips at 30 fps; lit, the arm turns at that rate (cKF speed
## 0.5 a tick).
const CLIP_FPS := 30.0
const LIT_FRAMES_PER_SEC := 0.5 * DecompTime.TICK_HZ
## `add_calc` a tick, fraction `1 − √0.7` for the beam and `1 − √0.9` for the fade, steps
## held to 0.5–50: as half-lives and speeds a second.
static var BEAM_HALF_LIFE: float = Motion.half_life_from_fraction(1.0 - 0.8366600265340756)
static var FADE_HALF_LIFE: float = Motion.half_life_from_fraction(1.0 - 0.9486832980505138)
const CALC_MAX_SPEED := 50.0 * DecompTime.TICK_HZ
const CALC_MIN_SPEED := 0.5 * DecompTime.TICK_HZ
## Beam prim at the peak (frame 51).
const PEAK_BLUE := 220.0
const PEAK_ALPHA := 240.0
## Beam ramps by distance from frame 51: [limit, blue, alpha] per tick at 0.5 frames a
## tick, so twice that per frame of distance. From `RAMP_END` frames away it eases instead.
const RAMPS: Array = [[10, 4.5, 7.0], [30, 1.25, 2.25], [40, 4.0, 0.5]]
const RAMP_END := 40
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

var _anim: AnimationPlayer = null
var _clip: StringName = &""
var _beam: Array[StandardMaterial3D] = []


func _ready() -> void:
	## The host attaches its `GeneratedVisual` after its children are ready.
	call_deferred(&"_bind")


func _physics_process(delta: float) -> void:
	advance(delta)
	_apply()


## `aTOU_actor_move` over `delta` seconds.
func advance(delta: float) -> void:
	if follow_clock and Game != null and Game.lighthouse != null and Clock != null:
		lit = Game.lighthouse.lamp_on_now()
	var before: float = frame
	if state != State.WAIT:
		frame += LIT_FRAMES_PER_SEC * delta
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
			## Stops on the step that reaches frame 51 (`int(frame) == 51`).
			var rest := float(FRAME_REST)
			var reached: bool = (
				int(frame) == FRAME_REST or (before < rest and frame >= rest)
				or (frame < before and (before < rest or frame >= rest))
			)
			if reached:
				frame = rest
				state = State.WAIT
	_color_ctrl(delta)


## Test-only: no in-game callers; kept for tests.
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


func _color_ctrl(delta: float) -> void:
	if state == State.WAIT:
		beam_blue = _ease(beam_blue, 0.0, BEAM_HALF_LIFE, delta)
		beam_alpha = _ease(beam_alpha, 0.0, BEAM_HALF_LIFE, delta)
		fade = _ease(fade, 0.0, FADE_HALF_LIFE, delta)
		return
	if absi(int(frame) - FRAME_REST) >= RAMP_END:
		beam_blue = _ease(beam_blue, 0.0, BEAM_HALF_LIFE, delta)
		beam_alpha = _ease(beam_alpha, 0.0, BEAM_HALF_LIFE, delta)
	else:
		var beam: Vector2 = beam_at(frame)
		beam_blue = beam.x
		beam_alpha = beam.y
	fade = _ease(fade, 255.0, FADE_HALF_LIFE, delta)


## The beam's blue and alpha with the arm on `at`, inside `RAMP_END` frames of 51. After the
## peak each frame away takes its own ramp off (frame 52 the first, so frame 90 is left at
## 9 / 14 to ease out); before it the beam has built up from nothing, one ramp a frame from
## 39 away, to 211 / 226 on frame 50.
static func beam_at(at: float) -> Vector2:
	var away: int = int(at) - FRAME_REST
	if away == 0:
		return Vector2(PEAK_BLUE, PEAK_ALPHA)
	if away > 0:
		return Vector2(PEAK_BLUE, PEAK_ALPHA) - _ramp_sum(1, mini(away, RAMP_END - 1))
	return _ramp_sum(-away, RAMP_END - 1)


## The ramp steps for distances `from`..`to` frames, two ticks a frame.
static func _ramp_sum(from: int, to: int) -> Vector2:
	var sum := Vector2.ZERO
	for d: int in range(from, to + 1):
		for ramp: Array in RAMPS:
			if d < int(ramp[0]):
				sum += 2.0 * Vector2(float(ramp[1]), float(ramp[2]))
				break
	return sum


static func _ease(value: float, target: float, half_life: float, delta: float) -> float:
	return Motion.approach(value, target, half_life, CALC_MAX_SPEED, CALC_MIN_SPEED, delta)


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
