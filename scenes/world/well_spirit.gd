class_name WellSpirit
extends EventNpc

## The wishing well's spirit (`ac_npc_hem`, `SP_NPC_HEM`). Called up beside the well once the
## town has been perfect long enough; it speaks first (`MSG_HEM_GOLD_AXE1`), and as it does
## the golden axe goes into the pockets and the perfect-day count starts over
## (`aNHM_set_force_talk_info_talk_request`). Then it fades back into the well.

const MSG_GOLD_AXE := 11345
const GOLDEN_AXE := &"golden_axe"
const FADE_SEC := 0.8

var _spoke: bool = false


class Speech extends BankTalk:
	func start_msg() -> int:
		return WellSpirit.MSG_GOLD_AXE


func _init() -> void:
	species = &"hem"
	display_name = "Spirit"


func can_talk() -> bool:
	return false


func think(_delta: float) -> void:
	if _spoke or not can_call_out():
		return
	_spoke = true
	var axe: ItemData = ItemCatalog.get_item(GOLDEN_AXE)
	if axe != null and Game.inventory != null:
		Game.inventory.add(axe, 1)
	Game.golden_axe_got = true
	Game.perfect_streak = 0
	Game.perfect_streak_day = -1
	if not begin_talk(player_node(), Speech.new()):
		_vanish()


func talk_ended(_script: BankTalk) -> void:
	_vanish()


func _vanish() -> void:
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector3.ZERO, FADE_SEC).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


## `aSHR_make_hem`: one unit in front of the well, facing the player.
static func appear(well: Node3D, player: Node3D) -> Node3D:
	if well == null or well.get_parent() == null:
		return null
	var spirit := WellSpirit.new()
	var front := Vector3(sin(well.global_rotation.y), 0.0, cos(well.global_rotation.y))
	if player != null:
		var to: Vector3 = player.global_position - well.global_position
		spirit.home_yaw = atan2(to.x, to.z)
	well.get_parent().add_child(spirit)
	spirit.global_position = well.global_position + front * 2.0
	spirit.scale = Vector3.ONE * 0.01
	spirit.create_tween().tween_property(spirit, "scale", Vector3.ONE, FADE_SEC)
	return spirit
