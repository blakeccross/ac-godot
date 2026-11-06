class_name Kappn
extends EventNpc

## Kapp'n (`ac_npc_sendo`, `SP_NPC_SENDO`, skeleton `wip_1`) at the tiller of his dinghy, on the town's
## wharf or the island's landing. `IslandService` seats him in the boat and runs what his talks lead to.

signal talked(script: KappnTalk)

var service: IslandService = null
var at_island: bool = false


func _init() -> void:
	species = &"wip"
	display_name = "Kapp'n"


## `aSEN_think_init_proc` waits with `WIPWAIT1`.
func idle_clip() -> String:
	return "npc_1_wipwait1"


func talk_clip() -> String:
	return "npc_1_wipwait1"


func can_talk() -> bool:
	return visible and service != null and service.is_idle()


func make_talk() -> BankTalk:
	var talk := KappnTalk.new(KappnTalk.Kind.ISLAND if at_island else KappnTalk.Kind.TOWN)
	talk.raining = Weather.is_raining()
	talk.female = Game.resident.player_gender == IntroSequence.GENDER_FEMALE
	return talk


func talk_ended(script: BankTalk) -> void:
	super.talk_ended(script)
	talked.emit(script as KappnTalk)
