class_name InteriorCatalogPublic
extends RefCounted

## Post office / police / dump / snow cabin / Able Sisters / lighthouse /
## tent / cottage room templates.


static func register() -> void:
	## Post / police: always enterable; hour checks in decomp are lights only.
	var post := InteriorCatalog.make_room(
		&"post_office",
		Room.Kind.POST_OFFICE,
		"Post Office",
		PostDisplay.INNER_ORIGIN,
		PostDisplay.INNER_SIZE,
		{}
	)
	post.wall_id = &""
	post.floor_id = &""
	post.door_cell = PostDisplay.DOOR_CELL
	post.spawn_cell = PostDisplay.SPAWN_CELL
	post.shell_ids = PackedStringArray([String(PostDisplay.SHELL_ID)])
	InteriorCatalog.put_room(post)
	var police := InteriorCatalog.make_room(
		&"police_box",
		Room.Kind.POLICE,
		"Police Station",
		PoliceDisplay.INNER_ORIGIN,
		PoliceDisplay.INNER_SIZE,
		{}
	)
	police.wall_id = &""
	police.floor_id = &""
	police.door_cell = PoliceDisplay.DOOR_CELL
	police.spawn_cell = PoliceDisplay.SPAWN_CELL
	police.shell_ids = PackedStringArray([String(PoliceDisplay.SHELL_ID)])
	InteriorCatalog.put_room(police)
	InteriorCatalog.put_room(
		InteriorCatalog.make_room(
			&"buggy", Room.Kind.DUMP, "Dump", Vector2i(4, 4), Vector2i(8, 8),
			{"floor": InteriorStyleCatalog.FLOOR_STONE}
		)
	)
	var snow := InteriorCatalog.make_room(
		&"kamakura", Room.Kind.KAMAKURA, "Snow Cabin", Vector2i(5, 5), Vector2i(6, 6), {}
	)
	snow.wall_id = &""
	snow.floor_id = &""
	snow.shell_ids = PackedStringArray(["rom_kamakura"])
	InteriorCatalog.put_room(snow)
	## Able: closed 02:00–07:00 (`aNW_check_opend`); open 7→2 wraps past midnight.
	## `rom_tailor` keeps the acre origin. `rom_tailor.col.json`: the walkable room is
	## FG cells x∈[1,9) z∈[1,7) (matches the shell floor, world x[-14,2] z[-14,-2]),
	## with a door porch at cells (4-5, 7-8) — the `rom_tailor_ent` mat, world
	## x[-8,-4] z[-2,0]. `ac_needlework_indoor.c` GX (mannequins z=100, stands z=180)
	## maps straight through `gx_to_world`.
	var needle := InteriorCatalog.make_public_room(
		&"needlework", Room.Kind.NEEDLEWORK, "Able Sisters", Vector2i(1, 1), Vector2i(8, 6), 7, 2
	)
	needle.wall_id = &""
	needle.floor_id = &""
	needle.shell_ids = PackedStringArray(["rom_tailor"])
	## Exit at the door: `rom_tailor.col.json` porch cells (4-5, 7-8). The player
	## spawns here too (`ABLE_SPAWN_GX` → cell (4,7)) and walks north into the shop.
	needle.door_cell = Vector2i(4, 7)
	needle.spawn_cell = Vector2i(4, 6)
	## The table / sewing machine / register / boxes are baked into the shell.
	InteriorCatalog.put_room(needle)
	## `rom_toudai` (decomp `rom_toudai.c`): baked interior shell, now that it's converted.
	## Door/spawn cells aren't overridden — `InteriorBuilder` derives them from the shell's
	## own collision gaps (`rom_toudai.col.json`), same as `tent`/`kamakura` below.
	var lighthouse := InteriorCatalog.make_room(
		&"lighthouse", Room.Kind.LIGHTHOUSE, "Lighthouse", Vector2i(6, 6), Vector2i(4, 4), {}
	)
	lighthouse.wall_id = &""
	lighthouse.floor_id = &""
	lighthouse.shell_ids = PackedStringArray(["rom_toudai"])
	InteriorCatalog.put_room(lighthouse)
	var tent := InteriorCatalog.make_room(&"tent", Room.Kind.TENT, "Tent", Vector2i(5, 5), Vector2i(6, 6), {})
	tent.wall_id = &""
	tent.floor_id = &""
	tent.shell_ids = PackedStringArray(["rom_tent"])
	InteriorCatalog.put_room(tent)
	InteriorCatalog.put_room(
		InteriorCatalog.make_room(&"cottage", Room.Kind.COTTAGE, "Cottage", Vector2i(5, 5), Vector2i(6, 6), {})
	)
	InteriorCatalog.put_house(&"post_office", &"", &"post_office", [&"post_office"])
	InteriorCatalog.put_house(&"police_box", &"", &"police", [&"police_box"])
	InteriorCatalog.put_house(&"dump", &"", &"buggy", [&"buggy"])
	InteriorCatalog.put_house(&"kamakura", &"", &"kamakura", [&"kamakura"])
	InteriorCatalog.put_house(&"needlework", &"", &"able_sisters", [&"needlework"])
	InteriorCatalog.put_house(&"lighthouse", &"", &"lighthouse", [&"lighthouse"])
	InteriorCatalog.put_house(&"tent", &"", &"tent", [&"tent"])
	InteriorCatalog.put_house(&"cottage", &"", &"cottage", [&"cottage"])
	InteriorCatalog.bind_building(&"buggy", &"dump")
	InteriorCatalog.bind_building(&"kamakura", &"kamakura")
	InteriorCatalog.bind_building(&"lighthouse", &"lighthouse")
	InteriorCatalog.bind_building(&"tent", &"tent")
