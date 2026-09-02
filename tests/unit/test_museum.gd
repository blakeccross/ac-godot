class_name TestMuseum
extends GdUnitTestSuite

## Museum display bits, donation mapping, and wing tables.


func before_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()


func test_nibble_packing_round_trip() -> void:
	var book := MuseumBook.new()
	assert_bool(book.set_fossil(0, int(MuseumBook.Donator.PLAYER1))).is_true()
	assert_bool(book.set_fossil(1, int(MuseumBook.Donator.PLAYER2))).is_true()
	assert_that(book.fossil_info(0)).is_equal(int(MuseumBook.Donator.PLAYER1))
	assert_that(book.fossil_info(1)).is_equal(int(MuseumBook.Donator.PLAYER2))
	assert_bool(MuseumBook.is_donated(book.fossil_info(0))).is_true()
	assert_bool(MuseumBook.is_donated(book.fossil_info(24))).is_false()


func test_save_round_trip() -> void:
	Game.museum.set_fish(3, int(MuseumBook.Donator.PLAYER1))
	Game.museum.set_insect(0, int(MuseumBook.Donator.PLAYER1))
	var snap: Dictionary = Game.to_save()
	Game.museum.clear()
	assert_that(Game.museum.count_fish()).is_equal(0)
	Game.apply_snapshot(snap)
	assert_bool(Game.museum.has_fish_id(&"koi")).is_true()
	assert_bool(Game.museum.has_insect_type(0)).is_true()


func test_fill_complete_skips_forgeries() -> void:
	Game.museum.fill_complete()
	## 15 art slots minus ART02/ART03 forgeries.
	assert_that(Game.museum.count_art()).is_equal(13)
	assert_that(Game.museum.count_fossils()).is_equal(25)
	assert_that(Game.museum.count_fish()).is_equal(40)
	assert_that(Game.museum.count_insects()).is_equal(40)
	assert_that(Game.museum.count_all()).is_equal(25 + 13 + 40 + 40)


func test_forgery_cannot_donate() -> void:
	var art2 := FurnitureData.new()
	art2.id = &"int_sum_art02"
	art2.visual_id = &"int_sum_art02"
	ItemCatalog.remember(art2)
	assert_that(Game.museum.display_info_for_item(art2)).is_equal(MuseumBook.DisplayInfo.CANNOT_DONATE)


func test_donate_fish_from_inventory() -> void:
	var fish: FishData = FishCatalog.get_fish(&"carp")
	assert_that(fish).is_not_null()
	Game.inventory.add(fish, 1)
	var msg: String = Game.donate_to_museum(&"carp")
	assert_str(msg).contains("Donated")
	assert_that(Game.inventory.count_of(&"carp")).is_equal(0)
	assert_bool(Game.museum.has_fish_id(&"carp")).is_true()
	assert_that(Game.museum.display_info_for_item(fish)).is_equal(MuseumBook.DisplayInfo.ALREADY_DONATED)


func test_fish_index_matches_agyo_order() -> void:
	assert_that(MuseumDisplay.fish_index(&"crucian_carp")).is_equal(0)
	assert_that(MuseumDisplay.fish_index(&"carp")).is_equal(2)
	assert_that(MuseumDisplay.fish_index(&"coelacanth")).is_equal(31)
	assert_that(MuseumDisplay.fish_index(&"arapaima")).is_equal(39)
	assert_that(MuseumDisplay.fish_tank(2)).is_equal(0)
	assert_that(MuseumDisplay.fish_tank(31)).is_equal(4)


func test_fossil_set_complete() -> void:
	Game.museum.set_fossil(0)
	Game.museum.set_fossil(1)
	assert_bool(MuseumDisplay.fossil_set_just_completed(Game.museum, 1)).is_false()
	Game.museum.set_fossil(2)
	assert_bool(MuseumDisplay.fossil_set_just_completed(Game.museum, 2)).is_true()


