class_name FurnitureBirth
extends Node

## A piece of furniture arriving in a room, or leaving it (`aMR_FtrBirth`, `aMR_BirthWait`,
## `aMR_FtrBye`). Put down, it stays out of sight for 46 ticks while the leaf (`LeafFlight`) comes
## in, then drops in squashing and stretching (scale `1 - s`, `1 + s`, `1 - s` with
## `s = sin(counter) * modifier`, the modifier shrinking by 0.4 and the counter's step growing by 1500
## each time the swing comes round, until the modifier is under 0.02), with the digging sound
## (`NA_SE_ITEM_HORIDASHI`) and two puffs of dust at its corners on tick 2 and two more on tick 6.
## Picked up, it shrinks by a twelfth of its size a tick (nothing below a quarter), puffing at its
## centre on the third tick, then it is gone.

enum Mode { BIRTH, BYE }

const WAIT_TICKS := 46
const BIRTH_STEP := 6000
const BIRTH_MODIFIER := 0.5
const STEP_GROWTH := 1500
const MODIFIER_DECAY := 0.4
const MODIFIER_END := 0.02
const BYE_SHRINK := 1.0 / 12.0
const BYE_FLOOR := 0.25
const BYE_DUST_TICK := 2
const DUST_INSET := 0.6
const DUST_FORWARD := 3.5 * FieldCatalog.GX_TO_METERS
const SE_ID := &"item_horidashi"

var mode: Mode = Mode.BIRTH
## The four dust spots of a birth, or (centre only) of a bye.
var spots: Array[Vector3] = []

var _piece: Node3D
var _base_scale: Vector3 = Vector3.ONE
var _acc: float = 0.0
var _tick: int = 0
var _counter: int = 0
var _step: int = BIRTH_STEP
var _modifier: float = BIRTH_MODIFIER
var _born: bool = false
var _dust_timer: int = 0


## `piece` arrives: hidden until its turn, then bouncing in. `corners` are its four dust spots.
static func birth(piece: Node3D, corners: Array[Vector3]) -> FurnitureBirth:
	return _attach(piece, Mode.BIRTH, corners)


## `piece` leaves: shrinks away and frees itself. `centre` is where the dust goes.
static func bye(piece: Node3D, centre: Vector3) -> FurnitureBirth:
	var spot: Array[Vector3] = [centre]
	return _attach(piece, Mode.BYE, spot)


## The four dust spots round a footprint of `cells` (`aMR_GetDust4Position`): 0.6 of the way out
## in x, all the way in z, and a touch forward.
static func corners_of(grid: WorldGrid, cells: Array[Vector2i]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if grid == null or cells.is_empty():
		return out
	var lo := Vector3(INF, 0.0, INF)
	var hi := Vector3(-INF, 0.0, -INF)
	for cell: Vector2i in cells:
		var at: Vector3 = grid.cell_to_world(cell)
		lo.x = minf(lo.x, at.x - grid.cell_size * 0.5)
		lo.z = minf(lo.z, at.z - grid.cell_size * 0.5)
		hi.x = maxf(hi.x, at.x + grid.cell_size * 0.5)
		hi.z = maxf(hi.z, at.z + grid.cell_size * 0.5)
	var mid := Vector3((lo.x + hi.x) * 0.5, 0.0, (lo.z + hi.z) * 0.5)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var x: float = mid.x + (hi.x - lo.x) * 0.5 * corner.x * DUST_INSET
		var z: float = mid.z + (hi.z - lo.z) * 0.5 * corner.y + DUST_FORWARD
		out.append(Vector3(x, 0.0, z))
	return out


static func _attach(piece: Node3D, p_mode: Mode, p_spots: Array[Vector3]) -> FurnitureBirth:
	if piece == null:
		return null
	var fx := FurnitureBirth.new()
	fx.name = "FurnitureBirth"
	fx.mode = p_mode
	fx.spots = p_spots
	fx._piece = piece
	fx._base_scale = piece.scale
	piece.add_child(fx)
	if p_mode == Mode.BIRTH:
		piece.visible = false
	else:
		fx._dust_timer = BYE_DUST_TICK
	return fx


func _process(delta: float) -> void:
	if _piece == null or not is_instance_valid(_piece):
		queue_free()
		return
	_acc += delta * DecompTime.TICK_HZ
	while _acc >= 1.0 and is_instance_valid(self):
		_acc -= 1.0
		if mode == Mode.BIRTH:
			_birth_tick()
		else:
			_bye_tick()


func _birth_tick() -> void:
	if not _born:
		_tick += 1
		if _tick < WAIT_TICKS:
			return
		_born = true
		_piece.visible = true
		_dust_timer = 0
		Audio.play_se(SE_ID, _piece)
	var prev: int = _counter
	_counter = _wrap(_counter + _step)
	var swing: float = sin(float(_counter) / 65536.0 * TAU) * _modifier
	var squash: float = 1.0 - swing
	_piece.scale = Vector3(_base_scale.x * squash, _base_scale.y * (1.0 + swing), _base_scale.z * squash)
	if _dust_timer == 2:
		_puff(0)
		_puff(2)
	elif _dust_timer == 6:
		_puff(1)
		_puff(3)
	_dust_timer += 1
	if prev < 0 and _counter >= 0:
		_modifier *= MODIFIER_DECAY
		_step += STEP_GROWTH
	if absf(_modifier) < MODIFIER_END:
		_piece.scale = _base_scale
		queue_free()


func _bye_tick() -> void:
	var scale: float = _piece.scale.x / _base_scale.x - BYE_SHRINK
	if scale < BYE_FLOOR:
		scale = 0.0
	_piece.scale = _base_scale * scale if scale > 0.0 else Vector3.ONE * 0.0001
	var dust: int = _dust_timer
	_dust_timer -= 1
	if dust == 0:
		_puff(0)
	if scale == 0.0:
		_piece.queue_free()


func _puff(index: int) -> void:
	if index < 0 or index >= spots.size():
		return
	FootstepEffects.furniture_dust(_piece.get_parent(), spots[index])


## An `s16`: the counter wraps through -0x8000 … 0x7FFF.
static func _wrap(value: int) -> int:
	return ((value + 32768) & 0xFFFF) - 32768
