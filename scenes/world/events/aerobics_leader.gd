extends EventNpc

## Out front of the aerobics (`ac_taisou_npc0`): Copper leads the routine facing the line
## (`SP_NPC_EV_TAISOU_0`), Tortimer does it behind them (`SP_NPC_SONCHO_D078`). Both run the
## radio routine's moves in order. Copper shouts encouragement without turning; Tortimer
## turns to talk: the exercise card at Morning Aerobics (`RadioCard`), the Sports Fair
## souvenir otherwise (`TortimerHoliday`).

## `msg_base2`: Copper's three lines, morning aerobics / Sports Fair.
const COPPER_MSG_MORNING := 0x2665
const COPPER_MSG_FAIR := 0x2668

## `plc` (Copper) or `ttl` (Tortimer).
@export var leader: StringName = &"plc"
## `mSC_EVENT_*` for the Sports Fair souvenir (Tortimer only).
var holiday: int = -1
var _seq: int = 0
var _pause: float = 0.0


func _ready() -> void:
	_apply_leader()
	super._ready()


func _apply_leader() -> void:
	species = leader
	display_name = "Tortimer" if leader == &"ttl" else "Copper"
	talk_turn = leader == &"ttl"


func setup() -> void:
	_pause = 0.0


func idle_clip() -> String:
	return str(_clips()[0])


func talk_clip() -> String:
	return "npc_1_wait1" if leader == &"ttl" else idle_clip()


func _clips() -> Array:
	return (FestivalCrowd.FAMILIES[&"taisou"] as Dictionary)["clips"]


func morning() -> bool:
	return event_id == &"morning_aerobics"


## The routine's moves in order (`aTS0_ctrl_gymnastic`).
func think(delta: float) -> void:
	_pause -= delta
	if _pause > 0.0:
		return
	var clips: Array = _clips()
	_pause = play_clip(str(clips[_seq % clips.size()]), false)
	_seq += 1


func make_talk() -> BankTalk:
	if leader != &"ttl":
		var base: int = COPPER_MSG_MORNING if morning() else COPPER_MSG_FAIR
		return BankTalk.Fixed.new(base + rng().randi_range(0, 2))
	var record: Dictionary = Game.events.area(&"soncho_record") if Game != null and Game.events != null else {}
	if morning():
		var card := RadioCard.new(Game.inventory if Game != null else null, Game.radio_card if Game != null else {}, record, rng())
		card.foreigner = Game != null and Game.foreigner
		return card
	var t := TortimerHoliday.new(holiday, record, Game.inventory if Game != null else null, rng())
	t.female = Game != null and String(Game.player_gender) == "female"
	return t


func talk_ended(script: BankTalk) -> void:
	super.talk_ended(script)
	_pause = 0.0
