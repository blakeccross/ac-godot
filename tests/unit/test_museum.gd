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


func test_fill_complete_fills_every_painting() -> void:
	## `mMmd_RequestMuseumDisplay` takes `FTR_SUM_ART01`–`ART15`: no painting slot stays empty.
	var book := MuseumBook.new()
	book.fill_complete()
	assert_int(book.count_art()).is_equal(MuseumBook.ART_NUM)
	assert_bool(book.is_complete()).is_true()


func test_every_painting_can_be_donated() -> void:
	## `mMmd_GetDisplayInfo`: ART02 is an ordinary painting; only Redd's `art_forgery_*` items refuse.
	var art2 := FurnitureData.new()
	art2.id = &"int_sum_art02"
	art2.visual_id = &"int_sum_art02"
	ItemCatalog.remember(art2)
	assert_that(Game.museum.display_info_for_item(art2)).is_equal(MuseumBook.DisplayInfo.CAN_DONATE)


func test_donate_fish_from_inventory() -> void:
	var fish: FishData = FishCatalog.get_fish(&"carp")
	assert_that(fish).is_not_null()
	Game.inventory.add(fish, 1)
	var msg: String = String(MuseumDonation.donate(&"carp")["message"])
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


func test_museum_fish_stays_inside_its_glass() -> void:
	## `Museum_Fish_BGCheck`: whatever the swim does, the check point never passes the tank's
	## `54 + _28` half, and the height stays in the 60–110 GX band.
	var school := MuseumFishSchool.new()
	auto_free(school)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for id: StringName in [&"carp", &"eel", &"arowana", &"salmon"]:
		var index: int = MuseumDisplay.fish_index(id)
		school.add(MuseumFishActor.create(FishCatalog.get_fish(id), index, rng))
	for _i in 3000:
		school.tick(1.0)
		for a: MuseumFishActor in school.fish:
			var c: Vector3 = MuseumFishActor.TANK_POS_GX[a.tank]
			var half_x: float = (189.0 if a.tank == 4 else 54.0) + 0.01
			assert_float(absf(a.objchk.x - c.x)).is_less_equal(half_x)
			assert_float(a.pos.y).is_between(MuseumFishActor.Y_MIN, MuseumFishActor.Y_MAX)
	## They swim, rather than sit still.
	for a: MuseumFishActor in school.fish:
		assert_bool(a.pos.distance_to(MuseumFishActor.TANK_POS_GX[a.tank]) > 0.0).is_true()


func test_museum_fish_models_are_act_mus() -> void:
	assert_str(MuseumDisplay.museum_fish_model_path(0)).contains("act_mus_funa_a1")
	assert_str(MuseumDisplay.museum_fish_model_path(32)).contains("act_mus_zari")
	assert_str(MuseumDisplay.museum_fish_model_path(35)).is_equal("")
	assert_bool(ResourceLoader.exists(MuseumDisplay.museum_fish_model_path(0))).is_true()
	assert_bool(ResourceLoader.exists(MuseumDisplay.museum_fish_model_path(39))).is_true()
	var grid := WorldGrid.new()
	grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	var fish: FishData = FishCatalog.get_fish(&"crucian_carp")
	var actor: MuseumFishActor = MuseumFishActor.create(fish, 0, RandomNumberGenerator.new())
	var visual: MuseumFishVisual = MuseumFishVisual.create(actor)
	assert_that(visual).is_not_null()
	## Stand-up GLB: nose +Y / dorsal −X → swim nose +Z / dorsal +Y.
	actor.yaw = 0.0
	actor.pitch = 0.0
	visual._apply_actor_pose()
	var nose: Vector3 = (visual.basis * Vector3.UP).normalized()
	var dorsal: Vector3 = (visual.basis * Vector3.LEFT).normalized()
	## Godot FORWARD is −Z; swim at yaw 0 uses +Z (`sin/cos` on XZ).
	assert_vector(nose).is_equal_approx(Vector3.BACK, Vector3.ONE * 0.001)
	assert_vector(dorsal).is_equal_approx(Vector3.UP, Vector3.ONE * 0.001)
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
		actor.advance(1.0 / 30.0)
		seen[actor.pose_index()] = true
	assert_bool(seen.has(0)).is_true()
	assert_bool(seen.has(1)).is_true()


