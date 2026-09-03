class_name TestInterior
extends GdUnitTestSuite


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Clock.apply_snapshot({"year": 2001, "month": 1, "day": 1, "hour": 12, "minute": 0})
	Game.reset_session()
	InteriorCatalog.reset()
	ItemCatalog.reload()


func after_test() -> void:
	Game.reset_session()
	InteriorCatalog.reset()
	Clock.reset_to_default()
	Clock.paused = false


func test_catalog_covers_every_gc_interior() -> void:
	var rooms: Array[StringName] = InteriorCatalog.room_ids()
	assert_int(rooms.size()).is_equal(37)
	for id: StringName in [
		&"shop0",
		&"broker_shop",
		&"post_office",
		&"police_box",
		&"buggy",
		&"shop1",
		&"shop2",
		&"shop3_1",
		&"shop3_2",
		&"kamakura",
		&"museum_entrance",
		&"museum_painting",
		&"museum_fossil",
		&"museum_insect",
		&"museum_fish",
		&"needlework",
		&"lighthouse",
		&"tent",
		&"player_main",
		&"player_upper",
		&"player_basement",
		&"cottage",
		&"npc_0",
		&"npc_14",
	]:
		assert_bool(InteriorCatalog.has_room(id)).is_true()
	assert_that(InteriorCatalog.resolve_entry(&"player_house")).is_equal(&"player_main")
	assert_that(InteriorCatalog.resolve_entry(&"npc_house_3")).is_equal(&"npc_3")
	assert_that(InteriorCatalog.resolve_entry(&"acre_shop")).is_equal(&"shop0")
	assert_that(InteriorCatalog.resolve_entry(&"museum")).is_equal(&"museum_entrance")
	assert_that(InteriorCatalog.resolve_entry(&"able_sisters")).is_equal(&"needlework")
	assert_bool(InteriorCatalog.has_room(&"npc_filbert")).is_true()
	assert_that(InteriorCatalog.resolve_entry(&"filbert")).is_equal(&"npc_filbert")
	var filbert: Room = InteriorCatalog.room_template(&"npc_filbert")
	var rosie: Room = InteriorCatalog.room_template(&"npc_rosie")
	assert_that(filbert).is_not_null()
	assert_that(rosie).is_not_null()
	assert_bool(filbert.wall_id != rosie.wall_id or filbert.floor_id != rosie.floor_id).is_true()
	assert_bool(filbert.shell_ids.has("rom_myhome2_floor")).is_true()
	assert_bool(filbert.shell_ids.has("rom_myhome2_wall")).is_true()
	var player_main: Room = InteriorCatalog.room_template(&"player_main")
	assert_bool(player_main.shell_ids.has("rom_myhome1_floor")).is_true()
	assert_that(player_main.inner_origin).is_equal(InteriorCatalog.PLAYER_INNER_ORIGIN)
	assert_that(player_main.inner_size).is_equal(InteriorCatalog.PLAYER_INNER_SIZE)
	assert_that(player_main.wall_id).is_equal(InteriorCatalog.wall_style_id(InteriorCatalog.PLAYER_START_WALL))
	assert_that(player_main.floor_id).is_equal(InteriorCatalog.floor_style_id(InteriorCatalog.PLAYER_START_FLOOR))
	assert_int(player_main.placements.size()).is_equal(2)
	var starter_ids: PackedStringArray = PackedStringArray()
	for entry: FurniturePlacement in player_main.placements:
		starter_ids.append(String(entry.furniture_id))
	assert_bool(starter_ids.has("int_nog_mikanbox")).is_true()
	assert_bool(starter_ids.has("int_sum_casse01")).is_true()
	assert_bool(InteriorCatalog.room_template(&"shop0").shell_ids.has("rom_shop1f")).is_true()
	assert_int(InteriorCatalog.room_template(&"shop0").placements.size()).is_equal(2)
	assert_bool(InteriorCatalog.room_template(&"needlework").shell_ids.has("rom_tailor")).is_true()
	assert_int(InteriorCatalog.room_template(&"needlework").placements.size()).is_equal(1)


