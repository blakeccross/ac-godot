class_name TestEventNpcCollision
extends GdUnitTestSuite

## Event NPCs (Jack's costumed residents, the festival crowd) meet houses the way villagers do:
## as raised units of the heightfield. They are not placed on those units and cannot run across
## them.


func _town_with_house() -> Array:
	var data := WorldData.new()
	data.columns = 16
	data.rows = 16
	data.cell_size = 2.0
	data.acre_visual = &""
	data.bake()
	var b := BuildingPlacement.new()
	b.id = &"npc_house_0"
	b.kind = &"house"
	b.cell = Vector2i(8, 8)
	b.footprint = Vector2i(3, 3)
	b.visual_id = &"obj_s_house1"
	data.buildings.append(b)
	StructureOffset.apply(data)
	var grid := WorldGrid.new()
	grid.configure_from_world(data)
	return [data, grid, b]


func test_running_straight_at_a_house_is_stopped() -> void:
	var town: Array = _town_with_house()
	var data: WorldData = town[0]
	var grid: WorldGrid = town[1]
	var home: Vector2i = StructureOffset.npc_home_cell(town[2])
	var body: Vector3 = grid.cell_to_world(home + Vector2i(0, -1))
	var from := Vector3(body.x - 8.0, body.y, body.z)
	var pos: Vector3 = from
	for _i: int in 200:
		var want: Vector3 = pos + Vector3(0.05, 0.0, 0.0)
		pos = FieldCollision.revise_xz(data, grid, pos, want)
	assert_float(pos.x).is_less(body.x)


func test_house_body_units_are_not_stand_spots() -> void:
	var town: Array = _town_with_house()
	var data: WorldData = town[0]
	var world: World = auto_free(World.new())
	world.layout = data
	world.grid = town[1]
	var mgr: EventManager = auto_free(EventManager.new())
	mgr.world = world
	var home: Vector2i = StructureOffset.npc_home_cell(town[2])
	var raised := 0
	var open := 0
	for dz: int in range(-4, 5):
		for dx: int in range(-4, 5):
			var cell: Vector2i = home + Vector2i(dx, dz)
			if FieldCollision.is_raised_plus(data, cell):
				raised += 1
				assert_bool(mgr.npc_can_stand(cell)).is_false()
			elif mgr.npc_can_stand(cell):
				open += 1
	assert_int(raised).is_greater(0)
	assert_int(open).is_greater(0)
