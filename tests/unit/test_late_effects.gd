class_name TestLateEffects
extends GdUnitTestSuite

## The party popper, the costume puff, the spirit's glow and the cannon shell against the numbers
## in `ef_clacker`, `ef_kamifubuki`, `ef_tape`, `ef_halloween`, `ef_make_hem` and `ef_killer`.

func test_a_popper_waits_four_ticks_then_bursts_into_confetti_and_streamers() -> void:
	var popper := auto_free(PartyPopper.new()) as PartyPopper
	add_child(popper)
	popper.start(Vector3.ZERO)
	for i: int in 3:
		popper._tick()
	assert_int(popper._confetti.size()).is_equal(0)
	assert_vector(popper._body_pos).is_equal(Vector3.ZERO)
	popper._tick()
	popper._tick()
	## Timer 76: the burst, then the body starts to move.
	assert_int(popper._confetti.size()).is_equal(PartyPopper.CONFETTI_COUNT)
	assert_int(popper._tapes.size()).is_equal(PartyPopper.TAPE_COUNT)


func test_the_popper_body_flies_up_and_out_at_four_and_a_half_gx_a_tick() -> void:
	var popper := auto_free(PartyPopper.new()) as PartyPopper
	add_child(popper)
	popper.start(Vector3.ZERO)
	for i: int in 6:
		popper._tick()
	## First moving tick: gravity first, then the step.
	var first: Vector3 = popper._body_pos
	assert_float(first.y).is_greater(3.5)
	assert_float(first.z).is_greater(1.5)
	assert_float(first.x).is_equal_approx(0.0, 0.0001)


func test_confetti_and_streamers_are_gone_before_the_popper_is() -> void:
	var popper := auto_free(PartyPopper.new()) as PartyPopper
	add_child(popper)
	popper.start(Vector3.ZERO)
	for i: int in PartyPopper.BODY_TICKS + 2:
		popper._tick()
	assert_int(popper._timer).is_equal(0)
	for i: int in PartyPopper.CONFETTI_TICKS:
		popper._tick()
	assert_int(popper._confetti.size()).is_equal(0)
	assert_int(popper._tapes.size()).is_equal(0)


func test_confetti_colours_run_five_to_a_colour() -> void:
	var popper := auto_free(PartyPopper.new()) as PartyPopper
	add_child(popper)
	popper.start(Vector3.ZERO)
	for i: int in 5:
		popper._tick()
	var counts: Dictionary = {}
	for c: Dictionary in popper._confetti:
		counts[int(c["color"])] = int(counts.get(int(c["color"]), 0)) + 1
	assert_dict(counts).is_equal({0: 5, 1: 5, 2: 5, 3: 5})


func test_the_spirit_glow_brightens_holds_and_fades() -> void:
	assert_float(SpiritGlow._sphere_alpha(0.0)).is_equal(0.0)
	assert_float(SpiritGlow._sphere_alpha(60.0)).is_equal_approx(0.5, 0.0001)
	assert_float(SpiritGlow._sphere_alpha(135.0)).is_equal(1.0)
	assert_float(SpiritGlow._sphere_alpha(151.0)).is_equal(1.0)
	assert_float(SpiritGlow._sphere_alpha(173.0)).is_equal_approx(0.5, 0.0001)
	assert_float(SpiritGlow._sphere_alpha(196.0)).is_equal(0.0)


func test_the_glow_sphere_swells_toward_its_size() -> void:
	var size: float = 0.0
	for i: int in 200:
		size = SpiritGlow._ease(size)
	assert_float(size).is_equal_approx(SpiritGlow.SPHERE_SCALE, 0.002)
	assert_float(SpiritGlow._ease(0.0)).is_less_equal(SpiritGlow.SCALE_MAX_STEP)


func test_the_cannon_stays_quiet_against_the_wall_it_would_shoot_at() -> void:
	var host := auto_free(Node3D.new()) as Node3D
	add_child(host)
	var bounds := Rect2(Vector2(0.0, 0.0), Vector2(8.0, 8.0))
	assert_object(CannonShot.fire(host, Vector3(4.0, 0.0, 7.5), 0.0, bounds)).is_null()
	assert_object(CannonShot.fire(host, Vector3(4.0, 0.0, 1.0), 0.0, bounds)).is_not_null()
	assert_object(CannonShot.fire(host, Vector3(0.5, 0.0, 4.0), PI * 1.5, bounds)).is_null()


