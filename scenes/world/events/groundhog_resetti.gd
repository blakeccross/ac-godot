extends EventNpc

## Groundhog Day's "groundhog" (`ac_ev_majin`, `SP_NPC_EV_MAJIN`): Mr. Resetti pops out of a
## hole on the shrine acre (`APPEAR1`, `eEC_EFFECT_RESET_HOLE`), says what the weather means
## for spring (`aEMJ_set_force_talk_info`: clear `0x3DAF + RANDOM(3)`, snow `0x3DB2 + RANDOM(3)`,
## anything else `0x3DAF`) and drops back down (`GO_UG1`). Then Tortimer gives his speech.

signal done

enum Think { APPEAR, SPEAK, RETIRE }

const MSG_CLEAR := 0x3DAF
const MSG_SNOW := 0x3DB2
const APPEAR := "npc_1_appear1"
const WAIT_R := "npc_1_wait_r1"
const GO_UG := "npc_1_go_ug1"

var think_state: Think = Think.APPEAR


func _init() -> void:
	species = ResettiVisit.RESETTI
	display_name = "Resetti"
	talk_turn = false


func setup() -> void:
	play_clip(APPEAR, false)


static func speech_msg(weather: StringName, rng: RandomNumberGenerator) -> int:
	match weather:
		&"clear":
			return MSG_CLEAR + rng.randi_range(0, 2)
		&"snow":
			return MSG_SNOW + rng.randi_range(0, 2)
	return MSG_CLEAR


func idle_clip() -> String:
	return WAIT_R


func can_talk() -> bool:
	return false


func think(_delta: float) -> void:
	match think_state:
		Think.APPEAR:
			if clip_done():
				play_clip(WAIT_R, true)
				think_state = Think.SPEAK
		Think.SPEAK:
			if can_call_out():
				var msg: int = speech_msg(Game.weather if Game != null else &"clear", rng())
				if not begin_talk(player_node(), BankTalk.Fixed.new(msg), false):
					_retire()
		Think.RETIRE:
			if clip_done():
				done.emit()
				queue_free()


func talk_ended(_script: BankTalk) -> void:
	_retire()


func _retire() -> void:
	think_state = Think.RETIRE
	play_clip(GO_UG, false)
