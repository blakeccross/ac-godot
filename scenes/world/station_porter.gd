class_name StationPorter
extends Node3D

## Porter (`ac_npc_station_master`, `SP_NPC_STATION_MASTER`) standing on the station platform.
## The title demo places him from `title_demo_actable` at block (3, 1), unit (5, 4) — no
## one-unit east shift, which only normal play applies (`mEv_IsNotTitleDemo`). In the demo he
## runs think 8 (`aSTM_talk_wait` → `aSTM_look_player`): each time his current action ends he
## turns to face the player (`aNPC_ACT_TURN2`, action 14: `WAIT1` clip, `0x800` × 30 per second) if
## they are more than 67.5° off his facing, otherwise he waits one `WAIT1` loop.
##
## Normal play (`fd_npc_land_actable`, with his talk and train-calling) is not modelled yet.

const SKELETON := &"mnk_1"
const WAIT_CLIP := "npc_1_wait1"
## Block (3, 1) unit (5, 4), unit centre: 3·640 + 5·40 + 20, 1·640 + 4·40 + 20.
const TITLE_GX := Vector3(2140.0, 0.0, 820.0)
const TICK_HZ := PlayerLocomotion.LOGIC_HZ
## `chase_angle` scales its step by `game_GameFrame_2F` (frame × 0.5), so a chase-angle turn is
## `step × 30` per second at any frame rate: `0x800` → half of it per 60 Hz frame.
const TURN_STEP := TAU * float(0x800) / 65536.0 * 30.0 / TICK_HZ
const LOOK_CONE := deg_to_rad(67.5)

var facing: float = 0.0
var _turning: bool = false
var _wait_left: float = 0.0
var _wait_len: float = 1.0
var _accum: float = 0.0
var _built: bool = false


@onready var _body: StaticBody3D = $Body


func _ready() -> void:
	visible = false
	_body.process_mode = Node.PROCESS_MODE_DISABLED
	set_physics_process(false)


## Stand at `world` (ground height) facing south (NPC default angle 0), then start looking.
func place(world: Vector3) -> void:
	_build()
	global_position = world
	facing = 0.0
	rotation.y = facing
	_turning = false
	_wait_left = 0.0
	visible = true
	## `MASSTYPE_IMMOVABLE` (`aSTM_think_init_proc`): the player bumps into him.
	_body.process_mode = Node.PROCESS_MODE_INHERIT
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_accum += delta * TICK_HZ
	while _accum >= 1.0:
		_accum -= 1.0
		_tick()
	rotation.y = facing


func _tick() -> void:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var to: Vector3 = player.global_position - global_position
	var want: float = atan2(to.x, to.z)
	if _turning:
		facing = turn_toward(facing, want)
		if is_equal_approx(facing, want):
			_turning = false
		return
	_wait_left -= 1.0 / TICK_HZ
	if _wait_left > 0.0:
		return
	## `aSTM_look_player` on action end.
	if needs_turn(facing, want):
		_turning = true
	else:
		_wait_left = _wait_len


## `aSTM_look_player`: turn unless the player is within ±67.5° of his facing.
static func needs_turn(p_facing: float, toward_player: float) -> bool:
	return absf(angle_difference(p_facing, toward_player)) >= LOOK_CONE


## One tick of `aNPC_ACT_TURN2` (`mv_add_angl` 0x800).
static func turn_toward(p_facing: float, target: float) -> float:
	var diff: float = angle_difference(p_facing, target)
	if absf(diff) <= TURN_STEP:
		return target
	return wrapf(p_facing + signf(diff) * TURN_STEP, -PI, PI)


func _build() -> void:
	if _built:
		return
	_built = true
	GeneratedVisual.attach_special_npc(self, SKELETON)
	var anim: AnimationPlayer = VisualAnimation.find_animation_player(self)
	if anim == null:
		return
	for anim_name: String in anim.get_animation_list():
		if anim_name.ends_with(WAIT_CLIP):
			var animation: Animation = anim.get_animation(anim_name)
			animation.loop_mode = Animation.LOOP_LINEAR
			_wait_len = maxf(animation.length, 0.1)
			anim.play(anim_name)
			return
