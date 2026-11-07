extends EventNpc

## Katrina in her fortune tent (`ac_ev_gypsy`, `SP_NPC_GYPSY`, skeleton `bpt_1`). She faces
## the door, turning back to it after a talk (`aEGPS_actor_move`). `KatrinaTalk`; the
## destiny lasts until the date changes (`Game_play_Reset_destiny`).

var _given: bool = false


func _init() -> void:
	species = &"bpt"
	display_name = "Katrina"


func make_talk() -> BankTalk:
	return KatrinaTalk.new(Game.destiny(), _given, Game.inventory, rng())


func talk_ended(script: BankTalk) -> void:
	super.talk_ended(script)
	var t := script as KatrinaTalk
	if t != null and t.given_this_visit:
		_given = true
		Game.set_destiny(t.destiny)
