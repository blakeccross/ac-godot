class_name MuseumDialogue
extends RefCounted

## Builds Blathers' donation conversation at runtime (`ac_npc_curator` donate branches).
## One flow: pick a pocket item -> examine + species trivia -> commit -> completion
## fanfare -> "anything else?". Rejections (dupe / not-collected / forgery / raw fossil)
## route straight to their own node. Trivia text is spliced from `blathers_trivia` so a
## local verbatim bank overrides it transparently.

const CONV_ID := &"blathers_donate"
const TRIVIA_ID := &"blathers_trivia"

## `{op:"museum_menu"}` choices Blathers' scene node listens for after the talk closes.
const AGAIN_EVENT := {"op": "museum_menu", "choice": "donate_again"}


## `preselect` jumps straight to that pocket item's outcome (pocket DONATE interaction).
static func build_donate(preselect: StringName = &"") -> DialogueData:
	var inv: Inventory = Game.inventory if Game != null else null
	var book: MuseumBook = Game.museum if Game != null else null
	var nodes: Dictionary = _static_nodes()
	var options: Array = []
	var start_id := "ask"
	var seen: Dictionary = {}
	if inv != null and book != null:
		for slot_i: int in Inventory.POCKET_SLOTS:
			var slot: InventorySlot = inv.slot_at(slot_i)
			if slot == null or slot.is_empty():
				continue
			var item_id: StringName = slot.item.item_id
			if seen.has(item_id):
				continue
			seen[item_id] = true
			var data: ItemData = ItemCatalog.get_item(item_id)
			if data == null or not _is_offerable(data):
				continue
			var node_id := "pick_%s" % String(item_id)
			_add_item_branch(nodes, node_id, data, book)
			options.append({"text": data.display_name, "goto": node_id})
			if preselect != &"" and item_id == preselect:
				start_id = node_id
	if options.is_empty() and start_id == "ask":
		start_id = "nothing"
	options.append({"text": "Nothing right now.", "goto": "cancel"})
	nodes["ask"]["options"] = options
	return DialogueData.from_dict(
		{"id": String(CONV_ID), "speaker_id": "blathers", "start": start_id, "nodes": nodes}
	)


## Blathers' spoken response to the item the player just picked in the donate-select
## pockets. `result` is `Game.donate_museum_result` (commit already applied on `ok`).
static func build_outcome(item_id: StringName, result: Dictionary) -> DialogueData:
	var nodes: Dictionary = _static_nodes()
	var reason := String(result.get("reason", ""))
	var category := int(result.get("category", -1))
	var start_id := "thanks_one"
	match reason:
		"generic_fossil":
			start_id = "farway"
		"forgery":
			start_id = "forgery"
		"already_donated":
			start_id = _dupe_node(category)
		"ok":
			var data: ItemData = ItemCatalog.get_item(item_id)
			var index := int(result.get("index", -1))
			nodes["outcome_ex"] = {
				"type": "line",
				"text": _examine_line(data, category) if data != null else "Hoo! Splendid.",
				"next": "outcome_tr",
			}
			nodes["outcome_tr"] = {
				"type": "line",
				"text": _trivia_text(data, category, index) if data != null else "A fine addition, hoo.",
				"next": _completion_node(result),
			}
			start_id = "outcome_ex"
		_:
			start_id = "decline"
	return DialogueData.from_dict(
		{"id": String(CONV_ID), "speaker_id": "blathers", "start": start_id, "nodes": nodes}
	)


## Which fanfare / lecture / plain-thanks node a successful donation lands on.
static func _completion_node(result: Dictionary) -> String:
	if bool(result.get("completed_museum", false)):
		return "fanfare_museum"
	if bool(result.get("completed_collection", false)):
		return "fanfare_collection"
	if bool(result.get("completed_set", false)):
		var gi: int = MuseumDisplay.FOSSIL_SET_NAMES.find(String(result.get("set_name", "")))
		if gi >= 0:
			return "lecture_%d" % gi
	return "thanks_one"


## Items worth offering to Blathers — museum categories plus the raw dug fossil.
static func is_offerable(data: ItemData) -> bool:
	return _is_offerable(data)


static func _is_offerable(data: ItemData) -> bool:
	if data.id == &"fossil":
		return true
	if data is FishData or data is BugData:
		return true
	if data is FurnitureData:
		var cat: int = int(MuseumDisplay.map_item(data).get("category", -1))
		return cat == MuseumDisplay.Category.FOSSIL or cat == MuseumDisplay.Category.ART
	return not MuseumDisplay.map_item(data).is_empty()


