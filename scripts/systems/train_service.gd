class_name TrainService
extends Node

## Runs the town train for the whole play session (`mTRC_init` once, `mTRC_move` every play
## frame, indoors too; it stops while the game is paused, like `mSM_PROCESS_WAIT`). Owned by
## `Game`. Drives the `FieldTrain` in the loaded outdoor scene and plays the train's sounds
## (`Na_KishaStatusTrg` / `Na_KishaStatusLevel`).
##
## Sounds are placed against the decomp "mic": the player + (0, 240, 77) GX outdoors, the exit
## door indoors (`mTRC_SetMicPos`). Stereo pan uses one shared panner on the `Train` bus, set
## from the locomotive's bearing each tick (the wheel clack really comes from 250 GX behind).

const TICK_HZ := TrainControl.TICK_HZ
const MIC_OFFSET_GX := Vector3(0.0, 240.0, 77.0)
## `train_position.y` (GAFE01_00 `mTRC_*_init`): the height the sounds use.
const SOUND_Y_GX := 180.0

## `sou_scene_mode`: 0 = title (every ongen call returns), 1 = field, 2 = room.
const SCENE_SILENT := 0
const SCENE_FIELD := 1
const SCENE_ROOM := 2

const WHISTLE_ARRIVE := {SCENE_FIELD: &"70", SCENE_ROOM: &"6e"}
const WHISTLE_DEPART := {SCENE_FIELD: &"71", SCENE_ROOM: &"6f"}
const STOP_SE := &"73"
const CHUFF_SE := &"3b"
const CLACK_SE := &"3f"
const RUN_LEVEL_SE := &"lev_10"

## `SOU_ONGEN_AREA1` and the `distance2vol` / `distance2vol4KITEKI` curves (GX).
const ONGEN_AREA := 540.0
const ONGEN_BASE_VOLUME := 1.15
const KITEKI_BASE_VOLUME := 1.15
const KITEKI_MIN := 320.0
const KITEKI_MAX := 6400.0

const BUS := "Train"

var control: TrainControl = TrainControl.new()

var _initialized: bool = false
var _accum: float = 0.0
## `sou_kisha_status`, `sou_shu_count`, `sou_tonton_count`.
var _status: int = 0
var _shu: int = 0
var _tonton: int = 0
var _run_player: AudioStreamPlayer
var _panner: AudioEffectPanner


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_ensure_bus()
	_run_player = AudioStreamPlayer.new()
	_run_player.name = "RunLevel"
	_run_player.bus = BUS
	add_child(_run_player)


## `mTRC_init`: a new play session starts with no train and a fresh timetable.
func reset() -> void:
	_initialized = false
	_accum = 0.0
	_status = 0
	_shu = 0
	_tonton = 0
	_stop_run()
	var train: FieldTrain = _field_train()
	if train != null:
		train.despawn()


func _physics_process(delta: float) -> void:
	if not is_active():
		_stop_run()
		var idle: FieldTrain = _field_train()
		if idle != null:
			idle.despawn()
		return
	if not _initialized:
		control.init(Clock.now_sec(), Clock.day)
		_initialized = true
	_accum += delta * TICK_HZ
	while _accum >= 1.0:
		_accum -= 1.0
		_tick()


## `mTRC_go_process`: the field train runs in play (not the K.K. / Rover intro scenes, and not
## while the intro arrival stage owns its own train) and in title demo 1 only.
static func is_active() -> bool:
	if Game.world_mode != WorldData.Mode.GENERATED:
		return false
	if Game.title_demo_active:
		return TitleDemo.has_parked_train(Game.title_demo_index)
	return Game.phase == Game.Phase.PLAYING and not Game.intro_station_active


func _tick() -> void:
	var parked: bool = Game.title_demo_active
	var state: int = control.step(Clock.now_sec(), Clock.day, Game.first_job.is_active(), parked)
	var mode: int = _scene_mode()
	var mic: Vector3 = _mic_gx()
	var loco := Vector3(control.x_gx, SOUND_Y_GX, TrainControl.RAIL_Z_GX)
	if control.is_running():
		_level(mode, mic, loco)
	if state != TrainControl.STATE_NONE:
		_trigger(mode, state, mic, loco)
	_sync_visual(parked, mode, mic)


## `Na_KishaStatusTrg`.
func _trigger(mode: int, state: int, mic: Vector3, loco: Vector3) -> void:
	var distance: float = mic.distance_to(loco)
	match state:
		TrainControl.STATE_DEMO:
			_status = 1
		TrainControl.STATE_APPROACH:
			_status = 2
			_play_whistle(mode, WHISTLE_ARRIVE, distance)
		TrainControl.STATE_STOPPED:
			_status = 3
			_play_ongen(mode, STOP_SE, distance)
		TrainControl.STATE_PULL_OUT:
			_status = 4
			_play_whistle(mode, WHISTLE_DEPART, distance)
		TrainControl.STATE_GONE:
			_status = 0
			_stop_run()


## `Na_KishaStatusLevel`: the running loop at the locomotive, a steam chuff and a wheel clack
## on counters that speed up with the train.
func _level(mode: int, mic: Vector3, loco: Vector3) -> void:
	var distance: float = mic.distance_to(loco)
	_panner.pan = pan_for(mic, loco)
	if _status == 0:
		return
	_update_run(mode, distance)
	var speed: float = control.speed
	var shu_period: int = int(20.0 - 2.5 * speed)
	var tonton_period: int = int(90.0 - 11.5 * speed)
	if _shu == 4 and speed > 0.4:
		_play_ongen(mode, CHUFF_SE, distance)
	if _tonton == 10 and speed > 0.4:
		var caboose := Vector3(control.caboose_x_gx(), SOUND_Y_GX, TrainControl.RAIL_Z_GX)
		_play_ongen(mode, CLACK_SE, mic.distance_to(caboose))
	if _shu > shu_period:
		_shu = 0
	if _tonton > tonton_period:
		_tonton = 0
	_shu += 1
	_tonton += 1


