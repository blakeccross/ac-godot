class_name FirstJob
extends RefCounted

## Part-time job after the house (`mQst` FIRSTJOB + `ac_npc_rcn_guide2`).
## Full chore chain: cloth → plant → [hello] → furniture → letter → open →
## carpet → axe → notice → done.

signal changed

enum Kind {
	NONE,
	START,
	CHANGE_CLOTH,
	PLANT_FLOWER,
	INTRODUCTIONS,
	DELIVER_FTR,
	SEND_LETTER,
	OPEN,
	DELIVER_CARPET,
	DELIVER_AXE,
	POST_NOTICE,
	SEND_LETTER2,
	DELIVER_AXE2,
	DONE,
}

## `ITM_CLOTH016` work uniform.
const UNIFORM_ID := &"shirt_016"
## Default worn shirt (`ITM_CLOTH001` male starter table).
const DEFAULT_CLOTH_ID := &"shirt_001"
## Plant kit sizes (`aNRG2_set_possession` JOB2).
const PLANT_FLOWER_COUNT := 7
const PLANT_SAPLING_COUNT := 3
## Delivery / stationery stand-ins for decomp items.
const FURNITURE_ID := &"wood_chair"
const CARPET_ID := &"floor_tile"
const AXE_ID := &"axe"
const PAPER_ID := &"paper"
## Assign / hint lines for named-recipient chores — must include `{recipient}`.
const DIALOGUE_FURNITURE := &"nook_job_furniture"
const DIALOGUE_FURNITURE_HINT := &"nook_job_furniture_hint"
const DIALOGUE_LETTER := &"nook_job_letter"
const DIALOGUE_LETTER_HINT := &"nook_job_letter_hint"
const DIALOGUE_CARPET := &"nook_job_carpet"
const DIALOGUE_CARPET_HINT := &"nook_job_carpet_hint"
const DIALOGUE_AXE := &"nook_job_axe"
const DIALOGUE_AXE_HINT := &"nook_job_axe_hint"
## Progress: 0 finished, 2 active, 3 letter mailed (`mQst_base_c.progress`).
const PROGRESS_DONE := 0
const PROGRESS_ACTIVE := 2
const PROGRESS_LETTER_MAILED := 3

var kind: Kind = Kind.NONE
var progress: int = 0
var wrong_cloth: bool = false
## `Common_Get(quest).work` — force-greet once per shop visit.
var shop_greeted: bool = false
## Current delivery / letter target (`mQst_errand_c.recipient`).
var recipient_id: StringName = &""
## Item expected for the active delivery chore.
var item_id: StringName = &""
## Villagers already used: [0]=furniture, [1]=letter/axe (`used_ids`).
var used_ids: Array[StringName] = []
## Tortimer / Soncho arbeit trophy (`mSC_SPECIAL_EVENT_ARBEIT`).
var tortimer_met: bool = false
## `mEv_SAVED_FJOPENQUEST` — normal villager quest talk unlocked mid-job.
var open_quest: bool = false


func is_active() -> bool:
	return kind != Kind.NONE and kind != Kind.DONE


func begin_after_house() -> void:
	## `mQst_SetFirstJobStart` after Nook EXIT (`aID_retire_rcn_guide_wait`).
	kind = Kind.START
	progress = 0
	wrong_cloth = false
	shop_greeted = false
	recipient_id = &""
	item_id = &""
	used_ids.clear()
	tortimer_met = false
	open_quest = false
	changed.emit()


func clear() -> void:
	kind = Kind.NONE
	progress = 0
	wrong_cloth = false
	shop_greeted = false
	recipient_id = &""
	item_id = &""
	used_ids.clear()
	tortimer_met = false
	open_quest = false
	changed.emit()


func finish() -> void:
	## `mEv_UnSetFirstJob` + clear errand when chores end.
	kind = Kind.DONE
	progress = 0
	wrong_cloth = false
	shop_greeted = false
	recipient_id = &""
	item_id = &""
	open_quest = false
	changed.emit()


