class_name PostBook
extends RefCounted

## Post office mail desk (`PostOffice_c` / `m_post_office.c`). Owned by `Game`.
## Letter body / delivery scheduling stay thin until inventory mail exists.

const MAIL_STORAGE_SIZE := 5
const KEEP_MAIL_PLAYERS_MAX := 10

## Stored mail count on the desk (`mPO_get_keep_mail_sum`).
var keep_mail_sum_players: int = 0
var keep_mail_sum_npcs: int = 0


func clear() -> void:
	keep_mail_sum_players = 0
	keep_mail_sum_npcs = 0


func get_keep_mail_sum() -> int:
	return keep_mail_sum_players + keep_mail_sum_npcs


func is_desk_full() -> bool:
	return get_keep_mail_sum() >= MAIL_STORAGE_SIZE


## Accept a letter onto the desk (`mPO_receipt_proc` send-type mail, simplified).
func receipt_mail() -> bool:
	if is_desk_full():
		return false
	keep_mail_sum_players = mini(keep_mail_sum_players + 1, KEEP_MAIL_PLAYERS_MAX)
	return true


func to_save() -> Dictionary:
	return {
		"keep_mail_sum_players": keep_mail_sum_players,
		"keep_mail_sum_npcs": keep_mail_sum_npcs,
	}


func apply_snapshot(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var row: Dictionary = data as Dictionary
	keep_mail_sum_players = int(row.get("keep_mail_sum_players", 0))
	keep_mail_sum_npcs = int(row.get("keep_mail_sum_npcs", 0))
