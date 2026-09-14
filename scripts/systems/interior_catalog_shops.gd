class_name InteriorCatalogShops
extends RefCounted

## Nook's shop tiers + Crazy Redd's tent room templates.


static func register() -> void:
	## Floor/wall: `aSI_wall/floor_default_table` → ETC bank `WALL_SHOP*` / `FLOOR_SHOP*`.
	## Shells bake style-0 placeholders; runtime paints the shop bank indices.
	var shop0 := InteriorCatalog.make_public_room(
		&"shop0",
		Room.Kind.SHOP,
		"Nook's Cranny",
		ShopDisplay.CRANNY_INNER_ORIGIN,
		ShopDisplay.CRANNY_INNER_SIZE,
		9,
		22
	)
	shop0.wall_id = ShopDisplay.nook_wall_id(0)
	shop0.floor_id = ShopDisplay.nook_floor_id(0)
	shop0.door_cell = ShopDisplay.CRANNY_DOOR_CELL
	shop0.spawn_cell = ShopDisplay.CRANNY_SPAWN_CELL
	shop0.shell_ids = PackedStringArray(["rom_shop1f", "rom_shop1w"])
	InteriorCatalog.put_room(shop0)
	var shop1 := InteriorCatalog.make_public_room(
		&"shop1", Room.Kind.SHOP, "Nook 'n' Go", Vector2i(3, 3), Vector2i(10, 10), 7, 23
	)
	shop1.wall_id = ShopDisplay.nook_wall_id(1)
	shop1.floor_id = ShopDisplay.nook_floor_id(1)
	shop1.shell_ids = PackedStringArray(["rom_shop2f", "rom_shop2w"])
	InteriorCatalog.put_room(shop1)
	var shop2 := InteriorCatalog.make_public_room(
		&"shop2", Room.Kind.SHOP, "Nookway", Vector2i(3, 3), Vector2i(10, 10), 9, 22
	)
	shop2.wall_id = ShopDisplay.nook_wall_id(2)
	shop2.floor_id = ShopDisplay.nook_floor_id(2)
	shop2.shell_ids = PackedStringArray(["rom_shop3f", "rom_shop3w"])
	InteriorCatalog.put_room(shop2)
	var shop3_1 := InteriorCatalog.make_public_room(
		&"shop3_1", Room.Kind.SHOP, "Nookington's", Vector2i(3, 3), Vector2i(10, 10), 9, 22
	)
	shop3_1.wall_id = ShopDisplay.nook_wall_id(3)
	shop3_1.floor_id = ShopDisplay.nook_floor_id(3)
	shop3_1.linked_rooms = [&"shop3_2"]
	shop3_1.shell_ids = PackedStringArray(["rom_shop4_1"])
	InteriorCatalog.put_room(shop3_1)
	var shop3_2 := InteriorCatalog.make_public_room(
		&"shop3_2", Room.Kind.SHOP, "Nookington's Annex", Vector2i(3, 3), Vector2i(10, 10), 9, 22
	)
	shop3_2.wall_id = &"wall_70"
	shop3_2.floor_id = &"floor_70"
	shop3_2.parent_room_id = &"shop3_1"
	shop3_2.shell_ids = PackedStringArray(["rom_shop4_2f", "rom_shop4_2w"])
	InteriorCatalog.put_room(shop3_2)
	## Broker is event-gated outdoors, not clock hours (`aBRS_open_check`).
	var broker := InteriorCatalog.make_room(
		&"broker_shop", Room.Kind.BROKER, "Redd's Tent", Vector2i(5, 5), Vector2i(6, 6), {}
	)
	broker.wall_id = &""
	broker.floor_id = &""
	broker.shell_ids = PackedStringArray(["rom_tent"])
	InteriorCatalog.put_room(broker)
	InteriorCatalog.put_house(&"shop", &"", &"acre_shop", [&"shop0"])
	InteriorCatalog.put_house(&"broker_shop", &"", &"broker_shop", [&"broker_shop"])
	InteriorCatalog.bind_building(&"broker_shop", &"broker_shop")