func _sync_visual(parked: bool, mode: int, mic: Vector3) -> void:
	var train: FieldTrain = _field_train()
	if train == null:
		return
	var player_block: Vector2i = _player_block()
	if player_block.x < 0 or not control.in_area(player_block):
		train.despawn()
		return
	if not train.is_spawned():
		train.spawn(control)
	var door: Dictionary = train.tick(control, parked)
	if bool(door.get("sound", false)):
		var caboose := Vector3(train.cars.caboose_x, SOUND_Y_GX, TrainControl.RAIL_Z_GX)
		_play_ongen(mode, TrainCars.DOOR_SE, mic.distance_to(caboose))


func _update_run(mode: int, distance: float) -> void:
	if mode == SCENE_SILENT or distance > ONGEN_AREA:
		_stop_run()
		return
	if _run_player.stream == null:
		var stream: AudioStream = SeCatalog.stream_for(RUN_LEVEL_SE)
		if stream == null:
			return
		var looped: AudioStream = stream.duplicate()
		if looped is AudioStreamOggVorbis:
			(looped as AudioStreamOggVorbis).loop = true
		elif looped is AudioStreamWAV:
			(looped as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		_run_player.stream = looped
	_run_player.volume_db = linear_to_db(maxf(ongen_volume(distance), 0.0001))
	if not _run_player.playing:
		_run_player.play()


func _stop_run() -> void:
	if _run_player != null:
		_run_player.stop()
		_run_player.stream = null


func _play_whistle(mode: int, ids: Dictionary, distance: float) -> void:
	if mode == SCENE_SILENT or distance > KITEKI_MAX:
		return
	_play(ids.get(mode, ids[SCENE_FIELD]) as StringName, whistle_volume(distance))


## `Na_OngenTrgStart` → `Sou_PosTrgStart` default branch.
func _play_ongen(mode: int, id: StringName, distance: float) -> void:
	if mode == SCENE_SILENT or distance > ONGEN_AREA:
		return
	_play(id, ongen_volume(distance))


func _play(id: StringName, volume: float) -> void:
	if volume <= 0.0:
		return
	var stream: AudioStream = SeCatalog.stream_for(id)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = BUS
	player.volume_db = linear_to_db(volume)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## `distance2vol`.
static func ongen_volume(distance: float) -> float:
	if distance > ONGEN_AREA:
		return 0.0
	return minf(ONGEN_BASE_VOLUME - (ONGEN_BASE_VOLUME / (ONGEN_AREA * ONGEN_AREA)) * distance * distance, 1.5)


## `distance2vol4KITEKI`: linear from 1.15 at 320 GX to 0 at 6400 (the decomp's early-outs are
## dead code; `Sou_PosTrgStart` already drops anything past 6400).
static func whistle_volume(distance: float) -> float:
	var scale: float = KITEKI_BASE_VOLUME / (KITEKI_MAX - KITEKI_MIN)
	return maxf(KITEKI_BASE_VOLUME - scale * (distance - KITEKI_MIN), 0.0)


## `atans_table(dz, dx)` → `angle2pan` (without the `pan_kochou` curve): −1 left … 1 right.
## Due east is hard right, due west hard left, north / south centred.
static func pan_for(mic: Vector3, source: Vector3) -> float:
	var angle: int = int(round(atan2(source.x - mic.x, source.z - mic.z) / TAU * 65536.0)) & 0xFFFF
	var a: int = angle >> 8
	var p: int
	if a >= 0x40 and a <= 0xC0:
		p = mini(0x80 - (a - 0x40), 0x7F)
	elif a >= 0xC1:
		p = a - 0xC0
	else:
		p = a + 0x40
	return clampf((float(p) - 64.0) / 64.0, -1.0, 1.0)


func _scene_mode() -> int:
	if Game.title_demo_active:
		return SCENE_SILENT
	return SCENE_ROOM if Game.current_room_id != &"" else SCENE_FIELD


## `mTRC_SetMicPos`.
func _mic_gx() -> Vector3:
	var base: Vector3 = Game.outdoor_return
	if Game.current_room_id == &"":
		var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
		if player != null:
			base = player.global_position
	return TownSpace.world_to_gx(base) + MIC_OFFSET_GX


func _player_block() -> Vector2i:
	if Game.current_room_id != &"":
		return Vector2i(-1, -1)
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return Vector2i(-1, -1)
	var gx: Vector3 = TownSpace.world_to_gx(player.global_position)
	return Vector2i(int(gx.x / TrainControl.BLOCK_GX), int(gx.z / TrainControl.BLOCK_GX))


func _field_train() -> FieldTrain:
	return get_tree().get_first_node_in_group(FieldTrain.GROUP) as FieldTrain


func _ensure_bus() -> void:
	var index: int = AudioServer.get_bus_index(BUS)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, Audio.SFX_BUS)
		AudioServer.add_bus_effect(index, AudioEffectPanner.new())
	for i: int in AudioServer.get_bus_effect_count(index):
		var effect: AudioEffect = AudioServer.get_bus_effect(index, i)
		if effect is AudioEffectPanner:
			_panner = effect as AudioEffectPanner
	if _panner == null:
		_panner = AudioEffectPanner.new()
		AudioServer.add_bus_effect(index, _panner)
