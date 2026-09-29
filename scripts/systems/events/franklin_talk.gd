class_name FranklinTalk
extends BankTalk

## Franklin hiding on Harvest Festival day (`ac_ev_turkey`, messages 0x3BFE–0x3C21). The
## first talk is his story (0x3BFE–0x3C01, one after another); later ones start at his
## reaction to seeing the player again (0x3C05 + present). Either way: no knife and fork in
## the pockets → a plea (0x3C02 + RANDOM(3)); with them → he takes them and hands over this
## year's present (0x3C11 + present), one of the ten harvest pieces, the rug or the wall,
## never a repeat until all twelve are given (`aETKY_DecidePresent`). Once he's talked this
## visit, he just chats (0x3C1D + 5).

const MSG_STORY := 0x3BFE
const MSG_STORY_LAST := 0x3C01
const MSG_PLEA := 0x3C02
const MSG_AGAIN := 0x3C05
const MSG_THANKS := 0x3C11
const MSG_CHAT := 0x3C1D
const FORK := &"knife_and_fork"

## `aEv_turkey_save_c.given_present_bitfield` (kept across years) and today's talk count.
var area: Dictionary = {}
var inventory: Inventory
var rng: RandomNumberGenerator
var spoke_this_visit: bool = false
var present_idx: int = 0


func _init(p_area: Dictionary, p_inventory: Inventory = null, p_rng: RandomNumberGenerator = null, p_present: int = -1) -> void:
	area = p_area
	inventory = p_inventory
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	present_idx = p_present if p_present >= 0 else decide_present(area, rng)


## The ten harvest pieces (by catalog index), then the rug and wall 66.
static func presents() -> Array[StringName]:
	var out: Array[StringName] = FtrCatalog.list("harvest_festival")
	out.append(FtrCatalog.goods_id("carpet", 66))
	out.append(FtrCatalog.goods_id("wall", 66))
	return out


## `aETKY_DecidePresent`: one not given yet; all given → start over.
static func decide_present(p_area: Dictionary, r: RandomNumberGenerator) -> int:
	var count: int = 12
	var all_bits: int = (1 << count) - 1
	var given: int = int(p_area.get("given", 0))
	if given & all_bits == all_bits:
		given = 0
		p_area["given"] = 0
	var open: Array[int] = []
	for i: int in count:
		if (given >> i) & 1 == 0:
			open.append(i)
	return open[r.randi_range(0, open.size() - 1)] if not open.is_empty() else 0


func start_msg() -> int:
	if spoke_this_visit:
		return MSG_CHAT + rng.randi_range(0, 4)
	var talks: int = int(area.get("talks", 0))
	area["talks"] = talks + 1
	return MSG_AGAIN + present_idx if talks > 0 else MSG_STORY


func next_step() -> Dictionary:
	if current_msg >= MSG_STORY and current_msg < MSG_STORY_LAST:
		return msg(current_msg + 1)
	if current_msg == MSG_STORY_LAST or current_msg == MSG_AGAIN + present_idx:
		return _fork_sequence()
	return {}


## `aETKY_SetKnifeForkSequence` → `aETKY_Give_Me_Fork` → `aETKY_Give_You_Present`.
func _fork_sequence() -> Dictionary:
	if inventory == null or inventory.count_of(FORK) == 0:
		return msg(MSG_PLEA + rng.randi_range(0, 2))
	var list: Array[StringName] = presents()
	var present: StringName = list[present_idx] if present_idx < list.size() else &""
	var data: ItemData = ItemCatalog.get_item(present)
	if context != null:
		context.set_item_str(0, PoliceTalk.with_article(data.display_name) if data != null else "")
	inventory.remove(FORK, 1)
	if data != null:
		inventory.add(data, 1)
	area["given"] = int(area.get("given", 0)) | (1 << present_idx)
	return {"anim": {"take": FORK}, "then": {"anim": {"give": present}, "msg": MSG_THANKS + present_idx}}
