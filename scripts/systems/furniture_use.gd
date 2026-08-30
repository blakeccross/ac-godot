class_name FurnitureUse
extends RefCounted

## Data-driven furniture verbs. Hosts call `actions` / `apply`; they do not switch on kind.

const ANIM_SIT := &"ply_1_sit1"
const ANIM_LIE := &"ply_1_bed1"


static func actions(host: Node, ctx: InteractionContext) -> Array[Interaction]:
	var out: Array[Interaction] = []
	if Game.held_furniture() != null:
		return out
	var data: FurnitureData = _data(host)
	var entry: FurniturePlacement = _entry(host)
	var label: String = data.display_name if data else "Furniture"
	if data != null and data.is_sittable():
		out.append(Interaction.of(Interaction.SIT, "Sit on %s" % label, 8, ANIM_SIT))
	if data != null and data.is_bed():
		out.append(Interaction.of(Interaction.LIE, "Lie on %s" % label, 8, ANIM_LIE))
	if data != null and data.has_storage():
		out.append(Interaction.of(Interaction.OPEN, "Open %s" % label, 9))
	if data != null and data.is_toggleable():
		var powered: bool = entry == null or entry.on
		var verb: String = "Turn off %s" if powered else "Turn on %s"
		out.append(Interaction.of(Interaction.TOGGLE, verb % label, 7))
	if data != null and _can_take(data, entry):
		out.append(Interaction.of(Interaction.TAKE, "Take from %s" % label, 10))
	elif data != null and _can_display(data, ctx):
		out.append(Interaction.of(Interaction.DISPLAY, "Put on %s" % label, 10))
	if Game.is_decorating():
		## Pick up beats sit/open so A relocates furniture. Place uses player facing.
		out.append(Interaction.of(Interaction.PICK_UP, "Pick up %s" % label, 12))
		if data == null or data.can_rotate:
			out.append(Interaction.of(Interaction.ROTATE, "Rotate %s" % label, 5))
	return out


static func apply(action: Interaction, host: Node, ctx: InteractionContext) -> bool:
	if action == null or host == null:
		return false
	var pid: StringName = host.get("occupant_id") as StringName
	match action.id:
		Interaction.SIT:
			Game.post_notice("You sit down.")
			return true
		Interaction.LIE:
			Game.post_notice("You lie down.")
			return true
		Interaction.OPEN:
			return open_storage(pid, ctx)
		Interaction.TOGGLE:
			return toggle(pid)
		Interaction.DISPLAY:
			return put_display(pid, ctx)
		Interaction.TAKE:
			return take_display(pid, ctx)
		Interaction.PICK_UP:
			return Game.pick_up_furniture(pid)
		Interaction.ROTATE:
			return Game.rotate_furniture(pid)
		_:
			return false


static func open_storage(placement_id: StringName, ctx: InteractionContext) -> bool:
	if Game.interior_session == null:
		return false
	var entry: FurniturePlacement = Game.interior_session.room.placement_by_id(placement_id)
	var data: FurnitureData = Game.interior_session.furniture_of(entry.furniture_id) if entry else null
	if entry == null or data == null or not data.has_storage():
		return false
	var inv: Inventory = ctx.inventory if ctx else Game.inventory
	var held: ItemData = _held_item(inv)
	if held != null and not (held is FurnitureData):
		if entry.stored.size() >= data.keep_count():
			Game.post_notice("It's full.")
			return false
		if inv.remove(held.id, 1) > 0:
			return false
		entry.stored.append(String(held.id))
		Game.post_notice("Put %s away." % held.display_name)
		return true
	if entry.stored.is_empty():
		Game.post_notice("It's empty.")
		return false
	var take_id := StringName(entry.stored[entry.stored.size() - 1])
	var take: ItemData = ItemCatalog.get_item(take_id)
	if take == null or not inv.has_space_for(take, 1):
		Game.post_notice("Pockets are full.")
		return false
	entry.stored.remove_at(entry.stored.size() - 1)
	inv.add(take, 1)
	Game.post_notice("Took %s." % take.display_name)
	return true


static func toggle(placement_id: StringName) -> bool:
	if Game.interior_session == null:
		return false
	var entry: FurniturePlacement = Game.interior_session.room.placement_by_id(placement_id)
	if entry == null:
		return false
	entry.on = not entry.on
	Game.post_notice("Turned %s." % ("on" if entry.on else "off"))
	return true


static func put_display(placement_id: StringName, ctx: InteractionContext) -> bool:
	if Game.interior_session == null:
		return false
	var entry: FurniturePlacement = Game.interior_session.room.placement_by_id(placement_id)
	var data: FurnitureData = Game.interior_session.furniture_of(entry.furniture_id) if entry else null
	var inv: Inventory = ctx.inventory if ctx else Game.inventory
	var held: ItemData = _held_item(inv)
	if entry == null or data == null or held == null or not data.accepts_display(held):
		return false
	if entry.display_id != &"":
		Game.post_notice("Something is already there.")
		return false
	if inv.remove(held.id, 1) > 0:
		return false
	entry.display_id = held.id
	Game.post_notice("Placed %s." % held.display_name)
	return true


static func take_display(placement_id: StringName, ctx: InteractionContext) -> bool:
	if Game.interior_session == null:
		return false
	var entry: FurniturePlacement = Game.interior_session.room.placement_by_id(placement_id)
	var inv: Inventory = ctx.inventory if ctx else Game.inventory
	if entry == null or entry.display_id == &"":
		return false
	var take: ItemData = ItemCatalog.get_item(entry.display_id)
	if take == null or not inv.has_space_for(take, 1):
		Game.post_notice("Pockets are full.")
		return false
	inv.add(take, 1)
	entry.display_id = &""
	Game.post_notice("Took %s." % take.display_name)
	return true


static func _data(host: Node) -> FurnitureData:
	if host == null:
		return null
	return host.get("data") as FurnitureData


static func _entry(host: Node) -> FurniturePlacement:
	if host == null or Game.interior_session == null or Game.interior_session.room == null:
		return null
	var pid: StringName = host.get("occupant_id") as StringName
	return Game.interior_session.room.placement_by_id(pid)


static func _held_item(inv: Inventory) -> ItemData:
	if inv == null:
		return null
	var slot: InventorySlot = inv.selected_slot()
	if slot == null or slot.is_empty():
		return null
	return ItemCatalog.get_item(slot.item.item_id)


static func _can_display(data: FurnitureData, ctx: InteractionContext) -> bool:
	var held: ItemData = _held_item(ctx.inventory if ctx else Game.inventory)
	return data.accepts_display(held)


static func _can_take(data: FurnitureData, entry: FurniturePlacement) -> bool:
	if entry == null or entry.display_id == &"":
		return false
	return (
		data.kind == FurnitureData.Kind.DISPLAY
		or data.kind == FurnitureData.Kind.MANNEQUIN
		or data.kind == FurnitureData.Kind.UMBRELLA
	)
