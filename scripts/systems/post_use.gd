class_name PostUse
extends RefCounted

## Post office desk ops (`ac_npc_post_girl` send / save / bank / repay).

const PRESET_CHUNK := 1000
const BODY_PRESETS: Array[String] = [
	"Hello! How are you today?\nI hope we can hang out soon!",
	"Just writing to say hi.\nSee you around town!",
	"Thinking of you!\nCome visit when you can.",
]


## `amount < 0` deposits the whole wallet.
static func deposit_amount(amount: int) -> String:
	if Game == null or Game.inventory == null:
		return ""
	var inv: Inventory = Game.inventory
	if amount < 0:
		amount = inv.wallet
	if inv.wallet <= 0:
		return "Your pockets are empty."
	if amount <= 0:
		return "Nothing to deposit."
	var put: int = inv.deposit_savings(amount)
	if put <= 0:
		return "Nothing to deposit."
	return "Deposited %d Bells. Savings: %d." % [put, inv.savings]


## `amount < 0` withdraws as much as the wallet can hold.
static func withdraw_amount(amount: int) -> String:
	if Game == null or Game.inventory == null:
		return ""
	var inv: Inventory = Game.inventory
	if amount < 0:
		amount = inv.savings
	if inv.savings <= 0:
		return "Your savings are empty."
	if amount <= 0:
		return "Nothing to withdraw."
	var room: int = Inventory.WALLET_MAX - inv.wallet
	if room <= 0:
		return "Your wallet is full."
	var take: int = inv.withdraw_savings(amount)
	if take <= 0:
		return "Nothing to withdraw."
	return "Withdrew %d Bells. Savings: %d." % [take, inv.savings]


## `amount < 0` pays as much as wallet / remaining loan allows.
static func repay_amount(amount: int) -> String:
	if Game == null or Game.inventory == null:
		return ""
	var inv: Inventory = Game.inventory
	if inv.loan <= 0:
		return "You don't owe anything."
	if amount < 0:
		amount = inv.loan
	if inv.wallet <= 0:
		return "Your pockets are empty."
	if amount <= 0:
		return "Nothing to repay."
	var paid: int = inv.repay_loan(amount)
	if paid <= 0:
		return "Nothing to repay."
	if inv.loan <= 0:
		return "Paid off %d Bells. Your loan is clear!" % paid
	return "Paid %d Bells. Still owing %d." % [paid, inv.loan]


static func send_mail_at(index: int) -> String:
	if Game == null or Game.inventory == null or Game.post == null:
		return ""
	if Game.post.is_desk_full():
		return "The desk is full — we can't take more mail."
	var letter: MailData = Game.inventory.mail_at(index)
	if letter == null or not letter.is_sendable():
		return "That isn't a finished letter."
	var copy: MailData = letter.duplicate_mail()
	if not Game.post.receipt_mail(copy):
		return "The desk is full — we can't take more mail."
	Game.inventory.remove_mail(index)
	_refresh_mail_piles()
	if Game.first_job != null and Game.first_job.is_active():
		Game.first_job.note_letter_mailed(copy.recipient_id)
		if Game.first_job.chore_finished():
			Game.set_interact_prompt("Talk to Tom Nook")
	return "We'll deliver your letter to %s!" % copy.recipient_name


static func save_mail_at(index: int) -> String:
	if Game == null or Game.inventory == null or Game.post == null:
		return ""
	if Game.post.is_desk_full():
		return "There's no room to save another letter."
	var letter: MailData = Game.inventory.mail_at(index)
	if letter == null or letter.is_empty():
		return "That slot is empty."
	var copy: MailData = letter.duplicate_mail()
	if not Game.post.receipt_mail(copy):
		return "There's no room to save another letter."
	Game.inventory.remove_mail(index)
	_refresh_mail_piles()
	return "We'll keep that letter safe for you."


static func write_letter(to_id: StringName, body_index: int = 0) -> String:
	if Game == null or Game.inventory == null:
		return ""
	if Game.inventory.empty_mail_slot_count() <= 0:
		return "Your letter slots are full."
	var villager: VillagerData = VillagerCatalog.get_villager(to_id)
	var to_name: String = villager.display_name if villager != null else String(to_id)
	if to_name == "":
		to_name = String(to_id)
	var body: String = BODY_PRESETS[clampi(body_index, 0, BODY_PRESETS.size() - 1)]
	var mail: MailData = MailData.make_send(
		to_id, to_name, body, Game.player_name, &"player"
	)
	if Game.inventory.add_mail(mail) < 0:
		return "Your letter slots are full."
	return "Wrote a letter to %s." % to_name


static func recipient_candidates() -> Array[Dictionary]:
	## Prefer town residents; fall back to catalog starters.
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	if Game != null and Game.villagers != null:
		var snap: Dictionary = Game.villagers.to_save()
		for key: Variant in snap.keys():
			var id := StringName(str(key))
			if id == &"" or seen.has(id):
				continue
			seen[id] = true
			var data: VillagerData = VillagerCatalog.get_villager(id)
			var name: String = data.display_name if data != null else String(id)
			out.append({"id": id, "name": name})
	if out.is_empty():
		for villager: VillagerData in VillagerCatalog.starters():
			if villager == null or villager.id == &"" or seen.has(villager.id):
				continue
			seen[villager.id] = true
			out.append({"id": villager.id, "name": villager.display_name})
	if out.is_empty():
		out.append({"id": &"filbert", "name": "Filbert"})
	return out


