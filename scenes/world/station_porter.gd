class_name StationPorter
extends Node3D

## Porter (`ac_npc_station_master`, `SP_NPC_STATION_MASTER`) standing on the station platform.
## The title demo places him from `title_demo_actable` at block (3, 1), unit (5, 4) — no
## one-unit east shift, which only normal play applies (`mEv_IsNotTitleDemo`). In the demo he
## runs think 8 (`aSTM_talk_wait` → `aSTM_look_player`): each time his current action ends he
## turns to face the player (`aNPC_ACT_TURN2`, action 14: `WAIT1` clip, `0x800` × 30 per second) if
## they are more than 67.5° off his facing, otherwise he waits one `WAIT1` loop.
##
## Station arrival (`mEv_CheckFirstIntro`, `aSTM_think_init_proc`): he starts at the same unit
## turned −90° (facing west, up the line), and `GET_OFF_WAIT` turns him to the player at once.
## After his force-talk (`0x07DD`) he turns east (`INTERRUPT_TURN`), walks one unit east
## (`INTERRUPT_MOVE`, `aNPC_ACT_WALK` to `x + 40`), then turns back to the player and looks
## after them from there (`THINK_4`, `aSTM_talk_wait`) — the unit normal play puts him on.
##
## Normal play (`fd_npc_land_actable`, with his talk and train-calling) is not modelled yet.

const SKELETON := &"mnk_1"
const WAIT_CLIP := "npc_1_wait1"
const WALK_CLIP := "npc_1_walk1"
## Block (3, 1) unit (5, 4), unit centre: 3·640 + 5·40 + 20, 1·640 + 4·40 + 20.
const TITLE_GX := Vector3(2140.0, 0.0, 820.0)
## `chase_angle` scales its step by `game_GameFrame_2F` (frame × 0.5), so a chase-angle turn is
## `step × 30` per second at any frame rate: `0x800` → half of it per 60 Hz frame.
const TURN_STEP := float(0x800) * MLib.S16 / DecompTime.TICKS_PER_FRAME
const LOOK_CONE := deg_to_rad(67.5)
## `aSTM_think_init_proc` (first intro): `rotation.y += DEG2SHORT_ANGLE2(-90)` from angle 0.
const INTRO_YAW := -PI * 0.5
## `aSTM_interrupt_*_init`: one unit (`mFI_UT_WORLDSIZE_X_F`) east of where he stands.
const STEP_EAST_GX := 40.0

enum Mode { LOOK, TURN_EAST, WALK_EAST }

var facing: float = 0.0
var _turning: bool = false
var _wait_left: float = 0.0
var _wait_len: float = 1.0
var _steps := FrameStepper.new()
var _built: bool = false
var _mode: Mode = Mode.LOOK
var _goal: Vector3 = Vector3.ZERO
var _move: NpcPointMove = NpcPointMove.new()
var _anim: AnimationPlayer
## `aSTM_norm_talk_request` (THINK_4 onward): set by whoever owns his talk; empty = no talk.
var talk_handler: Callable = Callable()
## He is the one talking (force or normal talk): the mouth flaps while text is laid in.
var speaking: bool = false
var _face: NpcFace = NpcFace.new()
## First-intro think chain (`aSTM_intro_demo_wait_init` closes the platform gate).
var _intro: bool = false


@onready var _body: StaticBody3D = $Body


func _ready() -> void:
	visible = false
	_body.process_mode = Node.PROCESS_MODE_DISABLED
	set_physics_process(false)


## Stand at `world` (ground height) facing south (NPC default angle 0), then start looking.
func place(world: Vector3) -> void:
	_intro = false
	_place(world, 0.0)


## `aSTM_think_init_proc` first-intro branch + `aSTM_get_off_wait_init`: turned −90°, then an
## unconditional `TURN2` toward the player (no 67.5° cone on this first request).
func place_intro(world: Vector3) -> void:
	_place(world, INTRO_YAW)
	_intro = true
	_turning = true


## His current action has ended (`action.step == aNPC_ACTION_END_STEP`): the think table only
## advances — and a force-talk only starts — between actions.
func is_idle() -> bool:
	return _mode == Mode.LOOK and not _turning


## `aSTM_talk_end_chk` → `INTERRUPT_TURN` → `INTERRUPT_MOVE`: turn to and walk one unit east.
func begin_step_east() -> void:
	_goal = global_position + Vector3(STEP_EAST_GX * FieldCatalog.GX_TO_METERS, 0.0, 0.0)
	_mode = Mode.TURN_EAST
	_turning = false
	_move.reset(facing)


