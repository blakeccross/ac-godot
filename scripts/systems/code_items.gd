class_name CodeItems
extends RefCounted

## The decomp item numbers secret codes carry (`mActor_name_t`, `m_name_table.h`) for the
## port's items, both ways: furniture (`FTR0_START` / `FTR1_START`, four facings an index),
## clothing, carpets, wallpaper, the tools, umbrellas, balloons, pinwheels, fans and fruit.

const FTR0_START := 0x1000
const FTR1_START := 0x3000
const NET := 0x2200
const UMBRELLA0 := 0x2204
const GOLDEN_NET := 0x2239
const BALLOON0 := 0x2244
const PINWHEEL0 := 0x224C
const FAN0 := 0x2254
const CLOTH0 := 0x2400
const CARPET0 := 0x2600
const WALL0 := 0x2700
const FOOD0 := 0x2800
const TOOLS: Array[StringName] = [&"net", &"axe", &"shovel", &"fishing_rod"]
const GOLDEN: Array[StringName] = [&"golden_net", &"golden_axe", &"golden_shovel", &"golden_fishing_rod"]
const BALLOONS: Array[StringName] = [
	&"red_balloon", &"yellow_balloon", &"blue_balloon", &"green_balloon", &"purple_balloon",
	&"bunny_p_balloon", &"bunny_b_balloon", &"bunny_o_balloon",
]
const PINWHEELS: Array[StringName] = [
	&"yellow_pinwheel", &"red_pinwheel", &"tiger_pinwheel", &"green_pinwheel", &"pink_pinwheel",
	&"striped_pinwheel", &"flower_pinwheel", &"fancy_pinwheel",
]
const FANS: Array[StringName] = [
	&"bluebell_fan", &"plum_fan", &"bamboo_fan", &"cloud_fan", &"maple_fan", &"fan_fan",
	&"flower_fan", &"leaf_fan",
]
## `ITM_FOOD_APPLE`… (`+6` is unused).
const FOODS: Array[StringName] = [&"apple", &"cherry", &"pear", &"peach", &"orange", &"mushroom", &"", &"coconut"]


## `mRmTp_FtrIdx2FtrItemNo(idx, SOUTH)`.
static func ftr_no(index: int) -> int:
	return FTR0_START + (index << 2) if index < 0x400 else FTR1_START + ((index - 0x400) << 2)


## The item number for a port item, or −1.
static func number_of(id: StringName) -> int:
	var ftr: int = FtrCatalog.index_of(id)
	if ftr >= 0:
		return ftr_no(ftr)
	var raw := String(id)
	if raw.begins_with("shirt_") and raw.substr(6).is_valid_int():
		return CLOTH0 + int(raw.substr(6))
	if raw.begins_with("wall_") and raw.substr(5).is_valid_int():
		return WALL0 + int(raw.substr(5))
	if raw.begins_with("floor_") and raw.substr(6).is_valid_int():
		return CARPET0 + int(raw.substr(6))
	for table: Array in [[TOOLS, NET], [GOLDEN, GOLDEN_NET], [BALLOONS, BALLOON0], [PINWHEELS, PINWHEEL0], [FANS, FAN0], [FOODS, FOOD0]]:
		var i: int = (table[0] as Array).find(id)
		if i >= 0:
			return int(table[1]) + i
	var tool := ItemCatalog.get_item(id) as ToolData
	if tool != null and tool.umbrella_index >= 0:
		return UMBRELLA0 + tool.umbrella_index
	return -1


## The port item for an item number, or `&""`.
static func id_of(number: int) -> StringName:
	if number >= FTR0_START and number < 0x2000:
		return _known(FtrCatalog.item_id((number - FTR0_START) >> 2))
	if number >= FTR1_START and number < 0x4000:
		return _known(FtrCatalog.item_id(0x400 + ((number - FTR1_START) >> 2)))
	if number >= CLOTH0 and number < CARPET0:
		return _known(StringName("shirt_%03d" % (number - CLOTH0)))
	if number >= CARPET0 and number < WALL0:
		return _known(InteriorStyleCatalog.floor_style_id(number - CARPET0))
	if number >= WALL0 and number < FOOD0:
		return _known(InteriorStyleCatalog.wall_style_id(number - WALL0))
	for table: Array in [[TOOLS, NET], [GOLDEN, GOLDEN_NET], [BALLOONS, BALLOON0], [PINWHEELS, PINWHEEL0], [FANS, FAN0], [FOODS, FOOD0]]:
		var i: int = number - int(table[1])
		if i >= 0 and i < (table[0] as Array).size():
			return _known((table[0] as Array)[i])
	if number >= UMBRELLA0 and number < UMBRELLA0 + 32:
		for data: ItemData in ItemCatalog.all_items():
			if data is ToolData and (data as ToolData).umbrella_index == number - UMBRELLA0:
				return data.id
	return &""


static func _known(id: StringName) -> StringName:
	return id if id != &"" and ItemCatalog.get_item(id) != null else &""


## `mMpswd_check_present_user`: what a player may trade in for a code — goods the shops sell
## (furniture, clothes, carpets, wallpaper), the tools, toys and fruit; not fish, insects or
## anything gift-wrapped.
static func giftable(data: ItemData) -> bool:
	if data == null or data.category == ItemData.Category.FISH or data.category == ItemData.Category.BUG:
		return false
	return number_of(data.id) >= 0
