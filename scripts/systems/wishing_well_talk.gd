class_name WishingWellTalk
extends BankTalk

## The wishing well (`ac_shrine`, `aSHR_talk`). `MSG_4388` asks the errand:
##
## - "How are things?" — the town assessment (`mFAs_GetFieldRank_Condition`): the problem it
##   finds, with the acre to look at (`0x2C4F` trash, `0x2C45` too few trees, `0x2C46` too
##   many, `0x2C47` weeds), else a line by rank (`0x2C4E − rank`), or at rank 6 after fifteen
##   perfect days, `0x2C50` and the spirit with the golden axe (`aSHR_ACTION_MAKE_HEM`).
## - "Apologize" — throw a quest item you cannot deliver into the well (`aSHR_talk_gomen`):
##   kept if its owner or recipient still lives here (`0x1129` / `0x112A`), else gone (`0x112B`).

const MSG_ASK := 4388
const MSG_NOTHING_TO_APOLOGIZE := 0x1127
const MSG_CHOOSE := 0x1128
const MSG_STILL_WAITED_FOR := 0x1129
const MSG_RETURN_IT := 0x112A
const MSG_APOLOGIZED := 0x112B
const MSG_TREE_LESS := 0x2C45
const MSG_TREE_OVER := 0x2C46
const MSG_GRASS_OVER := 0x2C47
const MSG_RANK_BASE := 0x2C4E
const MSG_DUST_OVER := 0x2C4F
const MSG_GOLDEN_AXE := 0x2C50
## `choume_str`: acre rows are lettered A–F from the north.
const ROWS := "QABCDEF"

var world: Node
var inventory: Inventory
var rng: RandomNumberGenerator
## Set when the talk ends on `0x2C50`: the well calls up the spirit.
var summon_spirit: bool = false


func _init(p_world: Node, p_inventory: Inventory, p_rng: RandomNumberGenerator = null) -> void:
	world = p_world
	inventory = p_inventory
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()


func start_msg() -> int:
	return MSG_ASK


func picked(msg_no: int, index: int) -> int:
	if msg_no != MSG_ASK:
		return -1
	match index:
		0:
			return _how_are_things()
		1:
			return MSG_NOTHING_TO_APOLOGIZE
	return -1


## "Apologize" with something to apologize for: the pockets open, quest items only
## (`mSM_IV_OPEN_SHRINE`).
func pick_step(msg_no: int, index: int) -> Dictionary:
	if msg_no == MSG_ASK and index == 1 and _has_quest_items():
		return {"hand": {"pocket": -1, "mode": "shrine"}}
	return {}


func hand_result(item: StringName, pocket: int = -1) -> Dictionary:
	if item == &"" or pocket < 0 or inventory == null:
		return {}
	var tags: Dictionary = Game.quests.to_from_for_pocket(inventory, pocket) if Game.quests != null else {}
	if not tags.is_empty():
		if Game.residents != null and Game.residents.has_resident(StringName(str(tags.get("to", "")))):
			return {"msg": MSG_STILL_WAITED_FOR}
		if Game.residents != null and Game.residents.has_resident(StringName(str(tags.get("from", "")))):
			return {"msg": MSG_RETURN_IT}
	elif Game.first_job != null and Game.first_job.is_active():
		return {"msg": MSG_RETURN_IT}
	var data: ItemData = ItemCatalog.get_item(item)
	if context != null:
		context.frees = PackedStringArray([data.display_name if data != null else String(item)])
	if Game.quests != null:
		Game.quests.clear_by_pocket(inventory, pocket)
	inventory.remove_from_slot(pocket, 1)
	return {"msg": MSG_APOLOGIZED}


func _how_are_things() -> int:
	var result: Dictionary = Game.rate_town(world, rng, true)
	var rank: int = int(result["rank"])
	var condition: int = int(result["condition"])
	if (
		rank == TownAssessment.RANK_PERFECT
		and Game.perfect_town_long_enough()
		and not Game.golden_axe_got
		and inventory != null and inventory.has_space(1)
		and not (Game.first_job != null and Game.first_job.is_active())
		and condition != TownAssessment.Condition.DUST_OVER
	):
		summon_spirit = true
		return MSG_GOLDEN_AXE
	if condition == TownAssessment.Condition.NO_CASE:
		return MSG_RANK_BASE - rank
	var block: Vector2i = result["block"]
	if context != null:
		context.frees = PackedStringArray([ROWS.substr(clampi(block.y, 0, 6), 1), str(block.x)])
	match condition:
		TownAssessment.Condition.DUST_OVER:
			return MSG_DUST_OVER
		TownAssessment.Condition.TREE_LESS:
			return MSG_TREE_LESS
		TownAssessment.Condition.TREE_OVER:
			return MSG_TREE_OVER
	return MSG_GRASS_OVER


func _has_quest_items() -> bool:
	if inventory == null:
		return false
	for i: int in Inventory.POCKET_SLOTS:
		var s: InventorySlot = inventory.slot_at(i)
		if s != null and not s.is_empty() and s.item.condition == InventoryItem.Condition.QUEST:
			return true
	return false
