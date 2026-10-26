class_name InteriorCatalogMuseum
extends RefCounted

## Museum entrance + wing room templates.


static func register() -> void:
	## Pipeline shells keep baked TEX_EDGE textures — no wallpaper/carpet bank.
	## Inner sizes match floor prims at acre scale (`rom_museum*_floor*`).
	## Floor prim AABB at acre scale: X cells 1–11, Z cells 3–11 → (1,3)+(10,8).
	## Old (3,3)+(10,10) plus the one-cell wall inset put west collision too far in
	## and left a gap past the east visual wall.
	## Always open — `aMsm_ctrl_light` is lights only (6–18), not an entry gate.
	var entrance := InteriorCatalog.make_room(
		&"museum_entrance", Room.Kind.MUSEUM, "Museum", Vector2i(1, 3), Vector2i(10, 8), {}
	)
	entrance.linked_rooms = [
		&"museum_painting", &"museum_fossil", &"museum_insect", &"museum_fish"
	]
	entrance.wall_id = &""
	entrance.floor_id = &""
	entrance.shell_ids = PackedStringArray(["rom_museum1"])
	InteriorCatalog.put_room(entrance)
	var wing_sizes := {
		&"museum_painting": Vector2i(14, 12),
		&"museum_fossil": Vector2i(14, 12),
		&"museum_insect": Vector2i(12, 14),
		&"museum_fish": Vector2i(10, 14),
	}
	## Floor prims sit one cell in from acre NW (not vertically centered).
	## Painting/fossil floor z ends at 26 m (cell 13); insect/fish extend to acre SE.
	var wing_origins := {
		&"museum_painting": Vector2i(1, 1),
		&"museum_fossil": Vector2i(1, 1),
		&"museum_insect": Vector2i(1, 1),
		&"museum_fish": Vector2i(3, 1),
	}
	var wing_shells := {
		&"museum_painting": PackedStringArray(["rom_museum3"]),
		&"museum_fossil": PackedStringArray(["rom_museum2"]),
		&"museum_insect": PackedStringArray(["rom_museum4", "rom_museum4_wall", "rom_museum4_ue"]),
		&"museum_fish": PackedStringArray(["rom_museum5", "rom_museum5_wall"]),
	}
	for wing: StringName in entrance.linked_rooms:
		var label := String(wing).replace("museum_", "").capitalize()
		var inner: Vector2i = wing_sizes.get(wing, Vector2i(10, 10)) as Vector2i
		var origin: Vector2i = wing_origins.get(wing, Vector2i.ZERO) as Vector2i
		var room := InteriorCatalog.make_room(wing, Room.Kind.MUSEUM, "%s Wing" % label, origin, inner, {})
		room.parent_room_id = &"museum_entrance"
		room.wall_id = &""
		room.floor_id = &""
		if wing_shells.has(wing):
			room.shell_ids = wing_shells[wing]
		InteriorCatalog.put_room(room)
	InteriorCatalog.put_house(
		&"museum",
		&"",
		&"museum",
		[
			&"museum_entrance",
			&"museum_painting",
			&"museum_fossil",
			&"museum_insect",
			&"museum_fish",
		]
	)
