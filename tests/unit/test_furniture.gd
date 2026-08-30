class_name TestFurniture
extends GdUnitTestSuite


func before_test() -> void:
	Clock.reset_to_default()
	Clock.paused = true
	Game.reset_session()
	InteriorCatalog.reset()
	ItemCatalog.reload()


func after_test() -> void:
	Game.reset_session()
	InteriorCatalog.reset()
	Clock.reset_to_default()
	Clock.paused = false


func test_authored_catalog_fields() -> void:
	var chair: FurnitureData = ItemCatalog.get_item(&"wood_chair") as FurnitureData
	assert_that(chair.visual_id).is_equal(&"int_sum_chair01")
	assert_that(chair.kind).is_equal(FurnitureData.Kind.CHAIR)
	assert_that(chair.contact).is_equal(FurnitureData.Contact.CHAIR_FRONT)
	assert_that(chair.placement).is_equal(FurnitureData.Placement.FLOOR)
	assert_bool(chair.is_sittable()).is_true()
	assert_bool(chair.can_rotate).is_true()
	var table: FurnitureData = ItemCatalog.get_item(&"wood_table") as FurnitureData
	assert_that(table.kind).is_equal(FurnitureData.Kind.TABLE)
	assert_that(table.placement).is_equal(FurnitureData.Placement.TABLE)
	assert_that(table.shape).is_equal(FurnitureData.Shape.TYPE_B)
	assert_bool(table.allows_on_top()).is_true()
	var dresser: FurnitureData = ItemCatalog.get_item(&"wood_dresser") as FurnitureData
	assert_bool(dresser.has_storage()).is_true()
	assert_int(dresser.keep_count()).is_equal(3)
	var tv: FurnitureData = ItemCatalog.get_item(&"wood_tv") as FurnitureData
	assert_bool(tv.is_toggleable()).is_true()
	assert_bool(tv.starts_off).is_true()


func test_visual_stub_infers_kind() -> void:
	var sofa: FurnitureData = ItemCatalog.furniture_for_visual(&"int_sum_sofa01")
	assert_that(sofa.kind).is_equal(FurnitureData.Kind.SOFA)
	assert_bool(sofa.is_sittable()).is_true()
	var chest: FurnitureData = ItemCatalog.furniture_for_visual(&"int_sum_classicchest01")
	assert_that(chest.kind).is_equal(FurnitureData.Kind.STORAGE)
	assert_bool(chest.has_storage()).is_true()
	var bed: FurnitureData = ItemCatalog.furniture_for_visual(&"int_sum_bed01")
	assert_bool(bed.is_bed()).is_true()


func test_wall_and_surface_placement() -> void:
	var room: Room = Game.interiors.room(&"player_main")
	var interior := Interior.new()
	interior.bind(room)
	var picture: FurnitureData = ItemCatalog.furniture_for_visual(&"int_ike_art_ang")
	picture.placement = FurnitureData.Placement.WALL
	var north_wall: Vector2i = room.inner_origin + Vector2i(1, 0)
	var inner: Vector2i = room.inner_origin + Vector2i(1, 1)
	assert_bool(interior.can_place(picture, north_wall, WorldGrid.Facing.NORTH)).is_true()
	assert_bool(interior.can_place(picture, inner, WorldGrid.Facing.NORTH)).is_false()
	var table: FurnitureData = ItemCatalog.get_item(&"wood_table") as FurnitureData
	var placed: FurniturePlacement = interior.place(table, inner, WorldGrid.Facing.SOUTH)
	assert_that(placed).is_not_null()
	var mini: FurnitureData = ItemCatalog.furniture_for_visual(&"int_test_mini")
	mini.placement = FurnitureData.Placement.SMALL
	assert_bool(interior.can_place(mini, inner, WorldGrid.Facing.SOUTH)).is_true()
	var stacked: FurniturePlacement = interior.place(mini, inner, WorldGrid.Facing.SOUTH)
	assert_that(stacked).is_not_null()
	assert_int(stacked.layer).is_equal(1)
	assert_that(interior.grid.occupant_at(inner)).is_equal(placed.id)
	var chair: FurnitureData = ItemCatalog.get_item(&"wood_chair") as FurnitureData
	assert_bool(interior.can_place(chair, inner, WorldGrid.Facing.SOUTH)).is_false()


