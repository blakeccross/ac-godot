extends EventNpc

## Saharah (`ac_ev_carpetPeddler`, `SP_NPC_CARPETPEDDLER`, skeleton `cml_1`) standing in a
## random acre for her visit (`arabian_start`, `make_actor_in_free_block`). `SaharahTalk`.


func _init() -> void:
	species = &"cml"
	display_name = "Saharah"


func make_talk() -> BankTalk:
	var area: Dictionary = Game.events.area(&"carpet_peddler") if Game != null and Game.events != null else {}
	return SaharahTalk.new(area, Game.inventory if Game != null else null, rng())
