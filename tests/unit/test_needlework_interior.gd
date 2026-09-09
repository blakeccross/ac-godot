class_name TestNeedleworkInterior
extends GdUnitTestSuite

## Able Sisters interior build (`InteriorBuilder.add_needlework_set`).


func test_room_keeps_acre_origin_and_gx_positions_land_inside() -> void:
	var room: Room = InteriorCatalog.room_template(&"needlework")
	## `rom_tailor` keeps the acre origin so `ac_needlework_indoor.c` GX maps directly.
	assert_bool(GeneratedVisual._shell_keeps_acre_origin(&"rom_tailor")).is_true()
	assert_vector(room.inner_origin).is_equal(Vector2i(1, 1))
	assert_vector(room.inner_size).is_equal(Vector2i(8, 6))
	var session := Interior.new()
	session.bind(room)
	var grid := session.grid
	## every mannequin / umbrella-stand GX maps onto walkable floor
	for gx: Vector3 in InteriorBuilder.NEEDLEWORK_MANNEQUIN_GX + InteriorBuilder.NEEDLEWORK_UMBRELLA_GX:
		var cell := grid.world_to_cell(MuseumDisplay.gx_to_world(grid, gx))
		assert_bool(room.is_inner(cell)).override_failure_message(
			"GX %s -> cell %s is off-floor" % [gx, cell]
		).is_true()
	## mannequins sit north of the umbrella stands, which sit north of the spawn
	var man_z := MuseumDisplay.gx_to_world(grid, InteriorBuilder.NEEDLEWORK_MANNEQUIN_GX[0]).z
	var umb_z := MuseumDisplay.gx_to_world(grid, InteriorBuilder.NEEDLEWORK_UMBRELLA_GX[0]).z
	var spawn_z := grid.cell_to_world(room.spawn_cell).z
	assert_bool(man_z < umb_z).is_true()
	assert_bool(umb_z < spawn_z).is_true()

	## Decomp: you enter AND leave at the door. The spawn is the exit cell (the
	## `rom_tailor.col.json` porch), and the whole room is NORTH of it, so walking
	## in never re-crosses the strip. (`block_auto_enter_doors` disarms the
	## spawn-on-exit until the player steps off.)
	var spawn_cell := grid.world_to_cell(MuseumDisplay.gx_to_world(grid, InteriorCatalog.ABLE_SPAWN_GX))
	assert_bool(room.is_exit_cell(spawn_cell)).is_true()
	assert_int(room.door_cell.y).is_equal(room.inner_origin.y + room.inner_size.y)  ## porch row, just south of the last inner row
	## every display / Sable / Mabel sits strictly north of the exit strip
	for gx: Vector3 in ([InteriorBuilder.NEEDLEWORK_SABLE_GX, InteriorBuilder.NEEDLEWORK_MABEL_GX]
			+ InteriorBuilder.NEEDLEWORK_MANNEQUIN_GX + InteriorBuilder.NEEDLEWORK_UMBRELLA_GX):
		var c := grid.world_to_cell(MuseumDisplay.gx_to_world(grid, gx))
		assert_bool(c.y < room.door_cell.y).override_failure_message("%s at cell %s not north of exit" % [gx, c]).is_true()


func test_add_needlework_set_places_sisters_and_displays() -> void:
	var room: Room = InteriorCatalog.room_template(&"needlework")
	var session := Interior.new()
	session.bind(room)
	var root := Node3D.new()
	auto_free(root)
	add_child(root)
	InteriorBuilder.new().add_needlework_set(root, session)
	assert_that(root.get_node_or_null("Mabel")).is_not_null()
	assert_that(root.get_node_or_null("Sable")).is_not_null()
	for i in 4:
		assert_that(root.get_node_or_null("Mannequin_%d" % i)).is_not_null()
		assert_that(root.get_node_or_null("UmbrellaStand_%d" % i)).is_not_null()
	## the animated `obj_misin` overlay (moving needle + belt) on the baked machine
	var machine: Node = root.get_node_or_null("SewingMachine")
	assert_that(machine).is_not_null()
	var mach_anim: AnimationPlayer = _find_anim(machine)
	assert_that(mach_anim).is_not_null()
	assert_bool(mach_anim.is_playing()).is_true()
	## a second pass must not duplicate
	InteriorBuilder.new().add_needlework_set(root, session)
	assert_int(root.get_children().filter(func(n): return n.name == &"Mabel").size()).is_equal(1)


func test_sable_sews_at_the_machine() -> void:
	var sable: Node = auto_free(load("res://scenes/world/interiors/sable.tscn").instantiate())
	add_child(sable)
	var ap: AnimationPlayer = _find_anim(sable)
	assert_that(ap).is_not_null()
	assert_bool(ap.is_playing()).is_true()
	## faces south (+Z, yaw 0) toward the player / the work — decomp `head.lock_flag`
	assert_float(sable.rotation.y).is_equal_approx(0.0, 0.05)

	## placed just north of the baked machine head (world ≈ (-12.5, _, -9.0))
	var room: Room = InteriorCatalog.room_template(&"needlework")
	var session := Interior.new()
	session.bind(room)
	var pos := MuseumDisplay.gx_to_world(session.grid, InteriorBuilder.NEEDLEWORK_SABLE_GX)
	assert_bool(room.is_inner(session.grid.world_to_cell(pos))).is_true()
	assert_float(pos.z).is_equal_approx(-10.5, 1.2)
	assert_float(pos.x).is_equal_approx(-11.7, 1.0)


func test_mabel_roams_and_collides_with_the_world() -> void:
	var mabel: Node = load("res://scenes/world/interiors/mabel.tscn").instantiate()
	add_child(mabel)
	auto_free(mabel)
	## `CharacterBody3D` so she can roam / follow the player (`aNNW_MY_PROC_*`).
	assert_bool(mabel is CharacterBody3D).is_true()
	## masks the world (furniture / walls) so she can't walk through it
	assert_int((mabel as CharacterBody3D).collision_mask & 1).is_equal(1)
	## on the character layer (4) — the player collides with her (immovable, like decomp)
	assert_int((mabel as CharacterBody3D).collision_layer & 4).is_equal(4)


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r:
			return r
	return null


func test_starter_shop_designs_are_distinct() -> void:
	var book := DesignBook.new()
	var seen: Dictionary = {}
	for i in 8:
		var key: int = hash(book.shop[i].pixels)
		assert_bool(seen.has(key)).override_failure_message(
			"shop design %d ('%s') is not visually distinct" % [i, book.shop[i].name]
		).is_false()
		seen[key] = true
	assert_bool(book.shop[0].pixels == DesignPattern.blank().pixels).is_false()


func test_design_texture_renders_32x32_rgba() -> void:
	var d := DesignPattern.generate(DesignPattern.Motif.CHECK, 3, 2, 9)
	var img := DesignTexture.image(d)
	assert_int(img.get_width()).is_equal(32)
	assert_int(img.get_height()).is_equal(32)
	assert_float(img.get_pixel(0, 0).a).is_equal(1.0)
