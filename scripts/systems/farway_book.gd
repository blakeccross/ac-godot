class_name FarwayBook
extends RefCounted

## Fossils mailed to the Farway Museum for identification (`m_museum.c` mail-in).
## Owned by `Game`. Each in-transit entry returns identified on the next 06:00 renew as
## a `RECV_PRESENT` letter with the fossil enclosed. Also drip-feeds the one-time intro
## letter that explains the system.

const SENDER_ID := &"farway_museum"
const SENDER_NAME := "Farway Museum"

var _in_transit: Array[int] = []
var _intro_pending: bool = false
var _intro_sent: bool = false
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func clear() -> void:
	_in_transit.clear()
	_intro_pending = false
	_intro_sent = false


## Ordinal day for scheduling (calendar day, not play session).
static func today_ordinal() -> int:
	if Clock == null:
		return 0
	var unix: int = int(
		Time.get_unix_time_from_datetime_dict(
			{"year": Clock.year, "month": Clock.month, "day": Clock.day, "hour": 12}
		)
	)
	return int(unix / 86400)


func in_transit_count() -> int:
	return _in_transit.size()


## Hand one dug fossil to the post office for the Farway Museum.
func queue_fossil(sent_ordinal: int = -1) -> void:
	_in_transit.append(sent_ordinal if sent_ordinal >= 0 else today_ordinal())


## Queue the introductory letter unless it has already gone out.
func request_intro_letter() -> void:
	if not _intro_sent:
		_intro_pending = true


## `field_renewed` (06:00): letters for everything sent before today, plus the intro.
func process_delivery(today_ord: int = -1) -> Array[MailData]:
	var today: int = today_ord if today_ord >= 0 else today_ordinal()
	var out: Array[MailData] = []
	if _intro_pending:
		_intro_pending = false
		_intro_sent = true
		out.append(_intro_letter())
	var kept: Array[int] = []
	for sent: int in _in_transit:
		if sent < today:
			out.append(_identified_letter())
		else:
			kept.append(sent)
	_in_transit = kept
	return out


func _identified_letter() -> MailData:
	FossilCatalog.ensure_loaded()
	var index: int = _rng.randi_range(0, maxi(1, FossilCatalog.count()) - 1)
	var row: Dictionary = FossilCatalog.row_for_index(index)
	var name: String = str(row.get("display_name", "a fossil"))
	var mail := MailData.new()
	mail.sender_id = SENDER_ID
	mail.sender_name = SENDER_NAME
	mail.sender_type = MailData.NameType.NPC
	mail.recipient_type = MailData.NameType.PLAYER
	mail.recipient_name = Game.player_name if Game != null else "Resident"
	mail.font = MailData.LetterFont.RECV_PRESENT
	mail.present_item_id = StringName(str(row.get("id", "")))
	mail.header = "Dear %s," % mail.recipient_name
	mail.body = (
		"We have examined the fossil you sent. It is %s. It is enclosed with this letter. "
		+ "Thank you for your contribution to science."
	) % name
	mail.footer = "— The Farway Museum"
	return mail


func _intro_letter() -> MailData:
	var mail := MailData.new()
	mail.sender_id = SENDER_ID
	mail.sender_name = SENDER_NAME
	mail.sender_type = MailData.NameType.NPC
	mail.recipient_type = MailData.NameType.PLAYER
	mail.recipient_name = Game.player_name if Game != null else "Resident"
	mail.font = MailData.LetterFont.RECV
	mail.header = "Dear %s," % mail.recipient_name
	mail.body = (
		"We hear you have taken up fossil hunting. Splendid! Blathers cannot identify "
		+ "fossils himself, so send any you dig up to us at the post office and we will "
		+ "name them and mail them back. One request: do not re-bury a fossil once dug."
	)
	mail.footer = "— The Farway Museum"
	return mail


func to_save() -> Dictionary:
	return {
		"in_transit": _in_transit.duplicate(),
		"intro_pending": _intro_pending,
		"intro_sent": _intro_sent,
	}


func apply_snapshot(data: Variant) -> void:
	clear()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var row: Dictionary = data
	var raw: Variant = row.get("in_transit", [])
	if typeof(raw) == TYPE_ARRAY:
		for entry: Variant in raw as Array:
			_in_transit.append(int(entry))
	_intro_pending = bool(row.get("intro_pending", false))
	_intro_sent = bool(row.get("intro_sent", false))