static func _add_item_branch(nodes: Dictionary, node_id: String, data: ItemData, book: MuseumBook) -> void:
	var item_id: StringName = data.id
	if item_id == &"fossil":
		nodes[node_id] = {"type": "branch", "when": [{"goto": "farway"}]}
		return
	var mapped: Dictionary = MuseumDisplay.map_item(data)
	var category: int = int(mapped.get("category", -1))
	var index: int = int(mapped.get("index", -1))
	if _is_forgery(data, category, index):
		nodes[node_id] = {"type": "branch", "when": [{"goto": "forgery"}]}
		return
	match book.display_info_for_item(data):
		MuseumBook.DisplayInfo.CANNOT_DONATE:
			nodes[node_id] = {"type": "branch", "when": [{"goto": "decline"}]}
			return
		MuseumBook.DisplayInfo.ALREADY_DONATED:
			nodes[node_id] = {"type": "branch", "when": [{"goto": _dupe_node(category)}]}
			return
		_:
			pass
	## CAN_DONATE: examine -> trivia -> commit -> completion check -> again.
	var examine_id := "%s_ex" % node_id
	var trivia_id := "%s_tr" % node_id
	var commit_id := "%s_cm" % node_id
	var result_id := "%s_rs" % node_id
	nodes[node_id] = {"type": "branch", "when": [{"goto": examine_id}]}
	nodes[examine_id] = {"type": "line", "text": _examine_line(data, category), "next": trivia_id}
	nodes[trivia_id] = {"type": "line", "text": _trivia_text(data, category, index), "next": commit_id}
	nodes[commit_id] = {
		"type": "event",
		"events": [{"op": "donate_commit", "item": String(item_id)}],
		"next": result_id,
	}
	var when: Array = [
		{"if": {"var_eq": {"name": "donate_completed_museum", "value": "yes"}}, "goto": "fanfare_museum"},
		{"if": {"var_eq": {"name": "donate_completed_collection", "value": "yes"}}, "goto": "fanfare_collection"},
	]
	for gi: int in MuseumDisplay.FOSSIL_SET_NAMES.size():
		var set_name: String = MuseumDisplay.FOSSIL_SET_NAMES[gi]
		when.append({
			"if": {"var_eq": {"name": "donate_set_name", "value": set_name}},
			"goto": "lecture_%d" % gi,
		})
	when.append({"goto": "thanks_one"})
	nodes[result_id] = {"type": "branch", "when": when}


static func _dupe_node(category: int) -> String:
	match category:
		MuseumDisplay.Category.FISH:
			return "dupe_fish"
		MuseumDisplay.Category.INSECT:
			return "dupe_bug"
		MuseumDisplay.Category.ART:
			return "dupe_art"
		_:
			return "dupe_fossil"


static func _is_forgery(data: ItemData, category: int, index: int) -> bool:
	if String(data.id).begins_with("art_forgery"):
		return true
	return category == MuseumDisplay.Category.ART and index in MuseumBook.FORGERY_ART_INDICES


