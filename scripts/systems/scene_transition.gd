extends CanvasLayer

## Persistent full-screen wipe that gates every scene swap (`m_fbdemo_wipe` /
## `Game_play_fbdemo_wipe_*` in the decomp). Not door-specific: buildings, interiors,
## the museum wings, and the intro chain all route through here.
##
## The original has two independent axes:
##   * a fade direction (`fb_fade_type`: OUT then IN) — modelled here as `play_wipe_out()`
##     that the caller awaits, then `play_wipe_in_if_pending()` on the freshly loaded scene;
##   * a wipe visual (`fb_wipe_type`) — `Style` below.
## `transition.wipe_type` in `Common` is the hand-off channel that carries the wipe across
## the load so the incoming scene fades in to match (or, for the intro, deliberately differs).
## `pending_style` / `pending_color` are that channel — they persist because this is an autoload.

## `WIPE_TYPE_*` visuals. Doors use `WIPE_TYPE_TRIFORCE` (`IRIS`); title / demo / K.K. use
## `WIPE_TYPE_FADE_BLACK`; the train -> town arrival fades out black then irises in
## (`WIPE_TYPE_CIRCLE_LEFT`). The decomp shapes `IRIS` with a hand-modelled mesh
## (`ef_wipe2`/`ef_wipe3`); here it's a screen-space circular mask shader
## (`shaders/iris_wipe.gdshader`) driven by the same 0..1 progress as the flat fade.
enum Style { FADE, IRIS }

## Rough hold (~0.6 s) before / after the scene load (`transition.wipe_rate` 28 / `fade_rate` 30).
const WIPE_SEC := 0.6
const IRIS_SHADER := preload("res://shaders/iris_wipe.gdshader")

## Armed by `play_wipe_out()` / `hold_black()`; consumed by `play_wipe_in_if_pending()`
## on the next scene. Persists across the load because this node is an autoload.
var wipe_in_pending: bool = false
var pending_style: Style = Style.FADE
var pending_color: Color = Color.BLACK

## Emitted when the wipe-in tween actually starts (after the new scene has settled).
signal wipe_in_started

var _rect: ColorRect
var _iris_material: ShaderMaterial
var _tween: Tween
## A wipe-in is armed but holding opaque until the new scene has drawn (see below).
var _wipe_in_waiting: bool = false
## Bumped by `cancel_wipe()` so a wipe-in still waiting on its first frames never starts.
var _wipe_generation: int = 0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.name = "WipeRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_rect = ColorRect.new()
	_rect.name = "Wipe"
	_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_rect)
	_iris_material = ShaderMaterial.new()
	_iris_material.shader = IRIS_SHADER
	_iris_material.set_shader_parameter("progress", 0.0)
	_iris_material.set_shader_parameter("iris_color", Color(0.0, 0.0, 0.0, 1.0))
	_rect.resized.connect(_sync_iris_rect_size)
	_sync_iris_rect_size()


func _sync_iris_rect_size() -> void:
	if _iris_material != null and _rect != null:
		_iris_material.set_shader_parameter("rect_size", _rect.size)


## Fade the screen out before a scene swap. `style` / `color` also become the pending
## wipe-in so the incoming scene matches; override the incoming half with `queue_wipe_in()`.
func play_wipe_out(style: Style = Style.FADE, color: Color = Color.BLACK) -> void:
	wipe_in_pending = true
	pending_style = style
	pending_color = color
	_apply_style_color(color)
	await _fade_to(1.0)


## Override just the wipe-in that a following `play_wipe_in_if_pending()` will play — e.g.
## the train fades out to black (`FADE_BLACK`) but the town irises in (`CIRCLE_LEFT`).
func queue_wipe_in(style: Style, color: Color = Color.BLACK) -> void:
	wipe_in_pending = true
	pending_style = style
	pending_color = color


## The scene faded itself out (e.g. K.K.'s strum-synced `%FadeRect` / `aNPS` 70-frame fade)
## and just needs the screen held opaque across the load until the next scene fades in.
func hold_black() -> void:
	wipe_in_pending = true
	pending_style = Style.FADE
	pending_color = Color.BLACK
	_apply_style_color(Color.BLACK)
	_set_alpha(1.0)


func play_wipe_in() -> void:
	wipe_in_pending = false
	await _fade_to(0.0)


func play_wipe_in_if_pending() -> void:
	if not wipe_in_pending:
		return
	## Stay fully opaque through the first indoor draw — otherwise one frame can flash
	## the new room before the fade-in tween starts.
	_apply_style_color(pending_color)
	_set_alpha(1.0)
	wipe_in_pending = false
	_wipe_in_waiting = true
	var generation: int = _wipe_generation
	## A freshly built scene stalls its first frames (node `_ready`, mesh / shader upload).
	## Tweens advance by real frame time, so starting the fade now would spend a good part of it
	## inside that stall and the iris would appear already half open (or open before the world
	## has drawn at all). Wait for the first drawn frames, then start.
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if generation != _wipe_generation:
		return
	_wipe_in_waiting = false
	wipe_in_started.emit()
	## Fire-and-forget so room spawn / arrive can start immediately under the fade.
	play_wipe_in()


## Lets a scene start its own opening beat (door emerge) on the same frame the wipe-in starts.
func wait_wipe_in_start() -> void:
	if _wipe_in_waiting:
		await wipe_in_started


func cancel_wipe() -> void:
	## Enter failed after wipe-out — restore visibility without a scene change.
	wipe_in_pending = false
	_wipe_generation += 1
	if _wipe_in_waiting:
		_wipe_in_waiting = false
		wipe_in_started.emit()  ## release anything waiting on the start (door emerge)
	pending_style = Style.FADE
	pending_color = Color.BLACK
	if _tween != null:
		_tween.kill()
		_tween = null
	_apply_style_color(Color.BLACK)
	_set_alpha(0.0)


## Keep the flat-fill rect and the iris shader's tint/material in lockstep, since
## `queue_wipe_in()` can hand a `FADE` wipe-out off to an `IRIS` wipe-in (or vice versa)
## and either one might end up driving the visible rect.
func _apply_style_color(color: Color) -> void:
	if _rect == null:
		return
	_rect.color = Color(color.r, color.g, color.b, _rect.color.a)
	if _iris_material != null:
		_iris_material.set_shader_parameter("iris_color", Color(color.r, color.g, color.b, 1.0))
	_rect.material = _iris_material if pending_style == Style.IRIS else null


## Snap both representations to `alpha` with no tween, for the instant hand-off points
## (`hold_black()`, the pre-fade-in flash guard, `cancel_wipe()`).
func _set_alpha(alpha: float) -> void:
	if _rect == null:
		return
	_rect.color.a = alpha
	if _iris_material != null:
		_iris_material.set_shader_parameter("progress", alpha)


func _fade_to(alpha: float) -> void:
	if _rect == null:
		return
	if _tween != null:
		_tween.kill()
	_rect.material = _iris_material if pending_style == Style.IRIS else null
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_parallel(true)
	_tween.tween_property(_rect, "color:a", alpha, WIPE_SEC)
	if _iris_material != null:
		_tween.tween_property(_iris_material, "shader_parameter/progress", alpha, WIPE_SEC)
	await _tween.finished
