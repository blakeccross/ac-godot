class_name TestBeeStartle
extends GdUnitTestSuite

## A bee nest's startle (`m_player_main_shock`) and the swarm's chase (`ac_bee`).

const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")


func before_test() -> void:
	TestIsolation.forget_groups(get_tree(), [Player.GROUP, &"bee_swarm"])
	Game.bees.chasing = false


func after_test() -> void:
	Game.bees.chasing = false
	if EventManager.demo_bgm == BeeSwarm.CHASE_BGM:
		EventManager.demo_bgm = &""


func _player() -> Player:
	var player: Player = auto_free(PLAYER_SCENE.instantiate()) as Player
	add_child(player)
	return player


func test_startle_holds_the_player_and_no_sting_lands() -> void:
	var player: Player = _player()
	await get_tree().process_frame
	assert_bool(player.can_be_stung()).is_true()
	player.request_shock(Player.BEE_SHOCK_START_SEC, PI * 0.5, false)
	await get_tree().process_frame
	assert_bool(player.shocked).is_true()
	assert_bool(player.can_be_stung()).is_false()
	## 24 ticks of standing, then `start + 44` ticks in all.
	await get_tree().create_timer(Player.BEE_SHOCK_START_SEC + Player.SHOCK_TAIL_SEC + 0.1).timeout
	assert_bool(player.shocked).is_false()
	assert_bool(player.can_be_stung()).is_true()
	## Turned toward the cause.
	assert_float(absf(angle_difference(player.facing_yaw(), PI * 0.5))).is_less(0.05)


func test_the_chase_music_starts_as_the_startle_ends() -> void:
	var player: Player = _player()
	await get_tree().process_frame
	var swarm: BeeSwarm = BeeSwarm.spawn(self, player.global_position + Vector3(6, 2.5, 0), player)
	auto_free(swarm)
	assert_that(EventManager.demo_bgm).is_not_equal(BeeSwarm.CHASE_BGM)
	await player.request_shock(0.0, 0.0, true)
	assert_that(EventManager.demo_bgm).is_equal(BeeSwarm.CHASE_BGM)


func test_the_swarm_waits_then_runs_the_player_down() -> void:
	## Appear (85 ticks) and flip upright (29) before the chase; then it speeds up to 8.9 GX a
	## frame — faster than the player runs.
	assert_float(BeeSwarm.APPEAR_SEC + BeeSwarm.FLIP_SEC).is_equal_approx(114.0 / 60.0, 0.001)
	assert_float(BeeSwarm.CHASE_SPEED).is_equal_approx(13.35, 0.01)
	var player: Player = _player()
	await get_tree().process_frame
	var swarm: BeeSwarm = BeeSwarm.spawn(self, player.global_position + Vector3(20, 2.5, 0), player)
	auto_free(swarm)
	swarm.phase = BeeSwarm.Phase.FLY
	for _i: int in 30:
		swarm._chase(1.0 / 60.0)
	assert_float(swarm._speed).is_greater(0.0)
	assert_float(swarm._speed).is_less_equal(BeeSwarm.CHASE_SPEED)
	var before: float = (swarm.global_position - player.global_position).length()
	for _i: int in 60:
		swarm._chase(1.0 / 60.0)
	assert_float((swarm.global_position - player.global_position).length()).is_less(before)