## Nodes that never change between builds (rejections, fanfares, loop).
static func _static_nodes() -> Dictionary:
	var bank: DialogueData = DialogueCatalog.conversation(TRIVIA_ID)
	var nodes: Dictionary = {
		"ask": {
			"type": "choice",
			"prompt": "Hoo! And what have you\nbrought to show me?",
			"options": [],
		},
		"nothing": {
			"type": "line",
			"text": "Ah — nothing on you for us\njust now? Not to worry.\nDo keep us in mind.",
		},
		"cancel": {
			"type": "line",
			"text": "Very good. The wings are\nthrough the far doors\nwhenever you wish.",
		},
		"farway": {
			"type": "line",
			"text": "Hoo! An unexamined fossil!\nMy heart flutters. But I've\nno certification to name it\n— post it to the Farway\nMuseum and they'll write\nback with its identity.",
			"next": "farway_2",
		},
		"farway_2": {
			"type": "line",
			"text": "One more thing: do NOT\nre-bury a fossil once dug.\nIt muddles their records\nterribly. Keep it in your\npockets or your home.",
			"next": "again",
		},
		"forgery": {
			"type": "line",
			"text": "Hoo now... I'm quite sure\nwe already hold this piece.\nWhich means one of the two\nis a forgery. Best I not\nlook into which. Do take\nit back, hm?",
			"next": "again",
		},
		"decline": {
			"type": "line",
			"text": "Hmm. A fine thing, but not\none we collect. We keep to\nfour fields only: fossils,\npaintings, fish, and insects.",
			"next": "again",
		},
		"dupe_fish": {
			"type": "line",
			"text": "Hoo — we already have this\nfish on display. A splendid\nspecimen. And no, I shan't\neat it; I find fish rather\ntoo fishy. Do take it back.",
			"next": "again",
		},
		"dupe_bug": {
			"type": "line",
			"text": "Hoo NO! We already hold\none of those, and one is\nquite enough! Do not let\nit out in here — insects\nare released OUT of doors!\nPut it away, I beg you!",
			"next": "again",
		},
		"dupe_art": {
			"type": "line",
			"text": "Hoo — this masterpiece is\nalready hanging in our\ngallery. A magnificent work,\nbut I must return this one\nto you.",
			"next": "again",
		},
		"dupe_fossil": {
			"type": "line",
			"text": "Ah — this fossil is already\npart of the collection.\nSpace is limited, alas, so\nI must hand it back.",
			"next": "again",
		},
		"fanfare_museum": {
			"type": "line",
			"text": "Hoo! HOO, I say! Every\nwing full, every collection\ncomplete! A museum to\nrival any in the world.\nI am simply erupting\nwith pride!",
			"next": "again",
		},
		"fanfare_collection": {
			"type": "line",
			"text": "Wait — could it be? Yes!\nThat completes an entire\ncollection! Huzzah! A fine\nday for the museum, and\nfor {town}.",
			"next": "again",
		},
		"thanks_one": {
			"type": "line",
			"text": "You have our deepest\ngratitude. It will be on\ndisplay in the wing.",
			"next": "again",
		},
		"again": {
			"type": "choice",
			"prompt": "Is there anything else\nyou'd care to donate?",
			"options": [
				{"text": "Yes, one more.", "events": [AGAIN_EVENT]},
				{"text": "That's all for now.", "goto": "thanks_all"},
			],
		},
		"thanks_all": {
			"type": "line",
			"text": "Your support means the\nworld to us. Truly. Do\nvisit the wings, hm?",
		},
	}
	## Per-skeleton completion lectures, spliced from the trivia bank when present.
	for gi: int in MuseumDisplay.FOSSIL_SET_NAMES.size():
		var lecture: String = _bank_text(bank, "set_%d" % gi)
		if lecture == "":
			lecture = (
				"And that completes the\n%s! A triumph — it will\nbe assembled in the hall\nat once, hoo."
				% MuseumDisplay.FOSSIL_SET_NAMES[gi]
			)
		nodes["lecture_%d" % gi] = {"type": "line", "text": lecture, "next": "again"}
	## Let the bank override the fanfares too.
	var museum_full: String = _bank_text(bank, "museum_complete")
	if museum_full != "":
		nodes["fanfare_museum"]["text"] = museum_full
	var collection_full: String = _bank_text(bank, "collection_complete")
	if collection_full != "":
		nodes["fanfare_collection"]["text"] = collection_full
	return nodes


static func _bank_text(bank: DialogueData, key: String) -> String:
	if bank == null:
		return ""
	var node: Dictionary = bank.node(StringName(key))
	return String(node.get("text", "")) if not node.is_empty() else ""


static func _examine_line(data: ItemData, category: int) -> String:
	match category:
		MuseumDisplay.Category.FOSSIL:
			return "Hoo! A genuine %s!\nMy word... breathtaking." % data.display_name
		MuseumDisplay.Category.ART:
			return "Hoo my! So this is\n%s.\nThe original, at last." % data.display_name
		MuseumDisplay.Category.FISH:
			return "Hoo! A fine %s.\nWe'll take good care of it." % data.display_name
		MuseumDisplay.Category.INSECT:
			return "Hoo... a %s.\nYes. Well. Quite." % data.display_name
	return "Hoo! A %s." % data.display_name


## Trivia spliced from the `blathers_trivia` bank (authored or locally overridden).
static func _trivia_text(data: ItemData, category: int, index: int) -> String:
	var key := _trivia_key(data, category, index)
	var bank: DialogueData = DialogueCatalog.conversation(TRIVIA_ID)
	if bank != null:
		for candidate: String in [key, _trivia_fallback_key(category)]:
			var node: Dictionary = bank.node(StringName(candidate))
			if not node.is_empty() and String(node.get("text", "")) != "":
				return String(node["text"])
	return "A worthy addition to the\ncollection, hoo."


static func _trivia_key(data: ItemData, category: int, index: int) -> String:
	match category:
		MuseumDisplay.Category.FISH:
			return "fish_%s" % String(data.id)
		MuseumDisplay.Category.INSECT:
			return "bug_%s" % String(data.id)
		MuseumDisplay.Category.FOSSIL:
			return "fossil_%d" % index
		MuseumDisplay.Category.ART:
			return "art_%d" % index
	return "generic"


static func _trivia_fallback_key(category: int) -> String:
	match category:
		MuseumDisplay.Category.FISH:
			return "examine_fish"
		MuseumDisplay.Category.INSECT:
			return "examine_bug"
		MuseumDisplay.Category.FOSSIL:
			return "examine_fossil"
		MuseumDisplay.Category.ART:
			return "examine_art"
	return "generic"