func test_fish_tank_decor_follows_the_decomp_layout() -> void:
	assert_int(MuseumDisplay.PLANT_POS.size()).is_equal(14)
	assert_int(MuseumDisplay.BUBBLE_POS.size()).is_equal(20)
	assert_int(MuseumDisplay.BUBBLE_TANK.size()).is_equal(20)
	assert_vector(MuseumDisplay.PLANT_POS[0]).is_equal_approx(Vector3(179.0, 0.0, 170.0), Vector3.ONE * 0.001)
	assert_vector(MuseumDisplay.LILY_POS).is_equal_approx(Vector3(420.0, 0.0, 220.0), Vector3.ONE * 0.001)
	assert_int(MuseumDisplay.PLANT_TANK[1]).is_equal(2)
	assert_float(MuseumDisplay.plant_speed_scale(0)).is_equal_approx(1.0, 0.001)
	assert_float(MuseumDisplay.plant_speed_scale(1)).is_equal_approx(3.0, 0.001)
	## Floor snap: GX 40 is the walkable floor, vents start at 60, the surface is 115.
	assert_float(MuseumDisplay.tank_world_y(60.0)).is_equal_approx(1.0, 0.001)
	assert_float(MuseumDisplay.tank_world_y(115.0)).is_equal_approx(3.75, 0.001)
	var bubbles: GDScript = load("res://features/museum/museum_bubbles.gd") as GDScript
	## Largest bubble (effect scale 0.005) on the 0.8-unit card is 0.2 m across.
	assert_float(bubbles.call("node_scale_for", 0.005)).is_equal_approx(0.25, 0.0001)
	assert_float(bubbles.call("node_scale_for", 0.00125)).is_equal_approx(0.0625, 0.0001)


func test_museum_bubbles_grow_to_the_vent_scale() -> void:
	var host := Node3D.new()
	host.set_script(load("res://features/museum/museum_bubbles.gd"))
	add_child(host)
	host._vents[0].wait = 0.0
	host._step_vents()
	for _i: int in 6:
		host._step_bubbles()
	var bubble: Variant = host._live[0]
	## The billboard shader scales the quad; the node itself stays at 1.
	var card: Vector2 = (bubble.mat as ShaderMaterial).get_shader_parameter("card_scale")
	assert_float(card.x).is_greater(0.05)
	assert_float(card.x).is_less(0.3)
	assert_float((bubble.host as Node3D).position.y).is_greater(0.9)
	host.free()


func test_fish_tank_meshes_resolve() -> void:
	assert_bool(FieldCatalog.mesh_paths(&"obj_suisou1").size() > 0).is_true()
	assert_bool(FieldCatalog.mesh_paths(&"obj_museum5").size() > 0).is_true()
	assert_float(FieldCatalog.actor_draw_scale(&"obj_suisou1")).is_equal_approx(0.01, 0.0001)
	assert_float(FieldCatalog.actor_draw_scale(&"obj_museum5")).is_equal_approx(0.0625, 0.0001)
	assert_float(FieldCatalog.actor_uniform_scale_for(&"obj_museum5")).is_equal_approx(
		FieldCatalog.acre_uniform_scale(), 0.0001
	)


func test_tank_caustic_uses_both_water_tiles() -> void:
	## emu64 cycle 1 samples tile 1. Tile 0 is albedo; tile 1 is the occlusion slot.
	var std := StandardMaterial3D.new()
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tile0 := GradientTexture2D.new()
	var tile1 := GradientTexture2D.new()
	std.albedo_texture = tile0
	std.ao_texture = tile1
	var mat := VisualStructureMaterials.apply_fish_tank_surface(
		std, "obj_suisou1_water1_tex", std, &"obj_suisou1"
	) as ShaderMaterial
	assert_that(mat).is_not_null()
	assert_str(String(mat.get_meta("tank_layer", &""))).is_equal("caustic")
	assert_object(mat.get_shader_parameter("ripple_texture_a")).is_same(tile0)
	assert_object(mat.get_shader_parameter("ripple_texture_b")).is_same(tile1)


