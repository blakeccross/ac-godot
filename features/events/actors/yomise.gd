extends EventNpc

## Redd behind the fireworks stall (`ac_ev_yomise`, `SP_NPC_EV_YOMISE2`, skeleton `fob_1`),
## fanning himself (`aYMS_make_utiwa`). `YomiseTalk` sells tonight's goods; only a player
## facing the counter gets served (`Actor_player_look_direction_check`, 45°).

const SERVE_ANGLE := deg_to_rad(45.0)


func _init() -> void:
	species = &"fob"
	display_name = "Redd"
	talk_label = "Talk to Redd"


func idle_clip() -> String:
	return "npc_1_utiwa_wait1"


func can_talk() -> bool:
	var p: Node3D = player_node()
	if p == null:
		return visible
	var to: Vector3 = p.global_position - global_position
	return visible and absf(angle_difference(home_yaw, atan2(to.x, to.z))) < SERVE_ANGLE


func make_talk() -> BankTalk:
	var area: Dictionary = {}
	if Game != null and Game.events != null:
		area = Game.events.area(&"fireworks_show")
		var today: String = Game.events.day_key()
		if str(area.get("date", "")) != today:
			area.clear()
			area["date"] = today
	return YomiseTalk.new(area, Game.inventory if Game != null else null, rng())
