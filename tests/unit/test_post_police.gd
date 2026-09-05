extends GdUnitTestSuite

## Post office + police box interiors (`PostDisplay` / `PoliceDisplay` / books).


func before_test() -> void:
	Game.reset_session()


func test_catalog_room_layout_matches_decomp() -> void:
	var post: Room = InteriorCatalog.room_template(&"post_office")
	assert_that(post).is_not_null()
	assert_that(post.kind).is_equal(Room.Kind.POST_OFFICE)
	assert_that(post.inner_origin).is_equal(PostDisplay.INNER_ORIGIN)
	assert_that(post.inner_size).is_equal(PostDisplay.INNER_SIZE)
	assert_that(post.door_cell).is_equal(PostDisplay.DOOR_CELL)
	assert_bool(post.shell_ids.has("grd_post_office")).is_true()
	assert_bool(post.is_always_open()).is_true()
	var police: Room = InteriorCatalog.room_template(&"police_box")
	assert_that(police).is_not_null()
	assert_that(police.kind).is_equal(Room.Kind.POLICE)
	assert_that(police.inner_origin).is_equal(PoliceDisplay.INNER_ORIGIN)
	assert_that(police.inner_size).is_equal(PoliceDisplay.INNER_SIZE)
	assert_that(police.door_cell).is_equal(PoliceDisplay.DOOR_CELL)
	assert_bool(police.shell_ids.has("police_indoor")).is_true()
	assert_bool(police.is_always_open()).is_true()


func test_spawn_gx_tables() -> void:
	assert_vector(PostDisplay.SPAWN_GX).is_equal(Vector3(100.0, 0.0, 200.0))
	assert_vector(PostDisplay.POST_GIRL_STAND_GX).is_equal(Vector3(160.0, 0.0, 100.0))
	assert_vector(PoliceDisplay.SPAWN_GX).is_equal(Vector3(200.0, 0.0, 400.0))
	assert_vector(PoliceDisplay.BOOKER_STAND_GX).is_equal(Vector3(180.0, 0.0, 260.0))
	assert_int(PoliceDisplay.LOST_FOUND_CELLS.size()).is_equal(20)
	assert_that(PoliceDisplay.LOST_FOUND_CELLS[0]).is_equal(Vector2i(1, 1))
	assert_that(PoliceDisplay.LOST_FOUND_CELLS[19]).is_equal(Vector2i(7, 5))


func test_post_girl_day_night_species() -> void:
	assert_that(PostDisplay.post_girl_species(12)).is_equal(PostDisplay.PELLY_SPECIES)
	assert_that(PostDisplay.post_girl_species(7)).is_equal(PostDisplay.PELLY_SPECIES)
	assert_that(PostDisplay.post_girl_species(18)).is_equal(PostDisplay.PELLY_SPECIES)
	assert_that(PostDisplay.post_girl_species(19)).is_equal(PostDisplay.PHYLLIS_SPECIES)
	assert_that(PostDisplay.post_girl_species(6)).is_equal(PostDisplay.PHYLLIS_SPECIES)
	assert_str(PostDisplay.post_girl_name(PostDisplay.PELLY_SPECIES)).is_equal("Pelly")
	assert_str(PostDisplay.post_girl_name(PostDisplay.PHYLLIS_SPECIES)).is_equal("Phyllis")


func test_police_book_init_and_claim() -> void:
	var book := PoliceBook.new()
	assert_int(book.keep_item_sum()).is_equal(0)
	book.ensure_init()
	assert_int(book.keep_item_sum()).is_equal(3)
	assert_that(book.item_at(0)).is_not_equal(&"")
	assert_that(book.item_at(1)).is_not_equal(&"")
	assert_that(book.item_at(2)).is_not_equal(&"")
	Game.inventory.clear()
	var before: int = Game.inventory.count_of_occupied()
	var msg: String = book.claim(0, Game.inventory)
	assert_str(msg).contains("Received")
	assert_that(book.item_at(0)).is_equal(&"")
	assert_int(book.keep_item_sum()).is_equal(2)
	assert_int(Game.inventory.count_of_occupied()).is_equal(before + 1)


func test_police_book_keep_shifts_when_full() -> void:
	var book := PoliceBook.new()
	book.clear()
	for i: int in PoliceBook.STORAGE_COUNT:
		book.keep_item(&"wood_chair")
	assert_int(book.keep_item_sum()).is_equal(PoliceBook.STORAGE_COUNT)
	assert_bool(book.keep_item(&"shirt_000")).is_true()
	assert_int(book.keep_item_sum()).is_equal(PoliceBook.STORAGE_COUNT)
	assert_that(book.item_at(PoliceBook.STORAGE_COUNT - 1)).is_equal(&"shirt_000")


