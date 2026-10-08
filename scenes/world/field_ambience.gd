class_name FieldAmbience
extends Node

## Water you can hear (`Bg_Draw_Actor_move` → `aFD_OperateWaterSound`). Each acre's bg data
## names up to six sound sources (`mFM_bg_sound_source_c`, `AcreGrid.sounds`). On the beach
## acres the two nearest surf sources of the acre and its east and west neighbours play the
## sea (0x1C, 175 GX further south); inland the two nearest river or waterfall sources of the
## 3×3 acres around the player play the river (0x0B). An acre with a pond plays its water
## (0x16) and, May to August at 18–21 and 4–6 o'clock, its frogs (0xA1). Loops are `lev_*`
## renders, loud as `Ongen.volume` from the field mic. Not panned.

const KIND_RIVER := 1
const KIND_SEA := 2
const KIND_POND := 3
const SE_RIVER := &"lev_b"
const SE_SEA := &"lev_1c"
const SE_POND := &"lev_16"
const SE_FROG := &"lev_a1"
const SEA_OFS_Z_GX := 175.0
const SOURCE_LIFT_GX := 40.0
const UT_GX := 40.0
const BLOCK_GX := 640.0
## `aFD_block_offset_table`: current, west, east, then the rest of the 3×3.
const SEARCH: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, -1),
	Vector2i(1, -1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1),
]
const ROW_SEARCH := 3

var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	for i: int in 4:
		var p := AudioStreamPlayer.new()
		p.bus = Audio.SFX_BUS
		add_child(p)
		_players.append(p)


## Sound sources of decomp block `block` in GX, `[kind, Vector3]`.
static func block_sources(layout: WorldData, block: Vector2i) -> Array:
	var out: Array = []
	if layout == null or layout.acre_visuals.size() != TownFieldGenerator.BLOCK_TOTAL:
		return out
	if block.x < 0 or block.x >= TownFieldGenerator.BLOCK_X or block.y < 0 or block.y >= TownFieldGenerator.BLOCK_Z:
		return out
	var visual := StringName(layout.acre_visuals[block.y * TownFieldGenerator.BLOCK_X + block.x])
	var raw: PackedInt32Array = FieldCatalog.acre_sounds(visual)
	for i: int in range(0, raw.size() - 2, 3):
		var pos := Vector3(
			block.x * BLOCK_GX + raw[i + 1] * UT_GX + UT_GX * 0.5, 0.0, block.y * BLOCK_GX + raw[i + 2] * UT_GX + UT_GX * 0.5
		)
		out.append([raw[i], pos])
	return out


## `aFD_OperateWaterSound`: the nearest two of `kind` around `block` (`count` acres of the
## search table), nearest first.
static func nearest_two(layout: WorldData, block: Vector2i, kind: int, count: int, center: Vector3) -> Array[Vector3]:
	var found: Array[Vector3] = []
	for i: int in count:
		for src: Array in block_sources(layout, block + SEARCH[i]):
			if int(src[0]) == kind:
				found.append(src[1] as Vector3)
	var flat := Vector2(center.x, center.z)
	found.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return flat.distance_squared_to(Vector2(a.x, a.z)) < flat.distance_squared_to(Vector2(b.x, b.z)))
	return found.slice(0, 2)


## `mRF_BLOCKKIND_MARINE`: the beach row and the sea.
static func is_marine(layout: WorldData, block: Vector2i) -> bool:
	if layout == null or layout.acre_types.size() != TownFieldGenerator.BLOCK_TOTAL:
		return block.y == TownAssessment.FG_BLOCK_Z
	var t: int = int(layout.acre_types[block.y * TownFieldGenerator.BLOCK_X + block.x])
	return t == TownFieldGenerator.T_BEACH or t == TownFieldGenerator.T_BEACH_RIVER \
		or t == TownFieldGenerator.T_BEACH_RIVER_BRIDGE or t >= TownFieldGenerator.T_OCEAN


## `Bg_Draw_Actor_move`'s frog window.
static func frogs_sing(month: int, hour: int) -> bool:
	return month >= 5 and month <= 8 and ((hour >= 18 and hour <= 21) or (hour >= 4 and hour <= 6))


func _process(_delta: float) -> void:
	var world := World.find(get_tree())
	var player := Player.find(get_tree())
	if world == null or player == null or Game.current_room_id != &"" or Game.title_demo_active:
		_silence()
		return
	var layout: WorldData = world.layout
	var player_gx: Vector3 = TownSpace.world_to_gx(player.global_position)
	var mic: Vector3 = player_gx + Ongen.MIC_OFFSET_GX
	var block: Vector2i = TownSpace.block_of(player_gx)
	var sources: Array = []
	if is_marine(layout, block):
		for p: Vector3 in nearest_two(layout, block, KIND_SEA, ROW_SEARCH, player_gx):
			sources.append([SE_SEA, p + Vector3(0.0, 0.0, SEA_OFS_Z_GX)])
	else:
		for p: Vector3 in nearest_two(layout, block, KIND_RIVER, SEARCH.size(), player_gx):
			sources.append([SE_RIVER, p])
	for src: Array in block_sources(layout, block):
		if int(src[0]) != KIND_POND:
			continue
		var pond: Vector3 = src[1]
		sources.append([SE_POND, pond])
		if frogs_sing(Clock.month, Clock.hour):
			sources.append([SE_FROG, pond + Vector3(UT_GX * 0.5, 0.0, UT_GX * 0.5)])
		break
	for i: int in _players.size():
		var p: AudioStreamPlayer = _players[i]
		if i >= sources.size():
			p.stop()
			continue
		var id: StringName = sources[i][0]
		var at: Vector3 = sources[i][1]
		at.y = player_gx.y + SOURCE_LIFT_GX
		var vol: float = Ongen.volume(mic.distance_to(at))
		if vol <= 0.0:
			p.stop()
			continue
		if p.get_meta(&"se", &"") != id:
			p.stop()
			p.stream = Ongen.looped(SeCatalog.stream_for(id))
			p.set_meta(&"se", id)
		p.volume_db = linear_to_db(maxf(vol, 0.0001))
		if p.stream != null and not p.playing:
			p.play()


func _silence() -> void:
	for p: AudioStreamPlayer in _players:
		p.stop()
