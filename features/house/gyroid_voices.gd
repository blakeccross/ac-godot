class_name GyroidVoices
extends Node

## What a switched-on gyroid sounds like (`ac_hnw_common.c` `sAdo_RhythmStart` / `sAdo_RhythmPos`,
## `rhythm.c`, seq 246). Every gyroid in the room plays its own rhythm voice on one shared beat
## clock; the clock keeps the tempo of whatever music is playing (`Na_RhythmGrpProcess`'s
## `tempo_adjust`) and the pattern's beat type (swung for some K.K. songs). Fourteen voices at
## most (`rhythm_buffer[14]`), the nearest to the room mic.
##
## The pipeline renders each voice as a 16-beat loop at 120 BPM (`gyroid_NNN`, `_swing`). Tempo
## plays it faster or slower and a pitch shifter on the `Gyroid` bus puts the pitch back.

const VOICES := 14
const BUS := "Gyroid"
const PAN_STEPS := 9
## The renders: 16 beats, eight seconds, at 120 BPM.
const LOOP_BEATS := 16.0
const LOOP_SEC := 8.0
const REF_BPM := 120.0
## `tempo_adjust` moves the rhythm tempo one beat per audio frame toward the music's.
const TEMPO_SLEW := 60.0 * 8.0
const PITCH_MIN := 0.5
const PITCH_MAX := 2.0
## Seconds off before a voice is pulled back onto the clock.
const DRIFT := 0.12

## The shared rhythm clock: beats since the room loaded, and the tempo it runs at.
static var beats: float = 0.0
static var bpm: float = REF_BPM
static var swing: bool = false
## True while a room is running this node, so dancers follow the clock instead of their own.
static var running: bool = false

var _players: Array[AudioStreamPlayer] = []
var _pitch: AudioEffectPitchShift


func _ready() -> void:
	running = true
	beats = 0.0
	bpm = REF_BPM
	_ensure_bus()
	for _i: int in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_players.append(p)


func _exit_tree() -> void:
	running = false
	_silence()


## Tempo and beat type for `track` (the music now playing), or the idle 120 BPM.
static func rhythm_for(track: StringName) -> Dictionary:
	var info: Dictionary = BgmCatalog.rhythm_info(track)
	if float(info["bpm"]) <= 0.0:
		return {"bpm": REF_BPM, "swing": false}
	return info


static func stream_id(gyroid: int, swung: bool) -> StringName:
	return StringName("gyroid_%03d%s" % [gyroid, "_swing" if swung else ""])


## Where in a 16-beat loop the clock is, in seconds of the render (120 BPM).
static func loop_position(beat_count: float) -> float:
	return fposmod(beat_count, LOOP_BEATS) * (LOOP_SEC / LOOP_BEATS)


## How much faster than the render the loop has to play to run at `tempo`.
static func playback_rate(tempo: float) -> float:
	return clampf(tempo / REF_BPM, PITCH_MIN, PITCH_MAX)


## Gyroid numbers (0–126) of the switched-on gyroids in `session`'s room, by placement id.
static func sounding(session: IndoorSession) -> Array:
	var out: Array = []
	if session == null or session.room == null or not FurnitureAmbience.ACTOR_ROOMS.has(int(session.room.kind)):
		return out
	for entry: FurniturePlacement in session.room.placements:
		if entry == null or not entry.on or entry.layer > 0:
			continue
		var data: FurnitureData = session.furniture_of(entry.furniture_id)
		if data == null or data.kind != FurnitureData.Kind.GYROID:
			continue
		var gyroid: int = GyroidRhythm.gyroid_index(FurnitureCatalog.index_of(data.id))
		if gyroid >= 0:
			out.append([entry.id, gyroid])
	return out