func test_fish_tank_materials_stop_layer_fighting() -> void:
	## MASK frame + BLEND evw share wall planes; CULL_DISABLED made each quad fight itself.
	var host := Node3D.new()
	auto_free(host)
	add_child(host)
	var pivot: Node3D = GeneratedVisual.attach(host, &"obj_suisou1")
	assert_that(pivot).is_not_null()
	var saw_mask := false
	var saw_blend := false
	for node: Node in pivot.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i: int in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(i)
			if mat is ShaderMaterial:
				saw_blend = true
				var layer: StringName = (mat as ShaderMaterial).get_meta("tank_layer", &"")
				assert_bool(layer in [&"evw", &"mizu", &"caustic"]).is_true()
				if layer == &"caustic":
					var water1: Texture2D = (mat as ShaderMaterial).get_shader_parameter("ripple_texture_a")
					var water2: Texture2D = (mat as ShaderMaterial).get_shader_parameter("ripple_texture_b")
					assert_that(water1).is_not_null()
					assert_that(water2).is_not_null()
					assert_object(water2).is_not_same(water1)
				continue
			if not mat is StandardMaterial3D:
				continue
			var std := mat as StandardMaterial3D
			assert_int(std.cull_mode).is_equal(BaseMaterial3D.CULL_BACK)
			if std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				saw_mask = true
				assert_int(std.depth_draw_mode).is_equal(BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY)
			elif std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
				saw_blend = true
				assert_int(std.depth_draw_mode).is_equal(BaseMaterial3D.DEPTH_DRAW_DISABLED)
		## Do not XZ-scale the blend mesh — that shrank water away from the frame.
		if String(mi.name).ends_with("_blend"):
			assert_float(mi.scale.x).is_equal_approx(1.0, 0.0001)
	assert_bool(saw_mask).is_true()
	assert_bool(saw_blend).is_true()


func test_museum_fish_glow_follows_the_tank_the_player_faces() -> void:
	## Standing in tank 0: that light is full (55) and the far tank is out of the 60 GX fade.
	var near: Array[Dictionary] = MuseumFishLight.glow_gx(Vector3(220.0, 0.0, 220.0))
	assert_float(float(near[0]["power"])).is_equal_approx(55.0, 0.01)
	assert_float(float(near[1]["power"])).is_equal_approx(0.0, 0.01)
	## Sea tank: both lights offset ±20 GX from the player, still inside the bowl.
	var sea: Array[Dictionary] = MuseumFishLight.glow_gx(Vector3(320.0, 0.0, 20.0))
	assert_vector(sea[0]["pos"] as Vector3).is_equal_approx(Vector3(300.0, 0.0, 20.0), Vector3(0.01, 0.01, 0.01))
	assert_vector(sea[1]["pos"] as Vector3).is_equal_approx(Vector3(340.0, 0.0, 20.0), Vector3(0.01, 0.01, 0.01))
	assert_float(float(sea[0]["power"])).is_equal_approx(55.0 * 40.0 / 60.0, 0.01)
	## Past the last tank the lights switch off.
	var away: Array[Dictionary] = MuseumFishLight.glow_gx(Vector3(320.0, 0.0, 600.0))
	assert_float(float(away[0]["power"])).is_equal_approx(0.0, 0.01)
	assert_float(float(away[1]["power"])).is_equal_approx(0.0, 0.01)


