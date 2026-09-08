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
## (`WIPE_TYPE_CIRCLE_LEFT`). The iris shader is deferred, so `IRIS` currently renders as a
## plain colour fade — the type is still tracked so it upgrades in place once the mesh lands.
enum Style { FADE, IRIS }

## Rough hold (~0.6 s) before / after the scene load (`transition.wipe_rate` 28 / `fade_rate` 30).
const WIPE_SEC := 0.6

## Armed by `play_wipe_out()` / `hold_black()`; consumed by `play_wipe_in_if_pending()`
## on the next scene. Persists across the load because this node is an autoload.
var wipe_in_pending: bool = false
var pending_style: Style = Style.FADE
var pending_color: Color = Color.BLACK

var _rect: ColorRect
var _tween: Tween


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


## Fade the screen out before a scene swap. `style` / `color` also become the pending
## wipe-in so the incoming scene matches; override the incoming half with `queue_wipe_in()`.
func play_wipe_out(style: Style = Style.FADE, color: Color = Color.BLACK) -> void:
	wipe_in_pending = true
	pending_style = style
	pending_color = color
	if _rect != null:
		_rect.color = Color(color.r, color.g, color.b, _rect.color.a)
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
	if _rect != null:
		_rect.color = Color(0.0, 0.0, 0.0, 1.0)


func play_wipe_in() -> void:
	wipe_in_pending = false
	await _fade_to(0.0)


func play_wipe_in_if_pending() -> void:
	if not wipe_in_pending:
		return
	## Stay fully opaque through the first indoor draw — otherwise one frame can flash
	## the new room before the fade-in tween starts.
	if _rect != null:
		_rect.color = Color(pending_color.r, pending_color.g, pending_color.b, 1.0)
	## Fire-and-forget so room spawn / arrive can start immediately under the fade.
	play_wipe_in()


func cancel_wipe() -> void:
	## Enter failed after wipe-out — restore visibility without a scene change.
	wipe_in_pending = false
	pending_style = Style.FADE
	pending_color = Color.BLACK
	if _tween != null:
		_tween.kill()
		_tween = null
	if _rect != null:
		_rect.color.a = 0.0


func _fade_to(alpha: float) -> void:
	if _rect == null:
		return
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_rect, "color:a", alpha, WIPE_SEC)
	await _tween.finished
