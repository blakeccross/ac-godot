extends EventNpc

## Joan the turnip seller (`ac_ev_kabuPeddler`, `SP_NPC_KABUPEDDLER`, skeleton `boa_1`):
## Sunday 06:00–11:59 in a random acre (`turnipbuyer_start`). Talk: `JoanTalk`.


func _init() -> void:
	species = &"boa"
	display_name = "Joan"


func make_talk() -> BankTalk:
	var price: int = 100
	if Game != null and Game.shops != null:
		Game.shops.kabu.update(Clock.year, Clock.month, Clock.day)
		price = maxi(Game.shops.kabu.price_on(0), 1)
	var t := JoanTalk.new(price, Game.inventory if Game != null else null)
	t.setup(Game.events.area(&"kabu_peddler") if Game != null and Game.events != null else {})
	return t
