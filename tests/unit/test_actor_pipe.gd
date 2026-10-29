extends GdUnitTestSuite

## `ActorPipe`: actor-vs-actor push (`CollisionCheck_setOC_HitInfo`).


class Pipe extends Node3D:
	var weight: int = ActorPipe.WEIGHT_NORMAL
	var height: float = ActorPipe.NPC_HEIGHT

	func pipe_radius() -> float:
		return ActorPipe.RADIUS

	func pipe_height() -> float:
		return height

	func pipe_weight() -> int:
		return weight

	func pipe_active() -> bool:
		return true


func _pipe(at: Vector3, weight: int = ActorPipe.WEIGHT_NORMAL) -> Pipe:
	var p := Pipe.new()
	p.weight = weight
	auto_free(p)
	add_child(p)
	p.add_to_group(ActorPipe.GROUP)
	p.global_position = at
	return p


func test_share_follows_the_mass_types() -> void:
	## Two normal actors split by weight; heavy only yields to immovable; immovable never moves.
	assert_float(ActorPipe.share(50, 50)).is_equal_approx(0.5, 0.0001)
	assert_float(ActorPipe.share(50, 253)).is_equal_approx(253.0 / 303.0, 0.0001)
	assert_float(ActorPipe.share(50, ActorPipe.WEIGHT_HEAVY)).is_equal(1.0)
	assert_float(ActorPipe.share(ActorPipe.WEIGHT_HEAVY, 50)).is_equal(0.0)
	assert_float(ActorPipe.share(ActorPipe.WEIGHT_HEAVY, ActorPipe.WEIGHT_HEAVY)).is_equal(0.5)
	assert_float(ActorPipe.share(ActorPipe.WEIGHT_HEAVY, ActorPipe.WEIGHT_IMMOVABLE)).is_equal(1.0)
	assert_float(ActorPipe.share(ActorPipe.WEIGHT_IMMOVABLE, 50)).is_equal(0.0)


func test_overlapping_pipes_push_apart_by_their_shares() -> void:
	## 2 m apart is touching (20 GX + 20 GX); at 1.2 m each normal actor gives 0.4 m.
	var a := _pipe(Vector3.ZERO)
	var b := _pipe(Vector3(1.2, 0.0, 0.0))
	var both: Array = [a, b]
	var r: Dictionary = ActorPipe.resolve(both)
	assert_vector(r[a.get_instance_id()]).is_equal_approx(Vector3(-0.4, 0.0, 0.0), Vector3.ONE * 0.0001)
	assert_vector(r[b.get_instance_id()]).is_equal_approx(Vector3(0.4, 0.0, 0.0), Vector3.ONE * 0.0001)
	## An immovable one holds; the other takes the whole overlap.
	b.weight = ActorPipe.WEIGHT_IMMOVABLE
	r = ActorPipe.resolve(both)
	assert_vector(r[a.get_instance_id()]).is_equal_approx(Vector3(-0.8, 0.0, 0.0), Vector3.ONE * 0.0001)
	assert_vector(r.get(b.get_instance_id(), Vector3.ZERO)).is_equal(Vector3.ZERO)
	## Apart, or at different heights, nothing.
	b.global_position = Vector3(2.1, 0.0, 0.0)
	assert_bool(ActorPipe.resolve(both).is_empty()).is_true()
	b.global_position = Vector3(1.0, ActorPipe.NPC_HEIGHT + 0.1, 0.0)
	assert_bool(ActorPipe.resolve(both).is_empty()).is_true()