func reset_shop_visit() -> void:
	shop_greeted = false


func wearing_uniform(cloth_id: StringName) -> bool:
	return cloth_id == UNIFORM_ID


func tick_cloth(cloth_id: StringName) -> void:
	## `aQMgr_move_own_errand_cloth`: progress 2→0 when worn; 0→2 if changed out.
	if kind != Kind.CHANGE_CLOTH:
		if is_active() and kind > Kind.CHANGE_CLOTH and not wrong_cloth:
			if not wearing_uniform(cloth_id):
				wrong_cloth = true
				changed.emit()
		return
	var next: int = progress
	match progress:
		PROGRESS_ACTIVE:
			if wearing_uniform(cloth_id):
				next = PROGRESS_DONE
		PROGRESS_DONE:
			if not wearing_uniform(cloth_id):
				next = PROGRESS_ACTIVE
	if next != progress:
		progress = next
		changed.emit()


func cloth_job_finished() -> bool:
	return kind == Kind.CHANGE_CLOTH and progress == PROGRESS_DONE


func plant_job_finished(inventory: Inventory) -> bool:
	if kind != Kind.PLANT_FLOWER or progress != PROGRESS_ACTIVE or inventory == null:
		return false
	return not _pockets_have_plant(inventory)


func mark_plant_finished() -> void:
	if kind == Kind.PLANT_FLOWER and progress == PROGRESS_ACTIVE:
		progress = PROGRESS_DONE
		changed.emit()


func chore_finished() -> bool:
	return is_active() and progress == PROGRESS_DONE and kind != Kind.START


func mark_met_tortimer() -> void:
	if tortimer_met:
		return
	tortimer_met = true
	_tick_introductions()
	changed.emit()


func note_villager_talked(villager_id: StringName) -> void:
	## Introductions + OPEN finish checks run off talk.
	if villager_id == &"":
		return
	if kind == Kind.INTRODUCTIONS and progress == PROGRESS_ACTIVE:
		_tick_introductions()
	elif kind == Kind.OPEN and progress == PROGRESS_ACTIVE:
		mark_open_finished()


func mark_open_finished() -> void:
	if kind == Kind.OPEN and progress == PROGRESS_ACTIVE:
		progress = PROGRESS_DONE
		changed.emit()


func mark_notice_posted() -> void:
	if kind == Kind.POST_NOTICE and progress == PROGRESS_ACTIVE:
		progress = PROGRESS_DONE
		changed.emit()


func note_letter_mailed(to_id: StringName) -> void:
	## Mail path sets progress 3; quest manager then 3→0 when letter exists.
	if not _is_letter_kind() or progress != PROGRESS_ACTIVE:
		return
	if to_id == &"" or to_id != recipient_id:
		return
	progress = PROGRESS_LETTER_MAILED
	changed.emit()
	## Immediate finish (`aQMgr_move_own_errand_letter` when letter_info.exists).
	progress = PROGRESS_DONE
	changed.emit()


func try_deliver_to(villager_id: StringName, inventory: Inventory) -> bool:
	## Hand QUEST delivery item to the errand recipient.
	if inventory == null or villager_id == &"" or villager_id != recipient_id:
		return false
	if not _is_delivery_kind() or progress != PROGRESS_ACTIVE:
		return false
	if item_id == &"" or not _remove_quest_item(inventory, item_id):
		return false
	progress = PROGRESS_DONE
	changed.emit()
	return true


func can_deliver_to(villager_id: StringName, inventory: Inventory) -> bool:
	if inventory == null or villager_id == &"" or villager_id != recipient_id:
		return false
	if not _is_delivery_kind() or progress != PROGRESS_ACTIVE:
		return false
	return _has_quest_item(inventory, item_id)


func needs_introductions() -> bool:
	## Insert hello job unless every resident is met and Tortimer is known.
	return not (intros_complete() and tortimer_met)