func test_the_cannon_shell_slows_and_squashes_at_the_wall_then_leaves() -> void:
	var host := auto_free(Node3D.new()) as Node3D
	add_child(host)
	var bounds := Rect2(Vector2(0.0, 0.0), Vector2(8.0, 8.0))
	var shot: CannonShot = CannonShot.fire(host, Vector3(4.0, 0.0, 1.0), 0.0, bounds)
	assert_object(shot).is_not_null()
	var seen_squash: bool = false
	var seen_slow: bool = false
	for i: int in 400:
		if not is_instance_valid(shot) or shot.is_queued_for_deletion():
			break
		shot._process(1.0 / 60.0)
		seen_slow = seen_slow or shot._slowed
		seen_squash = seen_squash or (shot._squash < 1.0 and shot._squash > 0.0)
	assert_bool(seen_slow).is_true()
	assert_bool(seen_squash).is_true()
	assert_bool(not is_instance_valid(shot) or shot.is_queued_for_deletion()).is_true()


func test_the_gong_flashes_only_in_a_ringside_room() -> void:
	var host := auto_free(Node3D.new()) as Node3D
	add_child(host)
	var gong := FurnitureData.new()
	gong.visual_id = &"int_nog_gong"
	var room := Room.new()
	room.wall_id = FurnitureCatalog.goods_id("wall", 3)
	assert_object(GongFlash.ring(host, gong, room, null)).is_null()
	room.wall_id = FurnitureCatalog.goods_id("wall", GongFlash.RINGSIDE_WALL)
	var flash: GongFlash = GongFlash.ring(host, gong, room, null)
	assert_object(flash).is_not_null()
	var other := FurnitureData.new()
	other.visual_id = &"int_nog_fan01"
	assert_object(GongFlash.ring(host, other, room, null)).is_null()


func test_a_gong_flash_pops_in_every_eight_ticks_and_lasts_five() -> void:
	var host := auto_free(Node3D.new()) as Node3D
	add_child(host)
	var gong := FurnitureData.new()
	gong.visual_id = &"int_nog_gong"
	var room := Room.new()
	room.wall_id = FurnitureCatalog.goods_id("wall", GongFlash.RINGSIDE_WALL)
	var flash: GongFlash = GongFlash.ring(host, gong, room, null)
	flash._process(1.0 / 60.0)
	assert_int(flash._made).is_equal(1)
	for i: int in 7:
		flash._process(1.0 / 60.0)
	assert_int(flash._made).is_equal(1)
	flash._process(1.0 / 60.0)
	assert_int(flash._made).is_equal(2)


func test_the_spirit_ground_light_fades_as_it_arrives_and_leaves() -> void:
	assert_float(SpiritLight.alpha_at(0.0, false)).is_equal(170.0)
	assert_float(SpiritLight.alpha_at(119.0, false)).is_equal(0.0)
	assert_float(SpiritLight.alpha_at(140.0, false)).is_equal(0.0)
	assert_float(SpiritLight.alpha_at(175.0, false)).is_equal(50.0)
	assert_float(SpiritLight.alpha_at(400.0, false)).is_equal(50.0)
	assert_float(SpiritLight.alpha_at(0.0, true)).is_equal(50.0)
	assert_float(SpiritLight.alpha_at(130.0, true)).is_equal(0.0)
	assert_float(SpiritLight.alpha_at(195.0, true)).is_equal(170.0)


func test_a_leaf_flies_from_the_player_to_the_piece_and_lands_by_tick_eight() -> void:
	var player := auto_free(Node3D.new()) as Node3D
	add_child(player)
	var host := auto_free(Node3D.new()) as Node3D
	add_child(host)
	var piece := FurnitureData.new()
	piece.id = &"test_piece"
	var leaf: LeafFlight = LeafFlight.fly(host, player, Vector3(4.0, 0.0, 4.0), piece)
	if leaf == null:
		return
	var arc: float = pow(18.0, 2.0) * (-10.0 / 98.0) + 20.0
	var start := Vector3(0.0, 20.0 + arc, 10.0) * LeafFlight.GX
	assert_vector(leaf._sprite.global_position).is_equal_approx(start, Vector3.ONE * 0.01)
	leaf._age = 30.0
	leaf._place()
	assert_vector(Vector3(leaf._sprite.global_position.x, 0.0, leaf._sprite.global_position.z)).is_equal_approx(Vector3(4.0, 0.0, 4.0), Vector3.ONE * 0.01)


func test_a_washed_car_glitters_in_eleven_stars_at_distinct_spots() -> void:
	var host := auto_free(Node3D.new()) as Node3D
	add_child(host)
	var fx: CarBlight = CarBlight.start(host, Vector3.ZERO, false)
	for i: int in 50:
		fx._process(1.0 / 60.0)
	assert_int(fx._stars_made).is_equal(11)
	var spots: int = 0
	for bit: int in 16:
		if fx._used & (1 << bit) != 0:
			spots += 1
	assert_int(spots).is_equal(11)