func test_npc_room_uses_fg_furniture() -> void:
	if not FileAccess.file_exists(InteriorCatalog.NPC_ROOMS_PATH):
		return
	var filbert: Room = InteriorCatalog.room_template(&"npc_filbert")
	assert_that(filbert).is_not_null()
	assert_int(filbert.placements.size()).is_greater(1)
	var ids: PackedStringArray = PackedStringArray()
	for entry: FurniturePlacement in filbert.placements:
		ids.append(String(entry.furniture_id))
	assert_bool(ids.has("wood_chair")).is_false()
	assert_bool(ids.has("int_ari_table01") or ids.has("int_sum_fruittv01")).is_true()
	for entry: FurniturePlacement in filbert.placements:
		assert_bool(String(entry.furniture_id).contains("hnw_common")).is_false()
	assert_that(filbert.inner_origin).is_equal(Vector2i(1, 1))
	assert_that(filbert.inner_size).is_equal(Vector2i(6, 6))
	var session := Interior.new()
	session.bind(filbert)
	var shell: AABB = InteriorBuilder.new()._shell_bounds(filbert, session.grid)
	assert_float(shell.size.x).is_equal_approx(12.0, 0.001)
	assert_float(shell.size.z).is_equal_approx(12.0, 0.001)
	var cam := Camera3D.new()
	cam.set_script(load("res://scenes/world/follow_camera.gd"))
	auto_free(cam)
	add_child(cam)
	cam.call("lock_at", Vector3(1.0, 0.0, 2.0))
	assert_bool(bool(cam.get("_locked"))).is_true()
	cam.fov = 20.0
	var framed: Vector3 = cam.call("offset_for_ground_span", 16.0)
	assert_float(framed.y).is_greater(20.0)
	assert_float(framed.z).is_equal_approx(framed.y, 0.001)
	var tighter: Vector3 = cam.call("offset_for_ground_span", 12.0)
	assert_float(framed.y).is_greater(tighter.y)
	var small: Vector3 = cam.call("offset_to_frame_span", 8.0)
	var floor: Vector3 = cam.call("offset_to_frame_span", 1.0)
	assert_float(small.y).is_equal_approx(floor.y, 0.01)
	assert_float(small.y).is_greater(cam.call("offset_for_ground_span", 8.0).y)
	assert_float(framed.y).is_greater(small.y)
	var InteriorWorld := load("res://scenes/world/interior.gd")
	assert_bool(InteriorWorld.pins_follow_camera(filbert)).is_true()
	assert_bool(InteriorWorld.pins_follow_camera(InteriorCatalog.room_template(&"player_main"))).is_true()
	assert_bool(InteriorWorld.pins_follow_camera(InteriorCatalog.room_template(&"shop0"))).is_false()
	assert_bool(InteriorWorld.pins_follow_camera(InteriorCatalog.room_template(&"museum_fish"))).is_false()
	assert_bool(InteriorWorld.pins_follow_camera(InteriorCatalog.room_template(&"museum_entrance"))).is_false()


func test_alli_mannequins_carry_cloth_index() -> void:
	if not FileAccess.file_exists(InteriorCatalog.NPC_ROOMS_PATH):
		return
	var room: Room = InteriorCatalog.room_template(&"npc_alli")
	assert_that(room).is_not_null()
	var mannequins := 0
	for entry: FurniturePlacement in room.placements:
		if String(entry.furniture_id) != "int_fmanekin":
			continue
		mannequins += 1
		assert_int(entry.cloth_index).is_greater_equal(0)
	assert_int(mannequins).is_greater(1)


func test_apply_cloth_paints_seg08_only() -> void:
	var host := MeshInstance3D.new()
	auto_free(host)
	add_child(host)
	host.mesh = BoxMesh.new()
	var shirt := StandardMaterial3D.new()
	shirt.resource_name = "seg_08"
	host.set_surface_override_material(0, shirt)
	var path: String = FieldCatalog.cloth_albedo(0)
	if path.is_empty():
		return
	GeneratedVisual.apply_cloth(host, 0)
	var painted: StandardMaterial3D = host.get_surface_override_material(0) as StandardMaterial3D
	assert_that(painted).is_not_null()
	assert_that(painted.albedo_texture).is_not_null()
	assert_bool(painted.texture_repeat).is_false()


func test_mannequin_glb_shirt_gets_cloth_albedo() -> void:
	var paths: PackedStringArray = FieldCatalog.mesh_paths(&"int_fmanekin")
	if paths.is_empty() or FieldCatalog.cloth_albedo(0).is_empty():
		return
	var packed: PackedScene = load(paths[0]) as PackedScene
	assert_that(packed).is_not_null()
	var inst: Node = packed.instantiate()
	auto_free(inst)
	add_child(inst)
	GeneratedVisual.apply_preview_materials(inst)
	var labels := PackedStringArray()
	_collect_surface_labels(inst, labels)
	GeneratedVisual.apply_cloth(inst, 0)
	assert_str(" | ".join(labels)).contains("seg_08")
	assert_bool(_any_cloth_albedo(inst)).is_true()
	assert_bool(_cloth_uv_scale_is_half(inst)).is_true()


func _collect_surface_labels(node: Node, out: PackedStringArray) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var n: int = mi.mesh.get_surface_count() if mi.mesh != null else 1
		for i: int in n:
			out.append(GeneratedVisual._surface_label(mi, i, mi.get_active_material(i)))
	for child in node.get_children():
		_collect_surface_labels(child, out)


func _any_cloth_albedo(node: Node) -> bool:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var n: int = mi.mesh.get_surface_count() if mi.mesh != null else 1
		for i: int in n:
			var mat: Material = mi.get_active_material(i)
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null:
				if GeneratedVisual._is_cloth_surface(mi, i, mat):
					return true
	for child in node.get_children():
		if _any_cloth_albedo(child):
			return true
	return false