func test_sea_tank_highlight_uses_the_sea_prim() -> void:
	var host := Node3D.new()
	auto_free(host)
	add_child(host)
	var pivot: Node3D = GeneratedVisual.attach(host, &"obj_museum5")
	var found := false
	for node: Node in pivot.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i: int in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i) as ShaderMaterial
			if mat == null or mat.get_meta("tank_layer", &"") != &"evw":
				continue
			found = true
			assert_float(float(mat.get_shader_parameter("base_alpha"))).is_equal_approx(60.0 / 255.0, 0.001)
			assert_float(float(mat.get_shader_parameter("texture_alpha"))).is_equal_approx(20.0 / 256.0, 0.001)
	assert_bool(found).is_true()


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
	var aabb: AABB = VisualFit.local_aabb(pivot)
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
	## TYPEC skeletons use 2×2 so `furniture_world` adds +½ cell (`aMR_UnitNumber2Position`).
	assert_that(MuseumDisplay.fossil_footprint(0)).is_equal(Vector2i(2, 2))
	assert_that(MuseumDisplay.fossil_footprint(20)).is_equal(Vector2i(1, 1))
	assert_that(MuseumDisplay.fossil_footprint(9)).is_equal(Vector2i(2, 1))
	var wing := IndoorSession.new()
	wing.bind(fossil)
	var cell: Vector2i = MuseumDisplay.FOSSIL_CELLS[0]
	var type_c: Vector3 = wing.grid.furniture_world(cell, Vector2i(2, 2), WorldGrid.Facing.NORTH)
	var type_a: Vector3 = wing.grid.furniture_world(cell, Vector2i(1, 1), WorldGrid.Facing.NORTH)
	assert_vector(type_c).is_equal(type_a + Vector3(wing.grid.cell_size * 0.5, 0.0, wing.grid.cell_size * 0.5))


func test_painting_fossil_walls_stand_on_the_floor_edge() -> void:
	## The BG walks the whole inner rect (x 1–14, z 1–12): no wall box covers the outer
	## floor units.
	for wing_id: StringName in [&"museum_painting", &"museum_fossil"]:
		var room: Room = InteriorCatalog.room_template(wing_id)
		var wing := IndoorSession.new()
		wing.bind(room)
		var terrain := Node3D.new()
		auto_free(terrain)
		InteriorShellBuilder.add_museum_shell_collision(
			terrain, room, wing.grid, InteriorShellBuilder.museum_door_gaps(room, wing.grid)
		)
		for cell: Vector2i in [Vector2i(1, 6), Vector2i(14, 6), Vector2i(6, 12), Vector2i(6, 2)]:
			var at: Vector3 = wing.grid.cell_to_world(cell) + Vector3(0.0, 1.0, 0.0)
			assert_bool(_point_in_any_box(terrain, at)).override_failure_message(
				"%s %s" % [wing_id, cell]
			).is_false()
		## Just outside the inner rect is wall.
		var outside: Vector3 = wing.grid.cell_to_world(Vector2i(0, 6)) + Vector3(0.0, 1.0, 0.0)
		assert_bool(_point_in_any_box(terrain, outside)).is_true()


func test_entrance_door_gaps_keep_wing_openings() -> void:
	## Inset walls must not bury art / fossil / insect door sensors.
	var room: Room = InteriorCatalog.room_template(&"museum_entrance")
	var wing := IndoorSession.new()
	wing.bind(room)
	var gaps: Array[Dictionary] = InteriorShellBuilder.museum_door_gaps(room, wing.grid)
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


func test_fossil_exhibits_have_no_collision() -> void:
	## `ac_museum_fossil` has no `ClObj` and the wing's BG is open floor: the player walks
	## among (and through) the skeletons, as in the original.
	Game.museum.fill_complete()
	var room: Room = InteriorCatalog.room_template(&"museum_fossil")
	var wing := IndoorSession.new()
	wing.bind(room)
	var root := Node3D.new()
	auto_free(root)
	add_child(root)
	MuseumPresenter.new().present_fossils(root, wing)
	var fossil: Node3D = root.get_node_or_null("Fossil_00") as Node3D
	assert_that(fossil).is_not_null()
	assert_that(fossil.get_node_or_null("ExhibitCollision")).is_null()


