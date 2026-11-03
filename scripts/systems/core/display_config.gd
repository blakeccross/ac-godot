class_name DisplayConfig
extends RefCounted

## The screen shape the player picked: fixed 4:3 or 16:9 (black bars when the window differs) or
## adaptive, which fills the whole window. Kept in `user://config.cfg` under `[display]` and
## applied to the root window's content scale. Also holds whether the town camera scrolls to the
## next acre on its own 0.6 s sweep when the player wades (`camera_wade`); a phone defaults to
## off, where the camera just follows. Not an autoload.

enum Aspect { ADAPTIVE, WIDESCREEN, STANDARD }

const DEFAULT_PATH := "user://config.cfg"
const SECTION := "display"

const LABELS: Array[String] = ["Fill window", "16:9", "4:3"]
## Design height is 720 in every mode, so UI keeps its size and only the width changes.
const BASE_SIZE := Vector2i(1280, 720)
const STANDARD_SIZE := Vector2i(960, 720)

static var path: String = DEFAULT_PATH
static var aspect: int = Aspect.ADAPTIVE
## -1 = not chosen (the platform default), 0 = off, 1 = on.
static var wade_choice: int = -1
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		aspect = clampi(int(cfg.get_value(SECTION, "aspect", Aspect.ADAPTIVE)), 0, Aspect.STANDARD)
		wade_choice = clampi(int(cfg.get_value(SECTION, "camera_wade", -1)), -1, 1)


## Back to the default (tests; a fresh install).
static func reset(p_path: String = DEFAULT_PATH) -> void:
	path = p_path
	aspect = Aspect.ADAPTIVE
	wade_choice = -1
	_loaded = true


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value(SECTION, "aspect", aspect)
	cfg.set_value(SECTION, "camera_wade", wade_choice)
	cfg.save(path)


## Whether the town camera does `Camera2_main_Wade`'s scripted sweep across an acre line.
## Unchosen, it is on everywhere but a phone or tablet.
static func camera_wade() -> bool:
	ensure_loaded()
	if wade_choice >= 0:
		return wade_choice == 1
	return not InputDeviceTracker.on_mobile


static func set_camera_wade(on: bool) -> void:
	ensure_loaded()
	wade_choice = 1 if on else 0
	save()


static func label(mode: int = aspect) -> String:
	return LABELS[clampi(mode, 0, LABELS.size() - 1)]


## The next mode in the cycle, wrapping.
static func next(mode: int = aspect) -> int:
	return (mode + 1) % LABELS.size()


static func content_size(mode: int = aspect) -> Vector2i:
	return STANDARD_SIZE if mode == Aspect.STANDARD else BASE_SIZE


static func scale_aspect(mode: int = aspect) -> Window.ContentScaleAspect:
	if mode == Aspect.ADAPTIVE:
		return Window.CONTENT_SCALE_ASPECT_EXPAND
	return Window.CONTENT_SCALE_ASPECT_KEEP


## Picks `mode`, applies it to `window` and saves it.
static func set_aspect(mode: int, window: Window) -> void:
	aspect = clampi(mode, 0, Aspect.STANDARD)
	apply(window)
	save()


static func apply(window: Window) -> void:
	if window == null:
		return
	window.content_scale_size = content_size()
	window.content_scale_aspect = scale_aspect()