func test_insect_active_schedule() -> void:
	## Common butterfly (0): active 8–17.
	assert_bool(MuseumDisplay.insect_is_active(0, 12)).is_true()
	assert_bool(MuseumDisplay.insect_is_active(0, 18)).is_false()
	## Firefly (27): active 19–4.
	assert_bool(MuseumDisplay.insect_is_active(27, 21)).is_true()
	assert_bool(MuseumDisplay.insect_is_active(27, 12)).is_false()


func test_delete_player_remaps_to_deleted() -> void:
	Game.museum.set_fish(0, int(MuseumBook.Donator.PLAYER2))
	Game.museum.delete_presented_by_player(1)
	assert_that(Game.museum.fish_info(0)).is_equal(int(MuseumBook.Donator.DELETED_PLAYER))
	assert_bool(MuseumBook.is_donated(Game.museum.fish_info(0))).is_true()


func test_map_item_categories() -> void:
	var fish: FishData = FishCatalog.get_fish(&"piranha")
	var mapped: Dictionary = MuseumDisplay.map_item(fish)
	assert_that(mapped.get("category")).is_equal(MuseumDisplay.Category.FISH)
	assert_that(mapped.get("index")).is_equal(24)
	var bug: BugData = BugCatalog.get_bug(&"common_butterfly")
	mapped = MuseumDisplay.map_item(bug)
	assert_that(mapped.get("category")).is_equal(MuseumDisplay.Category.INSECT)
	assert_that(mapped.get("index")).is_equal(0)


func test_fish_actor_stays_in_tank() -> void:
	var grid := WorldGrid.new()
	grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	var fish: FishData = FishCatalog.get_fish(&"carp")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var actor: MuseumFishActor = MuseumFishActor.create(fish, 2, grid, rng)
	assert_that(actor).is_not_null()
	assert_that(actor.tank).is_equal(0)
	## Swim Y is `_0C` minus tank water-line (40 GX) after floor snap.
	assert_float(actor.position.y).is_greater(0.5)
	assert_float(actor.position.y).is_less(4.0)
	for _i in 120:
		actor.tick(1.0 / 30.0)
	var center: Vector3 = MuseumDisplay.gx_to_world(grid, Vector3(MuseumDisplay.TANK_POS_GX[0].x, 0.0, MuseumDisplay.TANK_POS_GX[0].z))
	var half: Vector3 = MuseumDisplay.tank_half(0) * FieldCatalog.GX_TO_METERS
	assert_float(actor.position.x).is_greater_equal(center.x - half.x - 0.01)
	assert_float(actor.position.x).is_less_equal(center.x + half.x + 0.01)
	assert_float(actor.position.z).is_greater_equal(center.z - half.z - 0.01)
	assert_float(actor.position.z).is_less_equal(center.z + half.z + 0.01)
	assert_float(actor.position.y).is_greater(0.0)


func test_museum_fish_models_are_act_mus() -> void:
	assert_str(MuseumDisplay.museum_fish_model_path(0)).contains("act_mus_funa_a1")
	assert_str(MuseumDisplay.museum_fish_model_path(32)).contains("act_mus_zari")
	assert_str(MuseumDisplay.museum_fish_model_path(35)).is_equal("")
	assert_bool(ResourceLoader.exists(MuseumDisplay.museum_fish_model_path(0))).is_true()
	assert_bool(ResourceLoader.exists(MuseumDisplay.museum_fish_model_path(39))).is_true()
	var grid := WorldGrid.new()
	grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	var fish: FishData = FishCatalog.get_fish(&"crucian_carp")
	var actor: MuseumFishActor = MuseumFishActor.create(fish, 0, grid, RandomNumberGenerator.new())
	var visual: MuseumFishVisual = MuseumFishVisual.create(actor)
	assert_that(visual).is_not_null()
	visual.free()


func test_insect_actor_pose_flaps() -> void:
	var grid := WorldGrid.new()
	grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	var bug: BugData = BugCatalog.get_bug(&"common_butterfly")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	Clock.hour = 12
	var actor: MuseumInsectActor = MuseumInsectActor.create(bug, grid, rng)
	assert_that(actor).is_not_null()
	assert_bool(actor.active).is_true()
	var seen: Dictionary = {}
	for _i in 60:
		actor.tick(1.0 / 30.0)
		seen[actor.pose_index()] = true
	assert_bool(seen.has(0)).is_true()
	assert_bool(seen.has(1)).is_true()


