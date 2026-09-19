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
	## Not every plot is grass in every town layout, so some homes can be dropped — but most
	## land, never more than the 14 named villagers, and never a duplicate.
	assert_int(houses.size()).is_between(8, TitleDemo.NPCS.size())
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
	assert_int(villagers).is_equal(houses.size())


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


func test_demo_town_keeps_every_structure_where_the_normal_town_puts_it() -> void:
	## Regression: the fixed FG table has no structures, so an early version of the demo fell
	## back to unrefined acre-type positions — the post office landed inside the shop. The real
	## templates place and refine structures; the fixed table only supplies props and homes.
	if not _demo_ready():
		return
	var normal: Dictionary = _structures(WorldGenerator.generate(WorldGenerator.DEFAULT_SEED))
	var demo: Dictionary = _structures(WorldGenerator.generate(WorldGenerator.DEFAULT_SEED, true))
	assert_bool(normal.has("post_office")).is_true()
	assert_bool(demo.has("post_office")).is_true()
	assert_dict(demo).is_equal(normal)


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
