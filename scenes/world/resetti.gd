extends EventNpc

## Mr. Resetti after a reset (`ac_reset_demo`, `ac_npc_majin*`). He waits below ground until
## the player is free (`aMJN_start_wait`), pops up (`APPEAR1`) and starts talking himself
## (`mDemo_TYPE_SPEAK`); the fourth visit hangs about until spoken to (`aMJN2_THINK_WAIT`).
## Then back down (`GO_UG1`) and the reset is forgiven (`reset_flag` off). At night a warm
## light hangs in front of his face (`aRSD_set_point_light`, 19:00–05:00, RGB 255,200,0).

enum Think { START_WAIT, CALL, WAIT, EXIT }

const APPEAR := "npc_1_appear1"
const WAIT_R := "npc_1_wait_r1"
const GO_UG := "npc_1_go_ug1"
const LIGHT_COLOR := Color8(255, 200, 0)

var think_state: Think = Think.START_WAIT
var visit: Array = []
var _called: bool = false
var _light: OmniLight3D


class Lecture extends BankTalk:
	var opening: int = -1

	func _init(msg_no: int) -> void:
		opening = msg_no

	func start_msg() -> int:
		return opening


func setup() -> void:
	display_name = "Resetti" if species == ResettiVisit.RESETTI else "Don"
	visible = false
	collision_layer = 0
	_light = OmniLight3D.new()
	_light.light_color = LIGHT_COLOR
	_light.omni_range = 3.0
	_light.position = Vector3(0.0, 1.0, 0.5)
	_light.visible = false
	add_child(_light)


func idle_clip() -> String:
	return WAIT_R if think_state != Think.START_WAIT else "npc_1_wait1"


func can_talk() -> bool:
	return visible and think_state == Think.WAIT


func make_talk() -> BankTalk:
	return Lecture.new(int(visit[3])) if think_state == Think.WAIT and int(visit[3]) >= 0 else null


func think(_delta: float) -> void:
	_light.visible = visible and (Clock.hour >= 19 or Clock.hour < 5)
	match think_state:
		Think.START_WAIT:
			if can_call_out():
				think_state = Think.CALL
				visible = true
				collision_layer = 1
				play_clip(APPEAR, false)
		Think.CALL:
			if clip_done() and not _called and can_call_out():
				_called = true
				if not begin_talk(player_node(), Lecture.new(int(visit[1]))):
					_leave()
		Think.EXIT:
			if clip_done():
				_finish()


func talk_ended(_script: BankTalk) -> void:
	if think_state == Think.CALL and bool(visit[2]):
		think_state = Think.WAIT
		play_clip(WAIT_R, true)
		return
	_leave()


func _leave() -> void:
	think_state = Think.EXIT
	play_clip(GO_UG, false)


## `aRSD_retire_npc_wait`: he is gone, so the session is forgiven.
func _finish() -> void:
	Game.reset_flag = false
	var world: World = World.find(get_tree())
	if world != null:
		world.call("_play_outdoor_bgm")
	queue_free()


## Put him a few steps in front of the player, facing them.
static func spawn(parent: Node, player: Node3D) -> Node3D:
	var packed: PackedScene = load("res://scenes/world/resetti.tscn") as PackedScene
	if packed == null or parent == null or player == null:
		return null
	var npc := packed.instantiate()
	var v: Array = ResettiVisit.visit(Game.reset_count)
	Game.reset_count = ResettiVisit.normalized(Game.reset_count)
	npc.set("visit", v)
	npc.set("species", v[0])
	var yaw: float = player.call("facing_yaw") if player.has_method("facing_yaw") else 0.0
	npc.set("home_yaw", yaw + PI)
	parent.add_child(npc)
	(npc as Node3D).global_position = player.global_position + Vector3(sin(yaw), 0.0, cos(yaw)) * 2.5
	return npc
