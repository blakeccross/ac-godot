class_name WellCoin
extends Node3D

## A coin tossed into the wishing well on New Year's Day (`ef_coin`). It flies up and over
## at 5.5 GX a tick under 0.2 gravity, tumbling, toward the well (192.65° plus a little
## either way). At the water line it splashes in
## (SE 0x467) and sinks 0.14 GX a tick for 4.5 GX, fading from 180 to 0 over 300 ticks.

const SCENE_PATH := "res://scenes/world/well_coin.tscn"
const VISUAL := &"ef_coin"
const FLY_TICKS := 100
const SINK_TICKS := 300
const START := Vector3(9.0, 11.0, -15.0)
const SPEED_Y := 5.5
const SPEED_XZ := 0.77
const GRAVITY := -0.2
## `offset.x = 14 + eCoin_GetFountainHeight() - 3`, the fountain being the shrine acre's base
## height + 40 — the ground the well stands on — so the water is 11 GX above that ground.
const WATER_ABOVE_GROUND := 14.0 - 3.0
const SINK_DEPTH := 4.5
const SINK_SPEED := 0.14
const SE_TOSS := &"466"
const SE_SPLASH := &"467"

var _pos_gx: Vector3
var _vel: Vector3
var _water_gx: float
var _spin := Vector3.ZERO
var _ticks: int = 0
var _sunk: bool = false
var _steps := FrameStepper.new(DecompTime.TICK_HZ, 8.0)
var _visual: Node3D


## `eCoin_ct` from the player at `from` (metres), over a well standing on ground `base_y`.
static func toss(parent: Node, from: Vector3, base_y: float, rng: RandomNumberGenerator) -> WellCoin:
	var coin := (load(SCENE_PATH) as PackedScene).instantiate() as WellCoin
	coin.setup(from, base_y, rng)
	parent.add_child(coin)
	return coin


func setup(from: Vector3, base_y: float, rng: RandomNumberGenerator) -> void:
	_pos_gx = from / FieldCatalog.GX_TO_METERS + START
	var jitter: float = rng.randf() * 768.0 if rng.randi_range(0, 9) & 1 == 1 else -rng.randf() * 1024.0
	var angle: float = (jitter / 65536.0) * TAU + deg_to_rad(192.65625)
	_vel = Vector3(sin(angle) * SPEED_XZ, SPEED_Y, cos(angle) * SPEED_XZ)
	_water_gx = base_y / FieldCatalog.GX_TO_METERS + WATER_ABOVE_GROUND
	_spin = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)


func _ready() -> void:
	var paths: PackedStringArray = FieldCatalog.mesh_paths(VISUAL)
	if not paths.is_empty():
		_visual = (load(paths[0]) as PackedScene).instantiate() as Node3D
		add_child(_visual)
	Audio.play_se(SE_TOSS, self)
	_apply()


func _physics_process(delta: float) -> void:
	_steps.add(delta)
	while _steps.next():
		if not tick():
			queue_free()
			return
	_apply()


## One `eCoin_mv`; false when it is gone.
func tick() -> bool:
	_ticks += 1
	if not _sunk:
		_vel.y += GRAVITY
		_pos_gx += _vel
		_spin += Vector3(deg_to_rad(21.09375), deg_to_rad(18.28125), deg_to_rad(19.6875))
		## Thrown from the water line's own height (11 GX up), so it counts on the way down.
		if _vel.y < 0.0 and _pos_gx.y <= _water_gx:
			_pos_gx.y = _water_gx
			_sunk = true
			_ticks = 0
			_spin = Vector3.ZERO
			Audio.play_se(SE_SPLASH, self)
		elif _ticks >= FLY_TICKS:
			return false
		return true
	if _pos_gx.y > _water_gx - SINK_DEPTH:
		_pos_gx.y = maxf(_pos_gx.y - SINK_SPEED, _water_gx - SINK_DEPTH)
	return _ticks < SINK_TICKS


func sunk() -> bool:
	return _sunk


func height_gx() -> float:
	return _pos_gx.y


## Opacity once in the water (`calc_adjust(300 - timer, 0, 300, 180, 0)`).
func alpha() -> float:
	if not _sunk:
		return 1.0
	return lerpf(180.0, 0.0, clampf(float(_ticks) / float(SINK_TICKS), 0.0, 1.0)) / 255.0


func _apply() -> void:
	global_position = _pos_gx * FieldCatalog.GX_TO_METERS
	rotation = _spin
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
