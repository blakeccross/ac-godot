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
## The playing track's level (`play_bgm`'s `level_db`).
var bgm_trim_db: float = 0.0
var _front: int = 0
var _fade: Tween
var _arm_player: AudioStreamPlayer
var _arm_fade: Tween
## `Na_SysLevStart` / `Stop` — a looping *level* SE (`Sou_LevStart`), catalog id `lev_<hex>`.
## Level ids are their own table: rain 7 / 8 / 9 are not the door trigger SEs 7 / 8 / 9.
var _syslev_player: AudioStreamPlayer
var _syslev_id: int = 0
## `sAdo_Inst`: a 16-step town tune on the note SEs. The step is byte 0 of the melody
## voice's header in seq 248, counted in tatums of the SE sequence (120 BPM, 48 a beat:
## 96 a second): the tune board's voice 0 is 24 (0.25 s a step), the hourly chime's voice
## 0xFF is 64 (0.667 s).
const MELODY_STEP_SEC := 24.0 / 96.0
const CHIME_STEP_SEC := 64.0 / 96.0
## `sou_chime_volume`: the chime at full volume on the field, 0.45 in rooms.
const CHIME_INDOOR_DB := -6.94
var _melody_step_sec: float = MELODY_STEP_SEC
var _melody: PackedByteArray = PackedByteArray()
var _melody_step: int = -1
var _melody_t: float = 0.0
var _melody_player: AudioStreamPlayer
var _melody_rng := RandomNumberGenerator.new()
## `Na_Inst` with a villager's `melody_inst` (their voice): `{spec, phoneme, pitch, volume_db}`,
## empty for the chime notes.
var _melody_voice: Dictionary = {}
## `mBGM_KATEGORIE_FANFARE` (`mBGMPsComp_make_ps_fanfare` / `delete_ps_fanfare`): a jingle on
## top of the music. Its sequence is a short phrase and then a quiet loop that plays under the
## report until the fanfare is taken off; the music under it stops meanwhile and starts over
## afterwards. Music asked for while one plays waits for it (`_fanfare_base`).
var _fanfare_player: AudioStreamPlayer
var _fanfare_id: StringName = &""
var _fanfare_base: StringName = &""
## `Na_VoiceSe` / `sou_voice_se_toguru`: Animalese runs on two voice subtracks taken in turn,
## so at most two phonemes overlap and each new one cuts the one from two glyphs back.
var _voice_players: Array[AudioStreamPlayer] = []
var _voice_next: int = 0
## `mBGMPsComp_pause` (`pause_volume`): the music turned down under a menu — half under
## the pockets and the notice board, silent under the tune board. 1 is full.
const PAUSE_POCKETS := 0.5
const PAUSE_TUNE_BOARD := 0.0
const PAUSE_FADE_SEC := 0.2
var _pause_level: float = 1.0
var _pause_fade: Tween


func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	## K.K.'s sound option (mono folds the master bus) and saved button mappings.
	GameConfig.ensure_loaded()
	InputBindings.ensure_loaded()
	_players = [_make_player(), _make_player()]
	_arm_player = _make_player()
	_fanfare_player = _make_player()
	_syslev_player = AudioStreamPlayer.new()
	_syslev_player.bus = SFX_BUS
	add_child(_syslev_player)
	_melody_player = AudioStreamPlayer.new()
	_melody_player.bus = SFX_BUS
	add_child(_melody_player)
	for _i: int in 2:
		var voice := AudioStreamPlayer.new()
		voice.bus = SFX_BUS
		add_child(voice)
		_voice_players.append(voice)
	set_process(false)


## `sAdo_Inst`: play a town tune (`TownTune` values). Restarts one already playing.
func play_melody(notes: PackedByteArray, voice: Dictionary = {}, step_sec: float = MELODY_STEP_SEC, volume_db: float = 0.0) -> void:
	_melody_voice = voice
	_melody = TownTune.sanitize(notes)
	_melody_step = -1
	_melody_step_sec = maxf(step_sec, 0.01)
	_melody_t = _melody_step_sec
	_melody_player.volume_db = volume_db
	set_process(true)


## `sAdo_InstCountGet`: the step playing, or −1 when no tune is.
func melody_step() -> int:
	return _melody_step


func stop_melody() -> void:
	_melody_step = -1
	_melody_player.stop()
	set_process(false)


func _process(delta: float) -> void:
	_melody_t += delta
	while _melody_t >= _melody_step_sec:
		_melody_t -= _melody_step_sec
		_melody_step += 1
		if _melody_step >= TownTune.LENGTH:
			_melody_step = -1
			set_process(false)
			return
		_sound_step(int(_melody[_melody_step]))


