class_name LeafFlight
extends Node3D

## The picture of a piece of furniture flying from the player to where it is set down
## (`eEC_EFFECT_KAGU_HAPPA`, `ef_kagu_happa.c`, from `aMR_SetReserveFurniture`): the pocket icon
## starts 20 GX up and 10 ahead of the player, travels in 28 ticks along an arc, wobbling
## ±28° as it swells to full size, lands on the piece by tick 8 of its 36 and, at tick 2, kicks up
## a puff of dust where it fell.

const GX := FieldCatalog.GX_TO_METERS
const TOTAL_TICKS := 36.0
const ARRIVE_TICK := 8.0
const ARRIVE_Z_TICK := 28.0
const ARC_UNTIL_TICK := 10.0
const PUFF_TICK := 2.0
## `eKagu_Happa_mv`: size (GX matrix scale) it eases to, and the per-tick wobble.
const FULL_SCALE := 0.01
const WOBBLE_STEP := 0x924 * MathUtil.S16
const WOBBLE_RANGE := 5120.0 * MathUtil.S16
## A full-size icon, in metres across.
const ICON_METERS := 0.9

var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _size: float = 0.0
var _wobble: float = 0.0
var _puffed: bool = false
var _sprite: Sprite3D


## Fly the icon of `data` from `player` to `target` (world metres), under `host`.
static func fly(host: Node, player: Node3D, target: Vector3, data: ItemData) -> LeafFlight:
	if host == null or player == null or data == null:
		return null
	var tex: Texture2D = InventoryChrome.icon_for_item(data)
	if tex == null:
		return null
	var leaf := LeafFlight.new()
	leaf.name = "LeafFlight"
	var yaw: float = player.rotation.y
	leaf._from = player.global_position + Vector3(sin(yaw) * 10.0, 20.0, cos(yaw) * 10.0) * GX
	leaf._to = target
	host.add_child(leaf)
	leaf.global_transform = Transform3D.IDENTITY
	leaf._sprite = Sprite3D.new()
	leaf._sprite.texture = tex
	leaf._sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	leaf._sprite.pixel_size = ICON_METERS / maxf(tex.get_width(), 1.0)
	leaf._sprite.shaded = false
	leaf._sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	leaf._sprite.transparent = true
	leaf._sprite.no_depth_test = false
	leaf._sprite.top_level = true
	leaf.add_child(leaf._sprite)
	leaf._place()
	return leaf


func _process(delta: float) -> void:
	var from: float = _age
	_age += delta * DecompTime.TICK_HZ
	for _i: int in int(floor(_age)) - int(floor(from)):
		_step()
	if not _puffed and _timer() <= PUFF_TICK:
		_puffed = true
		FootstepEffects.party_puff(get_parent(), _to)
	_place()
	if _age >= TOTAL_TICKS:
		queue_free()


func _timer() -> float:
	return TOTAL_TICKS - _age


## `add_calc(&scale, 0.01, 0.25 ease, 0.0015, 5e-5)` and the wobble turn, once a tick.
func _step() -> void:
	var step: float = (FULL_SCALE - _size) * (1.0 - sqrt(1.0 - 0.25))
	step = clampf(step, -0.0015, 0.0015)
	if absf(FULL_SCALE - _size) < 5e-5:
		_size = FULL_SCALE
	else:
		_size += step
	if _timer() > ARC_UNTIL_TICK:
		_wobble += WOBBLE_STEP


func _place() -> void:
	if _sprite == null:
		return
	var t: float = _timer()
	var at := Vector3(
		_adjust(t, ARRIVE_TICK, TOTAL_TICKS, _to.x, _from.x),
		_adjust(t, ARRIVE_TICK, TOTAL_TICKS, _to.y, _from.y),
		_adjust(t, ARRIVE_TICK, ARRIVE_Z_TICK, _to.z, _from.z),
	)
	if t > ARC_UNTIL_TICK:
		at.y += (pow(t - 18.0, 2.0) * (-10.0 / 98.0) + 20.0) * GX
	elif t <= PUFF_TICK:
		at.y += 5.0 * GX
	_sprite.global_position = at
	_sprite.scale = Vector3.ONE * (_size / FULL_SCALE)
	_sprite.rotation = Vector3(0.0, 0.0, sin(_wobble) * WOBBLE_RANGE)


static func _adjust(now: float, start: float, end: float, a: float, b: float) -> float:
	if now <= start:
		return a
	if now >= end:
		return b
	return a + (now - start) * ((b - a) / (end - start))
