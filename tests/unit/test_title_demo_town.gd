class_name TestTitleDemoTown
extends GdUnitTestSuite

## `WorldGenerator.generate(seed, true)`: the attract-mode town. Needs the FG catalog and
## `demos.json` (`--kind title`); without them the town falls back to its normal templates,
## which the first test checks.


func _demo_ready() -> bool:
	return FgCatalog.has_catalog() and TitleDemo.has_data()


func _npc_houses(data: WorldData) -> Array[BuildingPlacement]:
	var out: Array[BuildingPlacement] = []
	for b: BuildingPlacement in data.buildings:
		if b != null and String(b.id).begins_with("npc_house_"):
			out.append(b)
	return out


func test_normal_town_is_unchanged_by_the_flag_default() -> void:
	var plain: WorldData = WorldGenerator.generate(WorldGenerator.DEFAULT_SEED)
	var explicit: WorldData = WorldGenerator.generate(WorldGenerator.DEFAULT_SEED, false)
	assert_str(plain.fingerprint()).is_equal(explicit.fingerprint())
	if FgCatalog.has_catalog():
		assert_int(_npc_houses(plain).size()).is_equal(WorldGenerator.STARTER_NPC_HOUSES)


func test_demo_town_is_deterministic_and_differs_from_the_normal_one() -> void:
	if not _demo_ready():
		return
	var a: WorldData = WorldGenerator.generate(WorldGenerator.DEFAULT_SEED, true)
	var b: WorldData = WorldGenerator.generate(WorldGenerator.DEFAULT_SEED, true)
	assert_str(a.fingerprint()).is_equal(b.fingerprint())
	assert_str(a.fingerprint()).is_not_equal(
		WorldGenerator.generate(WorldGenerator.DEFAULT_SEED).fingerprint()
	)


func test_demo_villagers_are_the_fixed_fourteen_each_with_a_home() -> void:
	if not _demo_ready():
		return
	var data: WorldData = WorldGenerator.generate(WorldGenerator.DEFAULT_SEED, true)
	var houses: Array[BuildingPlacement] = _npc_houses(data)
	## On the fixed map every villager with a marker gets a home: 13 of 14 (Lobo has no
	## `0x50xx` marker in `l_title_demo_fg`). Never a duplicate.
	if TitleDemo.acres().is_empty():
		assert_int(houses.size()).is_between(8, TitleDemo.NPCS.size())
	else:
		assert_int(houses.size()).is_equal(TitleDemo.NPCS.size() - 1)
	var allowed: Array[StringName] = []
	for row: Dictionary in TitleDemo.NPCS:
		allowed.append(row["id"] as StringName)
	var seen: Dictionary = {}
	for house: BuildingPlacement in houses:
		assert_bool(allowed.has(house.resident_id)).is_true()
		assert_bool(seen.has(house.resident_id)).is_false()
		seen[house.resident_id] = true
	var villagers := 0
	for o: ObjectPlacement in data.objects:
		if o != null and o.kind == &"villager":
			villagers += 1
	if TitleDemo.acres().is_empty():
		assert_int(villagers).is_greater_equal(houses.size())
	else:
		## `title_demo_actable` births all 14, Lobo without a house.
		assert_int(villagers).is_equal(TitleDemo.NPCS.size())


func test_demo_villagers_are_born_on_their_actor_table_units() -> void:
	if not _demo_ready() or TitleDemo.acres().is_empty():
		return
	var data: WorldData = WorldGenerator.generate(WorldGenerator.DEFAULT_SEED, true)
	var cells: Dictionary = {}
	for o: ObjectPlacement in data.objects:
		if o != null and o.kind == &"villager":
			cells[o.id] = o.cell
	for row: Dictionary in TitleDemo.NPCS:
		var id: StringName = row["id"]
		assert_bool(cells.has(id)).is_true()
		assert_vector(Vector2(cells[id])).is_equal(Vector2(WorldGenerator.title_demo_start_cell(row)))


func test_a_home_sits_where_the_decomp_table_puts_it() -> void:
	if not _demo_ready():
		return
	## Bob: acre (1, 2), unit (3, 7). The fixed FG marks the house one unit north of that unit
	## (0x5000 at unit (3, 6)) and the 3x3 is centred on the marker.
	var data: WorldData = WorldGenerator.generate(WorldGenerator.DEFAULT_SEED, true)
	var bob: BuildingPlacement = null
	for house: BuildingPlacement in _npc_houses(data):
		if house.resident_id == &"bob":
			bob = house
	if bob == null:
		return
	var origin: Vector2i = WorldGenerator._fg_origin(1, 2)
	assert_vector(Vector2(bob.cell)).is_equal(Vector2(origin + Vector2i(3, 7) + Vector2i(-1, -2)))


