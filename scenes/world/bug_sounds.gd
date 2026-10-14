class_name BugSounds
extends Node

## Insects you can hear. Each program raises a held level SE (`sAdo_OngenPos`, the
## actor's `ongen`) on the frames it sounds — cicadas and crickets crying, locusts whirring
## mid-leap, mosquitoes buzzing, beetles and bees flying off — and one-shots
## (`sAdo_OngenTrgStart`, `trg_se`) such as a drowning splash or a cicada's escape. Level
## sources play as `lev_*` loops at `Ongen.volume` from the field mic, the nearest
## `VOICES` of them; a loop stops once its actor stops calling. Not panned.

const VOICES := 4
## A level SE that skips a frame keeps sounding this long (the cicada's cry is refreshed
## every frame, the cockroach's scuttle only now and then).
const HOLD_SEC := 0.1

var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	for i: int in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = Audio.SFX_BUS
		add_child(p)
		_players.append(p)


## The nearest `count` sounding actors as `[actor, distance_gx]`, nearest first, from the
## mic at `mic_m` (metres). Sources past `Ongen.AREA` are dropped.
static func pick(actors: Array, mic_m: Vector3, count: int = VOICES) -> Array:
	var out: Array = []
	for a: BugActor in actors:
		if a == null or a.finished or a.ongen < 0:
			continue
		var d: float = a.position.distance_to(mic_m) / FieldCatalog.GX_TO_METERS
		if d > Ongen.AREA:
			continue
		out.append([a, d])
	out.sort_custom(func(x: Array, y: Array) -> bool: return float(x[1]) < float(y[1]))
	return out.slice(0, count)


static func se_id(ongen: int) -> StringName:
	return StringName("lev_%x" % ongen)


func _process(_delta: float) -> void:
	var world := World.find(get_tree())
	var player := Player.find(get_tree())
	if world == null or player == null or world.bugs == null or Game.current_room_id != &"" or Game.title_demo_active:
		_silence()
		return
	var mic_m: Vector3 = player.global_position + Ongen.MIC_OFFSET_GX * FieldCatalog.GX_TO_METERS
	for a: BugActor in world.bugs.actors:
		for id: StringName in a.trg_se:
			_trigger(id, a.position, mic_m)
		a.trg_se.clear()
	for gone: Array in world.bugs.gone_se:
		_trigger(gone[0], gone[1], mic_m)
	world.bugs.gone_se.clear()
	var now: float = Time.get_ticks_msec() / 1000.0
	var sources: Array = pick(world.bugs.actors, mic_m)
	var claimed: Dictionary = {}
	for src: Array in sources:
		claimed[src[0]] = src[1]
	## Keep each voice on its actor while that actor keeps sounding.
	var free: Array[AudioStreamPlayer] = []
	for p: AudioStreamPlayer in _players:
		var held: Variant = p.get_meta(&"actor", null)
		if held != null and is_instance_valid(held) and claimed.has(held):
			_drive(p, held as BugActor, float(claimed[held]), now)
			claimed.erase(held)
		elif p.playing and now - float(p.get_meta(&"heard", 0.0)) < HOLD_SEC:
			continue
		else:
			p.stop()
			p.set_meta(&"actor", null)
			free.append(p)
	for src: Array in sources:
		if not claimed.has(src[0]) or free.is_empty():
			continue
		var p: AudioStreamPlayer = free.pop_back()
		p.set_meta(&"actor", src[0])
		_drive(p, src[0] as BugActor, float(src[1]), now)


## `Na_OngenTrgStart`: a one-shot, silent past `Ongen.AREA`.
func _trigger(id: StringName, at_m: Vector3, mic_m: Vector3) -> void:
	var vol: float = Ongen.volume(at_m.distance_to(mic_m) / FieldCatalog.GX_TO_METERS)
	if vol > 0.0:
		Audio.play_se(id, Audio, 1.0, linear_to_db(vol))


func _drive(p: AudioStreamPlayer, a: BugActor, distance: float, now: float) -> void:
	var id: StringName = se_id(a.ongen)
	if p.get_meta(&"se", &"") != id:
		p.stop()
		p.stream = Ongen.looped(SeCatalog.stream_for(id))
		p.set_meta(&"se", id)
	p.volume_db = linear_to_db(maxf(Ongen.volume(distance), 0.0001))
	p.set_meta(&"heard", now)
	if p.stream != null and not p.playing:
		p.play()


func _silence() -> void:
	for p: AudioStreamPlayer in _players:
		p.stop()
		p.set_meta(&"actor", null)
