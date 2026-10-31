class_name GongFlash
extends Node3D

## The camera flashes in a ringside-seating room when its gong is struck
## (`ac_nog_gong` → `eEC_EFFECT_FLASHC` → `eEC_EFFECT_FLASH`, `ef_flash.c`): for 240 ticks, a
## white star pops in along the back wall every 8, each for five ticks.

const VISUAL := &"ef_takurami01_kira"
## `WALL_NPC065`, the ringside-seating wall.
const RINGSIDE_WALL := 65
const TOTAL_TICKS := 240.0
const PERIOD_TICKS := 8.0
const FLASH_TICKS := 5.0
const SE_CAMERA := &"17e"
## `eFlashC_mv`: where on the back wall a flash lands, in GX from the wall.
const WALL_GAP := 3.0
const HEIGHT_GX := 75.0
const HEIGHT_SPREAD_GX := 20.0
## `light_color` 27 / 255 for `flash_length` ticks, as an omni light over the room.
const LIGHT_ENERGY := 1.2
const LIGHT_RANGE := 14.0
const LIGHT_OFFSET := 2.0
const PRIM := Color(1.0, 1.0, 1.0, 200.0 / 255.0)

var _room: Room
var _grid: WorldGrid
var _rng := RandomNumberGenerator.new()
var _age: float = 0.0
var _made: int = 0
## Each live flash: {card, at, size, born}.
var _flashes: Array[Dictionary] = []


## Start the flashes if `data` is the gong and the room's wall is the ringside one.
static func ring(host: Node, data: FurnitureData, room: Room, grid: WorldGrid) -> GongFlash:
	if host == null or data == null or room == null or data.visual_id != &"int_nog_gong":
		return null
	if room.wall_id != FurnitureCatalog.goods_id("wall", RINGSIDE_WALL):
		return null
	Audio.play_se(SE_CAMERA)
	var flash := GongFlash.new()
	flash.name = "GongFlash"
	flash._room = room
	flash._grid = grid
	flash._rng.randomize()
	host.add_child(flash)
	return flash


func _process(delta: float) -> void:
	var step: float = delta * DecompTime.TICK_HZ
	_age += step
	while float(_made) * PERIOD_TICKS < _age and float(_made) * PERIOD_TICKS < TOTAL_TICKS:
		_flash_at(float(_made) * PERIOD_TICKS)
		_made += 1
	for entry: Dictionary in _flashes.duplicate():
		var elapsed: float = _age - float(entry["born"])
		if elapsed >= FLASH_TICKS:
			(entry["card"] as Node3D).queue_free()
			_flashes.erase(entry)
			continue
		var grow: float = _adjust(elapsed, 0.0, 2.0, float(entry["size"]) * 0.005, 0.01)
		EffectCards.face(entry["card"] as Node3D, entry["at"] as Vector3, grow)
	if _age >= TOTAL_TICKS + FLASH_TICKS:
		queue_free()


func _flash_at(born: float) -> void:
	var cell: float = _grid.cell_size if _grid != null else 2.0
	var width: float = float(_room.inner_size.x) * cell
	var wall_z: float = float(_room.inner_origin.y) * cell
	var local := Vector3(
		float(_room.inner_origin.x) * cell + _rng.randf() * width,
		(HEIGHT_GX - HEIGHT_SPREAD_GX * 0.5 + _rng.randf() * HEIGHT_SPREAD_GX) * EffectCards.GX,
		wall_z + WALL_GAP * EffectCards.GX,
	)
	var at: Vector3 = WorldGrid.room_point(_grid, local)
	## `eFlash_ct`: every other flash also lights the room (`regist_effect_light`, +27 of 255
	## for 3-10 ticks).
	if _made & 1 == 1:
		_light_room(at)
	var card: Node3D = EffectCards.make(self, VISUAL, PRIM, Color.WHITE)
	if card == null:
		return
	_flashes.append({"card": card, "at": at, "size": 0.3 + _rng.randf() * 0.7, "born": born})


func _light_room(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color.WHITE
	light.light_energy = LIGHT_ENERGY
	light.omni_range = LIGHT_RANGE
	light.shadow_enabled = false
	add_child(light)
	light.global_position = at + Vector3(0.0, 0.0, LIGHT_OFFSET)
	var ticks: float = floorf(3.0 + _rng.randf() * 7.0)
	get_tree().create_timer(ticks * DecompTime.TICK_SEC).timeout.connect(light.queue_free)


## `eEL_CalcAdjust`.
static func _adjust(now: float, start: float, end: float, a: float, b: float) -> float:
	if now <= start:
		return a
	if now >= end:
		return b
	return a + (now - start) * ((b - a) / (end - start))
