extends Node

## Music / SFX buses. Call play methods from scenes; do not scatter AudioStreamPlayer setup.

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const FADE_SEC := 1.0

var fade_sec: float = FADE_SEC
var current_id: StringName = &""

var _players: Array[AudioStreamPlayer] = []
var _front: int = 0
var _fade: Tween


func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	_players = [_make_player(), _make_player()]


func play_sfx(stream: AudioStream, at: Node = self) -> void:
	if stream == null or at == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = SFX_BUS
	at.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


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


func stop_bgm() -> void:
	if current_id == &"" and not _any_playing():
		return
	_kill_fade()
	if fade_sec <= 0.0:
		for player: AudioStreamPlayer in _players:
			player.stop()
			player.volume_db = 0.0
	else:
		_fade = create_tween()
		_fade.set_parallel(true)
		for player: AudioStreamPlayer in _players:
			if player.playing:
				_fade.tween_property(player, "volume_db", -40.0, fade_sec)
		_fade.chain().tween_callback(_stop_all)
	current_id = &""


func _stop_all() -> void:
	for player: AudioStreamPlayer in _players:
		player.stop()
		player.volume_db = 0.0


func _any_playing() -> bool:
	for player: AudioStreamPlayer in _players:
		if player.playing:
			return true
	return false


func _kill_fade() -> void:
	if _fade != null:
		_fade.kill()
		_fade = null


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