func intros_complete() -> bool:
	if not tortimer_met:
		return false
	var ids: Array[StringName] = resident_ids()
	if ids.is_empty():
		return false
	if Game == null or Game.relationships == null:
		return false
	for id: StringName in ids:
		var bond: Relationship = Game.relationships.get_or_create(id)
		if bond == null or bond.talk_count <= 0:
			return false
	return true


func setup_change_cloth() -> void:
	kind = Kind.CHANGE_CLOTH
	progress = PROGRESS_ACTIVE
	recipient_id = &""
	item_id = &""
	changed.emit()


func setup_plant_flower() -> void:
	kind = Kind.PLANT_FLOWER
	progress = PROGRESS_ACTIVE
	recipient_id = &""
	item_id = &""
	changed.emit()


func setup_introductions() -> void:
	kind = Kind.INTRODUCTIONS
	progress = PROGRESS_ACTIVE
	recipient_id = &""
	item_id = &""
	changed.emit()
	_tick_introductions()


func setup_deliver_furniture(inventory: Inventory) -> bool:
	var target: StringName = _pick_unused_resident([])
	if target == &"":
		return false
	if not _give_quest_item(inventory, FURNITURE_ID):
		return false
	kind = Kind.DELIVER_FTR
	progress = PROGRESS_ACTIVE
	recipient_id = target
	item_id = FURNITURE_ID
	_remember_used(0, target)
	changed.emit()
	return true


func setup_send_letter(inventory: Inventory, letter2: bool = false) -> bool:
	var exclude: Array[StringName] = []
	if used_ids.size() > 0 and used_ids[0] != &"":
		exclude.append(used_ids[0])
	var target: StringName = _pick_unused_resident(exclude)
	if target == &"":
		return false
	if not give_paper(inventory):
		return false
	kind = Kind.SEND_LETTER2 if letter2 else Kind.SEND_LETTER
	progress = PROGRESS_ACTIVE
	recipient_id = target
	item_id = PAPER_ID
	_remember_used(1, target)
	changed.emit()
	return true


func setup_open_quest() -> void:
	kind = Kind.OPEN
	progress = PROGRESS_ACTIVE
	recipient_id = &""
	item_id = &""
	open_quest = true
	changed.emit()


func setup_deliver_carpet(inventory: Inventory) -> bool:
	var target: StringName = _pick_unused_resident(used_ids.duplicate())
	if target == &"":
		## Fall back to any resident if town is tiny.
		target = _pick_unused_resident([])
	if target == &"":
		return false
	if not _give_quest_item(inventory, CARPET_ID):
		return false
	kind = Kind.DELIVER_CARPET
	progress = PROGRESS_ACTIVE
	recipient_id = target
	item_id = CARPET_ID
	changed.emit()
	return true


func setup_deliver_axe(inventory: Inventory, axe2: bool = false) -> bool:
	var target: StringName = &""
	if used_ids.size() > 1:
		target = used_ids[1]
	if target == &"":
		target = _pick_unused_resident([])
	if target == &"":
		return false
	if not _give_quest_item(inventory, AXE_ID):
		return false
	kind = Kind.DELIVER_AXE2 if axe2 else Kind.DELIVER_AXE
	progress = PROGRESS_ACTIVE
	recipient_id = target
	item_id = AXE_ID
	changed.emit()
	return true


func setup_post_notice() -> void:
	kind = Kind.POST_NOTICE
	progress = PROGRESS_ACTIVE
	recipient_id = &""
	item_id = &""
	changed.emit()