func _cloth_uv_scale_is_half(node: Node) -> bool:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var n: int = mi.mesh.get_surface_count() if mi.mesh != null else 1
		for i: int in n:
			var mat: Material = mi.get_active_material(i)
			if mat is StandardMaterial3D and GeneratedVisual._is_cloth_surface(mi, i, mat):
				var std := mat as StandardMaterial3D
				if std.albedo_texture != null and is_equal_approx(std.uv1_scale.x, 0.5):
					return true
	for child in node.get_children():
		if _cloth_uv_scale_is_half(child):
			return true
	return false


func test_save_restores_alli_mannequin_cloth() -> void:
	if not FileAccess.file_exists(InteriorCatalog.NPC_ROOMS_PATH):
		return
	var room: Room = Game.interiors.room(&"npc_alli")
	assert_that(room).is_not_null()
	var bags: Array = []
	for entry: FurniturePlacement in room.placements:
		var bag: Dictionary = entry.to_save()
		bag.erase("cl")
		bags.append(bag)
	Game.interiors.apply_snapshot({"rooms": {"npc_alli": {"placements": bags}}})
	var loaded: Room = Game.interiors.room(&"npc_alli")
	var mannequins := 0
	for entry: FurniturePlacement in loaded.placements:
		if String(entry.furniture_id) != "int_fmanekin":
			continue
		mannequins += 1
		assert_int(entry.cloth_index).is_greater_equal(0)
	assert_int(mannequins).is_greater(1)
	var template: Room = InteriorCatalog.room_template(&"npc_alli")
	for entry: FurniturePlacement in template.placements:
		if String(entry.furniture_id) == "int_fmanekin":
			assert_int(entry.cloth_index).is_greater_equal(0)


func test_huggy_piano_occupies_se_typec_block() -> void:
	## NORTH TYPEC must not rotate occupancy onto the gyroid at (3,4) (`mRmTp_size_l_data`).
	if not FileAccess.file_exists(InteriorCatalog.NPC_ROOMS_PATH):
		return
	var room: Room = InteriorCatalog.room_template(&"npc_huggy")
	assert_that(room).is_not_null()
	var piano: FurniturePlacement = null
	for entry: FurniturePlacement in room.placements:
		if String(entry.furniture_id).contains("piano"):
			piano = entry
			break
	assert_that(piano).is_not_null()
	assert_that(piano.cell).is_equal(Vector2i(4, 4))
	assert_that(piano.facing).is_equal(WorldGrid.Facing.NORTH)
	var interior := Interior.new()
	interior.bind(room)
	var data: FurnitureData = interior.furniture_of(piano.furniture_id)
	assert_that(piano.resolved_footprint(data)).is_equal(Vector2i(2, 2))
	for cell: Vector2i in [Vector2i(4, 4), Vector2i(4, 5), Vector2i(5, 4), Vector2i(5, 5)]:
		assert_that(interior.grid.occupant_at(cell)).is_equal(piano.id)
	assert_that(interior.grid.occupant_at(Vector2i(3, 4))).is_not_equal(piano.id)
	assert_that(interior.grid.furniture_world(piano.cell, piano.resolved_footprint(data), piano.facing)).is_equal(
		interior.grid.cell_to_world(Vector2i(4, 4)) + Vector3(1.0, 0.0, 1.0)
	)


func test_style_page_from_wall_floor_labels() -> void:
	assert_int(GeneratedVisual._style_page("wall_15_0.png")).is_equal(0)
	assert_int(GeneratedVisual._style_page("player_room_wall_0_1")).is_equal(1)
	assert_int(GeneratedVisual._style_page("floor_03_2.png")).is_equal(2)
	assert_int(GeneratedVisual._style_page("room_wall room01")).is_equal(0)
	assert_int(GeneratedVisual._style_page("wall_15.png")).is_equal(0)


func test_room_trim_is_not_wallpaper() -> void:
	assert_that(GeneratedVisual._classify_room_surface("rom_myhome1_wall rom_myhome_window_tex")).is_equal(&"")
	assert_that(GeneratedVisual._classify_room_surface("rom_myhome2_wall rom_myhome_enter_tex")).is_equal(&"")
	assert_that(GeneratedVisual._classify_room_surface("rom_myhome1_wall player_room_wall_03_0")).is_equal(&"wall")
	assert_that(GeneratedVisual._classify_room_surface("rom_myhome1_floor player_room_floor_38_0")).is_equal(&"floor")
	## Museum / tailor shells bake wall and floor — do not treat as bank slots.
	assert_that(GeneratedVisual._classify_room_surface("rom_museum1 rom_museum1_floorA_tex")).is_equal(&"")
	assert_that(GeneratedVisual._classify_room_surface("rom_museum2 rom_museum2_wallA_tex")).is_equal(&"")
	assert_that(GeneratedVisual._classify_room_surface("rom_tailor rom_tailor_floorA_tex")).is_equal(&"")


func test_vertex_shade_material_multiplies_unshaded() -> void:
	## Museum / house walls: TEXEL0 × SHADE with G_LIGHTING off.
	var std := StandardMaterial3D.new()
	std.set_meta("extras", {"vertex_shade": true})
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	assert_bool(GeneratedVisual._is_vertex_shade_surface(mi, 0, std)).is_true()
	GeneratedVisual._apply_vertex_shade_material(std)
	assert_bool(std.vertex_color_use_as_albedo).is_true()
	assert_that(std.shading_mode).is_equal(BaseMaterial3D.SHADING_MODE_UNSHADED)
	mi.free()