func test_fish_tank_meshes_resolve() -> void:
	assert_bool(FieldCatalog.mesh_paths(&"obj_suisou1").size() > 0).is_true()
	assert_bool(FieldCatalog.mesh_paths(&"obj_museum5").size() > 0).is_true()
	assert_float(FieldCatalog.actor_draw_scale(&"obj_suisou1")).is_equal_approx(0.01, 0.0001)
	assert_float(FieldCatalog.actor_draw_scale(&"obj_museum5")).is_equal_approx(0.0625, 0.0001)
	assert_float(FieldCatalog.actor_uniform_scale_for(&"obj_museum5")).is_equal_approx(
		FieldCatalog.acre_uniform_scale(), 0.0001
	)


func test_museum5_uses_acre_ground_datum() -> void:
	## Sea tank verts are acre-space; floor datum Y=40 GX must land on world 0 like rom shells.
	var host := Node3D.new()
	auto_free(host)
	add_child(host)
	var pivot: Node3D = GeneratedVisual.attach(host, &"obj_museum5")
	assert_that(pivot).is_not_null()
	assert_float(pivot.scale.y).is_equal_approx(FieldCatalog.acre_uniform_scale(), 0.0001)
	assert_float(pivot.position.y).is_equal_approx(FieldCatalog.acre_ground_y_offset(), 0.01)
	## Authored min Y is below the 40 GX datum — after acre fit it sits under the floor,
	## while the water-line/datum plane is at host Y=0.
	var aabb: AABB = GeneratedVisual.local_aabb(pivot)
	var floor_y: float = pivot.position.y + 0.64 * pivot.scale.y
	assert_float(floor_y).is_equal_approx(0.0, 0.02)
	assert_float(pivot.position.y + aabb.position.y * pivot.scale.y).is_less(0.0)


func test_fossil_cells_are_absolute_ut() -> void:
	## `mMmd_UT(5,2)` etc. are 16×16 acre cells, not offsets from inner_origin.
	assert_that(MuseumDisplay.FOSSIL_CELLS[0]).is_equal(Vector2i(5, 2))
	assert_that(MuseumDisplay.FOSSIL_CELLS[4]).is_equal(Vector2i(13, 2))
	var fossil: Room = InteriorCatalog.room_template(&"museum_fossil")
	assert_that(fossil.inner_origin).is_equal(Vector2i(1, 1))
	assert_bool(fossil.is_inner(MuseumDisplay.FOSSIL_CELLS[0])).is_true()
	assert_bool(fossil.is_inner(MuseumDisplay.FOSSIL_CELLS[4])).is_true()
	var painting: Room = InteriorCatalog.room_template(&"museum_painting")
	assert_that(painting.inner_origin).is_equal(Vector2i(1, 1))
	assert_that(painting.inner_size).is_equal(Vector2i(14, 12))


func test_painting_fossil_shell_covers_floor_rim() -> void:
	## Wall meshes occupy the outer floor cell; margin-only boxes left a walk-through gap.
	for wing_id: StringName in [&"museum_painting", &"museum_fossil"]:
		var room: Room = InteriorCatalog.room_template(wing_id)
		var wing := Interior.new()
		wing.bind(room)
		var terrain := Node3D.new()
		auto_free(terrain)
		var builder := InteriorBuilder.new()
		builder.add_museum_shell_collision(
			terrain, room, wing.grid, builder.museum_door_gaps(room, wing.grid)
		)
		var inner_nw: Vector3 = wing.grid.cell_corner(room.inner_origin)
		var rim_end: float = inner_nw.z + wing.grid.cell_size
		var covered := false
		for child: Node in terrain.get_children():
			if not (child is StaticBody3D):
				continue
			var shape_node: CollisionShape3D = child.get_child(0) as CollisionShape3D
			if shape_node == null or not (shape_node.shape is BoxShape3D):
				continue
			var box: BoxShape3D = shape_node.shape as BoxShape3D
			if box.size.y < 1.0:
				continue
			var z0: float = child.position.z - box.size.z * 0.5
			var z1: float = child.position.z + box.size.z * 0.5
			## Rim coverage away from the south door gap (center aisle stays open).
			var x0: float = child.position.x - box.size.x * 0.5
			var x1: float = child.position.x + box.size.x * 0.5
			if x1 < 4.0 or x0 > 8.0:
				continue
			if z0 <= 0.05 and z1 >= rim_end - 0.05:
				covered = true
				break
		assert_bool(covered).is_true()


