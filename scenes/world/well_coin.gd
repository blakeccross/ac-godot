class_name WellCoin
extends Node3D

## A coin tossed into the wishing well on New Year's Day (`ef_coin`). It flies up and over,
## tumbling, toward the well (192.65° plus a little either way). At the water line it
## splashes in (SE 0x467), sinks 4.5 GX and fades from 180 to 0. Runs on `delta` in metres
## and seconds; the flight is closed form, so it lands at the same moment at any frame rate.

const SCENE_PATH := "res://scenes/world/well_coin.tscn"
const VISUAL := &"ef_coin"
const GX := FieldCatalog.GX_TO_METERS
## Gives up on a coin still flying after 100 ticks.
const FLY_TIME := 100.0 / 60.0
## Gone 300 ticks after the splash, fading all the way.
const SINK_TIME := 300.0 / 60.0
## Thrown from this far off the player (GX).
const START_GX := Vector3(9.0, 11.0, -15.0)
## 5.5 GX a tick up, 0.77 across, under 0.2 GX/tick² of gravity.
const SPEED_UP := 5.5 * GX * 60.0
const SPEED_ACROSS := 0.77 * GX * 60.0
const GRAVITY := 0.2 * GX * 3600.0
## `offset.x = 14 + eCoin_GetFountainHeight() - 3`, the fountain being the shrine acre's base
## height + 40 — the ground the well stands on — so the water is 11 GX above that ground.
const WATER_ABOVE_GROUND := (14.0 - 3.0) * GX
## Sinks 4.5 GX at 0.14 GX a tick.
const SINK_DEPTH := 4.5 * GX
const SINK_SPEED := 0.14 * GX * 60.0
## Tumbles 21.1° / 18.3° / 19.7° a tick on each axis while flying.
const SPIN_RATE := Vector3(21.09375, 18.28125, 19.6875) * (PI / 180.0) * 60.0
const SE_TOSS := &"466"
const SE_SPLASH := &"467"

## Seconds in the current phase (flying, then sinking).
var age: float = 0.0
var _start: Vector3
var _velocity: Vector3
var _water_y: float
var _spin0 := Vector3.ZERO
var _sunk: bool = false
var _visual: Node3D


## `eCoin_ct` from the player at `from` (metres), over a well standing on ground `base_y`.
static func toss(parent: Node, from: Vector3, base_y: float, rng: RandomNumberGenerator) -> WellCoin:
	var coin := (load(SCENE_PATH) as PackedScene).instantiate() as WellCoin
	coin.setup(from, base_y, rng)
	parent.add_child(coin)
	return coin


func setup(from: Vector3, base_y: float, rng: RandomNumberGenerator) -> void:
	_start = from + START_GX * GX
	var jitter: float = rng.randf() * 768.0 if rng.randi_range(0, 9) & 1 == 1 else -rng.randf() * 1024.0
	var angle: float = (jitter / 65536.0) * TAU + deg_to_rad(192.65625)
	_velocity = Vector3(sin(angle) * SPEED_ACROSS, SPEED_UP, cos(angle) * SPEED_ACROSS)
	_water_y = base_y + WATER_ABOVE_GROUND
	_spin0 = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)


func _ready() -> void:
	var paths: PackedStringArray = FieldCatalog.mesh_paths(VISUAL)
	if not paths.is_empty():
		_visual = (load(paths[0]) as PackedScene).instantiate() as Node3D
		add_child(_visual)
	Audio.play_se(SE_TOSS, self)
	_apply()


func _physics_process(delta: float) -> void:
	if not advance(delta):
		queue_free()
		return
	_apply()


## Moves the coin on by `delta` seconds; false once it is gone.
func advance(delta: float) -> bool:
	age += delta
	if not _sunk:
		var splash: float = splash_time()
		if age >= splash:
			## Into the water at the exact moment it reaches the line; the rest of this
			## step is spent sinking.
			_sunk = true
			age -= splash
			Audio.play_se(SE_SPLASH, self)
		elif age >= FLY_TIME:
			return false
		else:
			return true
	return age < SINK_TIME


## Seconds from the toss until it falls back to the water line (∞ if it never does).
func splash_time() -> float:
	## y(t) = start + v·t − ½·g·t² = water, taking the later root (on the way down).
	var a: float = -0.5 * GRAVITY
	var b: float = _velocity.y
	var c: float = _start.y - _water_y
	var disc: float = b * b - 4.0 * a * c
	if disc < 0.0:
		return INF
	return (-b - sqrt(disc)) / (2.0 * a)


func sunk() -> bool:
	return _sunk


## Where the coin is now (metres).
func coin_position() -> Vector3:
	if not _sunk:
		var t: float = age
		return _start + _velocity * t + Vector3(0.0, -0.5 * GRAVITY * t * t, 0.0)
	var t_splash: float = splash_time()
	var at: Vector3 = _start + _velocity * t_splash + Vector3(0.0, -0.5 * GRAVITY * t_splash * t_splash, 0.0)
	at.y = _water_y - minf(SINK_SPEED * age, SINK_DEPTH)
	return at


## Opacity once in the water (`calc_adjust(300 - timer, 0, 300, 180, 0)`).
func alpha() -> float:
	if not _sunk:
		return 1.0
	return lerpf(180.0, 0.0, clampf(age / SINK_TIME, 0.0, 1.0)) / 255.0


func _apply() -> void:
	global_position = coin_position()
	rotation = Vector3.ZERO if _sunk else _spin0 + SPIN_RATE * age
	if _visual != null and _sunk:
		_fade(_visual, alpha())


## `ef_coin_modelT`: the sinking coin draws translucent at `a`.
func _fade(node: Node, a: float) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i: int in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(i) as StandardMaterial3D
			if mat == null:
				var base := mi.get_active_material(i) as StandardMaterial3D
				if base == null:
					continue
				mat = base.duplicate() as StandardMaterial3D
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mi.set_surface_override_material(i, mat)
			mat.albedo_color.a = a
	for child: Node in node.get_children():
		_fade(child, a)
