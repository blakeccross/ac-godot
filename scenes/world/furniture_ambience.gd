class_name FurnitureAmbience
extends Node

## What furniture gives off while it is out: sounds and steam.
##
## A piece raises a held level SE every frame it sounds
## (`sAdo_OngenPos(ftr_actor, n, &ftr_actor->position)` in its `src/furniture/ac_*.c` move
## proc): fires and torches always, TVs, fans and the like only switched on, the pot only
## with its lid off. Level sources play as `lev_*` loops at `Ongen.volume` from the room
## mic, the nearest `VOICES` of them, in rooms whose furniture runs as actors (houses,
## tents); shops and the museum show models only. Not panned.
##
## Hot food steams (`eEC_EFFECT_SOBA_YUGE` from the same move procs): the stew every 8
## ticks, the barbecue every 16, the counter-top pot and the hot pot every 20–40 / 10–30.

const VOICES := 4

enum When { ALWAYS, ON, OFF }

## Visual id → [level SE, when it sounds].
const LOOPS := {
	&"int_nog_fan01": [0x01, When.ON],
	&"int_sum_kisha": [0x03, When.ON],
	&"int_sum_tv02": [0x04, When.ON],
	&"int_sum_tv01": [0x05, When.ON],
	&"int_sum_fruittv01": [0x06, When.ON],
	&"int_kon_snowtv": [0x2B, When.ON],
	&"int_ike_kama_danro01": [0x46, When.ALWAYS],
	&"int_tak_lion": [0x4A, When.ON],
	&"int_ike_jny_syon01": [0x4B, When.ON],
	## `fNNB_ct`: the pot boils with its switch off (`dynamic_work_s[0] = switch_bit != TRUE`).
	&"int_nog_nabe": [0x50, When.OFF],
	&"int_tak_ice": [0x51, When.ON],
	&"int_tak_stew": [0x54, When.ALWAYS],
	&"int_sugi_barbecue": [0x55, When.ALWAYS],
	&"int_tak_ham1": [0x56, When.ALWAYS],
	&"int_sugi_torch": [0x57, When.ALWAYS],
	&"int_nog_sprinkler": [0x5B, When.ON],
	&"int_ike_tent_fire02": [0x5C, When.ALWAYS],
	&"int_ike_tent_fire01": [0x5D, When.ALWAYS],
	&"int_iku_turkey_TV": [0x5E, When.ON],
	&"int_iku_mario_star": [0x5F, When.ON],
}

## Visual id → [GX above the piece, GX spread (`arg0`), fixed interval or 0, random
## interval min, random span, when].
const STEAM := {
	&"int_tak_stew": [15.0, 10, 8, 0, 0, When.ALWAYS],
	&"int_sugi_barbecue": [30.0, 9, 16, 0, 0, When.ALWAYS],
	## `fIKC_mv`: `fIKC_MIN_TIME` 20 + up to 20.
	&"int_ike_k_count01": [13.0, 6, 0, 20, 20, When.ALWAYS],
	&"int_nog_nabe": [18.0, 6, 0, 10, 20, When.OFF],
}

## Pieces that sound once when A switches them (`switch_changed_flag` →
## `sAdo_OngenTrgStart`): visual id → SE.
const PRESS := {
	&"int_ike_jny_rosia01": &"7a",
	&"int_ike_jny_hariko01": &"7b",
	## `fIPP_mv`: the piggy bank rattles only with bells in the wallet.
	&"int_ike_pst_pig01": &"7c",
	&"int_nog_gong": &"174",
	&"int_ike_prores_sandbag01": &"175",
	&"int_ike_prores_punch01": &"176",
	&"int_iku_mario_dokan": &"178",
	&"int_hos_mario_kinoko": &"179",
	&"int_iku_mario_coin": &"17a",
	&"int_yaz_mario_flower": &"17b",
	&"int_iku_mario_hatena": &"17f",
	&"int_hos_mario_hata": &"44e",
	&"int_iku_mario_koura": &"464",
	&"int_sum_hal_box01": &"144",
	&"int_sum_okiagari01": &"145",
	&"int_tak_noise": &"46a",
}

## Pieces that click on and off themselves (`sAdo_OngenTrgStart(0x16 / 0x17)` on
## `switch_changed_flag`); lamps already do through `Kind.TOGGLE`.
const CLICKS: Array[StringName] = [
	&"int_nog_fan01", &"int_sum_kisha", &"int_sum_tv01", &"int_sum_tv02", &"int_sum_fruittv01",
	&"int_kon_snowtv", &"int_tak_ice", &"int_nog_sprinkler", &"int_iku_turkey_TV", &"int_nog_nabe",
]

## Rooms whose furniture are `FTR_ACTOR`s (`aMR` in houses, tents, the igloo, the cottage).
const ACTOR_ROOMS: Array[int] = [
	Room.Kind.PLAYER, Room.Kind.NPC, Room.Kind.TENT, Room.Kind.KAMAKURA, Room.Kind.COTTAGE,
]

var _players: Array[AudioStreamPlayer] = []
var _steps := FrameStepper.new(DecompTime.TICK_HZ, 8.0)
var _tick: int = 0
## Placement id → ticks left before the next random puff.
var _puff_wait: Dictionary = {}


func _ready() -> void:
	for i: int in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = Audio.SFX_BUS
		add_child(p)
		_players.append(p)