func _place(world: Vector3, yaw: float) -> void:
	_build()
	global_position = world
	facing = yaw
	rotation.y = facing
	_mode = Mode.LOOK
	_move.reset(yaw)
	_turning = false
	_wait_left = 0.0
	_play(WAIT_CLIP)
	visible = true
	## `MASSTYPE_IMMOVABLE` (`aSTM_think_init_proc`): the player bumps into him.
	_body.process_mode = Node.PROCESS_MODE_INHERIT
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_steps.add(delta)
	while _steps.next():
		_tick()
	rotation.y = facing


## `mnk_1` eye / mouth banks: blinks always, `mMsg_Check_NowUtter` mouth while he speaks.
func _process(delta: float) -> void:
	if not visible:
		return
	_face.tick(delta, speaking and DialogueOverlay.uttering_in(get_tree()))


func _tick() -> void:
	match _mode:
		Mode.TURN_EAST:
			var want_east: float = _yaw_to(_goal)
			facing = turn_toward(facing, want_east)
			if is_equal_approx(facing, want_east):
				_mode = Mode.WALK_EAST
				_play(WALK_CLIP)
			return
		Mode.WALK_EAST:
			_tick_walk()
			return
	var player := Player.find(get_tree())
	if player == null:
		return
	var to: Vector3 = player.global_position - global_position
	var want: float = atan2(to.x, to.z)
	if _turning:
		facing = turn_toward(facing, want)
		if is_equal_approx(facing, want):
			_turning = false
		return
	_wait_left -= DecompTime.TICK_SEC
	if _wait_left > 0.0:
		return
	## `aSTM_look_player` on action end.
	if needs_turn(facing, want):
		_turning = true
	else:
		_wait_left = _wait_len


## `aNPC_act_to_point_move` (WALK) for the one-unit step.
func _tick_walk() -> void:
	var gx: float = FieldCatalog.GX_TO_METERS
	var pos: Vector3 = global_position / gx
	var goal: Vector3 = _goal / gx
	if NpcPointMove.arrived(pos, goal):
		## `aSTM_interrupt_move` → `THINK_4`: `aSTM_intro_demo_wait_init` turns to the player
		## and sets the unit he now stands on back to `mCoBG_ATTRIBUTE_32`.
		if _intro:
			FieldTrain.set_station_gate(get_tree(), false)
		_mode = Mode.LOOK
		_move.stop()
		_turning = true
		_play(WAIT_CLIP)
		return
	_move.facing = facing
	var next: Vector3 = _move.step_to(pos, goal, false)
	facing = _move.facing
	global_position.x = next.x * gx
	global_position.z = next.z * gx


func _yaw_to(world: Vector3) -> float:
	var to: Vector3 = world - global_position
	return atan2(to.x, to.z)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if not talk_handler.is_valid() or _mode != Mode.LOOK:
		return []
	return [Interaction.of(Interaction.TALK, "Talk to Porter", 20)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK or not talk_handler.is_valid():
		return false
	await talk_handler.call()
	return true


## `aSTM_look_player`: turn unless the player is within ±67.5° of his facing.
static func needs_turn(p_facing: float, toward_player: float) -> bool:
	return absf(angle_difference(p_facing, toward_player)) >= LOOK_CONE


## One tick of `aNPC_ACT_TURN2` (`mv_add_angl` 0x800).
static func turn_toward(p_facing: float, target: float) -> float:
	return NpcPointMove.chase_yaw(p_facing, target, TURN_STEP)


func _play(clip: String) -> void:
	if _anim == null:
		return
	for anim_name: String in _anim.get_animation_list():
		if anim_name.ends_with(clip):
			var animation: Animation = _anim.get_animation(anim_name)
			animation.loop_mode = Animation.LOOP_LINEAR
			if _anim.current_animation != anim_name:
				_anim.play(anim_name, 0.16)
			return


func _build() -> void:
	if _built:
		return
	_built = true
	var pivot: Node3D = GeneratedVisual.attach_special_npc(self, SKELETON)
	if pivot != null:
		_face.bind(pivot, &"mnk", SKELETON)
	_anim = VisualAnimation.find_animation_player(self)
	if _anim == null:
		return
	for anim_name: String in _anim.get_animation_list():
		if anim_name.ends_with(WAIT_CLIP):
			var animation: Animation = _anim.get_animation(anim_name)
			animation.loop_mode = Animation.LOOP_LINEAR
			_wait_len = maxf(animation.length, 0.1)
			_anim.play(anim_name)
			return