func advance_after_finished(inventory: Inventory) -> bool:
	## `next_job_no` after a finished chore. False if pockets block the next handoff.
	if not chore_finished():
		return false
	match kind:
		Kind.CHANGE_CLOTH:
			if not can_start_plant(inventory):
				return false
			setup_plant_flower()
			give_plant_kit(inventory)
		Kind.PLANT_FLOWER:
			if needs_introductions():
				setup_introductions()
			else:
				if not can_start_delivery(inventory):
					return false
				if not setup_deliver_furniture(inventory):
					return false
		Kind.INTRODUCTIONS:
			if not can_start_delivery(inventory):
				return false
			if not setup_deliver_furniture(inventory):
				return false
		Kind.DELIVER_FTR:
			if Game != null:
				Game.unlock_map()
			if not can_start_delivery(inventory):
				return false
			if not setup_send_letter(inventory):
				return false
		Kind.SEND_LETTER:
			setup_open_quest()
		Kind.SEND_LETTER2:
			if not can_start_delivery(inventory):
				return false
			if not setup_deliver_axe(inventory, true):
				return false
		Kind.OPEN:
			if not can_start_delivery(inventory):
				return false
			if not setup_deliver_carpet(inventory):
				return false
		Kind.DELIVER_CARPET:
			if not can_start_delivery(inventory):
				return false
			if not setup_deliver_axe(inventory):
				return false
		Kind.DELIVER_AXE, Kind.DELIVER_AXE2:
			setup_post_notice()
		Kind.POST_NOTICE:
			finish()
		_:
			return false
	return true


func give_uniform(inventory: Inventory) -> bool:
	if inventory == null:
		return false
	var item: ItemData = ItemCatalog.get_item(UNIFORM_ID)
	if item == null:
		return false
	if inventory.count_of(UNIFORM_ID) > 0:
		return true
	return inventory.add(item, 1) == 0


func give_plant_kit(inventory: Inventory) -> bool:
	if inventory == null:
		return false
	var flower: ItemData = ItemCatalog.get_item(&"flower")
	var sapling: ItemData = ItemCatalog.get_item(&"apple_sapling")
	if flower == null or sapling == null:
		return false
	if inventory.empty_slot_count() < _plant_slots_needed(flower, sapling):
		return false
	if inventory.add(flower, PLANT_FLOWER_COUNT) != 0:
		return false
	if inventory.add(sapling, PLANT_SAPLING_COUNT) != 0:
		return false
	return true


func give_paper(inventory: Inventory) -> bool:
	if inventory == null:
		return false
	var item: ItemData = ItemCatalog.get_item(PAPER_ID)
	if item == null:
		return false
	if inventory.count_of(PAPER_ID) > 0:
		return true
	return inventory.add(item, 1) == 0


func can_start_change_cloth(inventory: Inventory) -> bool:
	return inventory != null and inventory.empty_slot_count() > 0


func can_start_plant(inventory: Inventory) -> bool:
	if inventory == null:
		return false
	var flower: ItemData = ItemCatalog.get_item(&"flower")
	var sapling: ItemData = ItemCatalog.get_item(&"apple_sapling")
	if flower == null or sapling == null:
		return false
	return inventory.empty_slot_count() >= _plant_slots_needed(flower, sapling)


func can_start_delivery(inventory: Inventory) -> bool:
	return inventory != null and inventory.empty_slot_count() > 0


func gift_display_item() -> StringName:
	## Prop shown during Nook → player hand-over for the active chore.
	match kind:
		Kind.CHANGE_CLOTH:
			return UNIFORM_ID
		Kind.PLANT_FLOWER:
			return &"flower"
		Kind.DELIVER_FTR, Kind.DELIVER_CARPET, Kind.DELIVER_AXE, Kind.DELIVER_AXE2:
			return item_id
		Kind.SEND_LETTER, Kind.SEND_LETTER2:
			return PAPER_ID
		_:
			return &""