func _sound_step(note: int) -> void:
	match note:
		TownTune.TIE:
			return
		TownTune.REST:
			_melody_player.stop()
			return
		TownTune.RANDOM:
			note = _melody_rng.randi_range(0, TownTune.HIGHEST)
	if not _melody_voice.is_empty():
		play_voice(
			int(_melody_voice["spec"]), int(_melody_voice["phoneme"]),
			float(_melody_voice["pitch"]) * TownTune.note_pitch(note), float(_melody_voice["volume_db"])
		)
		return
	_melody_player.stream = SeCatalog.stream_for(TownTune.note_se(note))
	if _melody_player.stream != null:
		_melody_player.play()


## `sAdo_OngenTrgStart`: a one-shot from something on the field is heard from the mic
## (`SoundEmitter`): quieter with distance (`distance2vol`), gone past 540 GX, and panned by
## its bearing (`angle2pan`) through one of `PAN_STEPS` panned buses. Anything not on the
## field (a menu, a room, the Audio node itself) plays flat.
const PAN_STEPS := 9


func play_sfx(stream: AudioStream, at: Node = self, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	if stream == null or at == null:
		return
	var bus: String = SFX_BUS
	var placed: Vector2 = field_placement(at)
	if placed.x <= 0.0:
		return
	if placed != Vector2(1.0, 0.0):
		volume_db += linear_to_db(placed.x)
		bus = pan_bus(placed.y)
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = bus
	player.pitch_scale = maxf(0.01, pitch_scale)
	player.volume_db = volume_db
	at.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## `(volume, pan)` for a one-shot from `at`: `(1, 0)` off the field, `(0, …)` out of earshot.
func field_placement(at: Node) -> Vector2:
	var node := at as Node3D
	if node == null or not node.is_inside_tree():
		return Vector2(1.0, 0.0)
	return field_placement_at(node.get_tree(), node.global_position)


## `(volume, pan)` for a sound at world `pos`.
func field_placement_at(tree: SceneTree, pos: Vector3) -> Vector2:
	if tree == null or Game.is_indoors() or not TownSpace.is_outdoor_town():
		return Vector2(1.0, 0.0)
	var mic: Vector3 = SoundEmitter.field_mic(tree)
	if mic == Vector3.INF:
		return Vector2(1.0, 0.0)
	return Vector2(SoundEmitter.volume(mic.distance_to(pos)), SoundEmitter.pan(mic, pos))


## The SFX sub-bus panned nearest `pan` (−1 left … 1 right), made on first use.
func pan_bus(pan: float) -> String:
	var step: int = clampi(roundi((pan + 1.0) * 0.5 * float(PAN_STEPS - 1)), 0, PAN_STEPS - 1)
	if step == (PAN_STEPS - 1) / 2:
		return SFX_BUS
	var name: String = "%s_pan%d" % [SFX_BUS, step]
	if AudioServer.get_bus_index(name) == -1:
		var index: int = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(index, name)
		AudioServer.set_bus_send(index, SFX_BUS)
		var panner := AudioEffectPanner.new()
		panner.pan = float(step) / float(PAN_STEPS - 1) * 2.0 - 1.0
		AudioServer.add_bus_effect(index, panner)
	return name


## Play a catalog SE id (`cursol`, `bebe`, …). No-op if the stream is missing.
func play_se(id: StringName, at: Node = self, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	if id == &"":
		return
	play_sfx(SeCatalog.stream_for(id), at, pitch_scale, volume_db)


## Play an animalese phoneme clip for voice seq spec 1–3, on the next of the two voice
## subtracks (cutting whatever it was still saying).
func play_voice(
	spec: int,
	phoneme: int,
	pitch_scale: float = 1.0,
	volume_db: float = 0.0,
	_at: Node = self
) -> void:
	var stream: AudioStream = VoiceCatalog.stream_for(spec, phoneme)
	if stream == null or _voice_players.is_empty():
		return
	var voice: AudioStreamPlayer = _voice_players[_voice_next]
	_voice_next = (_voice_next + 1) % _voice_players.size()
	voice.stop()
	voice.stream = stream
	voice.pitch_scale = maxf(0.01, pitch_scale)
	voice.volume_db = volume_db
	voice.play()


## How many phonemes are sounding (tests: never more than the two subtracks).
func voices_playing() -> int:
	var n: int = 0
	for voice: AudioStreamPlayer in _voice_players:
		if voice.playing:
			n += 1
	return n


## Turn the music bus to `level` of full (1 restores it) for a menu over the field.
func set_music_pause(level: float) -> void:
	level = clampf(level, 0.0, 1.0)
	if is_equal_approx(level, _pause_level):
		return
	_pause_level = level
	var bus: int = AudioServer.get_bus_index(MUSIC_BUS)
	if bus < 0:
		return
	if _pause_fade != null:
		_pause_fade.kill()
	_pause_fade = create_tween()
	_pause_fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_pause_fade.tween_method(func(db: float) -> void: AudioServer.set_bus_volume_db(bus, db),
		AudioServer.get_bus_volume_db(bus), linear_to_db(maxf(level, 0.0001)), PAUSE_FADE_SEC)


## Test-only: no in-game callers; kept for tests.
func music_pause_level() -> float:
	return _pause_level


## `Na_SysLevStart`: loop level SE `id` (rain ambient uses 7 / 8 / 9 by level).
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
	var stream: AudioStream = SeCatalog.stream_for(StringName("lev_%x" % id))
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


## The level SE now looping (0 = none).
func syslev_id() -> int:
	return _syslev_id


## Test-only: no in-game callers; kept for tests.
func syslev_volume_db() -> float:
	return _syslev_player.volume_db if _syslev_player != null else 0.0


## `Na_SysLevStop`. Pass 0 / omit to stop whatever is playing.
func stop_syslev(id: int = 0) -> void:
	if id > 0 and _syslev_id != 0 and id != _syslev_id:
		return
	if _syslev_player != null:
		_syslev_player.stop()
		_syslev_player.stream = null
	_syslev_id = 0


## Rain SysLev from `aWeather_ChangeEnvSE`. The weather actor lives in every field *and*
## room, so it rains indoors too (quieter, `Weather.syslev_volume`) — except in the player's
## basement (`basement_event`) and in the title demo (`mEv_IsNotTitleDemo`). `level` is the
## weather actor's current level (it ramps after an in-session change); the saved intensity
## otherwise.
func sync_rain_syslev(
	kind: Weather.Kind,
	level: int,
	indoors: bool,
	basement: bool = false,
	umbrella: bool = false
) -> void:
	var id: int = Weather.rain_syslev_id(kind, level, umbrella)
	if id == 0 or basement or (Game != null and Game.title_demo_active):
		stop_syslev()
		return
	start_syslev(id, linear_to_db(Weather.syslev_volume(id, indoors)))


## `level_db` is `ps_comp->volume.ps_volume` (0 full; an event heard from the next acre
## plays at half), and changes in place when the track is already playing.
func play_bgm(id: StringName, level_db: float = 0.0) -> void:
	if _fanfare_id != &"":
		_fanfare_base = id
		return
	if id == current_id:
		_set_bgm_trim(level_db)
		return
	bgm_trim_db = level_db
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
	next_player.volume_db = -40.0 if fade_sec > 0.0 else bgm_trim_db
	next_player.play()
	_kill_fade()
	if fade_sec <= 0.0 or not prev_player.playing:
		prev_player.stop()
		next_player.volume_db = bgm_trim_db
	else:
		_fade = create_tween()
		_fade.set_parallel(true)
		_fade.tween_property(next_player, "volume_db", bgm_trim_db, fade_sec)
		_fade.tween_property(prev_player, "volume_db", -40.0, fade_sec)
		_fade.chain().tween_callback(prev_player.stop)
	_front = incoming
	current_id = id
	_start_arm_stem(id, next_player.volume_db)


## `mBGMPsComp_volume_change_fieldSchedEv`: move the music's level (dB) without restarting it.
func _set_bgm_trim(db: float) -> void:
	if is_equal_approx(db, bgm_trim_db):
		return
	bgm_trim_db = db
	if _players.is_empty() or not _players[_front].playing:
		return
	## Mid crossfade: leave it be — the level lands with the next change.
	if _fade != null and _fade.is_running():
		return
	if fade_sec <= 0.0:
		_players[_front].volume_db = db
		return
	_fade = create_tween()
	_fade.tween_property(_players[_front], "volume_db", db, fade_sec)


func stop_bgm() -> void:
	if _fanfare_id != &"":
		_fanfare_base = &""
		return
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


## `mBGMPsComp_make_ps_fanfare`: put the jingle `id` (a `BgmCatalog` id) over the music.
func push_fanfare(id: StringName) -> void:
	var stream: AudioStream = BgmCatalog.stream_for(id)
	if stream == null or id == _fanfare_id:
		return
	if _fanfare_id == &"":
		_fanfare_base = current_id
		_kill_fade()
		for player: AudioStreamPlayer in _players:
			player.stop()
			player.volume_db = 0.0
		_stop_arm(true)
		current_id = &""
	_fanfare_id = id
	_fanfare_player.stream = stream
	_fanfare_player.volume_db = 0.0
	_fanfare_player.play()


## `mBGMPsComp_delete_ps_fanfare`: take `id` off; the music it covered starts again.
func pop_fanfare(id: StringName) -> void:
	if _fanfare_id == &"" or id != _fanfare_id:
		return
	_fanfare_player.stop()
	_fanfare_id = &""
	var base: StringName = _fanfare_base
	_fanfare_base = &""
	if base != &"":
		play_bgm(base)


## Test-only: no in-game callers; kept for tests.
func fanfare_id() -> StringName:
	return _fanfare_id


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
