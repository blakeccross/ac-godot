class_name MikoTalk
extends BankTalk

## Katrina's New Year's lottery at the shrine (`ac_ev_miko`, messages 0x190C–0x1916). Only
## from across her table (`in_front`, 33.75°). 50 Bells buys a fortune: one of four readings
## sets the day's destiny (`Now_Private->destiny`) and a fortune letter (`mMl_TYPE_OMIKUJI`,
## four random lines + the verdict) goes into the pockets — which need a free mail slot.

const MSG_ASK := 0x190C
const MSG_BROKE := 0x190E
const MSG_MAIL_FULL := 0x190F
const MSG_CHANT := 0x1910
const MSG_READING := 0x1911
const MSG_HERE := 0x1915
const MSG_OTHER_SIDE := 0x1916
const PRICE := 50
## `destiny[omikuji]` as `Game.Destiny`: NORMAL, BAD_LUCK, MONEY_LUCK, GOODS_LUCK.
const DESTINY: Array[int] = [0, 3, 4, 5]
## `aEMK_get_omikuji`: four lines from these string runs (16 each), the verdict, the letter.
const LINE_BASES: Array[int] = [0x2B1, 0x2A1, 0x2DA, 0x2CA]
const VERDICT_BASE := 0x2C1
const VERDICT: Array[int] = [2, 3, 1, 0]
const LETTER_BASE := 0x072
const PAPER := 25

var in_front: bool = true
var inventory: Inventory
var rng: RandomNumberGenerator
var fortune: int = -1
var player_name: String = ""


func _init(p_inventory: Inventory = null, p_rng: RandomNumberGenerator = null) -> void:
	inventory = p_inventory
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()


func start_msg() -> int:
	return MSG_ASK if in_front else MSG_OTHER_SIDE


## `aEMK_talk_select`.
func picked(msg_no: int, index: int) -> int:
	if msg_no != MSG_ASK or index != 0:
		return -1
	if not mail_space(inventory):
		return MSG_MAIL_FULL
	if inventory == null or inventory.wallet < PRICE:
		return MSG_BROKE
	fortune = rng.randi_range(0, DESTINY.size() - 1)
	return -1


## `aEMK_talk_omikuji`: the reading, paid for.
func next_step() -> Dictionary:
	if current_msg == MSG_CHANT and fortune >= 0:
		inventory.set_wallet(inventory.wallet - PRICE)
		if Game != null:
			Game.set_destiny(DESTINY[fortune])
		return msg(MSG_READING + fortune)
	return {}


## `aEMK_talk_give`: "Here you go." — the fortune letter.
func entered(msg_no: int) -> void:
	if msg_no == MSG_HERE and fortune >= 0 and inventory != null:
		inventory.add_received_mail(fortune_letter())
		fortune = -1


func fortune_letter() -> MailData:
	var free: Dictionary = {}
	for i: int in LINE_BASES.size():
		free[i] = DialogueCatalog.rom_string(LINE_BASES[i] + rng.randi_range(0, 15))
	free[4] = DialogueCatalog.rom_string(VERDICT_BASE + VERDICT[maxi(fortune, 0)])
	var name: String = player_name if player_name != "" else (context.player_name if context != null else "")
	var text: Dictionary = MailBank.letter(LETTER_BASE + rng.randi_range(0, 2), name, free)
	var mail := MailData.new()
	mail.sender_name = "Katrina"
	mail.sender_type = MailData.NameType.NPC
	mail.recipient_name = name
	mail.recipient_type = MailData.NameType.PLAYER
	mail.font = MailData.LetterFont.RECV
	mail.paper_type = PAPER
	mail.header = str(text.get("header", ""))
	mail.body = str(text.get("body", ""))
	mail.footer = str(text.get("footer", ""))
	return mail


static func mail_space(inv: Inventory) -> bool:
	return inv != null and inv.empty_mail_slot_count() > 0
