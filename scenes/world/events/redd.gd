extends EventNpc

## Crazy Redd outside his tent (`ac_ev_broker`, `SP_NPC_BROKER`, skeleton `fox_1`), two units
## in front of the door (`broker_start`). He faces the street; after one talk he turns
## round (`aEBRK_ACTION_TURN`), walks in (`ENTER`, 60 GX) and is gone (`hide_request`). He
## is not out at all once the stock is gone, or after the player has been inside
## (`broker.hide_npc`).

const ENTER_DIST := 60.0 * FieldCatalog.GX_TO_METERS

enum Act { WAIT, TURN, ENTER, HIDDEN }

var act: Act = Act.WAIT
var _enter_from: Vector3


func _init() -> void:
	species = &"fox"
	display_name = "Redd"


func _area() -> Dictionary:
	return Game.events.area(&"broker_sale") if Game != null and Game.events != null else {}


func setup() -> void:
	if ReddStock.left(_area()) == 0 or bool(_area().get("hide_npc", false)):
		_hide()


func can_talk() -> bool:
	return visible and act == Act.WAIT


func make_talk() -> BankTalk:
	var t := ReddTalk.new(ReddTalk.Kind.OUTSIDE, _area(), Game.inventory if Game != null else null, rng())
	t.been_inside = bool(_area().get("entered", false))
	return t


func talk_ended(_script: BankTalk) -> void:
	## `aEBRK_think_main_proc`: turn to face the tent (180°) and walk in.
	act = Act.TURN


func think(delta: float) -> void:
	match act:
		Act.TURN:
			if turn_to(home_yaw + PI, delta):
				act = Act.ENTER
				_enter_from = global_position
				var forward := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
				move_to(global_position + forward * ENTER_DIST, 1.0 * 30.0 * FieldCatalog.GX_TO_METERS)


func arrived() -> void:
	if act == Act.ENTER:
		_hide()
		return
	super.arrived()


func _hide() -> void:
	act = Act.HIDDEN
	visible = false
	collision_layer = 0
	var vol: Node = get_node_or_null("InteractVolume")
	if vol is Area3D:
		(vol as Area3D).monitorable = false