func prompt_for_kind() -> String:
	match kind:
		Kind.START:
			return "Visit Tom Nook's shop"
		Kind.CHANGE_CLOTH:
			return "Wear the work uniform"
		Kind.PLANT_FLOWER:
			return "Plant trees and flowers near the shop"
		Kind.INTRODUCTIONS:
			return "Meet the villagers and Tortimer"
		Kind.DELIVER_FTR:
			return "Deliver furniture to %s" % recipient_name()
		Kind.SEND_LETTER, Kind.SEND_LETTER2:
			return "Mail a letter to %s" % recipient_name()
		Kind.OPEN:
			return "Talk to a villager about helping out"
		Kind.DELIVER_CARPET:
			return "Deliver carpet to %s" % recipient_name()
		Kind.DELIVER_AXE, Kind.DELIVER_AXE2:
			return "Deliver an axe to %s" % recipient_name()
		Kind.POST_NOTICE:
			return "Post a notice on a town sign"
		_:
			return ""


func to_save() -> Dictionary:
	var used: Array[String] = []
	for id: StringName in used_ids:
		used.append(String(id))
	return {
		"kind": int(kind),
		"progress": progress,
		"wrong_cloth": wrong_cloth,
		"recipient_id": String(recipient_id),
		"item_id": String(item_id),
		"used_ids": used,
		"tortimer_met": tortimer_met,
		"open_quest": open_quest,
	}