func test_storage_toggle_display_and_save() -> void:
	var room: Room = Game.interiors.room(&"player_main")
	var interior := Interior.new()
	interior.bind(room)
	Game.current_room_id = &"player_main"
	Game.bind_interior(interior)
	var dresser: FurnitureData = ItemCatalog.get_item(&"wood_dresser") as FurnitureData
	var drawer: FurniturePlacement = interior.place(dresser, room.inner_origin + Vector2i(1, 1), WorldGrid.Facing.SOUTH)
	assert_that(drawer).is_not_null()
	var apple: ItemData = ItemCatalog.get_item(&"apple")
	Game.inventory.add(apple, 1)
	Game.inventory.select(Game.inventory.count_of_occupied() - 1)
	var ctx := InteractionContext.new()
	ctx.inventory = Game.inventory
	assert_bool(FurnitureUse.open_storage(drawer.id, ctx)).is_true()
	assert_int(drawer.stored.size()).is_equal(1)
	assert_int(Game.inventory.count_of(&"apple")).is_equal(0)
	assert_bool(FurnitureUse.open_storage(drawer.id, ctx)).is_true()
	assert_int(Game.inventory.count_of(&"apple")).is_equal(1)
	var tv: FurnitureData = ItemCatalog.get_item(&"wood_tv") as FurnitureData
	var set: FurniturePlacement = interior.place(tv, room.inner_origin + Vector2i(2, 1), WorldGrid.Facing.SOUTH)
	assert_bool(set.on).is_false()
	assert_bool(FurnitureUse.toggle(set.id)).is_true()
	assert_bool(set.on).is_true()
	var case: FurnitureData = ItemCatalog.furniture_for_visual(&"int_ike_fish_tro2")
	var tank: FurniturePlacement = interior.place(case, room.inner_origin + Vector2i(1, 2), WorldGrid.Facing.SOUTH)
	var fish := ItemData.new()
	fish.id = &"test_fish"
	fish.display_name = "Fish"
	fish.category = ItemData.Category.FISH
	ItemCatalog.remember(fish)
	Game.inventory.add(fish, 1)
	for i: int in Inventory.POCKET_SLOTS:
		var slot: InventorySlot = Game.inventory.slot_at(i)
		if slot != null and not slot.is_empty() and slot.item.item_id == fish.id:
			Game.inventory.select(i)
			break
	assert_bool(case.accepts_display(fish)).is_true()
	assert_bool(FurnitureUse.put_display(tank.id, ctx)).is_true()
	assert_that(tank.display_id).is_equal(fish.id)
	var snap: Dictionary = drawer.to_save()
	assert_bool(snap.has("st")).is_false()
	drawer.stored.append("apple")
	var loaded: FurniturePlacement = FurniturePlacement.from_save(drawer.to_save())
	assert_int(loaded.stored.size()).is_equal(1)


func test_wallpaper_and_carpet_from_inventory() -> void:
	var room: Room = Game.interiors.room(&"player_main")
	var interior := Interior.new()
	interior.bind(room)
	Game.current_room_id = &"player_main"
	Game.bind_interior(interior)
	var wall: ItemData = ItemCatalog.get_item(&"wall_blue")
	assert_that(wall.category).is_equal(ItemData.Category.WALL)
	Game.inventory.add(wall, 1)
	assert_bool(Game.try_apply_cover(wall)).is_true()
	assert_that(room.wall_id).is_equal(InteriorCatalog.WALL_BLUE)
	var floor: ItemData = ItemCatalog.get_item(&"floor_tile")
	Game.inventory.add(floor, 1)
	assert_bool(Game.try_apply_cover(floor)).is_true()
	assert_that(room.floor_id).is_equal(InteriorCatalog.FLOOR_TILE)


func test_chair_scene_still_offers_sit() -> void:
	var node: Node = auto_free(load("res://scenes/world/furniture.tscn").instantiate())
	add_child(node)
	var ctx := InteractionContext.new()
	ctx.inventory = Inventory.new()
	var action: Interaction = Interaction.primary(node.get_interactions(ctx))
	assert_str(String(action.id)).is_equal(String(Interaction.SIT))


func test_decorating_picks_up_before_sit() -> void:
	Game.current_room_id = &"player_main"
	var node: Node = auto_free(load("res://scenes/world/furniture.tscn").instantiate())
	add_child(node)
	var ctx := InteractionContext.new()
	ctx.inventory = Game.inventory
	var action: Interaction = Interaction.primary(node.get_interactions(ctx))
	assert_str(String(action.id)).is_equal(String(Interaction.PICK_UP))
