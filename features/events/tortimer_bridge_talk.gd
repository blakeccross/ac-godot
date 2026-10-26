class_name TortimerBridgeTalk
extends BankTalk

## Tortimer by the river about the second bridge (`ac_ev_soncho_talk`). The first talk opens
## with a time-of-day line (0x2F33–0x2F36) into "build it somewhere around here?" (0x2F37);
## later ones with 0x2F3E–0x2F3F. "Here is good!" orders the bridge in his acre for tomorrow
## (0x2F38 / 0x2F40, the day in FREE0); otherwise one of five "I'll look elsewhere" lines
## (`aESC_owari_message`). Once ordered, one of three "just wait" lines (0x2F44–0x2F46).

const MSG_ASK_AGAIN := 0x2F3F

var block: Vector2i
var first_talk: bool = true
var today: int = 0
var hour: int = 12
var rng: RandomNumberGenerator


func _init(p_block: Vector2i, p_first_talk: bool, p_today: int, p_hour: int, p_rng: RandomNumberGenerator) -> void:
	block = p_block
	first_talk = p_first_talk
	today = p_today
	hour = p_hour
	rng = p_rng


func prepare() -> void:
	_set_day()


func start_msg() -> int:
	if bool(SecondBridge.state().get("pending", false)):
		return SecondBridge.MSG_PENDING + rng.randi_range(0, 2)
	return SecondBridge.time_msg(hour) if first_talk else SecondBridge.MSG_AGAIN


## `aESC_talk_select`: 1 orders the bridge here; 0 on the first talk looks elsewhere.
func picked(msg_no: int, index: int) -> int:
	if msg_no != SecondBridge.MSG_ASK and msg_no != MSG_ASK_AGAIN:
		return -1
	if index == 1:
		SecondBridge.order(block, today)
		_set_day()
		return -1
	if msg_no == SecondBridge.MSG_ASK:
		return SecondBridge.elsewhere_msg()
	return -1


## `aESC_talk_secand`: "STILL thinking?!" then a look-elsewhere line.
func next_step() -> Dictionary:
	if current_msg == SecondBridge.MSG_STILL:
		return {"msg": SecondBridge.elsewhere_msg()}
	return {}


## `aESC_set_day`: the build day's date.
func _set_day() -> void:
	var build: int = int(SecondBridge.state().get("build", -1))
	if build >= 0:
		set_free(0, str(EventDates.from_ordinal(build).z))