func test_painting_hangs_at_decomp_height() -> void:
	## `aMP_DrawOneArt` translates to Y=40 GX (2 m) — frame bottom rests on that line.
	assert_float(MuseumDisplay.ART_HANG_Y).is_equal_approx(2.0, 0.01)
	var cell: Vector2i = MuseumDisplay.ART_CELLS[0]
	var at := Vector3(
		float(cell.x) * 2.0 + 1.0, MuseumDisplay.ART_HANG_Y, float(cell.y) * 2.0 + 1.0
	)
	var room: Room = InteriorCatalog.room_template(&"museum_painting")
	var wing := IndoorSession.new()
	wing.bind(room)
	Game.museum.fill_complete()
	var root := Node3D.new()
	auto_free(root)
	add_child(root)
	MuseumPresenter.new().present(root, wing)
	var art: Node3D = root.get_node_or_null("Art_00") as Node3D
	assert_that(art).is_not_null()
	assert_vector(art.position).is_equal_approx(WorldGrid.room_point(wing.grid, at), Vector3.ONE * 0.0001)
	var pivot: Node3D = art.get_node_or_null("GeneratedVisual") as Node3D
	if pivot == null:
		return
	var aabb: AABB = VisualFit.local_aabb(pivot)
	var bottom_y: float = art.position.y + aabb.position.y * pivot.scale.y + pivot.position.y
	assert_float(bottom_y).is_equal_approx(MuseumDisplay.ART_HANG_Y, 0.05)


func test_insect_fish_exit_doors_are_east_west() -> void:
	## Corner sensors (z=560 GX = 28 m) must not be treated as south doors — that made the
	## interact box swallow the enter spawn and bounce the player straight out.
	assert_that(InteriorShellBuilder.museum_door_side(Vector3(29.0, 0.0, 28.0))).is_equal(&"east")
	assert_that(InteriorShellBuilder.museum_door_side(Vector3(3.0, 0.0, 28.0))).is_equal(&"west")
	assert_that(InteriorShellBuilder.museum_door_side(Vector3(16.0, 0.0, 29.0))).is_equal(&"south")
	var insect_box: Vector3 = InteriorShellBuilder.museum_door_box(Vector3(29.0, 0.0, 28.0))
	var fish_box: Vector3 = InteriorShellBuilder.museum_door_box(Vector3(3.0, 0.0, 28.0))
	var paint_box: Vector3 = InteriorShellBuilder.museum_door_box(Vector3(16.0, 0.0, 29.0))
	## East/west: deep in X, wide in Z.
	assert_float(insect_box.x).is_less(insect_box.z)
	assert_float(fish_box.x).is_less(fish_box.z)
	## South: wide in X, deep in Z.
	assert_float(paint_box.x).is_greater(paint_box.z)
	## The trigger is exactly the two 40 GX `DOOR` units, so it fires on the player's own unit.
	assert_vector(paint_box * Vector3(1, 0, 1)).is_equal_approx(Vector3(80.0, 0.0, 40.0) * FieldCatalog.GX_TO_METERS, Vector3.ONE * 0.0001)