func test_museum_uses_pipeline_shells() -> void:
	var entrance: Room = InteriorCatalog.room_template(&"museum_entrance")
	assert_bool(entrance.shell_ids.has("rom_museum1")).is_true()
	assert_that(entrance.wall_id).is_equal(&"")
	assert_that(entrance.floor_id).is_equal(&"")
	assert_that(entrance.inner_origin).is_equal(Vector2i(1, 3))
	assert_that(entrance.inner_size).is_equal(Vector2i(10, 8))
	var painting: Room = InteriorCatalog.room_template(&"museum_painting")
	assert_bool(painting.shell_ids.has("rom_museum3")).is_true()
	assert_that(painting.inner_size).is_equal(Vector2i(14, 12))
	var fossil: Room = InteriorCatalog.room_template(&"museum_fossil")
	assert_bool(fossil.shell_ids.has("rom_museum2")).is_true()
	var insect: Room = InteriorCatalog.room_template(&"museum_insect")
	assert_bool(insect.shell_ids.has("rom_museum4")).is_true()
	assert_bool(insect.shell_ids.has("rom_museum4_wall")).is_true()
	assert_bool(insect.shell_ids.has("rom_museum4_ue")).is_true()
	assert_that(insect.inner_size).is_equal(Vector2i(12, 14))
	var fish: Room = InteriorCatalog.room_template(&"museum_fish")
	assert_bool(fish.shell_ids.has("rom_museum5")).is_true()
	assert_bool(fish.shell_ids.has("rom_museum5_wall")).is_true()
	assert_that(fish.inner_size).is_equal(Vector2i(10, 14))


