class_name CostumePuff
extends Node3D

## The puff of violet smoke round the player when a trick-or-treater's trick changes their
## clothes or swaps a pocket item (`eEC_EFFECT_HALLOWEEN`, `ef_halloween.c`; `Player_actor_
## SetEffect_FromDemoOrder_common` order 0xFD). For 40 ticks, every fourth one, a
## `eEC_EFFECT_HALLOWEEN_SMOKE` rises from a random point 18 GX round the head and up to
## 25 below to 5 above it.

const GX := FieldCatalog.GX_TO_METERS
const TOTAL_TICKS := 40.0
const PERIOD_TICKS := 4.0
const SE_POOF := &"107"

var _at: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _made: int = 0
var _rng := RandomNumberGenerator.new()


## Puff over the player's head (the glyph point `feel_pos`), if there is a player.
static func at_player() -> CostumePuff:
	var tree := Engine.get_main_loop() as SceneTree
	var player: Player = Player.find(tree)
	if player == null:
		return null
	return start(player.get_parent(), player.feel.global_position)


static func start(host: Node, head: Vector3) -> CostumePuff:
	if host == null:
		return null
	var puff := CostumePuff.new()
	puff.name = "CostumePuff"
	puff._at = head
	puff._rng.randomize()
	host.add_child(puff)
	Audio.play_se(SE_POOF, puff)
	return puff


func _process(delta: float) -> void:
	_age += delta * DecompTime.TICK_HZ
	while float(_made + 1) * PERIOD_TICKS <= _age and float(_made + 1) * PERIOD_TICKS < TOTAL_TICKS:
		_made += 1
		_smoke()
	if _age >= TOTAL_TICKS:
		queue_free()


func _smoke() -> void:
	var a: float = _rng.randf() * TAU
	var at: Vector3 = _at + Vector3(18.0 * sin(a), -25.0 + _rng.randf() * 30.0, 5.0 + 18.0 * cos(a)) * GX
	FieldParticle.spawn(get_parent(), FieldEffects.Kind.HALLOWEEN_SMOKE, at, a, 0, 0)