func test_insect_fish_spawn_clears_exit_sensor() -> void:
	## Enter spawn sits outside the exit interact volume (after correct axis sizing).
	for wing_id: StringName in [&"museum_insect", &"museum_fish"]:
		var room: Room = InteriorCatalog.room_template(wing_id)
		var wing := IndoorSession.new()
		wing.bind(room)
		var exit: Dictionary = MuseumDisplay.WING_EXIT_DOORS[wing_id] as Dictionary
		var enter: Dictionary = {}
		for link: Dictionary in MuseumDisplay.ENTRANCE_WING_DOORS:
			if link["room"] == wing_id:
				enter = link
				break
		assert_bool(enter.is_empty()).is_false()
		var spawn: Vector3 = WorldGrid.room_point(wing.grid, enter["spawn"] as Vector3)
		var sensor: Vector3 = WorldGrid.room_point(wing.grid, exit["sensor"] as Vector3)
		var box: Vector3 = InteriorShellBuilder.museum_door_box(exit["sensor"] as Vector3)
		var half: Vector3 = box * 0.5
		var local: Vector3 = spawn - sensor
		var inside: bool = (
			absf(local.x) <= half.x + 0.05
			and absf(local.z) <= half.z + 0.05
		)
		assert_bool(inside).is_false()

	var room: Room = InteriorCatalog.room_template(&"museum_entrance")
	var wing := IndoorSession.new()
	wing.bind(room)
	var root := Node3D.new()
	auto_free(root)
	add_child(root)
	MuseumInteriorBuilder.add_blathers(root, wing)
	await get_tree().process_frame
	var blathers: Node3D = root.get_node_or_null("Blathers") as Node3D
	assert_that(blathers).is_not_null()
	assert_vector(blathers.position).is_equal(
		WorldGrid.room_point(wing.grid, MuseumDisplay.BLATHERS_STAND)
	)
	assert_float(blathers.rotation.y).is_equal_approx(
		WorldGrid.yaw_for_facing(MuseumDisplay.BLATHERS_FACING), 0.01
	)
	assert_bool(blathers.has_method("get_interactions")).is_true()
	var ctx := InteractionContext.new()
	ctx.inventory = Game.inventory
	var actions: Array = blathers.call("get_interactions", ctx)
	assert_int(actions.size()).is_greater(0)
	assert_that(actions[0].id).is_equal(Interaction.TALK)
	var anim: AnimationPlayer = VisualAnimation.find_animation_player(blathers)
	if anim != null:
		assert_bool(anim.is_playing()).is_true()
		assert_str(anim.current_animation).contains("wait")

	MuseumInteriorBuilder.add_museum_clock(root, wing)
	var clock: Node3D = root.get_node_or_null("MuseumClock") as Node3D
	if not FieldCatalog.mesh_paths(MuseumDisplay.CLOCK_VISUAL).is_empty():
		assert_that(clock).is_not_null()
		assert_vector(clock.position).is_equal(
			WorldGrid.room_point(wing.grid, MuseumDisplay.CLOCK)
		)
		var pivot: Node3D = clock.get_node_or_null("GeneratedVisual") as Node3D
		assert_that(pivot).is_not_null()
		## Mesh AABB min sits on the floor (joint Y alone would float mid-body).
		var aabb: AABB = VisualFit.local_aabb(pivot)
		var feet_y: float = pivot.position.y + aabb.position.y * pivot.scale.y
		assert_float(feet_y).is_equal_approx(0.0, 0.02)
	assert_bool(FieldCatalog.mesh_paths(&"rom_museum1").size() > 0).is_true()


func test_museum_rooms_collide_on_their_bg_units() -> void:
	## Every museum room collides exactly as its `collision[]`: the painting partitions (row 5
	## open at x 5–8, row 9 at x 7–10) and the insect cases (`rom_museum4`, height 6) block,
	## while the fossil wing is open floor — the fossils themselves carry no collision.
	var paint: Dictionary = InteriorUnitCollision.blocked_from_bg(
		&"rom_museum3", FieldCatalog.LAND_COUNTS, FieldCatalog.HEIGHT_MAX, Rect2i(0, 0, 16, 16)
	)
	for x: int in range(1, 15):
		assert_bool(paint.has(Vector2i(x, 5))).is_equal(x < 5 or x > 8)
		assert_bool(paint.has(Vector2i(x, 9))).is_equal(x < 7 or x > 10)
		assert_bool(paint.has(Vector2i(x, 6))).is_false()
	assert_float(float(paint[Vector2i(2, 5)])).is_equal_approx(3.0, 0.0001)  ## 60 GX
	var insect: Dictionary = InteriorUnitCollision.blocked_from_bg(
		&"rom_museum4", FieldCatalog.LAND_COUNTS, FieldCatalog.HEIGHT_MAX, Rect2i(0, 0, 16, 16)
	)
	if InteriorUnitCollision.bg_counts(&"rom_museum4").is_empty():
		return  ## pipeline not run
	assert_bool(insect.has(Vector2i(5, 4))).is_true()
	assert_bool(insect.has(Vector2i(2, 4))).is_false()
	var fossil: Dictionary = InteriorUnitCollision.blocked_from_bg(
		&"rom_museum2", FieldCatalog.LAND_COUNTS, FieldCatalog.HEIGHT_MAX, Rect2i(1, 1, 14, 12)
	)
	assert_bool(fossil.is_empty()).is_true()
	for id: StringName in [&"museum_painting", &"museum_fossil", &"museum_insect"]:
		var room: Room = InteriorCatalog.room_template(id)
		var wing := IndoorSession.new()
		wing.bind(room)
		var terrain := Node3D.new()
		auto_free(terrain)
		assert_bool(InteriorShellBuilder.add_museum_unit_collision(terrain, room, wing.grid)).is_true()
		assert_object(terrain.get_node_or_null("MuseumUnitCol")).is_not_null()


