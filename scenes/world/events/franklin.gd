extends EventNpc

## Franklin on Harvest Festival day (`ac_ev_turkey`, `SP_NPC_TURKEY`, skeleton `tuk_1`),
## hiding in an ordinary acre and glancing about (`aETKY_ActionKyoro`). He calls out to a
## player who comes close (`mDemo_TYPE_SPEAK`, 55 GX) the first time; `FranklinTalk` runs
## the rest.

const CALL_RANGE := 55.0 * FieldCatalog.GX_TO_METERS

var _present: int = -1
var _spoke: bool = false


func _init() -> void:
	species = &"tuk"
	display_name = "Franklin"


func idle_clip() -> String:
	return "npc_1_kyoro1"


func area() -> Dictionary:
	return Game.events.area(&"harvest_festival_franklin") if Game != null and Game.events != null else {}


func _day_area() -> Dictionary:
	var a: Dictionary = area()
	var today: String = Game.events.day_key() if Game != null and Game.events != null else ""
	if str(a.get("date", "")) != today:
		a["date"] = today
		a["talks"] = 0
	return a


func setup() -> void:
	_present = FranklinTalk.decide_present(_day_area(), rng())


func make_talk() -> BankTalk:
	var t := FranklinTalk.new(_day_area(), Game.inventory if Game != null else null, rng(), _present)
	t.spoke_this_visit = _spoke
	_spoke = true
	return t


func think(_delta: float) -> void:
	if not _spoke and can_call_out() and player_distance() <= CALL_RANGE:
		begin_talk(player_node())
