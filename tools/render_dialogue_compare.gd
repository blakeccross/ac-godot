extends SceneTree

## Headless snapshot via SubViewport (works with dummy/headless display).

const OUT := "assets/generated/ui/message/_godot_cheri_dialogue.png"
const TEXT := (
	"Whoa! You look so weird!\n"
	+ "And not weird in a hip way,\n"
	+ "either. More like, \"weird\"\n"
	+ "as in \"makes me wanna barf.\""
)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(960, 720)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = true
	vp.handle_input_locally = false
	root.add_child(vp)

	var overlay_scene: PackedScene = load("res://scenes/ui/dialogue_overlay.tscn")
	var overlay: CanvasLayer = overlay_scene.instantiate()
	vp.add_child(overlay)

	for _i: int in 4:
		await process_frame

	var root_ui: Control = overlay.get_node("%Root") as Control
	var chrome: MessageWindowChrome = overlay.get_node("%MessageChrome") as MessageWindowChrome
	root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ui.size = Vector2(960, 720)
	chrome.size = Vector2(960, 720)
	chrome.set_speaker("Cheri", MessageWindowChrome.SpeakerSex.FEMALE)
	chrome.set_body(TEXT)
	chrome.set_body_visible_chars(chrome.body_visible_char_count())
	chrome.set_continue_visible(true)
	chrome._layout()

	for _i: int in 6:
		await process_frame

	var tex: ViewportTexture = vp.get_texture()
	var img: Image = tex.get_image()
	if img == null:
		push_error("viewport image null")
		quit(1)
		return

	var cloud := MessageWindowChrome.cloud_rect()
	var scale := minf(960.0 / 320.0, 720.0 / 240.0)
	var origin := (Vector2(960, 720) - Vector2(320, 240) * scale) * 0.5
	var name_top := origin.y + (cloud.position.y - 14.0) * scale
	var bottom := origin.y + 240.0 * scale
	var crop := Rect2i(0, maxi(0, int(name_top)), 960, maxi(1, int(bottom - name_top)))
	crop = crop.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var out_img: Image = img.get_region(crop)
	var abs_out := ProjectSettings.globalize_path("res://" + OUT)
	out_img.save_png(abs_out)
	print("wrote ", abs_out, " ", out_img.get_width(), "x", out_img.get_height())
	quit(0)
