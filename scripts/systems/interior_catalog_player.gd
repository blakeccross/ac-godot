class_name InteriorCatalogPlayer
extends RefCounted

## Player house room templates (`InteriorCatalog._register_all`).


static func register() -> void:
	var main := InteriorCatalog.make_room(
		&"player_main",
		Room.Kind.PLAYER,
		"Living Room",
		InteriorCatalog.PLAYER_INNER_ORIGIN,
		InteriorCatalog.PLAYER_INNER_SIZE,
		{
			"decorate": true,
			"wall": InteriorStyleCatalog.wall_style_id(InteriorCatalog.PLAYER_START_WALL),
			"floor": InteriorStyleCatalog.floor_style_id(InteriorCatalog.PLAYER_START_FLOOR),
			"shells": PackedStringArray(["rom_myhome1_floor", "rom_myhome1_wall"]),
		}
	)
	_apply_small_door(main)
	InteriorCatalog.fill_player_starter(main)
	InteriorCatalog.put_room(main)
	InteriorCatalog.put_room(
		InteriorCatalog.make_room(
			&"player_upper",
			Room.Kind.PLAYER,
			"Upstairs",
			Vector2i(5, 5),
			Vector2i(6, 6),
			{
				"decorate": true,
				"wall": InteriorStyleCatalog.wall_style_id(InteriorCatalog.PLAYER_START_WALL),
				"floor": InteriorStyleCatalog.floor_style_id(InteriorCatalog.PLAYER_START_FLOOR),
				"parent": &"player_main",
				"shells": PackedStringArray(["rom_myhome2_floor", "rom_myhome2_wall"]),
			}
		)
	)
	InteriorCatalog.put_room(
		InteriorCatalog.make_room(
			&"player_basement",
			Room.Kind.PLAYER,
			"Basement",
			Vector2i(4, 4),
			Vector2i(8, 8),
			{
				"decorate": true,
				"wall": InteriorStyleCatalog.WALL_DEFAULT,
				"floor": InteriorStyleCatalog.FLOOR_STONE,
				"parent": &"player_main",
				"shells": PackedStringArray(["rom_myhome_ug"]),
			}
		)
	)
	InteriorCatalog.put_house(
		InteriorCatalog.PLAYER_HOUSE_ID, &"player", &"player_house", [&"player_main"]
	)


static func _apply_small_door(room: Room) -> void:
	## `l_proom_s_tmp` EXIT at (2,7)/(3,7); enter `{120,0,220}` facing north.
	if room == null:
		return
	room.door_cell = InteriorCatalog.PLAYER_SMALL_DOOR_CELL
	room.spawn_cell = InteriorCatalog.PLAYER_SMALL_SPAWN_CELL
