class_name TalkActions
extends RefCounted

## Plays a `BankTalk` step that needs the world: the pockets opened for a hand-over
## (`{"hand": …}`) or an item passed across (`{"anim": {"give"|"take": item}}`), then answers
## the runner. Shared by villagers and event NPCs.


static func handle(action: Dictionary, ui: DialogueOverlay, npc: Node3D, player: Node3D) -> void:
	var runner: DialogueRunner = ui.runner() if ui != null else null
	if runner == null:
		return
	ui.set_suspended(true)
	if action.has("hand"):
		var hand: Dictionary = action["hand"]
		Game.request_quest_handover(int(hand.get("pocket", -1)), str(hand.get("mode", "quest")))
		var picked: Array = await Game.quest_handover_resolved
		ui.set_suspended(false)
		runner.resolve_action({"item": picked[0], "pocket": picked[1]})
		return
	if action.has("text"):
		var text: String = await _edit_text(action["text"], ui)
		ui.set_suspended(false)
		runner.resolve_action({"text": text})
		return
	var anim: Dictionary = action.get("anim", {})
	if player != null and is_instance_valid(player) and npc != null and is_instance_valid(npc):
		if anim.has("give"):
			await HandOver.npc_gives_to_player(npc, player, anim["give"])
		elif anim.has("take"):
			await HandOver.player_gives_to_npc(player, npc, anim["take"])
	ui.set_suspended(false)
	runner.resolve_action({})


## `mSM_OVL_LEDIT` on the letter board: one line of `len` characters; resolves with the text
## (empty if the board is missing).
static func _edit_text(spec: Dictionary, ui: DialogueOverlay) -> String:
	var tree: SceneTree = ui.get_tree() if ui != null else null
	if tree == null:
		return ""
	var board := tree.get_first_node_in_group("letter_writer_ui")
	if board == null or not board.has_method("open_board") or bool(board.call("is_open")):
		return ""
	var box: Array = [""]
	board.call(
		"open_board", str(spec.get("initial", "")), int(spec.get("lines", 1)), int(spec.get("len", 16)),
		func(text: String) -> void: box[0] = text
	)
	await board.closed
	return str(box[0]).strip_edges()