static func fill_bank_frees(ctx: DialogueContext) -> void:
	if ctx == null:
		return
	var savings: int = Game.inventory.savings if Game != null and Game.inventory != null else 0
	var loan: int = Game.inventory.loan if Game != null and Game.inventory != null else 0
	ctx.frees = PackedStringArray(["", "", "", ""])
	ctx.frees[0] = ""
	ctx.frees[1] = str(loan)
	ctx.frees[2] = ""
	ctx.frees[3] = str(savings)


static func bank_menu_conversation(species: StringName = &"") -> DialogueData:
	var imported: DialogueData = DialogueCatalog.conversation(
		StringName("msg_%d" % (11746 + PostDisplay.draw_type(species)))
	)
	var menu: DialogueData = DialogueCatalog.conversation(PostDisplay.BANK_MENU_ID)
	if menu != null:
		return menu
	if imported != null:
		return imported
	return DialogueCatalog.conversation(PostDisplay.DEPOSIT_AMOUNT_ID)


static func send_mail_conversation() -> DialogueData:
	return _mail_pick_conversation(
		PostDisplay.SEND_MAIL_ID,
		"Which letter should we mail?",
		"send_mail",
		true
	)


static func save_mail_conversation() -> DialogueData:
	return _mail_pick_conversation(
		PostDisplay.SAVE_MAIL_ID,
		"Which letter should we keep?",
		"save_mail",
		false
	)


## Hand dug fossils to the desk for the Farway Museum. One choice per stack quantity.
static func farway_send_conversation() -> DialogueData:
	var have: int = Game.inventory.count_of(&"fossil") if Game != null and Game.inventory != null else 0
	var nodes := {
		"ask": {"type": "choice", "prompt": "How many fossils shall we send?", "options": []},
		"done": {"type": "line", "text": "Off they go! Watch your\nmailbox tomorrow."},
		"cancel": {"type": "line", "text": "No trouble. Come back with\nthem any time."},
		"empty": {"type": "line", "text": "You've no fossils on you to\nsend just now."},
	}
	if have <= 0:
		return DialogueData.from_dict(
			{"id": "post_farway", "speaker_id": "post_girl", "start": "empty", "nodes": nodes}
		)
	var options: Array = []
	for n: int in [1, 3, 5, have]:
		var count: int = mini(n, have)
		if count <= 0 or options.any(func(o: Dictionary) -> bool: return int(o.get("count", 0)) == count):
			continue
		var node_id := "send_%d" % count
		options.append({"text": "%d" % count, "count": count, "goto": node_id})
		nodes[node_id] = {
			"type": "event",
			"events": [{"op": "farway_send", "count": count}],
			"next": "done",
		}
	options.append({"text": "Never mind...", "goto": "cancel"})
	nodes["ask"]["options"] = options
	return DialogueData.from_dict(
		{"id": "post_farway", "speaker_id": "post_girl", "start": "ask", "nodes": nodes}
	)


static func write_letter_conversation() -> DialogueData:
	var options: Array = []
	var nodes := {
		"ask": {"type": "choice", "prompt": "Who is this letter for?", "options": options},
		"done": {"type": "line", "text": "All written! Check your Letters page."},
		"cancel": {"type": "line", "text": "Maybe later."},
	}
	var i: int = 0
	for entry: Dictionary in recipient_candidates():
		var node_id := "to_%d" % i
		options.append({"text": str(entry.get("name", "Villager")), "goto": node_id})
		nodes[node_id] = {
			"type": "event",
			"events": [{"op": "write_letter", "to": String(entry.get("id", "")), "body": 0}],
			"next": "done",
		}
		i += 1
		if i >= 6:
			break
	options.append({"text": "Never mind...", "goto": "cancel"})
	return DialogueData.from_dict(
		{"id": String(PostDisplay.WRITE_LETTER_ID), "speaker_id": "player", "start": "ask", "nodes": nodes}
	)


static func _mail_pick_conversation(
	conv_id: StringName, prompt: String, op: String, sendable_only: bool
) -> DialogueData:
	var options: Array = []
	var nodes := {
		"ask": {"type": "choice", "prompt": prompt, "options": options},
		"done": {"type": "line", "text": "All set!"},
		"cancel": {"type": "line", "text": "Oh, really? Come back\nanytime."},
		"empty": {"type": "line", "text": "You don't have a letter for that."},
	}
	var inv: Inventory = Game.inventory if Game != null else null
	var indices: Array[int] = []
	if inv != null:
		if sendable_only:
			indices = inv.sendable_mail_indices()
		else:
			for i: int in Inventory.MAIL_SLOTS:
				var mail: MailData = inv.mail_at(i)
				if mail != null and not mail.is_empty():
					indices.append(i)
	if indices.is_empty():
		return DialogueData.from_dict(
			{
				"id": String(conv_id),
				"speaker_id": "post_girl",
				"start": "empty",
				"nodes": nodes,
			}
		)
	for index: int in indices:
		var mail: MailData = inv.mail_at(index)
		var node_id := "m_%d" % index
		options.append({"text": mail.label(), "goto": node_id})
		nodes[node_id] = {
			"type": "event",
			"events": [{"op": op, "index": index}],
			"next": "done",
		}
	options.append({"text": "Never mind...", "goto": "cancel"})
	return DialogueData.from_dict(
		{"id": String(conv_id), "speaker_id": "post_girl", "start": "ask", "nodes": nodes}
	)


static func _refresh_mail_piles() -> void:
	if Game == null or Game.get_tree() == null:
		return
	var interior: Node = Game.get_tree().get_first_node_in_group("interior")
	if interior != null and interior.has_method("refresh_public_set"):
		interior.call("refresh_public_set")
