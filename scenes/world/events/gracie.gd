extends EventNpc

## Gracie (`ac_ev_designer`, `SP_NPC_DESIGNER`, skeleton `grf_1`) beside her car
## (`DESIGNER_CAR`, `obj_s_car`) on an empty lot (`designer_start`): one unit east and two
## south of it (`aEDSN_think_init_proc`). `GracieTalk` asks for a wash; the minigame is
## `aEDSN_game_end_wait`: the player scrubs (`ply_1_wash1`–`5`, speed from how fast A is
## pressed) and 100 presses inside 1080 frames finish it — with more than 360 frames left
## the result is 0 (her own shirt), else 1 (a common one); running out of time is 2.

const WASH_FRAMES := 1080
const FAST_FRAMES_LEFT := 360
const PRESSES := 100
const WASH_CLIPS: Array[String] = ["ply_1_wash1", "ply_1_wash2", "ply_1_wash3", "ply_1_wash4", "ply_1_wash5"]

enum Think { TALK_WAIT, GAME_START, WASHING, GAME_END }

var think_state: Think = Think.TALK_WAIT
var car_position: Vector3 = Vector3.ZERO
var _complete: bool = false
var _result: int = 2
var _frames_left: float = 0.0
var _presses: int = 0
var _speed: float = 0.0
var _clip_index: int = 0
var _player: Player
var _player_return: Vector3
var _player_yaw: float = 0.0


func _init() -> void:
	species = &"grf"
	display_name = "Gracie"


func _area() -> Dictionary:
	return Game.events.area(&"designer") if Game != null and Game.events != null else {}


func can_talk() -> bool:
	return visible and think_state == Think.TALK_WAIT


func make_talk() -> BankTalk:
	var t := GracieTalk.new(GracieTalk.Kind.NORMAL, _area(), Game.inventory if Game != null else null, rng())
	_fill(t)
	return t


func _fill(t: GracieTalk) -> void:
	t.complete = _complete
	t.result = _result
	if Game != null:
		t.female = String(Game.player_gender) == "girl" or String(Game.player_gender) == "female"
		t.wearing = FtrCatalog.named_list("cloth", "Event").has(Game.cloth_id)
		t.holding_tool = Game.inventory != null and Game.inventory.equipment_id != &""


func talk_ended(script: BankTalk) -> void:
	var t := script as GracieTalk
	if t == null:
		return
	match t.kind:
		GracieTalk.Kind.NORMAL:
			if t.wants_wash and not t.holding_tool:
				_start_wash()
		GracieTalk.Kind.START:
			think_state = Think.WASHING
		GracieTalk.Kind.RESULT:
			think_state = Think.TALK_WAIT
			if t.present != &"":
				var p: Node3D = player_node()
				if p != null:
					HandOver.npc_gives_to_player(self, p, t.present)


## `aEDSN_game_start_call_wait`: the player steps up to the car.
func _start_wash() -> void:
	_player = player_node() as Player
	if _player == null:
		return
	think_state = Think.GAME_START
	_player_return = _player.global_position
	_player_yaw = _player.rotation.y
	_player.set_busy(true)
	_player.set_cutscene_driven(true)
	_player.global_position = car_position + Vector3(0.0, 0.0, 1.6)
	_player.apply_facing(PI)
	_frames_left = WASH_FRAMES
	_presses = 0
	_speed = 0.0
	_clip_index = 0
	_play_wash_clip()
	var t := GracieTalk.new(GracieTalk.Kind.START, _area(), Game.inventory if Game != null else null, rng())
	_fill(t)
	begin_talk(_player, t, false)


func think(delta: float) -> void:
	if think_state != Think.WASHING:
		return
	## `aEDSN_game_end_wait`, per 60 Hz frame.
	var frames: float = delta * DecompTime.TICK_HZ
	if Input.is_action_just_pressed("interact"):
		_presses += 1
		_speed = minf(_speed + 0.61, 2.25)
	else:
		_speed = maxf(_speed - 0.07 * frames, 0.0)
	var ap: AnimationPlayer = _player.animation_player() if _player != null else null
	if ap != null:
		ap.speed_scale = _speed
		if not ap.is_playing():
			_clip_index = (_clip_index + 1) % WASH_CLIPS.size()
			_play_wash_clip()
	_frames_left -= frames
	if _frames_left <= 0.0:
		_finish_wash(2)
	elif _presses >= PRESSES:
		_finish_wash(0 if _frames_left > FAST_FRAMES_LEFT else 1)


func _play_wash_clip() -> void:
	var ap: AnimationPlayer = _player.animation_player() if _player != null else null
	if ap == null:
		return
	for anim_name: String in ap.get_animation_list():
		if anim_name.ends_with(WASH_CLIPS[_clip_index]):
			var a: Animation = ap.get_animation(anim_name)
			if a != null:
				a.loop_mode = Animation.LOOP_NONE
			ap.play(anim_name, 0.1)
			return


## `aEDSN_game_end_call_init` → forced talk idx 25.
func _finish_wash(result: int) -> void:
	think_state = Think.GAME_END
	_result = result
	_complete = true
	if _player != null and is_instance_valid(_player):
		var ap: AnimationPlayer = _player.animation_player()
		if ap != null:
			ap.speed_scale = 1.0
		_player.set_cutscene_driven(false)
		_player.set_busy(false)
		_player.global_position = _player_return
		_player.apply_facing(_player_yaw)
		_player.play_wait_idle()
	var t := GracieTalk.new(GracieTalk.Kind.RESULT, _area(), Game.inventory if Game != null else null, rng())
	_fill(t)
	begin_talk(_player, t)
