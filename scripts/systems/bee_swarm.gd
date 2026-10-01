class_name BeeSwarm
extends Node3D

## Bee nest swarm (`ac_bee`). Appears after a bee-tree shake, chases the player,
## and stings once in range when the player is attackable.

enum Phase { APPEAR, FLY, ATTACK, DISAPPEAR }

## Attack when XZ distance under 30 GX (`aBEE_ACT_ATTACK`).
const ATTACK_GX := 30.0
const CHASE_HEIGHT_GX := 50.0
const APPEAR_SEC := 0.45
## `BGM_BEE_CHASE` (`mBGMPsComp_make_ps_happening` from the shake's `shock`).
const CHASE_BGM := &"bee_chase"
## `Player_actor_Check_end_stung_bee`: the swarm leaves once the stung timer passes 162.
const ATTACK_END_TICKS := 162.0

var phase: Phase = Phase.APPEAR
var attackable: bool = false

var _player: Node3D
var _elapsed: float = 0.0
var _mesh: MeshInstance3D


static func spawn(parent: Node, at: Vector3, player: Node3D) -> BeeSwarm:
	if parent == null:
		return null
	var swarm := BeeSwarm.new()
	swarm.name = "BeeSwarm"
	swarm._player = player
	parent.add_child(swarm)
	swarm.global_position = at
	return swarm


func _ready() -> void:
	add_to_group("bee_swarm")
	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	_mesh.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.12, 0.05, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh.material_override = mat
	_mesh.scale = Vector3(0.15, 0.15, 0.15)
	add_child(_mesh)
	phase = Phase.APPEAR
	_elapsed = 0.0
	## `aBEE_appear_init`.
	Game.bee_chase = true
	if EventManager.demo_bgm == &"":
		EventManager.demo_bgm = CHASE_BGM
		Audio.play_bgm(CHASE_BGM)


func _exit_tree() -> void:
	## Gone (stung, or the scene changed): the chase is over, and so is its music.
	Game.bee_chase = false
	if EventManager.demo_bgm == CHASE_BGM:
		EventManager.demo_bgm = &""
		var world: World = World.find(get_tree())
		if world != null and is_instance_valid(world) and not world.is_queued_for_deletion():
			world.call("_play_outdoor_bgm")


## Called near the end of the shake clip (`STATUS_FOR_BEE_ATTACK` at frame 29.5).
func mark_attackable() -> void:
	attackable = true


func _process(delta: float) -> void:
	_elapsed += delta
	match phase:
		Phase.APPEAR:
			var t: float = clampf(_elapsed / APPEAR_SEC, 0.0, 1.0)
			_mesh.scale = Vector3.ONE * lerpf(0.15, 1.0, t)
			if t >= 1.0:
				phase = Phase.FLY
		Phase.FLY:
			_chase(delta)
		Phase.ATTACK:
			## `aBEE_attack`: hang about until `mPlib_Check_end_stung_bee`.
			_hover(delta)
		Phase.DISAPPEAR:
			var fade: float = clampf(1.0 - _elapsed / 0.5, 0.0, 1.0)
			_mesh.scale = Vector3.ONE * fade
			if fade <= 0.0:
				queue_free()


func _chase(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		phase = Phase.DISAPPEAR
		_elapsed = 0.0
		return
	var target: Vector3 = _player.global_position
	target.y += CHASE_HEIGHT_GX * FieldCatalog.GX_TO_METERS
	var to: Vector3 = target - global_position
	var dist_xz: float = Vector2(to.x, to.z).length()
	var speed: float = 4.5
	if dist_xz > 0.001:
		global_position += to.normalized() * speed * delta
	## Buzz sway.
	global_position.y += sin(Time.get_ticks_msec() * 0.02) * 0.02
	if attackable and dist_xz <= ATTACK_GX * FieldCatalog.GX_TO_METERS:
		_sting()


func _hover(delta: float) -> void:
	var player := _player as Player if is_instance_valid(_player) else null
	if player == null or not player.stung or _elapsed * DecompTime.TICK_HZ > ATTACK_END_TICKS:
		phase = Phase.DISAPPEAR
		_elapsed = 0.0
		return
	var target: Vector3 = player.global_position
	target.y += CHASE_HEIGHT_GX * FieldCatalog.GX_TO_METERS
	global_position = global_position.lerp(target, clampf(delta * 3.0, 0.0, 1.0))
	global_position.y += sin(Time.get_ticks_msec() * 0.02) * 0.02


## `mPlib_request_main_stung_bee_type1` → `aBEE_ACT_ATTACK`.
func _sting() -> void:
	PlayerSe.bee_sting(self)
	var player := _player as Player if is_instance_valid(_player) else null
	if player == null:
		Game.sting_by_bee()
		phase = Phase.DISAPPEAR
		_elapsed = 0.0
		return
	phase = Phase.ATTACK
	_elapsed = 0.0
	player.run_stung_bee()
