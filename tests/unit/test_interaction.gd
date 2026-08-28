class_name TestInteraction
extends GdUnitTestSuite

## Interaction is a verb payload. Hosts duck-type get_interactions / interact.
## The player must not switch on Tree vs Villager vs Furniture.


class _StubHost extends Node3D:
	var verb: StringName = Interaction.TALK
	var prompt: String = "Talk"
	var priority: int = 0
	var last_action: Interaction = null

	func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
		return [Interaction.of(verb, prompt, priority)]

	func interact(action: Interaction, _ctx: InteractionContext) -> bool:
		last_action = action
		return action != null and action.id == verb


class _FakeWorld extends Node:
	var released: StringName = &""

	func release_occupant(occupant_id: StringName) -> void:
		released = occupant_id


func before_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = true


func after_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func test_primary_picks_highest_priority() -> void:
	var actions: Array[Interaction] = [
		Interaction.of(Interaction.READ, "Read", 6),
		Interaction.of(Interaction.TALK, "Talk", 20),
		Interaction.of(Interaction.PICK_UP, "Pick up", 15),
	]
	var best: Interaction = Interaction.primary(actions)
	assert_that(best).is_not_null()
	assert_str(String(best.id)).is_equal(String(Interaction.TALK))
	assert_str(best.prompt).is_equal("Talk")


func test_primary_skips_empty() -> void:
	var actions: Array[Interaction] = [
		Interaction.of(&"", "Nope", 99),
		Interaction.of(Interaction.SIT, "Sit", 8),
	]
	var best: Interaction = Interaction.primary(actions)
	assert_str(String(best.id)).is_equal(String(Interaction.SIT))


func test_primary_empty_is_null() -> void:
	var actions: Array[Interaction] = []
	assert_object(Interaction.primary(actions)).is_null()


func test_host_from_walks_ancestors() -> void:
	var host := auto_free(_StubHost.new()) as _StubHost
	var mid := Node.new()
	var volume := Area3D.new()
	host.add_child(mid)
	mid.add_child(volume)
	assert_object(InteractionQuery.host_from(volume)).is_same(host)
	assert_bool(InteractionQuery.is_host(host)).is_true()
	assert_bool(InteractionQuery.is_host(volume)).is_false()
	assert_bool(InteractionQuery.is_host(auto_free(InteractVolume.new()))).is_false()


func test_best_in_areas_picks_closer_host_not_higher_priority() -> void:
	var talker := auto_free(_StubHost.new()) as _StubHost
	talker.verb = Interaction.TALK
	talker.priority = 20
	talker.position = Vector3(8, 0, 0)
	var item := auto_free(_StubHost.new()) as _StubHost
	item.verb = Interaction.PICK_UP
	item.prompt = "Pick up"
	item.priority = 15
	item.position = Vector3(1, 0, 0)
	var talk_area := Area3D.new()
	var item_area := Area3D.new()
	talker.add_child(talk_area)
	item.add_child(item_area)
	add_child(talker)
	add_child(item)
	var hit: InteractionQuery = InteractionQuery.best_in_areas(
		[talk_area, item_area], Vector3.ZERO, InteractionContext.new()
	)
	assert_object(hit.host).is_same(item)
	assert_str(String(hit.action.id)).is_equal(String(Interaction.PICK_UP))


func test_dummy_hosts_talk_and_pick_up_without_type_checks() -> void:
	var ctx := InteractionContext.new()
	ctx.inventory = Inventory.new()
	var villager := auto_free(_StubHost.new()) as _StubHost
	villager.verb = Interaction.TALK
	villager.prompt = "Talk to Pip"
	villager.priority = 20
	var ground := auto_free(_StubHost.new()) as _StubHost
	ground.verb = Interaction.PICK_UP
	ground.prompt = "Pick up Apple"
	ground.priority = 15
	var talk: Interaction = Interaction.primary(villager.get_interactions(ctx))
	var grab: Interaction = Interaction.primary(ground.get_interactions(ctx))
	assert_bool(villager.interact(talk, ctx)).is_true()
	assert_str(String(villager.last_action.id)).is_equal(String(Interaction.TALK))
	assert_bool(ground.interact(grab, ctx)).is_true()
	assert_str(String(ground.last_action.id)).is_equal(String(Interaction.PICK_UP))
	assert_bool(villager.interact(grab, ctx)).is_false()


