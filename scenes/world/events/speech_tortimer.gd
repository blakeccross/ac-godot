extends EventNpc

## Tortimer at the Groundhog Day stand (`ac_ev_speech_soncho`, `SP_NPC_EV_SPEECH_SONCHO`).
## Before 8:00 he chats (`mString_SPEECH_SONCHO_START + 1 + RANDOM(5)`); at 8:00 he gives his
## speech to a player who's there (`aESS_set_force_talk_info`, once); afterwards his lines
## depend on the weather — clear means spring is near, snow means six more weeks. He faces
## the crowd throughout (`aNPC_TALK_TURN_NONE`).

const MSG_SPEECH := 0x3DB5
const EVENT_SEC := 8 * 3600
## The speech waits for the player to be this close (m).
const AUDIENCE_RANGE := 16.0


func _init() -> void:
	species = &"ttl"
	display_name = "Tortimer"
	talk_turn = false


static func talk_msg(sec: int, weather: StringName, rng: RandomNumberGenerator) -> int:
	if sec < EVENT_SEC:
		return MSG_SPEECH + 1 + rng.randi_range(0, 4)
	match weather:
		&"clear":
			return MSG_SPEECH + 6 + rng.randi_range(0, 4)
		&"snow":
			return MSG_SPEECH + 11 + rng.randi_range(0, 4)
	return MSG_SPEECH + 6


func make_talk() -> BankTalk:
	return BankTalk.Fixed.new(talk_msg(Clock.now_sec(), Game.weather if Game != null else &"clear", rng()))


func think(_delta: float) -> void:
	if not can_call_out() or Clock.now_sec() < EVENT_SEC or Game == null or Game.events == null:
		return
	var area: Dictionary = Game.events.area(&"groundhog_day")
	var today: String = Game.events.day_key()
	if str(area.get("speech", "")) == today or player_distance() > AUDIENCE_RANGE:
		return
	area["speech"] = today
	begin_talk(player_node(), BankTalk.Fixed.new(MSG_SPEECH), false)
