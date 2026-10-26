class_name MuseumDonation
extends RefCounted

## Handing items to the museum: Blathers' donation counter (`mMmd_RequestMuseumDisplay`) and
## the Farway Museum mail-in for dug fossils (`mMsm`).


## Try to donate `item_id` and report what happened, so Blathers' dialogue can branch on it.
## `reason` is one of: not_item, cannot_donate, forgery, already_donated, not_held,
## generic_fossil, ok. `ok` means the item has left the pockets and is on display.
static func donate(item_id: StringName, player_no: int = 0) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"reason": "not_item",
		"category": -1,
		"index": -1,
		"donor": 0,
		"completed_set": false,
		"set_name": "",
		"completed_collection": false,
		"completed_museum": false,
		"message": "That's not something for the museum.",
	}
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null:
		return out
	var mapped: Dictionary = MuseumDisplay.map_item(data)
	var category: int = int(mapped.get("category", -1))
	var index: int = int(mapped.get("index", -1))
	out["category"] = category
	out["index"] = index
	## Raw dug fossils have no identity yet: the Farway Museum must examine them first.
	if item_id == &"fossil":
		return _reject(out, "generic_fossil", "Blathers can't identify an unexamined fossil.")
	var museum: MuseumBook = Game.museum
	match museum.display_info_for_item(data):
		MuseumBook.DisplayInfo.CANNOT_DONATE:
			var reason: String = "forgery" if _is_forgery(data, category, index) else "cannot_donate"
			return _reject(out, reason, "Blathers can't take that.")
		MuseumBook.DisplayInfo.ALREADY_DONATED:
			out["donor"] = museum.info(category, index)
			return _reject(out, "already_donated", "The museum already has that.")
	if Game.inventory.count_of(item_id) <= 0:
		return _reject(out, "not_held", "You don't have that.")
	if not museum.request_display(data, player_no):
		return _reject(out, "already_donated", "The museum already has that.")
	Game.inventory.remove(item_id, 1)
	out["ok"] = true
	out["reason"] = "ok"
	out["donor"] = clampi(player_no, 0, 3) + 1
	if category == MuseumDisplay.Category.FOSSIL and MuseumDisplay.fossil_set_just_completed(museum, index):
		out["completed_set"] = true
		out["set_name"] = MuseumDisplay.fossil_set_name(index)
	out["completed_collection"] = _collection_complete(category)
	out["completed_museum"] = museum.is_complete()
	if out["completed_museum"]:
		MuseumCompMail.schedule()
	out["message"] = _thanks(out)
	return out


## Post `count` dug fossils to the Farway Museum; they come back identified tomorrow.
## Returns what to tell the player.
static func mail_fossils(count: int = 1) -> String:
	var sending: int = clampi(count, 0, Game.inventory.count_of(&"fossil"))
	if sending <= 0:
		return "You have no fossils to send."
	Game.inventory.remove(&"fossil", sending)
	for _i: int in sending:
		Game.travel_book.queue_fossil()
	return "We'll send %d to the Farway Museum. Expect a reply tomorrow." % sending


static func _reject(out: Dictionary, reason: String, message: String) -> Dictionary:
	out["reason"] = reason
	out["message"] = message
	return out


static func _is_forgery(data: ItemData, category: int, index: int) -> bool:
	if String(data.id).begins_with("art_forgery"):
		return true
	return index in MuseumBook.FORGERY_ART_INDICES and category == MuseumDisplay.Category.ART


static func _collection_complete(category: int) -> bool:
	var museum: MuseumBook = Game.museum
	match category:
		MuseumDisplay.Category.FOSSIL:
			return museum.count_fossils() >= MuseumBook.FOSSIL_NUM
		MuseumDisplay.Category.ART:
			return museum.count_art() >= MuseumBook.DONATABLE_ART_NUM
		MuseumDisplay.Category.FISH:
			return museum.count_fish() >= MuseumBook.FISH_NUM
		MuseumDisplay.Category.INSECT:
			return museum.count_insects() >= MuseumBook.INSECT_NUM
	return false


static func _thanks(out: Dictionary) -> String:
	if out["completed_museum"]:
		return "That completes the collection — every wing is full!"
	if out["completed_collection"]:
		return "That completes a whole collection! Wonderful."
	if out["completed_set"]:
		return "That completes a skeleton! It will appear in the fossil wing."
	return "Donated! Visit the wing to see it on display."
