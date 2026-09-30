extends Node

## Renders disc messages that lean on the message codes: PAUSE timing, CHARSCALE with
## LINETYPE (msg 1917's shrinking "I think..."), LINEOFS with a big coloured shout
## (msg 2098's "AGHHH!"), and a MSGCLEAR page that turns by itself. Run headed:
##   Godot --path . res://scenes/dev/dialogue_effects_check.tscn
## Writes user://dialogue_fx_*.png.

const SHOTS := [["msg_2098", 70, "shout"], ["msg_1917", 60, "pause"], ["msg_1917", 260, "auto_page"]]


func _ready() -> void:
	await get_tree().process_frame
	var bg := ColorRect.new()
	bg.color = Color(0.30, 0.45, 0.28)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var overlay: DialogueOverlay = load("res://scenes/ui/dialogue_overlay.tscn").instantiate() as DialogueOverlay
	add_child(overlay)
	await get_tree().process_frame
	for shot: Array in SHOTS:
		var data := DialogueCatalog.conversation(StringName(shot[0]))
		if data == null:
			print("dialogue_fx: missing ", shot[0])
			continue
		var ctx := DialogueContext.new()
		ctx.speaker_name = "Tom Nook"
		ctx.player_name = "Blake"
		ctx.item0 = "a wallet"
		overlay.play(data, ctx)
		for _i in int(shot[1]):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://dialogue_fx_%s.png" % shot[2])
		print("dialogue_fx: wrote ", shot[2])
		overlay.close(true)
		await get_tree().process_frame
	## Last page of 1917: the shrinking line, all typed out.
	var last := DialogueCatalog.conversation(&"msg_1917")
	if last != null:
		overlay.play(last, DialogueContext.new())
		for _i in 3:
			await get_tree().process_frame
		overlay.runner().jump_to(&"p3")
		for _i in 90:
			await get_tree().process_frame
		overlay.fast_advance()
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://dialogue_fx_shrink.png")
		print("dialogue_fx: wrote shrink")
	get_tree().quit()
