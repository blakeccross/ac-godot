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
	var anim: Dictionary = action.get("anim", {})
	if player != null and is_instance_valid(player) and npc != null and is_instance_valid(npc):
		if anim.has("give"):
			await HandOver.npc_gives_to_player(npc, player, anim["give"])
		elif anim.has("take"):
			await HandOver.player_gives_to_npc(player, npc, anim["take"])
	ui.set_suspended(false)
	runner.resolve_action({})
