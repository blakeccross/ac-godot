extends GdUnitTestSuite

## `ac_nameplate`: a villager's house sign on the south-west unit of the plot.


class _Actor extends Node3D:
	var yaw: float = PI

	func facing_yaw() -> float:
		return yaw


class _GridWorld extends Node3D:
	var grid: WorldGrid = WorldGrid.new()


func test_sign_reads_from_the_south_only() -> void:
	var world: _GridWorld = auto_free(_GridWorld.new())
	world.grid.configure(16, 16, 2.0, Vector3.ZERO)
	add_child(world)
	var house: Node3D = auto_free(load("res://scenes/world/house.tscn").instantiate())
	house.name = "npc_house_0"
	world.grid.place(&"npc_house_0", Vector2i(4, 4), Vector2i(3, 3), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.BUILDING)
	assert_that(house.call("nameplate_cell", world.grid)).is_equal(Vector2i(4, 6))
	var actor: _Actor = auto_free(_Actor.new())
	world.add_child(actor)
	actor.global_position = world.grid.cell_to_world(Vector2i(4, 7))
	var ctx := InteractionContext.new()
	ctx.world = world
	ctx.actor = actor
	var acts: Array[Interaction] = house.call("get_interactions", ctx)
	assert_str(String(acts[0].id)).is_equal(String(Interaction.READ))
	## At the door instead: enter.
	actor.global_position = world.grid.cell_to_world(Vector2i(5, 7))
	acts = house.call("get_interactions", ctx)
	assert_str(String(acts[0].id)).is_equal(String(Interaction.ENTER))
	## The player's own house has no sign.
	house.name = "player_house"
	assert_that(house.call("nameplate_cell", world.grid)).is_equal(Vector2i(-1, -1))
