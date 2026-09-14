class_name InteriorRefresh
extends RefCounted

## Rebuilds a subset of an interior's furniture after a stateful event
## (purchase, mail/lost-and-found update) without freeing persistent
## fixtures (shopkeepers, clerks, curator). Presenters are idempotent —
## re-running `present_exhibits` / `furnish_fallback` only refills the
## cleared groups.


## Rebuild the shelf stock after a purchase.
static func shop_set(furniture_root: Node3D, room_content: Node3D, session: IndoorSession) -> void:
	if furniture_root == null or session == null:
		return
	var stale: Array[Node] = []
	for child: Node in furniture_root.get_children():
		if child.is_in_group("shop_set"):
			stale.append(child)
	for node: Node in stale:
		furniture_root.remove_child(node)
		## Never `free()` here — buy can refresh while `shop_stock.interact` is still on the stack.
		node.queue_free()
	_refurnish(furniture_root, room_content, session)


## Rebuild post mail piles / police lost-and-found without freeing clerks.
static func public_set(furniture_root: Node3D, room_content: Node3D, session: IndoorSession) -> void:
	if furniture_root == null or session == null or session.room == null:
		return
	var stale: Array[Node] = []
	for child: Node in furniture_root.get_children():
		if child.is_in_group("police_set") and child.name.begins_with("LostFound_"):
			stale.append(child)
		elif child.name.begins_with("MailPile_"):
			stale.append(child)
	for node: Node in stale:
		furniture_root.remove_child(node)
		node.queue_free()
	_refurnish(furniture_root, room_content, session)


## Re-run the room's own furnishing (idempotent presenters).
static func _refurnish(furniture_root: Node3D, room_content: Node3D, session: IndoorSession) -> void:
	if room_content != null and room_content.has_method("present_exhibits"):
		room_content.call("present_exhibits", furniture_root, session)
	else:
		InteriorBuilder.furnish_fallback(furniture_root, session)