func test_floor_atlas_retile_mirrors_odd_cells() -> void:
	## GX_MIRROR corner tile: odd cells flip so 2×2 becomes one medallion, not 4 copies.
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.RED)
	img.set_pixel(1, 0, Color.GREEN)
	img.set_pixel(0, 1, Color.BLUE)
	img.set_pixel(1, 1, Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	var mirrored: Texture2D = GeneratedVisual._tile_to_atlas(tex, Vector2i(4, 4), true, true)
	var out: Image = mirrored.get_image()
	assert_that(out.get_pixel(0, 0)).is_equal(Color.RED)
	assert_that(out.get_pixel(1, 0)).is_equal(Color.GREEN)
	assert_that(out.get_pixel(2, 0)).is_equal(Color.GREEN) ## flip_x of row0
	assert_that(out.get_pixel(3, 0)).is_equal(Color.RED)
	assert_that(out.get_pixel(0, 2)).is_equal(Color.BLUE) ## flip_y of col0
	assert_that(out.get_pixel(0, 3)).is_equal(Color.RED)
	assert_that(out.get_pixel(3, 3)).is_equal(Color.RED) ## flip both


func test_indoor_grid_uses_world_grid() -> void:
	var room: Room = Game.interiors.room(&"player_main")
	var interior := Interior.new()
	interior.bind(room)
	var open: Vector2i = room.inner_origin + Vector2i(1, 1)
	assert_int(interior.grid.columns).is_equal(16)
	assert_int(interior.grid.rows).is_equal(16)
	assert_float(interior.grid.cell_size).is_equal(2.0)
	assert_that(interior.grid.terrain_at(open)).is_equal(WorldGrid.Terrain.STONE)
	assert_that(interior.grid.terrain_at(Vector2i(0, 0))).is_equal(WorldGrid.Terrain.BLOCKED)
	assert_that(interior.grid.occupant_at(open)).is_equal(&"")
	assert_that(interior.grid.occupant_at(room.inner_origin)).is_not_equal(&"")


func test_place_rotate_footprint_and_collision() -> void:
	var room: Room = Game.interiors.room(&"player_main")
	var interior := Interior.new()
	interior.bind(room)
	var table: FurnitureData = ItemCatalog.get_item(&"wood_table") as FurnitureData
	assert_that(table.footprint).is_equal(Vector2i(2, 1))
	var anchor: Vector2i = room.inner_origin + Vector2i(1, 1)
	var south: FurniturePlacement = interior.place(table, anchor, WorldGrid.Facing.SOUTH)
	assert_that(south).is_not_null()
	assert_that(interior.grid.occupant_at(anchor)).is_equal(south.id)
	assert_that(interior.grid.occupant_at(anchor + Vector2i(1, 0))).is_equal(south.id)
	assert_bool(interior.can_place(table, anchor, WorldGrid.Facing.EAST, south.id)).is_true()
	assert_bool(interior.rotate(south.id, 1)).is_true()
	assert_that(south.facing).is_equal(WorldGrid.Facing.EAST)
	assert_that(interior.grid.occupant_at(anchor)).is_equal(south.id)
	assert_that(interior.grid.occupant_at(anchor + Vector2i(0, -1))).is_equal(south.id)
	assert_that(interior.grid.occupant_at(anchor + Vector2i(1, 0))).is_equal(&"")
	var chair: FurnitureData = ItemCatalog.get_item(&"wood_chair") as FurnitureData
	assert_bool(interior.can_place(chair, anchor, WorldGrid.Facing.SOUTH)).is_false()
	assert_bool(interior.can_place(chair, Vector2i(room.door_cell.x, room.door_cell.y), WorldGrid.Facing.SOUTH)).is_false()
	assert_bool(interior.can_place(chair, Vector2i(0, 0), WorldGrid.Facing.SOUTH)).is_false()


func test_pick_up_and_decorate() -> void:
	var room: Room = Game.interiors.room(&"player_main")
	var interior := Interior.new()
	interior.bind(room)
	Game.current_room_id = &"player_main"
	Game.bind_interior(interior)
	var chair: FurnitureData = ItemCatalog.get_item(&"wood_chair") as FurnitureData
	var placed: FurniturePlacement = interior.place(chair, room.inner_origin + Vector2i(1, 1), WorldGrid.Facing.SOUTH)
	assert_that(placed).is_not_null()
	assert_that(interior.pick_up(placed.id)).is_equal(&"wood_chair")
	assert_int(room.placements.size()).is_equal(2)
	assert_bool(interior.decorate_wall(InteriorCatalog.WALL_BLUE)).is_true()
	assert_that(room.wall_id).is_equal(InteriorCatalog.WALL_BLUE)
	assert_bool(interior.decorate_floor(InteriorCatalog.FLOOR_TILE)).is_true()
	assert_bool(interior.decorate_wall(&"nope")).is_false()
	var npc: Room = Game.interiors.room(&"npc_0")
	var npc_int := Interior.new()
	npc_int.bind(npc)
	assert_bool(npc_int.decorate_wall(InteriorCatalog.WALL_BLUE)).is_false()


func test_shop_hours_gate_entry() -> void:
	Clock.apply_snapshot({"year": 2001, "month": 1, "day": 1, "hour": 23, "minute": 0})
	var shop: Room = InteriorCatalog.room_template(&"shop0")
	assert_bool(InteriorCatalog.is_open_now(shop)).is_false()
	Clock.apply_snapshot({"year": 2001, "month": 1, "day": 1, "hour": 12, "minute": 0})
	assert_bool(InteriorCatalog.is_open_now(shop)).is_true()
	var house: Room = InteriorCatalog.room_template(&"player_main")
	Clock.apply_snapshot({"year": 2001, "month": 1, "day": 1, "hour": 3, "minute": 0})
	assert_bool(InteriorCatalog.is_open_now(house)).is_true()


func test_enter_exit_restores_outdoor_pose() -> void:
	Game.player_position = Vector3(4.0, 0.1, -2.0)
	Game.player_yaw = 0.5
	assert_bool(Game.is_indoors()).is_false()
	assert_that(InteriorCatalog.resolve_entry(&"player_house")).is_equal(&"player_main")
	Game.current_room_id = &"player_main"
	Game.outdoor_return = Vector3(4.0, 0.1, -2.0)
	Game.outdoor_return_yaw = 0.5
	assert_bool(Game.is_indoors()).is_true()
	assert_bool(Game.is_decorating()).is_true()
	Game.current_room_id = &""
	Game.player_position = Game.outdoor_return
	Game.player_yaw = Game.outdoor_return_yaw
	assert_vector(Game.player_position).is_equal(Vector3(4.0, 0.1, -2.0))
	assert_float(Game.player_yaw).is_equal(0.5)


func test_indoor_exit_door_is_walk_warp_not_a_prompt() -> void:
	## `EXIT_DOOR` leaves on step; no Leave verb on the exit sensor.
	Game.current_room_id = &"player_main"
	var door: Node = auto_free(load("res://scenes/world/door.tscn").instantiate())
	door.set("exits_interior", true)
	assert_int(door.get_interactions(InteractionContext.new()).size()).is_equal(0)
	Game.current_room_id = &""
	assert_str(String(Interaction.primary(door.get_interactions(InteractionContext.new())).id)).is_equal(
		String(Interaction.ENTER)
	)


func test_museum_door_auto_enters_when_open() -> void:
	## `aMsm_check_player` has no A button — walk-in while open, silent prompt.
	Game.block_auto_enter_doors = false
	var door: Node = auto_free(load("res://scenes/world/door.tscn").instantiate())
	door.set("occupant_id", &"museum")
	door.set("auto_enter", true)
	door.set("label", "Museum")
	Clock.hour = 12
	assert_bool(door.call("should_auto_enter")).is_true()
	var open_actions: Array = door.get_interactions(InteractionContext.new())
	assert_int(open_actions.size()).is_equal(1)
	assert_str((open_actions[0] as Interaction).prompt).is_equal("")
	Clock.hour = 22
	assert_bool(door.call("should_auto_enter")).is_false()
	var closed: Array = door.get_interactions(InteractionContext.new())
	assert_str((closed[0] as Interaction).prompt).contains("Museum")
	Clock.hour = 12


func test_museum_wing_door_auto_enters_indoors() -> void:
	## Wing links walk in with INTO_S1 — no E prompt while indoors.
	Game.block_auto_enter_doors = false
	Game.current_room_id = &"museum_entrance"
	var door: Node = auto_free(load("res://scenes/world/door.tscn").instantiate())
	door.set("auto_enter", true)
	door.set("linked_room_id", &"museum_fish")
	door.set("label", "Fish")
	assert_bool(door.call("should_auto_enter")).is_true()
	var actions: Array = door.get_interactions(InteractionContext.new())
	assert_int(actions.size()).is_equal(1)
	assert_str((actions[0] as Interaction).prompt).is_equal("")
	Game.block_auto_enter_doors = true
	assert_bool(door.call("should_auto_enter")).is_false()
	Game.block_auto_enter_doors = false
	Game.current_room_id = &""


func test_museum_entrance_doors_match_decomp() -> void:
	## Entrance layout (`MUSEUM_ENTRANCE_door_data` + wing returns):
	##   N-west painting · N-east fossil · W insect · E fish · S outdoors
	assert_int(MuseumDisplay.ENTRANCE_WING_DOORS.size()).is_equal(4)
	var paint: Dictionary = MuseumDisplay.ENTRANCE_WING_DOORS[0]
	var fossil: Dictionary = MuseumDisplay.ENTRANCE_WING_DOORS[1]
	var insect: Dictionary = MuseumDisplay.ENTRANCE_WING_DOORS[2]
	var fish: Dictionary = MuseumDisplay.ENTRANCE_WING_DOORS[3]
	assert_that(paint["room"]).is_equal(&"museum_painting")
	assert_vector(paint["sensor"] as Vector3).is_equal(Vector3(160.0, 0.0, 80.0))
	assert_vector(paint["spawn"] as Vector3).is_equal(Vector3(280.0, 0.0, 480.0))
	assert_that(paint["facing"]).is_equal(WorldGrid.Facing.NORTH)
	assert_that(fossil["room"]).is_equal(&"museum_fossil")
	assert_vector(fossil["sensor"] as Vector3).is_equal(Vector3(320.0, 0.0, 80.0))
	assert_vector(fossil["spawn"] as Vector3).is_equal(Vector3(280.0, 0.0, 480.0))
	assert_that(fossil["facing"]).is_equal(WorldGrid.Facing.NORTH)
	assert_that(insect["room"]).is_equal(&"museum_insect")
	assert_vector(insect["sensor"] as Vector3).is_equal(Vector3(80.0, 0.0, 280.0))
	assert_vector(insect["spawn"] as Vector3).is_equal(Vector3(520.0, 0.0, 560.0))
	assert_that(insect["facing"]).is_equal(WorldGrid.Facing.WEST)
	assert_that(fish["room"]).is_equal(&"museum_fish")
	assert_vector(fish["spawn"] as Vector3).is_equal(Vector3(120.0, 0.0, 560.0))
	assert_that(fish["facing"]).is_equal(WorldGrid.Facing.EAST)
	## Return spawns sit one cell inside the matching entrance opening.
	assert_vector(MuseumDisplay.WING_EXIT_DOORS[&"museum_painting"]["spawn"] as Vector3).is_equal(
		Vector3(160.0, 0.0, 120.0)
	)
	assert_vector(MuseumDisplay.WING_EXIT_DOORS[&"museum_fossil"]["spawn"] as Vector3).is_equal(
		Vector3(320.0, 0.0, 120.0)
	)
	assert_vector(MuseumDisplay.WING_EXIT_DOORS[&"museum_insect"]["spawn"] as Vector3).is_equal(
		Vector3(120.0, 0.0, 280.0)
	)
	assert_vector(MuseumDisplay.WING_EXIT_DOORS[&"museum_fish"]["spawn"] as Vector3).is_equal(
		Vector3(360.0, 0.0, 280.0)
	)
	assert_that(MuseumDisplay.WING_EXIT_DOORS[&"museum_fish"]["facing"]).is_equal(
		WorldGrid.Facing.WEST
	)
	## Door exit yaw uses furniture angles so EAST faces +X (into the fish room).
	assert_float(
		WorldGrid.yaw_for_furniture(fish["facing"] as WorldGrid.Facing)
	).is_equal_approx(PI * 0.5, 0.0001)
	assert_vector(MuseumDisplay.ENTRANCE_SPAWN_GX).is_equal(Vector3(240.0, 0.0, 440.0))
	assert_vector(MuseumDisplay.ENTRANCE_EXIT_SENSOR_GX).is_equal(Vector3(240.0, 0.0, 500.0))
	assert_float(MuseumDisplay.ENTRANCE_EXIT_SENSOR_GX.x).is_equal_approx(
		MuseumDisplay.ENTRANCE_SPAWN_GX.x, 0.01
	)
	assert_float(MuseumDisplay.ENTRANCE_EXIT_SENSOR_GX.z).is_greater(MuseumDisplay.ENTRANCE_SPAWN_GX.z)


func test_museum_grid_keeps_acre_nw_at_origin() -> void:
	## Authored shells / door GX / exhibits share acre NW at world 0 — not centered.
	var room: Room = InteriorCatalog.room_template(&"museum_entrance")
	var session := Interior.new()
	session.bind(room)
	assert_vector(session.grid.origin).is_equal(Vector3.ZERO)
	assert_vector(MuseumDisplay.gx_to_world(session.grid, MuseumDisplay.ENTRANCE_SPAWN_GX)).is_equal(
		Vector3(12.0, 0.0, 22.0)
	)
	var home: Room = InteriorCatalog.room_template(&"player_main")
	var home_session := Interior.new()
	home_session.bind(home)
	assert_float(home_session.grid.origin.x).is_less(0.0)


func test_museum_entrance_exit_sensor_matches_enter_x() -> void:
	var room: Room = InteriorCatalog.room_template(&"museum_entrance")
	var session := Interior.new()
	session.bind(room)
	var root := Node3D.new()
	auto_free(root)
	add_child(root)
	InteriorBuilder.new().build(root, session)
	var exit_door: Node3D = root.get_node_or_null("Doors/Exit") as Node3D
	assert_that(exit_door).is_not_null()
	var expected: Vector3 = MuseumDisplay.gx_to_world(session.grid, MuseumDisplay.ENTRANCE_EXIT_SENSOR_GX)
	assert_float(exit_door.position.x).is_equal_approx(expected.x, 0.05)
	assert_float(exit_door.position.z).is_equal_approx(expected.z, 0.05)
	## Not the generic room-center south cell (would be ~340 GX / cell 8).
	var wrong: Vector3 = session.grid.cell_to_world(room.door_cell)
	assert_float(absf(exit_door.position.x - wrong.x)).is_greater(0.5)


func test_door_cell_is_south_of_spawn() -> void:
	## Spawn sits one cell inside so walking onto the door does not fire on enter.
	var room: Room = InteriorCatalog.room_template(&"player_main")
	assert_that(room).is_not_null()
	assert_int(room.door_cell.x).is_equal(room.spawn_cell.x)
	assert_int(room.door_cell.y).is_equal(room.spawn_cell.y + 1)


func test_indoor_exit_walks_further_south() -> void:
	## INTO_S1 target is south of the door cell (+Z), facing SOUTH yaw 0.
	assert_float(StructureDoor.INTO_GX).is_greater(0.0)
	assert_float(WorldGrid.yaw_for_facing(WorldGrid.Facing.SOUTH)).is_equal_approx(0.0, 0.01)
	var door_pos := Vector3(4.0, 0.1, 8.0)
	var target: Vector3 = door_pos + Vector3(0.0, 0.0, StructureDoor.INTO_GX * FieldCatalog.GX_TO_METERS)
	assert_float(target.z).is_greater(door_pos.z)


func test_save_round_trip_placements_and_decoration() -> void:
	var room: Room = Game.interiors.room(&"player_main")
	var interior := Interior.new()
	interior.bind(room)
	interior.decorate_wall(InteriorCatalog.WALL_BLUE)
	var table: FurnitureData = ItemCatalog.get_item(&"wood_table") as FurnitureData
	var table_cell: Vector2i = room.inner_origin + Vector2i(1, 1)
	var placed: FurniturePlacement = interior.place(table, table_cell, WorldGrid.Facing.EAST)
	assert_that(placed).is_not_null()
	Game.current_room_id = &"player_main"
	Game.outdoor_return = Vector3(1.0, 0.1, 2.0)
	var snap: Dictionary = Game.to_save()
	Game.reset_session()
	assert_that(Game.current_room_id).is_equal(&"")
	Game.apply_snapshot(snap)
	assert_that(Game.current_room_id).is_equal(&"player_main")
	assert_vector(Game.outdoor_return).is_equal(Vector3(1.0, 0.1, 2.0))
	var loaded: Room = Game.interiors.room(&"player_main")
	assert_that(loaded.wall_id).is_equal(InteriorCatalog.WALL_BLUE)
	assert_int(loaded.placements.size()).is_equal(3)
	var found := false
	for entry: FurniturePlacement in loaded.placements:
		if entry.furniture_id == &"wood_table":
			found = true
			assert_that(entry.cell).is_equal(table_cell)
			assert_that(entry.facing).is_equal(WorldGrid.Facing.EAST)
	assert_bool(found).is_true()


func test_player_main_collision_matches_small_shell() -> void:
	var room: Room = InteriorCatalog.room_template(&"player_main")
	var session := Interior.new()
	session.bind(room)
	var shell: AABB = InteriorBuilder.new()._shell_bounds(room, session.grid)
	assert_float(shell.size.x).is_equal_approx(8.0, 0.001)
	assert_float(shell.size.z).is_equal_approx(8.0, 0.001)


func test_player_old_6x6_placements_shift_into_small_room() -> void:
	var room: Room = Game.interiors.room(&"player_main")
	var crate := FurniturePlacement.new()
	crate.id = &"ftr_1"
	crate.furniture_id = &"int_nog_mikanbox"
	crate.cell = Vector2i(5, 5)
	var tape := FurniturePlacement.new()
	tape.id = &"ftr_2"
	tape.furniture_id = &"int_sum_casse01"
	tape.cell = Vector2i(8, 5)
	room.placements = [crate, tape]
	var snap: Dictionary = Game.to_save()
	Game.reset_session()
	Game.apply_snapshot(snap)
	var loaded: Room = Game.interiors.room(&"player_main")
	var cells := {}
	for entry: FurniturePlacement in loaded.placements:
		cells[String(entry.furniture_id)] = entry.cell
	assert_that(cells.get("int_nog_mikanbox")).is_equal(InteriorCatalog.PLAYER_INNER_ORIGIN)
	assert_that(cells.get("int_sum_casse01")).is_equal(
		InteriorCatalog.PLAYER_INNER_ORIGIN + Vector2i(3, 0)
	)


func test_museum_wings_link_back_to_entrance() -> void:
	var entrance: Room = InteriorCatalog.room_template(&"museum_entrance")
	assert_int(entrance.linked_rooms.size()).is_equal(4)
	var painting: Room = InteriorCatalog.room_template(&"museum_painting")
	assert_that(painting.parent_room_id).is_equal(&"museum_entrance")


func test_builder_attaches_room_shell_when_converted() -> void:
	if FieldCatalog.mesh_paths(&"rom_myhome2_floor").is_empty():
		return
	var room: Room = Game.interiors.room(&"npc_filbert")
	var session := Interior.new()
	session.bind(room)
	var root := Node3D.new()
	auto_free(root)
	add_child(root)
	InteriorBuilder.new().build(root, session)
	var shell: Node = root.get_node_or_null("Terrain/GeneratedVisual")
	assert_that(shell).is_not_null()
	assert_that(room.wall_id).is_equal(VillagerCatalog.get_villager(&"filbert").wall_style_id())
	var meshes := 0
	for child: Node in shell.get_children():
		meshes += _count_mesh_instances(child)
	assert_int(meshes).is_greater(0)
	## Acre scale (no wall-AABB squash). Floor verts start one cell in; mapping
	## that min-corner onto the walkable rect puts the pivot on the field origin.
	assert_float((shell as Node3D).scale.x).is_equal_approx(FieldCatalog.acre_uniform_scale(), 0.001)
	var inner_nw: Vector3 = session.grid.cell_corner(room.inner_origin)
	assert_float((shell as Node3D).position.x).is_equal_approx(inner_nw.x - session.grid.cell_size, 0.2)
	assert_float((shell as Node3D).position.z).is_equal_approx(inner_nw.z - session.grid.cell_size, 0.2)
	var bodies := 0
	for child: Node in root.get_node("Terrain").get_children():
		if child is StaticBody3D:
			bodies += 1
	assert_int(bodies).is_less(8)


func test_npc_typec_footprint_on_placement() -> void:
	if not FileAccess.file_exists(InteriorCatalog.NPC_ROOMS_PATH):
		return
	var teddy: Room = InteriorCatalog.room_template(&"npc_teddy")
	assert_that(teddy).is_not_null()
	var piano: FurniturePlacement = null
	for entry: FurniturePlacement in teddy.placements:
		if String(entry.furniture_id).contains("piano"):
			piano = entry
			break
	assert_that(piano).is_not_null()
	assert_that(piano.footprint).is_equal(Vector2i(2, 2))


func _count_mesh_instances(node: Node) -> int:
	var n := 1 if node is MeshInstance3D else 0
	for child: Node in node.get_children():
		n += _count_mesh_instances(child)
	return n


func test_player_placeholder_save_upgrades_to_banks() -> void:
	var room: Room = Game.interiors.room(&"player_main")
	room.wall_id = InteriorCatalog.WALL_CREAM
	room.floor_id = InteriorCatalog.FLOOR_WOOD
	var chair := FurniturePlacement.new()
	chair.id = &"ftr_1"
	chair.furniture_id = &"wood_chair"
	chair.cell = Vector2i(6, 7)
	room.placements = [chair]
	var snap: Dictionary = Game.to_save()
	Game.reset_session()
	Game.apply_snapshot(snap)
	var loaded: Room = Game.interiors.room(&"player_main")
	assert_that(loaded.wall_id).is_equal(InteriorCatalog.wall_style_id(InteriorCatalog.PLAYER_START_WALL))
	assert_that(loaded.floor_id).is_equal(InteriorCatalog.floor_style_id(InteriorCatalog.PLAYER_START_FLOOR))
	assert_int(loaded.placements.size()).is_equal(2)
	var ids: PackedStringArray = PackedStringArray()
	for entry: FurniturePlacement in loaded.placements:
		ids.append(String(entry.furniture_id))
	assert_bool(ids.has("wood_chair")).is_false()
	assert_bool(ids.has("int_nog_mikanbox")).is_true()


func test_reset_clears_interior_book() -> void:
	Game.interiors.room(&"player_main").wall_id = InteriorCatalog.WALL_BLUE
	Game.current_room_id = &"player_main"
	Game.reset_session()
	assert_that(Game.current_room_id).is_equal(&"")
	assert_that(Game.interiors.room(&"player_main").wall_id).is_equal(
		InteriorCatalog.wall_style_id(InteriorCatalog.PLAYER_START_WALL)
	)