func test_entrance_door_gaps_keep_wing_openings() -> void:
	## Inset walls must not bury art / fossil / insect door sensors.
	var room: Room = InteriorCatalog.room_template(&"museum_entrance")
	var wing := Interior.new()
	wing.bind(room)
	var builder := InteriorBuilder.new()
	var gaps: Array[Dictionary] = builder.museum_door_gaps(room, wing.grid)
	var sides: PackedStringArray = PackedStringArray()
	for gap: Dictionary in gaps:
		sides.append(String(gap["side"]))
	assert_bool(sides.has("north")).is_true()
	assert_bool(sides.has("west")).is_true()
	assert_bool(sides.has("east")).is_true()
	assert_bool(sides.has("south")).is_true()
	assert_int(gaps.size()).is_equal(5)
	var north_centers: Array[float] = []
	for gap: Dictionary in gaps:
		if gap["side"] == &"north":
			north_centers.append(float(gap["center"]))
	assert_bool(north_centers.has(8.0)).is_true()
	assert_bool(north_centers.has(16.0)).is_true()


func test_fossil_exhibits_have_collision() -> void:
	Game.museum.fill_complete()
	var room: Room = InteriorCatalog.room_template(&"museum_fossil")
	var wing := Interior.new()
	wing.bind(room)
	var root := Node3D.new()
	auto_free(root)
	add_child(root)
	MuseumPresenter.new().present_fossils(root, wing)
	var fossil: Node3D = root.get_node_or_null("Fossil_00") as Node3D
	assert_that(fossil).is_not_null()
	assert_that(fossil.get_node_or_null("ExhibitCollision")).is_not_null()


func test_painting_hangs_at_decomp_height() -> void:
	## `aMP_DrawOneArt` translates to Y=40 GX — frame bottom rests on that line.
	assert_float(MuseumDisplay.ART_HANG_Y_GX).is_equal_approx(40.0, 0.01)
	var cell: Vector2i = MuseumDisplay.ART_CELLS[0]
	var gx := Vector3(
		float(cell.x) * 40.0 + 20.0, MuseumDisplay.ART_HANG_Y_GX, float(cell.y) * 40.0 + 20.0
	)
	assert_float(gx.y).is_equal_approx(40.0, 0.01)
	assert_float(gx.y * FieldCatalog.GX_TO_METERS).is_equal_approx(2.0, 0.01)
	var room: Room = InteriorCatalog.room_template(&"museum_painting")
	var wing := Interior.new()
	wing.bind(room)
	Game.museum.fill_complete()
	var root := Node3D.new()
	auto_free(root)
	add_child(root)
	MuseumPresenter.new().present(root, wing)
	var art: Node3D = root.get_node_or_null("Art_00") as Node3D
	assert_that(art).is_not_null()
	assert_vector(art.position).is_equal(MuseumDisplay.gx_to_world(wing.grid, gx))
	var pivot: Node3D = art.get_node_or_null("GeneratedVisual") as Node3D
	if pivot == null:
		return
	var aabb: AABB = GeneratedVisual.local_aabb(pivot)
	var bottom_y: float = art.position.y + aabb.position.y * pivot.scale.y + pivot.position.y
	assert_float(bottom_y).is_equal_approx(MuseumDisplay.ART_HANG_Y_GX * FieldCatalog.GX_TO_METERS, 0.05)
