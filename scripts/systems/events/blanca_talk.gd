class_name BlancaTalk
extends BankTalk

## What Blanca says. On the train (`aNM2_*`): "'Scuse me." and her plea for a face (0x33F2 the
## first time a player meets her, 0x33F3 after), then the editor; a face back gets one of
## three verdicts (0x31E1–0x31E3), a blank one "Shaky fingers! Draw my face properly!" (0x321A)
## and the editor again. In town (`aNMC_set_talk_info`): `MaskCat.town_msg`, with the painter's
## name in FREE0.

enum Kind { ASK, ASK_AGAIN, THANKS, REDO, TOWN }

const MSG_ASK_FIRST := 0x33F2
const MSG_ASK := 0x33F3
const MSG_THANKS := 0x31E1
const MSG_REDO := 0x321A

var kind: int = Kind.TOWN
var rng: RandomNumberGenerator
var first_today: bool = false


func _init(p_kind: int, p_rng: RandomNumberGenerator, p_first_today: bool = false) -> void:
	kind = p_kind
	rng = p_rng
	first_today = p_first_today


func prepare() -> void:
	set_free(0, str(MaskCat.state().get("creator", "")))
	set_free(1, Game.town_name if Game != null else "")


func start_msg() -> int:
	match kind:
		Kind.ASK:
			return MSG_ASK_FIRST
		Kind.ASK_AGAIN:
			return MSG_ASK
		Kind.THANKS:
			return MSG_THANKS + rng.randi_range(0, 2)
		Kind.REDO:
			return MSG_REDO
	return MaskCat.town_msg(first_today, rng)
