extends EventNpc

## Katrina at the shrine on New Year's Day (`ac_ev_miko`, `SP_NPC_EV_MIKO`, skeleton `bpt_1`),
## behind the fortune table. `MikoTalk` sells the lottery.

## `ABS(player_angle_y - rotation.y) < 33.75°`.
const FRONT_ANGLE := deg_to_rad(33.75)


func _init() -> void:
	species = &"bpt"
	display_name = "Katrina"


func make_talk() -> BankTalk:
	var t := MikoTalk.new(Game.inventory if Game != null else null, rng())
	var p: Node3D = player_node()
	if p != null:
		var to: Vector3 = p.global_position - global_position
		t.in_front = absf(angle_difference(home_yaw, atan2(to.x, to.z))) < FRONT_ANGLE
	return t
