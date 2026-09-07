class_name BeeSwarm
extends Node3D

## Bee nest swarm (`ac_bee`). Appears after a bee-tree shake, chases the player,
## and stings once in range when the player is attackable.

enum Phase { APPEAR, FLY, ATTACK, DISAPPEAR }

## Attack when XZ distance under 30 GX (`aBEE_ACT_ATTACK`).
const ATTACK_GX := 30.0
const CHASE_HEIGHT_GX := 50.0
const APPEAR_SEC := 0.45
const STING_LOCK_SEC := 1.2
const GAME_FPS := 30.0

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
		Phase.FLY, Phase.ATTACK:
			_chase(delta)
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


func _sting() -> void:
	phase = Phase.DISAPPEAR
	_elapsed = 0.0
	PlayerSe.bee_sting(self)
	Game.post_notice("You've been stung by bees!")
	if _player != null and is_instance_valid(_player) and _player.has_method("set_busy"):
		_player.call("set_busy", true)
		get_tree().create_timer(STING_LOCK_SEC).timeout.connect(
			func() -> void:
				if is_instance_valid(_player) and _player.has_method("set_busy"):
					_player.call("set_busy", false),
			CONNECT_ONE_SHOT
		)
