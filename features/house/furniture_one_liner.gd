class_name FurnitureOneLiner
extends RefCounted

## The three pieces that answer a tap with a line (`HITOKOTO`, `aMR_MSG_STATE_HITOKOTO*` in
## `ac_my_room_move.c_inc`): the lovely phone's Dial-a-Psychic call, the tanabata palm's
## fortune and Super Tortimer's April Fool. Each is a plain report from any side, after the
## ordinary switch flip. Message numbers are `aMR_msg_no_table`.

## visual id → { msg: first message, se: sound at the piece ("" for none) }
const LINES := {
	&"int_ike_k_otome01": {"msg": 14986, "se": &"166"},
	&"int_ike_k_tanabata01": {"msg": 15089, "se": &""},
	&"int_tak_nes01": {"msg": 15192, "se": &""},
}


static func has(data: FurnitureData) -> bool:
	return data != null and LINES.has(data.visual_id)


## Play the piece's sound and its message; returns once the window closes.
static func say(data: FurnitureData, node: Node3D) -> void:
	if not has(data):
		return
	var line: Dictionary = LINES[data.visual_id]
	if line["se"] != &"":
		Audio.play_se(line["se"] as StringName, node)
	var ui := DialogueOverlay.find(Game.get_tree())
	var convo: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % int(line["msg"])))
	if ui == null or convo == null:
		return
	ui.play(convo, DialogueContext.from_game())
	if ui.is_open():
		await ui.closed
