class_name MailBank
extends RefCounted

## Letter text from the disc (`m_handbill`): body (`mail`), header (`super`) and signature
## (`ps`) share one number. Written by `tools/build_assets.py --kind dialogue`.
## Missing until the pipeline has run; callers get empty strings then.

const PATH := "res://assets/generated/dialogue/mail.json"
## `PAPER_UNIQUE_NUM`.
const PAPER_NUM := 64

static var _banks: Dictionary = {}
static var _loaded: bool = false


static func has_bank() -> bool:
	_ensure()
	return _banks.has("mail")


static func text(bank: String, index: int) -> String:
	_ensure()
	var rows: Array = _banks.get(bank, []) as Array
	if index < 0 or index >= rows.size():
		return ""
	return str(rows[index])


## Raw byte size of an entry (the `mHandbillz` 192-byte body check counts control codes).
static func size_of(bank: String, index: int) -> int:
	_ensure()
	var rows: Array = _banks.get(bank + "_size", []) as Array
	if index < 0 or index >= rows.size():
		return 0
	return int(rows[index])


## `mNpc_LoadMailDataCommon2`: header/body/footer for `mail_no`, with `{name}` (header name
## slot, `header_back_start`) set to the recipient and `{freeN}` (`mHandbill_Set_free_str`)
## from `free`. Footer padding collapses to a single space.
static func letter(mail_no: int, recipient: String, free: Dictionary = {}) -> Dictionary:
	var header: String = text("super", mail_no).replace("{name}", recipient)
	var body: String = text("mail", mail_no)
	var footer: String = text("ps", mail_no)
	for key: Variant in free.keys():
		var tag: String = "{free%d}" % int(key)
		var value: String = str(free[key])
		header = header.replace(tag, value)
		body = body.replace(tag, value)
		footer = footer.replace(tag, value)
	var spaces := RegEx.create_from_string(" {2,}")
	footer = spaces.sub(footer, " ", true).strip_edges()
	return {"header": header, "body": body.strip_edges(false, true), "footer": footer}


static func reload() -> void:
	_loaded = false
	_banks.clear()
	_ensure()


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		_banks = parsed
