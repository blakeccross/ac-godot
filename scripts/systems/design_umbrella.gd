class_name DesignUmbrella
extends RefCounted

## The player's own designs as umbrellas (`ITM_MY_ORG_UMBRELLA0-7`, `mTG_nw_st_umbrella_proc`).
## The item only names the design slot; the canopy (`tol_umb_w`) draws whatever is in that
## slot now (`Player_Design_Get`), so editing the design repaints the umbrella.

const ID_FORMAT := "design_umbrella_%d"


static func item_id(slot: int) -> StringName:
	return StringName(ID_FORMAT % slot)


static func is_design_umbrella(item_id: StringName) -> bool:
	var tool := ItemCatalog.get_item(item_id) as ToolData
	return tool != null and tool.design_slot >= 0


## `mTG_nw_st_umbrella_proc`: allowed with a free pocket, or while the hand is empty or
## already holds a design umbrella (it is swapped for this one). Returns a notice, or "".
static func make(inv: Inventory, slot: int) -> String:
	var data: ItemData = ItemCatalog.get_item(item_id(slot))
	if inv == null or data == null:
		return ""
	if inv.equipment_id != &"" and is_design_umbrella(inv.equipment_id):
		inv.swap_equipped(data.id)
		Audio.play_se(&"5e")
		return ""
	if not inv.has_space_for(data, 1):
		## `mWR_WARNING_ORIGINAL`.
		return "Your pockets are full."
	inv.add(data, 1)
	if inv.equipment_id == &"":
		for i: int in Inventory.POCKET_SLOTS:
			var s: InventorySlot = inv.slot_at(i)
			if s != null and not s.is_empty() and s.item.item_id == data.id:
				inv.equip_slot(i)
				break
	Audio.play_se(&"5e")
	return ""
