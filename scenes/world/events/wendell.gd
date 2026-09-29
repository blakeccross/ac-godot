extends EventNpc

## Wendell (`ac_ev_artist`, `SP_NPC_ARTIST`, skeleton `wls_1`) in a random acre for his
## visit (`artist_start`, `make_actor_in_free_block`). `WendellTalk`.


func _init() -> void:
	species = &"wls"
	display_name = "Wendell"


func make_talk() -> BankTalk:
	var area: Dictionary = Game.events.area(&"artist") if Game != null and Game.events != null else {}
	return WendellTalk.new(area, Game.inventory if Game != null else null, rng())
