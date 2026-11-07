class_name TalkActions
extends RefCounted

## Plays a `TalkStep` demo that needs the world: the pockets opened for a hand-over, the
## letter board, or an item passed across, then answers the runner. Shared by villagers and
## event NPCs.


static func handle(step: TalkStep, ui: DialogueOverlay, npc: Node3D, player: Node3D) -> void:
	var runner: DialogueRunner = ui.runner() if ui != null else null
	if runner == null:
		return
	ui.set_suspended(true)
	if step.pockets_mode != "":
		Game.pocket_requests.request_handover(step.pocket, step.pockets_mode)
		var picked: Array = await Game.pocket_requests.handover_resolved
		ui.set_suspended(false)
		runner.resolve_action(picked[0], picked[1])
		return
	if step.text_len > 0:
		var text: String = await _edit_text(step, ui)
		ui.set_suspended(false)
		runner.resolve_action(&"", -1, text)
		return
	if player != null and is_instance_valid(player) and npc != null and is_instance_valid(npc):
		match step.handover:
			TalkStep.Handover.NPC_GIVES:
				await HandOver.npc_gives_to_player(npc, player, step.item)
			TalkStep.Handover.PLAYER_GIVES:
				await HandOver.player_gives_to_npc(player, npc, step.item)
	ui.set_suspended(false)
	runner.resolve_action()


## `mSM_OVL_LEDIT` on the letter board: `text_lines` lines of `text_len` characters; resolves
## with the text (empty if the board is missing).
static func _edit_text(step: TalkStep, ui: DialogueOverlay) -> String:
	var tree: SceneTree = ui.get_tree() if ui != null else null
	if tree == null:
		return ""
	var board: LetterWriterOverlay = LetterWriterOverlay.find(tree)
	if board == null or board.is_open():
		return ""
	var box: Array = [""]
	board.open_board(
		step.text_initial, step.text_lines, step.text_len,
		func(text: String) -> void: box[0] = text
	)
	await board.closed
	return str(box[0]).strip_edges()
