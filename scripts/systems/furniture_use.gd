class_name FurnitureUse
extends RefCounted

## Data-driven furniture verbs. Hosts call `actions` / `apply`; they do not switch on kind.



static func actions(host: Node, ctx: InteractionContext) -> Array[Interaction]:
	var out: Array[Interaction] = []
	if Game.held_furniture() != null:
		return out
	var data: FurnitureData = _data(host)
	var entry: FurniturePlacement = _entry(host)
	var label: String = data.display_name if data else "Furniture"
	## Chairs and beds are not verbs: walk into them (`FurnitureSeat`).
	if data != null and data.has_storage() and _from_front(ctx):
		if data.is_music_player():
			out.append(Interaction.of(Interaction.OPEN, "Use %s" % label, 9))
		else:
			out.append(Interaction.of(Interaction.OPEN, "Open %s" % label, 9, _open_clip(data)))
	if data != null and data.is_toggleable() and not data.is_music_player() and (not data.radio_aerobics or _from_front(ctx)):
		var powered: bool = entry == null or entry.on
		var verb: String = "Turn off %s" if powered else "Turn on %s"
		out.append(Interaction.of(Interaction.TOGGLE, verb % label, 7))
	if data != null and _can_take(data, entry):
		out.append(Interaction.of(Interaction.TAKE, "Take from %s" % label, 10))
	elif data != null and _can_display(data, ctx):
		out.append(Interaction.of(Interaction.DISPLAY, "Put on %s" % label, 10))
	## Moving, turning and picking up are not verbs: A grips and the stick moves the piece
	## (`FurnitureGrip`), B picks it up.
	return out


## `ply_1_kagu_open_{h,k,d}1` for the kind of chest (`Player_actor_request_main_open_furniture`).
static func _open_clip(data: FurnitureData) -> StringName:
	var type: int = data.storage_type if data.storage_type != FurnitureData.StorageType.NONE else FurnitureData.StorageType.DRAWERS
	return FurnitureStorage.OPEN_CLIPS[type] as StringName


static func apply(action: Interaction, host: Node, ctx: InteractionContext) -> bool:
	if action == null or host == null:
		return false
	var pid: StringName = host.get("occupant_id") as StringName
	match action.id:
		Interaction.OPEN:
			return await FurnitureTalk.run(host, ctx)
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


static func _from_front(ctx: InteractionContext) -> bool:
	return ctx == null or ctx.contact_side < 0 or ctx.contact_side == FurnitureGrip.ContactSide.FRONT


static func toggle(placement_id: StringName) -> bool:
	if Game.interior_session == null:
		return false
	var entry: FurniturePlacement = Game.interior_session.room.placement_by_id(placement_id)
	if entry == null:
		return false
	var data: FurnitureData = Game.interior_session.furniture_of(entry.furniture_id)
	if data != null and data.radio_aerobics:
		## Only one thing sounds at a time (`aMR_OneMDSwitchOn_TheOtherSwitchOff`).
		FurnitureMusic.set_switch(Game.interior_session, entry, not entry.on)
	else:
		entry.on = not entry.on
	if data != null and (data.kind == FurnitureData.Kind.TOGGLE or data.radio_aerobics):
		Audio.play_se(&"light_on" if entry.on else &"light_off")
	if data != null and data.kind == FurnitureData.Kind.GYROID:
		_hop(pid_node(placement_id))
	if data != null and data.radio_aerobics:
		FurnitureTalk.refresh_room_bgm()
	Game.post_notice("Turned %s." % ("on" if entry.on else "off"))
	return true


## A gyroid bounces when tapped (`aMR_HaniwaSwitchOn`). Its voice samples are not in the pipeline.
static func _hop(node: Node3D) -> void:
	if node == null:
		return
	var rest: float = node.position.y
	var tween: Tween = node.create_tween()
	tween.tween_property(node, "position:y", rest + 0.35, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "position:y", rest, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


static func pid_node(placement_id: StringName) -> Node3D:
	var host: Node = Game.get_tree().get_first_node_in_group("interior") if Game.get_tree() != null else null
	if host != null and host.has_method("furniture_node"):
		return host.call("furniture_node", placement_id) as Node3D
	return null


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