func test_every_museum_room_has_exit_gap() -> void:
	## Enter/exit sensors must cut shell walls in every wing.
	var expected: Dictionary = {
		## Exit sensor first, then wing links (painting, fossil, insect, fish).
		&"museum_entrance": [&"south", &"north", &"north", &"west", &"east"],
		&"museum_painting": [&"south"],
		&"museum_fossil": [&"south"],
		&"museum_insect": [&"east"],
		&"museum_fish": [&"west"],
	}
	for room_id: StringName in expected.keys():
		var room: Room = InteriorCatalog.room_template(room_id)
		var wing := IndoorSession.new()
		wing.bind(room)
		var gaps: Array[Dictionary] = InteriorShellBuilder.museum_door_gaps(room, wing.grid)
		var want: Array = expected[room_id] as Array
		assert_int(gaps.size()).is_equal(want.size())
		for i: int in gaps.size():
			assert_that(gaps[i]["side"]).is_equal(want[i])
			assert_float(float(gaps[i]["half"])).is_equal_approx(
				InteriorShellBuilder.MUSEUM_DOOR_HALF, 0.01
			)
		## Every door's own units stay open (the warp fires on them); past them is wall, as in
		## `collision[]`.
		if room_id != &"museum_entrance":
			continue
		var terrain := Node3D.new()
		auto_free(terrain)
		InteriorShellBuilder.add_museum_shell_collision(terrain, room, wing.grid, gaps)
		var sensors: Array[Vector3] = [MuseumDisplay.ENTRANCE_EXIT_SENSOR]
		for link: Dictionary in MuseumDisplay.ENTRANCE_WING_DOORS:
			sensors.append(link["sensor"] as Vector3)
		for sensor: Vector3 in sensors:
			var probe: Vector3 = WorldGrid.room_point(wing.grid, sensor) + Vector3(0.0, 1.0, 0.0)
			assert_bool(_point_in_any_box(terrain, probe)).override_failure_message(str(sensor)).is_false()


func test_fish_and_insect_door_thresholds_stay_clear() -> void:
	## z=560 corner exits: inset south wall used to sit on the door line.
	for room_id: StringName in [&"museum_fish", &"museum_insect"]:
		var room: Room = InteriorCatalog.room_template(room_id)
		var wing := IndoorSession.new()
		wing.bind(room)
		var gaps: Array[Dictionary] = InteriorShellBuilder.museum_door_gaps(room, wing.grid)
		var terrain := Node3D.new()
		auto_free(terrain)
		InteriorShellBuilder.add_museum_shell_collision(terrain, room, wing.grid, gaps)
		var link: Dictionary = MuseumDisplay.WING_EXIT_DOORS[room_id] as Dictionary
		## Where the entrance's door puts the player in this wing.
		var arrive: Vector3 = Vector3.ZERO
		for entry: Dictionary in MuseumDisplay.ENTRANCE_WING_DOORS:
			if entry["room"] == room_id:
				arrive = entry["spawn"] as Vector3
		var spawn: Vector3 = WorldGrid.room_point(wing.grid, arrive)
		var sensor: Vector3 = WorldGrid.room_point(wing.grid, link["sensor"] as Vector3)
		assert_bool(_point_in_any_box(terrain, spawn + Vector3(0.0, 1.0, 0.0))).is_false()
		assert_bool(_point_in_any_box(terrain, sensor + Vector3(0.0, 1.0, 0.0))).is_false()
		## One cell into the room from the door must also stay open.
		var inward := Vector3.ZERO
		match InteriorShellBuilder.museum_door_side(link["sensor"] as Vector3):
			&"west":
				inward = Vector3(wing.grid.cell_size, 0.0, 0.0)
			&"east":
				inward = Vector3(-wing.grid.cell_size, 0.0, 0.0)
			_:
				inward = Vector3.ZERO
		assert_bool(
			_point_in_any_box(terrain, spawn + inward + Vector3(0.0, 1.0, 0.0))
		).is_false()


