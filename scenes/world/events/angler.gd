extends EventNpc

## Chip at the bass-fishing tourney (`ac_ev_angler`, `SP_NPC_ANGLER`, skeleton `bev_1`). Each
## time he's set up a villager may have beaten the day's record (`aTRC_clip_random_topsize`);
## `AnglerTalk` measures the player's bass.

## Villagers out fishing today (`mEvMN_GetJointEventRandomNpc`), set by the presenter.
var anglers: Array = []


func _init() -> void:
	species = &"bev"
	display_name = "Chip"


func area() -> Dictionary:
	if Game == null or Game.events == null:
		return {}
	var id: StringName = event_id if event_id != &"" else &"fishing_tourney_1"
	var a: Dictionary = Game.events.area(id)
	var today: String = Game.events.day_key()
	if str(a.get("date", "")) != today:
		a.clear()
		a["date"] = today
	return a


func setup() -> void:
	AnglerTalk.roll_npc_record(area(), Clock.hour, anglers, rng())


func make_talk() -> BankTalk:
	return AnglerTalk.new(area(), Game.inventory if Game != null else null, rng(), Clock.hour)