## A piece whose sound follows its switch: A turns it on and off like a lamp
## (`aMR_FtrIdx2ChangeFtrSwitch` flips any piece's `switch_bit`).
static func switchable(data: FurnitureData) -> bool:
	if data == null:
		return false
	if PRESS.has(data.visual_id):
		return true
	var rule: Variant = LOOPS.get(data.visual_id)
	return rule != null and int(rule[1]) != When.ALWAYS


## The one-shot a piece plays when switched, or `&""`.
static func press_se(data: FurnitureData, wallet: int) -> StringName:
	if data == null:
		return &""
	if data.visual_id == &"int_ike_pst_pig01" and wallet == 0:
		return &""
	return PRESS.get(data.visual_id, &"")


static func clicks(data: FurnitureData) -> bool:
	return data != null and CLICKS.has(data.visual_id)


## The level SE a placed piece holds now, or −1.
static func level_for(data: FurnitureData, entry: FurniturePlacement) -> int:
	if data == null or entry == null:
		return -1
	var rule: Variant = LOOPS.get(data.visual_id)
	if rule == null or not _active(int(rule[1]), entry):
		return -1
	return int(rule[0])


static func _active(when: int, entry: FurniturePlacement) -> bool:
	match when:
		When.ON:
			return entry.on
		When.OFF:
			return not entry.on
	return true


## Whether a piece puffs steam on `tick`; `wait` holds its random countdown (decremented
## here, reset to `rng`'s next interval after a puff).
static func steams(data: FurnitureData, entry: FurniturePlacement, tick: int, wait: Array, rng: RandomNumberGenerator) -> bool:
	if data == null or entry == null:
		return false
	var rule: Variant = STEAM.get(data.visual_id)
	if rule == null or not _active(int(rule[5]), entry):
		return false
	var every: int = int(rule[2])
	if every > 0:
		return tick % every == 0
	if wait[0] < 0:
		wait[0] = int(rule[3]) + rng.randi_range(0, int(rule[4]) - 1)
		return true
	wait[0] -= 1
	return false


## Every sounding piece in the room as `[placement_id, level]`.
static func sources(session: IndoorSession) -> Array:
	var out: Array = []
	if session == null or session.room == null or not ACTOR_ROOMS.has(int(session.room.kind)):
		return out
	for entry: FurniturePlacement in session.room.placements:
		var lev: int = level_for(session.furniture_of(entry.furniture_id), entry)
		if lev >= 0:
			out.append([entry.id, lev])
	return out


func _process(delta: float) -> void:
	var host: Node = get_parent()
	var player := Player.find(get_tree())
	var session: IndoorSession = host.get("session") as IndoorSession if host != null else null
	if player == null or session == null or not host.has_method("furniture_node"):
		_silence()
		return
	_steps.add(delta)
	while _steps.next():
		_tick += 1
		_steam(host, session)
	var mic_m: Vector3 = player.global_position + Ongen.MIC_OFFSET_GX * FieldCatalog.GX_TO_METERS
	var heard: Array = []
	for src: Array in sources(session):
		var node: Node3D = host.call("furniture_node", src[0]) as Node3D
		if node == null:
			continue
		var d: float = node.global_position.distance_to(mic_m) / FieldCatalog.GX_TO_METERS
		if d <= Ongen.AREA:
			heard.append([src[0], src[1], d])
	heard.sort_custom(func(x: Array, y: Array) -> bool: return float(x[2]) < float(y[2]))
	heard = heard.slice(0, VOICES)
	var claimed: Dictionary = {}
	for h: Array in heard:
		claimed[h[0]] = h
	var free: Array[AudioStreamPlayer] = []
	for p: AudioStreamPlayer in _players:
		var held: StringName = p.get_meta(&"pid", &"")
		if held != &"" and claimed.has(held):
			_drive(p, claimed[held])
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
		_drive(p, h)


var _rng := RandomNumberGenerator.new()


func _steam(host: Node, session: IndoorSession) -> void:
	if session.room == null or not ACTOR_ROOMS.has(int(session.room.kind)):
		return
	for entry: FurniturePlacement in session.room.placements:
		var data: FurnitureData = session.furniture_of(entry.furniture_id)
		if data == null or not STEAM.has(data.visual_id):
			continue
		var wait: Array = [int(_puff_wait.get(entry.id, -1))]
		var puff: bool = steams(data, entry, _tick, wait, _rng)
		_puff_wait[entry.id] = wait[0]
		if not puff:
			continue
		var node: Node3D = host.call("furniture_node", entry.id) as Node3D
		if node == null:
			continue
		var rule: Array = STEAM[data.visual_id]
		var at: Vector3 = node.global_position + Vector3(0.0, float(rule[0]) * FieldCatalog.GX_TO_METERS, 0.0)
		FieldFx.spawn(host, FieldFx.Kind.SOBA_YUGE, at, 0.0, int(rule[1]), 0)


func _drive(p: AudioStreamPlayer, h: Array) -> void:
	var id: StringName = BugSounds.se_id(int(h[1]))
	if p.get_meta(&"se", &"") != id:
		p.stop()
		p.stream = Ongen.looped(SeCatalog.stream_for(id))
		p.set_meta(&"se", id)
	p.volume_db = linear_to_db(maxf(Ongen.volume(float(h[2])), 0.0001))
	if p.stream != null and not p.playing:
		p.play()


func _silence() -> void:
	for p: AudioStreamPlayer in _players:
		p.stop()
		p.set_meta(&"pid", &"")