func test_the_demo_has_its_apple_tree_at_acre_5_5_unit_14_8() -> void:
	if not _demo_ready():
		return
	var data: WorldData = WorldGenerator.generate(WorldGenerator.DEFAULT_SEED, true)
	var cell: Vector2i = WorldGenerator._fg_origin(5, 5) + Vector2i(14, 8)
	var found: ObjectPlacement = null
	for o: ObjectPlacement in data.objects:
		if o != null and o.cell == cell:
			found = o
	## The unit can sit on non-grass in a given town layout; when it is there it is the fruit tree.
	if found != null:
		assert_str(String(found.visual_id)).is_equal("TREE_APPLE_FRUIT")


func _structures(data: WorldData) -> Dictionary:
	var out: Dictionary = {}
	for b: BuildingPlacement in data.buildings:
		if b == null:
			continue
		var id: String = String(b.id)
		if id.begins_with("npc_house_") or id.begins_with("player_house"):
			continue
		out[id] = b.cell
	return out


func test_demo_town_is_the_fixed_decomp_map() -> void:
	## `data_fdd[SCENE_TITLE_DEMO].combi`: the attract town never uses a random field.
	if not _demo_ready() or TitleDemo.acres().is_empty():
		return
	var data: WorldData = WorldGenerator.generate(WorldGenerator.DEFAULT_SEED, true)
	var other: WorldData = WorldGenerator.generate(WorldGenerator.DEFAULT_SEED + 1, true)
	assert_str(",".join(data.acre_visuals)).is_equal(",".join(other.acre_visuals))
	var at := func(bx: int, bz: int) -> String:
		return data.acre_visuals[bz * TownFieldGenerator.BLOCK_X + bx]
	assert_str(at.call(3, 1)).is_equal("grd_s_t_st1_1")
	assert_str(at.call(3, 2)).is_equal("grd_s_f_mh_1")
	assert_str(at.call(3, 4)).is_equal("grd_s_c1_r1_1")
	assert_str(at.call(2, 6)).is_equal("grd_s_m_r1_b_2")
	## Rows 8–9 are outside the 7×8 demo field.
	assert_str(at.call(3, 8)).is_equal("")


func test_demo_structures_sit_in_their_fixed_acres() -> void:
	## Regression: the fixed FG was once laid over a generated BG, so its structure items were
	## dropped and acre-type fallbacks collided (the post office landed inside the shop). On the
	## demo's own map the fixed FG places every structure itself.
	if not _demo_ready() or TitleDemo.acres().is_empty():
		return
	var data: WorldData = WorldGenerator.generate(WorldGenerator.DEFAULT_SEED, true)
	var expect := {
		"post_office": Vector2i(1, 1),
		"station": Vector2i(3, 1),
		"acre_shop": Vector2i(4, 1),
		"wishing_well": Vector2i(1, 5),
		"police": Vector2i(4, 5),
	}
	var structures: Dictionary = _structures(data)
	for id: String in expect:
		assert_bool(structures.has(id)).is_true()
		var cell: Vector2i = structures[id]
		assert_vector(Vector2(cell.x / WorldGenerator.UT + 1, cell.y / WorldGenerator.UT + 1)).is_equal(
			Vector2(expect[id])
		)


func test_no_two_demo_structures_overlap() -> void:
	if not _demo_ready():
		return
	var data: WorldData = WorldGenerator.generate(WorldGenerator.DEFAULT_SEED, true)
	var solid: Array[BuildingPlacement] = []
	for b: BuildingPlacement in data.buildings:
		if b != null and b.occupy_grid:
			solid.append(b)
	for i: int in solid.size():
		for j: int in range(i + 1, solid.size()):
			var a: BuildingPlacement = solid[i]
			var b: BuildingPlacement = solid[j]
			var overlap: bool = (
				a.cell.x < b.cell.x + b.footprint.x and b.cell.x < a.cell.x + a.footprint.x
				and a.cell.y < b.cell.y + b.footprint.y and b.cell.y < a.cell.y + a.footprint.y
			)
			assert_bool(overlap).is_false()
