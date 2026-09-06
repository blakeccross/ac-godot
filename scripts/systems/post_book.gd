class_name PostBook
extends RefCounted

## Post office mail desk (`PostOffice_c` / `m_post_office.c`). Owned by `Game`.
## Desk holds up to 5 letters (`mPO_MAIL_STORAGE_SIZE`) for delivery / save-keep.

const MAIL_STORAGE_SIZE := 5
const KEEP_MAIL_PLAYERS_MAX := 10

## Occupied desk slots (`post_office.mail[]`).
var mail: Array[MailData] = []
## Legacy counters kept in sync for older saves / pile draw.
var keep_mail_sum_players: int = 0
var keep_mail_sum_npcs: int = 0


func _init() -> void:
	_ensure_slots()


func clear() -> void:
	mail.clear()
	_ensure_slots()
	keep_mail_sum_players = 0
	keep_mail_sum_npcs = 0


func get_keep_mail_sum() -> int:
	_sync_sums()
	return keep_mail_sum_players + keep_mail_sum_npcs


func is_desk_full() -> bool:
	return occupied_count() >= MAIL_STORAGE_SIZE


func occupied_count() -> int:
	var n: int = 0
	for letter: MailData in mail:
		if letter != null and not letter.is_empty():
			n += 1
	return n


## Accept a letter onto the desk (`mPO_receipt_proc` / `mPO_keep_contents`).
func receipt_mail(letter: MailData = null) -> bool:
	if is_desk_full():
		return false
	var slot: int = _first_free()
	if slot < 0:
		return false
	if letter != null and not letter.is_empty():
		mail[slot] = letter.duplicate_mail()
	else:
		## Counter-only stub (tests / legacy).
		mail[slot] = MailData.make_send(&"unknown", "Someone", "(Letter)")
	_sync_sums()
	return true


func mail_at(index: int) -> MailData:
	_ensure_slots()
	if index < 0 or index >= MAIL_STORAGE_SIZE:
		return null
	return mail[index]


func to_save() -> Dictionary:
	_sync_sums()
	var rows: Array = []
	for letter: MailData in mail:
		if letter == null or letter.is_empty():
			rows.append({})
		else:
			rows.append(letter.to_save())
	return {
		"mail": rows,
		"keep_mail_sum_players": keep_mail_sum_players,
		"keep_mail_sum_npcs": keep_mail_sum_npcs,
	}


func apply_snapshot(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var row: Dictionary = data as Dictionary
	var mail_v: Variant = row.get("mail", [])
	if typeof(mail_v) == TYPE_ARRAY:
		var i: int = 0
		for entry: Variant in mail_v as Array:
			if i >= MAIL_STORAGE_SIZE:
				break
			var loaded: MailData = MailData.from_save(entry)
			mail[i] = loaded if not loaded.is_empty() else MailData.new()
			i += 1
		_sync_sums()
		return
	## Legacy counter-only saves.
	keep_mail_sum_players = int(row.get("keep_mail_sum_players", 0))
	keep_mail_sum_npcs = int(row.get("keep_mail_sum_npcs", 0))
	var stub_n: int = mini(keep_mail_sum_players + keep_mail_sum_npcs, MAIL_STORAGE_SIZE)
	for j: int in stub_n:
		mail[j] = MailData.make_send(&"unknown", "Someone", "(Saved letter)")
	_sync_sums()


func _ensure_slots() -> void:
	while mail.size() < MAIL_STORAGE_SIZE:
		mail.append(MailData.new())
	while mail.size() > MAIL_STORAGE_SIZE:
		mail.pop_back()


func _first_free() -> int:
	_ensure_slots()
	for i: int in MAIL_STORAGE_SIZE:
		if mail[i] == null or mail[i].is_empty():
			return i
	return -1


func _sync_sums() -> void:
	_ensure_slots()
	var players: int = 0
	for letter: MailData in mail:
		if letter != null and not letter.is_empty():
			players += 1
	keep_mail_sum_players = mini(players, KEEP_MAIL_PLAYERS_MAX)
	keep_mail_sum_npcs = 0