func _process(delta: float) -> void:
	var host: Node = get_parent()
	var session: IndoorSession = host.get("session") as IndoorSession if host != null else null
	var player := Player.find(get_tree())
	var info: Dictionary = rhythm_for(Audio.current_id)
	bpm = move_toward(bpm, float(info["bpm"]), TEMPO_SLEW * delta)
	swing = bool(info["swing"])
	beats += delta * bpm / 60.0
	if session == null or player == null or not host.has_method("furniture_node"):
		_silence()
		return
	var rate: float = playback_rate(bpm)
	_set_pitch_back(rate)
	var mic: Vector3 = player.global_position + SoundEmitter.MIC_OFFSET
	var heard: Array = []
	for src: Array in sounding(session):
		var node: Node3D = host.call("furniture_node", src[0]) as Node3D
		if node == null:
			continue
		var distance: float = node.global_position.distance_to(mic)
		if distance <= SoundEmitter.AREA:
			heard.append([src[0], src[1], distance, SoundEmitter.pan(mic, node.global_position)])
	heard.sort_custom(func(a: Array, b: Array) -> bool: return float(a[2]) < float(b[2]))
	heard = heard.slice(0, VOICES)
	var claimed: Dictionary = {}
	for h: Array in heard:
		claimed[h[0]] = h
	var free: Array[AudioStreamPlayer] = []
	for p: AudioStreamPlayer in _players:
		var held: StringName = p.get_meta(&"pid", &"")
		if held != &"" and claimed.has(held):
			_drive(p, claimed[held], rate)
			claimed.erase(held)
		else:
			p.stop()
			p.set_meta(&"pid", &"")
			free.append(p)
	for h: Array in heard:
		if not claimed.has(h[0]) or free.is_empty():
			continue
		var p: AudioStreamPlayer = free.pop_back()
		p.set_meta(&"pid", h[0])
		_drive(p, h, rate)


func _drive(p: AudioStreamPlayer, h: Array, rate: float) -> void:
	var id: StringName = stream_id(int(h[1]), swing)
	if p.get_meta(&"stream_id", &"") != id:
		p.stop()
		p.stream = SoundEmitter.looped(SeCatalog.stream_for(id))
		p.set_meta(&"stream_id", id)
	p.bus = pan_bus(float(h[3]))
	p.pitch_scale = rate
	p.volume_db = linear_to_db(maxf(SoundEmitter.volume(float(h[2])), 0.0001))
	if p.stream == null:
		return
	var want: float = loop_position(beats)
	if not p.playing:
		p.play(want)
		return
	var off: float = absf(p.get_playback_position() - want)
	off = minf(off, LOOP_SEC - off)
	if off > DRIFT * maxf(rate, 1.0):
		p.seek(want)


func _silence() -> void:
	for p: AudioStreamPlayer in _players:
		p.stop()
		p.set_meta(&"pid", &"")


## `Gyroid` takes the shifter that cancels the tempo's change of pitch; each pan step is a
## sub-bus into it (`Audio.pan_bus` does the same for the SFX bus).
func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) == -1:
		var index: int = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(index, BUS)
		AudioServer.set_bus_send(index, Audio.SFX_BUS)
		_pitch = AudioEffectPitchShift.new()
		AudioServer.add_bus_effect(index, _pitch)
	else:
		var effect: AudioEffect = AudioServer.get_bus_effect(AudioServer.get_bus_index(BUS), 0)
		_pitch = effect as AudioEffectPitchShift


func _set_pitch_back(rate: float) -> void:
	var index: int = AudioServer.get_bus_index(BUS)
	if index == -1 or _pitch == null:
		return
	var needed: bool = absf(rate - 1.0) > 0.01
	AudioServer.set_bus_effect_enabled(index, 0, needed)
	if needed:
		_pitch.pitch_scale = 1.0 / rate


static func pan_bus(pan: float) -> String:
	var step: int = clampi(roundi((pan + 1.0) * 0.5 * float(PAN_STEPS - 1)), 0, PAN_STEPS - 1)
	@warning_ignore("integer_division")
	if step == (PAN_STEPS - 1) / 2:
		return BUS
	var name: String = "%s_pan%d" % [BUS, step]
	if AudioServer.get_bus_index(name) == -1:
		var index: int = AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(index, name)
		AudioServer.set_bus_send(index, BUS)
		var panner := AudioEffectPanner.new()
		panner.pan = float(step) / float(PAN_STEPS - 1) * 2.0 - 1.0
		AudioServer.add_bus_effect(index, panner)
	return name
