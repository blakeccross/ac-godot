class_name MailData
extends RefCounted

## One letter (`Mail_c`). Parallel to pocket items — 10 slots on `Inventory`.

enum LetterFont { RECV, SEND, RECV_READ, RECV_PRESENT, RECV_PRESENT_READ }
enum NameType { PLAYER, NPC, MUSEUM }

var recipient_id: StringName = &""
var recipient_name: String = ""
var recipient_type: NameType = NameType.NPC
var sender_id: StringName = &""
var sender_name: String = ""
var sender_type: NameType = NameType.PLAYER
var present_item_id: StringName = &""
var font: LetterFont = LetterFont.SEND
var header: String = ""
var body: String = ""
var footer: String = ""
var paper_type: int = 0


func is_empty() -> bool:
	return recipient_id == &"" and body.strip_edges() == "" and header.strip_edges() == ""


func is_sendable() -> bool:
	return not is_empty() and font == LetterFont.SEND and recipient_id != &""


func label() -> String:
	if recipient_name != "":
		return "To %s" % recipient_name
	if recipient_id != &"":
		return "To %s" % String(recipient_id)
	return "Letter"


func preview() -> String:
	var text: String = body.strip_edges()
	if text == "":
		text = header.strip_edges()
	if text == "":
		return label()
	if text.length() > 48:
		return text.substr(0, 45) + "..."
	return text


func duplicate_mail() -> MailData:
	var out := MailData.new()
	out.recipient_id = recipient_id
	out.recipient_name = recipient_name
	out.recipient_type = recipient_type
	out.sender_id = sender_id
	out.sender_name = sender_name
	out.sender_type = sender_type
	out.present_item_id = present_item_id
	out.font = font
	out.header = header
	out.body = body
	out.footer = footer
	out.paper_type = paper_type
	return out


func to_save() -> Dictionary:
	return {
		"recipient_id": String(recipient_id),
		"recipient_name": recipient_name,
		"recipient_type": int(recipient_type),
		"sender_id": String(sender_id),
		"sender_name": sender_name,
		"sender_type": int(sender_type),
		"present": String(present_item_id),
		"font": int(font),
		"header": header,
		"body": body,
		"footer": footer,
		"paper": paper_type,
	}


static func from_save(data: Variant) -> MailData:
	var out := MailData.new()
	if typeof(data) != TYPE_DICTIONARY:
		return out
	var row: Dictionary = data
	out.recipient_id = StringName(str(row.get("recipient_id", "")))
	out.recipient_name = str(row.get("recipient_name", ""))
	out.recipient_type = int(row.get("recipient_type", NameType.NPC)) as NameType
	out.sender_id = StringName(str(row.get("sender_id", "")))
	out.sender_name = str(row.get("sender_name", ""))
	out.sender_type = int(row.get("sender_type", NameType.PLAYER)) as NameType
	out.present_item_id = StringName(str(row.get("present", "")))
	out.font = int(row.get("font", LetterFont.SEND)) as LetterFont
	out.header = str(row.get("header", ""))
	out.body = str(row.get("body", ""))
	out.footer = str(row.get("footer", ""))
	out.paper_type = int(row.get("paper", 0))
	return out


static func make_send(
	to_id: StringName,
	to_name: String,
	body_text: String,
	from_name: String = "",
	from_id: StringName = &""
) -> MailData:
	var mail := MailData.new()
	mail.font = LetterFont.SEND
	mail.recipient_id = to_id
	mail.recipient_name = to_name
	mail.recipient_type = NameType.NPC
	mail.sender_id = from_id
	mail.sender_name = from_name
	mail.sender_type = NameType.PLAYER
	mail.header = "Dear %s," % (to_name if to_name != "" else String(to_id))
	mail.body = body_text
	mail.footer = from_name if from_name != "" else "Your friend"
	return mail
