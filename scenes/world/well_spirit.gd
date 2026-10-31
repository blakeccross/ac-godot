class_name WellSpirit
extends EventNpc

## The wishing well's spirit (`ac_npc_hem`, `SP_NPC_HEM`). Called up beside the well once the
## town has been perfect long enough; it speaks first (`MSG_HEM_GOLD_AXE1`), and as it does
## the golden axe goes into the pockets and the perfect-day count starts over
## (`aNHM_set_force_talk_info_talk_request`). Then it fades back into the well.

const MSG_GOLD_AXE := 11345
const GOLDEN_AXE := &"golden_axe"

var _spoke: bool = false
var _light: SpiritLight = null


class Speech extends BankTalk:
	func start_msg() -> int:
		return WellSpirit.MSG_GOLD_AXE


func _init() -> void:
	species = &"hem"
	display_name = "Spirit"


func can_talk() -> bool:
	return false


func think(_delta: float) -> void:
	if _spoke or not visible or not can_call_out():
		return
	_spoke = true
	var axe: ItemData = ItemCatalog.get_item(GOLDEN_AXE)
	if axe != null and Game.inventory != null:
		Game.inventory.add(axe, 1)
	Game.town.golden_axe_got = true
	Game.town.perfect_streak = 0
	Game.town.perfect_streak_day = -1
	if not begin_talk(player_node(), Speech.new()):
		_vanish()


## `mDemo_Set_talk_return_get_golden_axe_demo`: the player holds the axe up as it goes.
func talk_ended(_script: BankTalk) -> void:
	_vanish()
	var p := player_node() as Player
	if p != null:
		p.reports.get_golden_item(GOLDEN_AXE)


## `aSHR_make_hem` again: the glow comes up and the spirit goes with it.
func _vanish() -> void:
	if _light != null and is_instance_valid(_light):
		_light.finish()
	var glow: SpiritGlow = SpiritGlow.play(get_parent(), global_position, false)
	if glow == null:
		queue_free()
		return
	glow.swapped.connect(hide)
	glow.tree_exited.connect(queue_free)


## `aSHR_make_hem`: one unit in front of the well, facing the player.
static func appear(well: Node3D, player: Node3D) -> Node3D:
	if well == null or well.get_parent() == null:
		return null
	var spirit := (load("res://scenes/world/well_spirit.tscn") as PackedScene).instantiate() as WellSpirit
	var front := Vector3(sin(well.global_rotation.y), 0.0, cos(well.global_rotation.y))
	if player != null:
		var to: Vector3 = player.global_position - well.global_position
		spirit.home_yaw = atan2(to.x, to.z)
	well.get_parent().add_child(spirit)
	spirit.global_position = well.global_position + front * 2.0
	## It stands unseen in the glow until tick 150 (`Common_Set(hem_visible, TRUE)`).
	spirit.hide()
	spirit._light = SpiritLight.start(well.get_parent(), spirit.global_position)
	var glow: SpiritGlow = SpiritGlow.play(well.get_parent(), spirit.global_position, true)
	if glow != null:
		glow.swapped.connect(spirit.show)
	else:
		spirit.show()
	return spirit