func from_save(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d: Dictionary = data
	var kind_i: int = clampi(int(d.get("kind", 0)), 0, int(Kind.DONE))
	kind = kind_i as Kind
	progress = clampi(int(d.get("progress", 0)), 0, PROGRESS_LETTER_MAILED)
	wrong_cloth = bool(d.get("wrong_cloth", false))
	recipient_id = StringName(str(d.get("recipient_id", "")))
	item_id = StringName(str(d.get("item_id", "")))
	tortimer_met = bool(d.get("tortimer_met", false))
	open_quest = bool(d.get("open_quest", false))
	used_ids.clear()
	var raw_used: Variant = d.get("used_ids", [])
	if typeof(raw_used) == TYPE_ARRAY:
		for entry: Variant in raw_used:
			used_ids.append(StringName(str(entry)))
	shop_greeted = false
	changed.emit()


static func resident_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var seen: Dictionary = {}
	if Game != null and Game.villagers != null:
		var snap: Dictionary = Game.villagers.to_save()
		for key: Variant in snap.keys():
			var id := StringName(str(key))
			if id == &"" or seen.has(id):
				continue
			seen[id] = true
			out.append(id)
	if out.is_empty() and Game != null:
		var world: WorldData = Game.resolve_world_data()
		if world != null:
			for b: BuildingPlacement in world.buildings:
				if b == null or b.resident_id == &"":
					continue
				if seen.has(b.resident_id):
					continue
				seen[b.resident_id] = true
				out.append(b.resident_id)
	if out.is_empty():
		for villager: VillagerData in VillagerCatalog.starters():
			if villager == null or villager.id == &"" or seen.has(villager.id):
				continue
			seen[villager.id] = true
			out.append(villager.id)
	return out


func refresh_introductions() -> void:
	_tick_introductions()


func _tick_introductions() -> void:
	if kind == Kind.INTRODUCTIONS and progress == PROGRESS_ACTIVE and intros_complete():
		progress = PROGRESS_DONE
		changed.emit()


func recipient_name() -> String:
	## Display name for the active delivery / letter target.
	if recipient_id == &"":
		return "a villager"
	var data: VillagerData = VillagerCatalog.get_villager(recipient_id)
	if data != null and data.display_name != "":
		return data.display_name
	return String(recipient_id)


func needs_named_recipient() -> bool:
	## Delivery / letter chores must name the target in assign + hint talk.
	return _is_delivery_kind() or _is_letter_kind()


static func recipient_dialogue_ids() -> Array[StringName]:
	return [
		DIALOGUE_FURNITURE,
		DIALOGUE_FURNITURE_HINT,
		DIALOGUE_LETTER,
		DIALOGUE_LETTER_HINT,
		DIALOGUE_CARPET,
		DIALOGUE_CARPET_HINT,
		DIALOGUE_AXE,
		DIALOGUE_AXE_HINT,
	]


static func dialogue_names_recipient(data: DialogueData) -> bool:
	## True when some line/prompt still has the `{recipient}` placeholder.
	if data == null:
		return false
	data.ensure_loaded()
	for nid: Variant in data.nodes.keys():
		var rec: Variant = data.nodes[nid]
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = rec
		for field: String in ["text", "prompt"]:
			if str(row.get(field, "")).contains("{recipient}"):
				return true
	return false


static func ensure_dialogue_names_recipient(
	data: DialogueData, report: bool = true
) -> DialogueData:
	## Guardrail: assign/hint graphs must name the target; replace if authored poorly.
	if dialogue_names_recipient(data):
		return data
	if report:
		var id_label: String = String(data.id) if data != null else ""
		push_error(
			"FirstJob: dialogue '%s' is missing {recipient}; using fallback line." % id_label
		)
	return DialogueData.from_dict({
		"id": "nook_job_recipient_fallback",
		"speaker_id": "tom_nook",
		"start": "start",
		"nodes": {
			"start": {
				"type": "line",
				"text": "Please take this to {recipient}.",
			},
		},
	})


func _is_delivery_kind() -> bool:
	return kind in [
		Kind.DELIVER_FTR,
		Kind.DELIVER_CARPET,
		Kind.DELIVER_AXE,
		Kind.DELIVER_AXE2,
	]


func _is_letter_kind() -> bool:
	return kind == Kind.SEND_LETTER or kind == Kind.SEND_LETTER2


func _remember_used(slot: int, id: StringName) -> void:
	while used_ids.size() <= slot:
		used_ids.append(&"")
	used_ids[slot] = id


func _pick_unused_resident(exclude: Array[StringName]) -> StringName:
	var ids: Array[StringName] = resident_ids()
	var blocked: Dictionary = {}
	for id: StringName in exclude:
		blocked[id] = true
	for id: StringName in used_ids:
		blocked[id] = true
	var choices: Array[StringName] = []
	for id: StringName in ids:
		if blocked.has(id):
			continue
		choices.append(id)
	if choices.is_empty():
		for id: StringName in ids:
			choices.append(id)
	if choices.is_empty():
		return &""
	return choices[randi() % choices.size()]


func _give_quest_item(inventory: Inventory, id: StringName) -> bool:
	if inventory == null or id == &"":
		return false
	if _has_quest_item(inventory, id):
		return true
	var item: ItemData = ItemCatalog.get_item(id)
	if item == null:
		return false
	return inventory.add(item, 1, InventoryItem.Condition.QUEST) == 0


static func _has_quest_item(inventory: Inventory, id: StringName) -> bool:
	for i: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = inventory.slot_at(i)
		if slot == null or slot.is_empty():
			continue
		if slot.item.item_id == id and slot.item.condition == InventoryItem.Condition.QUEST:
			return true
	return false


static func _remove_quest_item(inventory: Inventory, id: StringName) -> bool:
	for i: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = inventory.slot_at(i)
		if slot == null or slot.is_empty():
			continue
		if slot.item.item_id == id and slot.item.condition == InventoryItem.Condition.QUEST:
			inventory.remove_from_slot(i, 1)
			return true
	return false


static func _plant_slots_needed(flower: ItemData, sapling: ItemData) -> int:
	var flower_slots: int = ceili(
		float(PLANT_FLOWER_COUNT) / float(maxi(1, flower.max_stack))
	)
	var sapling_slots: int = ceili(
		float(PLANT_SAPLING_COUNT) / float(maxi(1, sapling.max_stack))
	)
	return flower_slots + sapling_slots


static func _pockets_have_plant(inventory: Inventory) -> bool:
	for i: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = inventory.slot_at(i)
		if slot == null or slot.is_empty():
			continue
		var data: ItemData = ItemCatalog.get_item(slot.item.item_id)
		if data != null and data.plant_id != &"":
			return true
	return false