func test_post_book_desk_capacity() -> void:
	var book := PostBook.new()
	assert_int(book.get_keep_mail_sum()).is_equal(0)
	assert_bool(book.is_desk_full()).is_false()
	for _i: int in PostBook.MAIL_STORAGE_SIZE:
		assert_bool(book.receipt_mail()).is_true()
	assert_bool(book.is_desk_full()).is_true()
	assert_bool(book.receipt_mail()).is_false()


func test_enter_sets_decomp_spawns() -> void:
	## Avoid scene change; only assert spawn tables Game would set.
	Game.current_room_id = &""
	Game.has_interior_spawn = false
	var post_room: Room = InteriorCatalog.room_template(&"post_office")
	assert_that(post_room).is_not_null()
	## Mirror `Game.try_enter_interior` spawn branches.
	Game.interior_spawn_gx = PostDisplay.SPAWN_GX
	Game.interior_spawn_yaw = WorldGrid.yaw_for_facing(PostDisplay.SPAWN_FACING)
	Game.has_interior_spawn = true
	assert_vector(Game.interior_spawn_gx).is_equal(PostDisplay.SPAWN_GX)
	assert_float(Game.interior_spawn_yaw).is_equal_approx(
		WorldGrid.yaw_for_facing(PostDisplay.SPAWN_FACING), 0.01
	)
	Game.interior_spawn_gx = PoliceDisplay.SPAWN_GX
	Game.interior_spawn_yaw = WorldGrid.yaw_for_facing(PoliceDisplay.SPAWN_FACING)
	assert_vector(Game.interior_spawn_gx).is_equal(PoliceDisplay.SPAWN_GX)
	assert_float(Game.interior_spawn_yaw).is_equal_approx(
		WorldGrid.yaw_for_facing(PoliceDisplay.SPAWN_FACING), 0.01
	)


func test_scene_paths_and_shell_meshes() -> void:
	assert_str(InteriorCatalog.scene_path(&"post_office")).contains("post_office.tscn")
	assert_str(InteriorCatalog.scene_path(&"police_box")).contains("police_box.tscn")
	assert_bool(ResourceLoader.exists(InteriorCatalog.scene_path(&"post_office"))).is_true()
	assert_bool(ResourceLoader.exists(InteriorCatalog.scene_path(&"police_box"))).is_true()
	assert_bool(FieldCatalog.mesh_paths(&"grd_post_office").size() > 0).is_true()
	assert_bool(FieldCatalog.mesh_paths(&"police_indoor").size() > 0).is_true()
	assert_str(FieldCatalog.mesh_paths(&"grd_post_office")[0]).contains("interiors")


func test_post_police_shells_use_acre_scale() -> void:
	## Classic-N64 scale blew these shells ~16× too large → gray void at spawn.
	for room_id: StringName in [&"post_office", &"police_box"]:
		var room: Room = InteriorCatalog.room_template(room_id)
		var session := Interior.new()
		session.bind(room)
		var packed: PackedScene = load(InteriorCatalog.scene_path(room_id)) as PackedScene
		assert_that(packed).is_not_null()
		var root: Node3D = packed.instantiate() as Node3D
		auto_free(root)
		add_child(root)
		InteriorBuilder.new().populate_authored(root, session)
		var shell: Node3D = root.get_node_or_null("Shell/GeneratedVisual") as Node3D
		assert_that(shell).is_not_null()
		assert_float(shell.scale.x).is_equal_approx(FieldCatalog.acre_uniform_scale(), 0.001)
		assert_float(shell.position.x).is_equal_approx(session.grid.origin.x, 0.05)
		assert_float(shell.position.z).is_equal_approx(session.grid.origin.z, 0.05)


func test_save_roundtrip_books() -> void:
	Game.police.ensure_init()
	Game.police.keep_item(&"net")
	Game.post.receipt_mail()
	Game.post.receipt_mail()
	var snap: Dictionary = Game.to_save()
	var police_sum: int = Game.police.keep_item_sum()
	var mail_sum: int = Game.post.get_keep_mail_sum()
	Game.reset_session()
	Game.apply_snapshot(snap)
	assert_int(Game.police.keep_item_sum()).is_equal(police_sum)
	assert_int(Game.post.get_keep_mail_sum()).is_equal(mail_sum)