func _point_in_any_box(root: Node3D, point: Vector3) -> bool:
	for child: Node in root.get_children():
		if not (child is StaticBody3D):
			continue
		## One body per wall box, or one body holding every unit hull (`MuseumUnitCol`).
		for shape_v: Node in child.get_children():
			var shape_node: CollisionShape3D = shape_v as CollisionShape3D
			if shape_node == null or not (shape_node.shape is BoxShape3D):
				continue
			var half: Vector3 = (shape_node.shape as BoxShape3D).size * 0.5
			var local: Vector3 = point - (child as Node3D).position - shape_node.position
			if (
				absf(local.x) <= half.x + 0.01
				and absf(local.y) <= half.y + 0.01
				and absf(local.z) <= half.z + 0.01
			):
				return true
	return false


func _plaque() -> Node3D:
	var plaque: Node3D = auto_free(load("res://features/museum/museum_plaque.tscn").instantiate()) as Node3D
	add_child(plaque)
	return plaque


func test_fossil_talk_needs_the_cardinal_facing_and_reach() -> void:
	## `mRmTp_CheckTalkAble`: within 42.5 GX, facing the exhibit's side to within ±22.5°.
	var plaque := _plaque()
	plaque.call("setup_cardinal", "Fossil 1", 0, MuseumDisplay.FOSSIL_TALK_REACH, false, true)
	var gx := FieldCatalog.GX_TO_METERS
	var south := plaque.global_position + Vector3(0.0, 0.0, 30.0 * gx)
	assert_bool(plaque.call("can_talk", south, PI)).is_true()
	assert_bool(plaque.call("can_talk", south, PI + deg_to_rad(20.0))).is_true()
	## A diagonal facing never counts, nor the far side, nor out of reach.
	assert_bool(plaque.call("can_talk", south, PI + deg_to_rad(30.0))).is_false()
	assert_bool(plaque.call("can_talk", south, 0.0)).is_false()
	assert_bool(plaque.call("can_talk", plaque.global_position + Vector3(0.0, 0.0, 43.0 * gx), PI)).is_false()


func test_sign_talk_is_a_square_facing_north() -> void:
	## `Museum_Insect_Check_Talk_Distance`: |dx|, |dz| < 20 GX, facing north within 67.5°.
	var plaque := _plaque()
	plaque.call("setup_sign", "Case 1", MuseumDisplay.SIGN_TALK_HALF)
	var gx := FieldCatalog.GX_TO_METERS
	var at := plaque.global_position + Vector3(15.0 * gx, 0.0, 15.0 * gx)
	assert_bool(plaque.call("can_talk", at, PI)).is_true()
	assert_bool(plaque.call("can_talk", at, PI - deg_to_rad(60.0))).is_true()
	assert_bool(plaque.call("can_talk", at, PI - deg_to_rad(70.0))).is_false()
	assert_bool(plaque.call("can_talk", plaque.global_position + Vector3(21.0 * gx, 0.0, 0.0), PI)).is_false()


func test_exhibit_pages_follow_the_donors() -> void:
	## `Museum_*_GetMsgNo`: a page with more after it asks to read on (12194 / 12195); the last is
	## 12191 for a resident, 12192 for a former one; an empty case is 12193.
	var script: GDScript = load("res://features/museum/museum_plaque.gd")
	var talk: BankTalk = script.ExhibitTalk.new()
	assert_int(talk.start_msg()).is_equal(12193)
	var entries: Array[Dictionary] = [
		{"name": "a bee", "donor": MuseumBook.Donator.PLAYER1},
		{"name": "a moth", "donor": MuseumBook.Donator.DELETED_PLAYER},
		{"name": "a fly", "donor": MuseumBook.Donator.PLAYER2},
	]
	talk.entries = entries
	assert_int(talk.start_msg()).is_equal(12194)
	assert_int(talk.picked(12194, 0)).is_equal(12195)
	assert_int(talk.picked(12195, 0)).is_equal(12191)
	## "Quit reading" follows the message's own branch out.
	assert_int(talk.picked(12194, 1)).is_equal(-1)
