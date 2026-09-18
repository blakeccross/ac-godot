extends Node

## Renders the bottom-right HUD clock widget over a grass-green background so
## its badge colors/layout can be screenshotted for review. Needs a real
## rendering context (viewport screenshots are blank under --headless). Run:
##   Godot --path . res://scenes/dev/capture_clock_widget.tscn

const OUT := "res://recordings/clock_widget.png"


func _ready() -> void:
	await get_tree().process_frame
	var bg := ColorRect.new()
	bg.color = Color(0.20, 0.40, 0.22)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	## Pin the clock so the capture is reproducible — Clock otherwise keeps
	## following the real OS time every frame.
	Clock.paused = true
	Clock.rtc_override = true
	Clock.month = 9
	Clock.day = 3
	Clock.hour = 21
	Clock.minute = 52

	var widget: Control = load("res://scenes/ui/clock_widget.tscn").instantiate()
	add_child(widget)
	await get_tree().process_frame  # let _ready() run before touching its state
	widget.call("_refresh")
	widget.set_process(false)  # stop the idle-fade _process() from fighting our override
	widget.set("_alpha", 1.0)
	widget.modulate.a = 1.0

	for _i in 10:
		await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT)
	print("wrote ", OUT)

	get_tree().quit()