func test_item_pickup_adds_to_inventory() -> void:
	var pickup: Node = auto_free(load("res://scenes/world/item_pickup.tscn").instantiate())
	var ctx := InteractionContext.new()
	ctx.inventory = Inventory.new()
	ctx.world = auto_free(_FakeWorld.new())
	var actions: Array[Interaction] = pickup.get_interactions(ctx)
	assert_int(actions.size()).is_equal(1)
	assert_str(String(actions[0].id)).is_equal(String(Interaction.PICK_UP))
	assert_bool(pickup.interact(actions[0], ctx)).is_true()
	assert_int(ctx.inventory.count_of(&"apple")).is_equal(1)
	assert_bool(Game.is_interactable_removed(&"ground_apple")).is_true()
	assert_str(String((ctx.world as _FakeWorld).released)).is_equal("ground_apple")


func test_item_pickup_refuses_when_pockets_full() -> void:
	var pickup: Node = auto_free(load("res://scenes/world/item_pickup.tscn").instantiate())
	var ctx := InteractionContext.new()
	ctx.inventory = Inventory.new()
	var apple: ItemData = load("res://data/items/apple.tres")
	assert_int(ctx.inventory.add(apple, Inventory.POCKET_SLOTS)).is_equal(0)
	var action: Interaction = Interaction.primary(pickup.get_interactions(ctx))
	assert_bool(pickup.interact(action, ctx)).is_false()
	assert_int(ctx.inventory.count_of(&"apple")).is_equal(Inventory.POCKET_SLOTS)
	assert_bool(Game.is_interactable_removed(&"ground_apple")).is_false()


func test_scene_hosts_offer_expected_verbs() -> void:
	var ctx := InteractionContext.new()
	_assert_verb("res://scenes/world/tree.tscn", Interaction.SHAKE, ctx)
	_assert_verb("res://scenes/actors/villager.tscn", Interaction.TALK, ctx)
	_assert_verb("res://scenes/world/furniture.tscn", Interaction.SIT, ctx)
	_assert_verb("res://scenes/world/house.tscn", Interaction.ENTER, ctx)
	_assert_verb("res://scenes/world/shop.tscn", Interaction.SHOP, ctx)
	_assert_verb("res://scenes/world/sign.tscn", Interaction.READ, ctx)


func test_context_forwards_release_occupant() -> void:
	var world := auto_free(_FakeWorld.new()) as _FakeWorld
	var ctx := InteractionContext.new()
	ctx.world = world
	ctx.release_occupant(&"yard_chair")
	assert_str(String(world.released)).is_equal("yard_chair")


func test_player_has_no_object_type_switch() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/actors/player.gd")
	assert_str(src).contains("InteractionQuery.best_in_areas")
	assert_bool("is Tree" in src).is_false()
	assert_bool("is Villager" in src).is_false()
	assert_bool("is Furniture" in src).is_false()
	assert_bool("has_method(\"try_interact\")" in src).is_false()
	assert_bool("has_method(\"interact_prompt\")" in src).is_false()


func test_world_scene_wires_interactables() -> void:
	var world: Node = auto_free(load("res://scenes/world/world.tscn").instantiate())
	assert_that(world.get_node_or_null("Objects/Sign")).is_not_null()
	assert_that(world.get_node_or_null("Objects/Chair")).is_not_null()
	assert_that(world.get_node_or_null("Buildings/Shop")).is_not_null()
	assert_that(world.get_node_or_null("Buildings/House")).is_not_null()


func test_shop_hours_follow_clock() -> void:
	var shop: Node = auto_free(load("res://scenes/world/shop.tscn").instantiate())
	var ctx := InteractionContext.new()
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 12, "minute": 0 })
	var open_action: Interaction = Interaction.primary(shop.get_interactions(ctx))
	assert_str(open_action.prompt).is_equal("Shop")
	assert_bool(shop.interact(open_action, ctx)).is_true()
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 23, "minute": 0 })
	var closed_action: Interaction = Interaction.primary(shop.get_interactions(ctx))
	assert_str(closed_action.prompt).is_equal("Shop (closed)")
	assert_bool(shop.interact(closed_action, ctx)).is_false()


func test_villager_offers_no_talk_while_sleeping() -> void:
	var villager: Node = auto_free(load("res://scenes/actors/villager.tscn").instantiate())
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 7, "minute": 0 })
	assert_str(String(villager.current_activity())).is_equal("sleep")
	assert_int(villager.get_interactions(InteractionContext.new()).size()).is_equal(0)
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 10, "minute": 0 })
	assert_str(String(villager.current_activity())).is_equal("field")
	assert_int(villager.get_interactions(InteractionContext.new()).size()).is_equal(1)


func _assert_verb(scene_path: String, verb: StringName, ctx: InteractionContext) -> void:
	var host: Node = auto_free(load(scene_path).instantiate())
	assert_bool(InteractionQuery.is_host(host)).is_true()
	var action: Interaction = Interaction.primary(host.get_interactions(ctx))
	assert_that(action).is_not_null()
	assert_str(String(action.id)).is_equal(String(verb))
	assert_bool(host.interact(action, ctx)).is_true()
