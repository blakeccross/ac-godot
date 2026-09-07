extends Node

## Music / SFX buses. Call play methods from scenes; do not scatter AudioStreamPlayer setup.

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const FADE_SEC := 1.0
## Quick duck for `Na_TTKK_ARM` guitar stem (look-up / resume strum).
const ARM_FADE_SEC := 0.12
const ARM_MUTE_DB := -40.0

var fade_sec: float = FADE_SEC
var current_id: StringName = &""
## When true, guitar arm stem is silent (`Na_TTKK_ARM(TRUE)`).
var arm_muted: bool = false

var _players: Array[AudioStreamPlayer] = []
var _front: int = 0
var _fade: Tween
var _arm_player: AudioStreamPlayer
var _arm_fade: Tween
## `Na_SysLevStart` / `Stop` — looping ambient (rain 7/8/9). Same SE nums as door
## one-shots; playback mode differs (`Sou_LevStart` vs trg).
var _syslev_player: AudioStreamPlayer
var _syslev_id: int = 0


func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	_players = [_make_player(), _make_player()]
	_arm_player = _make_player()
	_syslev_player = AudioStreamPlayer.new()
	_syslev_player.bus = SFX_BUS
	add_child(_syslev_player)


func play_sfx(stream: AudioStream, at: Node = self, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	if stream == null or at == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = SFX_BUS
	player.pitch_scale = maxf(0.01, pitch_scale)
	player.volume_db = volume_db
	at.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Play a catalog SE id (`cursol`, `bebe`, …). No-op if the stream is missing.
func play_se(id: StringName, at: Node = self, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	if id == &"":
		return
	play_sfx(SeCatalog.stream_for(id), at, pitch_scale, volume_db)


## Play an animalese phoneme clip for voice seq spec 1–3.
func play_voice(
	spec: int,
	phoneme: int,
	pitch_scale: float = 1.0,
	volume_db: float = 0.0,
	at: Node = self
) -> void:
	play_sfx(VoiceCatalog.stream_for(spec, phoneme), at, pitch_scale, volume_db)


## `Na_SysLevStart`: loop SE id (rain ambient uses 7 / 8 / 9 by intensity).
func start_syslev(id: int, volume_db: float = 0.0) -> void:
	if id <= 0:
		stop_syslev()
		return
	if _syslev_id == id and _syslev_player != null and _syslev_player.playing:
		_syslev_player.volume_db = volume_db
		return
	if _syslev_player == null:
		_syslev_player = AudioStreamPlayer.new()
		_syslev_player.bus = SFX_BUS
		add_child(_syslev_player)
	var stream: AudioStream = SeCatalog.stream_for(StringName(str(id)))
	if stream == null:
		stop_syslev()
		return
	## Duplicate so door one-shots keep non-looping instances.
	var looped: AudioStream = stream.duplicate()
	if looped is AudioStreamOggVorbis:
		(looped as AudioStreamOggVorbis).loop = true
	elif looped is AudioStreamWAV:
		(looped as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_syslev_player.stop()
	_syslev_player.stream = looped
	_syslev_player.volume_db = volume_db
	_syslev_player.play()
	_syslev_id = id


## `Na_SysLevStop`. Pass 0 / omit to stop whatever is playing.
func stop_syslev(id: int = 0) -> void:
	if id > 0 and _syslev_id != 0 and id != _syslev_id:
		return
	if _syslev_player != null:
		_syslev_player.stop()
		_syslev_player.stream = null
	_syslev_id = 0


## Rain SysLev from `aWeather_ChangeEnvSE` (no umbrella variants yet).
func sync_rain_syslev(kind: Weather.Kind, intensity: Weather.Intensity, indoors: bool) -> void:
	if indoors or kind != Weather.Kind.RAIN:
		stop_syslev()
		return
	match intensity:
		Weather.Intensity.LIGHT:
			start_syslev(7)
		Weather.Intensity.NORMAL:
			start_syslev(8)
		Weather.Intensity.HEAVY:
			start_syslev(9)
		_:
			stop_syslev()


func play_bgm(id: StringName) -> void:
	if id == current_id:
		return
	if id == &"":
		stop_bgm()
		return
	var stream: AudioStream = BgmCatalog.stream_for(id)
	if stream == null:
		stop_bgm()
		return
	if _players.is_empty():
		_players = [_make_player(), _make_player()]
	var incoming: int = 1 - _front
	var next_player: AudioStreamPlayer = _players[incoming]
	var prev_player: AudioStreamPlayer = _players[_front]
	next_player.stream = stream
	next_player.volume_db = -40.0 if fade_sec > 0.0 else 0.0
	next_player.play()
	_kill_fade()
	if fade_sec <= 0.0 or not prev_player.playing:
		prev_player.stop()
		next_player.volume_db = 0.0
	else:
		_fade = create_tween()
		_fade.set_parallel(true)
		_fade.tween_property(next_player, "volume_db", 0.0, fade_sec)
		_fade.tween_property(prev_player, "volume_db", -40.0, fade_sec)
		_fade.chain().tween_callback(prev_player.stop)
	_front = incoming
	current_id = id
	_start_arm_stem(id, next_player.volume_db)


func stop_bgm() -> void:
	if current_id == &"" and not _any_playing():
		_stop_arm(true)
		return
	_kill_fade()
	if fade_sec <= 0.0:
		for player: AudioStreamPlayer in _players:
			player.stop()
			player.volume_db = 0.0
		_stop_arm(true)
	else:
		_fade = create_tween()
		_fade.set_parallel(true)
		for player: AudioStreamPlayer in _players:
			if player.playing:
				_fade.tween_property(player, "volume_db", -40.0, fade_sec)
		if _arm_player != null and _arm_player.playing:
			_fade.tween_property(_arm_player, "volume_db", ARM_MUTE_DB, fade_sec)
		_fade.chain().tween_callback(_stop_all)
	current_id = &""


## `Na_TTKK_ARM`: mute guitar stem while K.K. looks up / is not strumming.
func set_ttkk_arm(muted: bool) -> void:
	if arm_muted == muted:
		return
	arm_muted = muted
	if _arm_player == null or not _arm_player.playing:
		return
	_kill_arm_fade()
	var target_db: float = ARM_MUTE_DB if muted else 0.0
	if fade_sec <= 0.0:
		_arm_player.volume_db = target_db
		return
	_arm_fade = create_tween()
	_arm_fade.tween_property(_arm_player, "volume_db", target_db, ARM_FADE_SEC)


func _start_arm_stem(id: StringName, bed_volume_db: float) -> void:
	if _arm_player == null:
		_arm_player = _make_player()
	_kill_arm_fade()
	var arm: AudioStream = BgmCatalog.arm_stream_for(id)
	if arm == null:
		_arm_player.stop()
		_arm_player.stream = null
		return
	_arm_player.stream = arm
	if arm_muted:
		_arm_player.volume_db = ARM_MUTE_DB
	else:
		_arm_player.volume_db = bed_volume_db
	_arm_player.play()
	if not arm_muted and fade_sec > 0.0 and bed_volume_db < -0.5:
		_arm_fade = create_tween()
		_arm_fade.tween_property(_arm_player, "volume_db", 0.0, fade_sec)


func _stop_arm(immediate: bool = false) -> void:
	_kill_arm_fade()
	if _arm_player == null:
		return
	if immediate or fade_sec <= 0.0:
		_arm_player.stop()
		_arm_player.volume_db = 0.0
		_arm_player.stream = null


func _stop_all() -> void:
	for player: AudioStreamPlayer in _players:
		player.stop()
		player.volume_db = 0.0
	_stop_arm(true)


func _any_playing() -> bool:
	for player: AudioStreamPlayer in _players:
		if player.playing:
			return true
	if _arm_player != null and _arm_player.playing:
		return true
	return false


func _kill_fade() -> void:
	if _fade != null:
		_fade.kill()
		_fade = null


func _kill_arm_fade() -> void:
	if _arm_fade != null:
		_arm_fade.kill()
		_arm_fade = null


func _make_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = MUSIC_BUS
	add_child(player)
	return player


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var index: int = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")
