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
	var axe: ItemData = load("res://data/items/axe.tres")
	assert_int(ctx.inventory.add(axe, Inventory.POCKET_SLOTS)).is_equal(0)
	var action: Interaction = Interaction.primary(pickup.get_interactions(ctx))
	assert_bool(pickup.interact(action, ctx)).is_false()
	assert_int(ctx.inventory.count_of(&"axe")).is_equal(Inventory.POCKET_SLOTS)
	assert_int(ctx.inventory.count_of(&"apple")).is_equal(0)
	assert_bool(Game.is_interactable_removed(&"ground_apple")).is_false()


func test_scene_hosts_offer_expected_verbs() -> void:
	var ctx := InteractionContext.new()
	_assert_verb("res://scenes/world/tree.tscn", Interaction.SHAKE, ctx)
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 10, "minute": 0 })
	_assert_verb("res://scenes/actors/villager.tscn", Interaction.TALK, ctx)
	_assert_verb("res://scenes/world/furniture.tscn", Interaction.SIT, ctx)
	_assert_verb("res://scenes/world/house.tscn", Interaction.ENTER, ctx)
	_assert_verb("res://scenes/world/shop.tscn", Interaction.SHOP, ctx)
	_assert_verb("res://scenes/world/sign.tscn", Interaction.READ, ctx)
	_assert_verb("res://scenes/world/flower.tscn", Interaction.PICK_UP, ctx)
	_assert_verb("res://scenes/world/door.tscn", Interaction.ENTER, ctx)


func test_rock_dig_requires_shovel() -> void:
	ItemCatalog.reload()
	var rock: Node = auto_free(load("res://scenes/world/rock.tscn").instantiate())
	var empty := InteractionContext.new()
	empty.inventory = Inventory.new()
	assert_int(rock.get_interactions(empty).size()).is_equal(0)
	var ctx := _ctx_with_tool(&"shovel")
	var action: Interaction = Interaction.primary(rock.get_interactions(ctx))
	assert_that(action).is_not_null()
	assert_str(String(action.id)).is_equal(String(Interaction.DIG))
	assert_bool(rock.interact(action, ctx)).is_true()
	assert_bool(rock.interact(action, empty)).is_false()


func test_tree_chops_when_axe_equipped() -> void:
	ItemCatalog.reload()
	var tree: Node = auto_free(load("res://scenes/world/tree.tscn").instantiate())
	var empty := InteractionContext.new()
	empty.inventory = Inventory.new()
	assert_str(String(Interaction.primary(tree.get_interactions(empty)).id)).is_equal(
		String(Interaction.SHAKE)
	)
	var ctx := _ctx_with_tool(&"axe")
	ctx.world = auto_free(_FakeWorld.new())
	tree.set("occupant_id", &"tree_1")
	tree.set("persist_id", &"tree_1")
	var action: Interaction = Interaction.primary(tree.get_interactions(ctx))
	assert_str(String(action.id)).is_equal(String(Interaction.CHOP))
	assert_str(String(action.player_anim)).is_equal("ply_1_axe_swing1")
	assert_bool(tree.interact(action, ctx)).is_true()
	assert_bool(tree.is_queued_for_deletion()).is_false()
	assert_bool(Game.is_interactable_removed(&"tree_1")).is_false()
	assert_str(String((ctx.world as _FakeWorld).released)).is_equal("")
	assert_bool(tree.interact(action, ctx)).is_true()
	assert_bool(tree.interact(action, ctx)).is_true()
	assert_bool(tree.is_queued_for_deletion()).is_false()
	assert_bool(Game.is_stump(&"tree_1")).is_true()
	assert_int(tree.get_interactions(empty).size()).is_equal(0)
	var dig_ctx := _ctx_with_tool(&"shovel")
	dig_ctx.world = ctx.world
	var dig: Interaction = Interaction.primary(tree.get_interactions(dig_ctx))
	assert_str(String(dig.id)).is_equal(String(Interaction.DIG))
	assert_bool(tree.interact(dig, dig_ctx)).is_true()
	assert_bool(tree.is_queued_for_deletion()).is_true()
	assert_bool(Game.is_interactable_removed(&"tree_1")).is_true()
	assert_bool(Game.is_stump(&"tree_1")).is_false()
	assert_str(String((ctx.world as _FakeWorld).released)).is_equal("tree_1")


func test_hole_fill_requires_shovel() -> void:
	ItemCatalog.reload()
	Game.mark_hole(&"hole_4_5")
	var hole: Node = auto_free(load("res://scenes/world/hole.tscn").instantiate())
	hole.set("persist_id", &"hole_4_5")
	var empty := InteractionContext.new()
	empty.inventory = Inventory.new()
	assert_int(hole.get_interactions(empty).size()).is_equal(0)
	var ctx := _ctx_with_tool(&"shovel")
	var action: Interaction = Interaction.primary(hole.get_interactions(ctx))
	assert_that(action).is_not_null()
	assert_str(String(action.id)).is_equal(String(Interaction.FILL))
	assert_str(action.player_anim).is_equal("ply_1_fill_up1")
	assert_bool(hole.interact(action, ctx)).is_true()
	assert_bool(hole.is_queued_for_deletion()).is_true()
	assert_bool(Game.is_hole(&"hole_4_5")).is_false()


func test_saved_stump_offers_dig() -> void:
	ItemCatalog.reload()
	Game.mark_stump(&"tree_1")
	var tree: Node = auto_free(load("res://scenes/world/tree.tscn").instantiate())
	tree.set("persist_id", &"tree_1")
	assert_int(tree.get_interactions(InteractionContext.new()).size()).is_equal(0)
	var ctx := _ctx_with_tool(&"shovel")
	var action: Interaction = Interaction.primary(tree.get_interactions(ctx))
	assert_str(String(action.id)).is_equal(String(Interaction.DIG))


func test_flower_waters_when_can_equipped() -> void:
	ItemCatalog.reload()
	var flower: Node = auto_free(load("res://scenes/world/flower.tscn").instantiate())
	var ctx := _ctx_with_tool(&"watering_can")
	var action: Interaction = Interaction.primary(flower.get_interactions(ctx))
	assert_str(String(action.id)).is_equal(String(Interaction.WATER))
	assert_bool(flower.interact(action, ctx)).is_true()
	assert_bool(flower.is_queued_for_deletion()).is_false()


func test_seed_flower_cannot_pick() -> void:
	ItemCatalog.reload()
	Clock.apply_snapshot({"year": 2001, "month": 4, "day": 1, "hour": 12, "minute": 0})
	var flower: Node = auto_free(load("res://scenes/world/flower.tscn").instantiate())
	flower.set("persist_id", &"pansy_1")
	flower.set("plant", load("res://data/plants/pansy.tres"))
	flower.set("visual_id", &"FLOWER_PANSIES0")
	add_child(flower)
	var empty := InteractionContext.new()
	empty.inventory = Inventory.new()
	assert_int(flower.get_interactions(empty).size()).is_equal(0)
	var ctx := _ctx_with_tool(&"watering_can")
	var action: Interaction = Interaction.primary(flower.get_interactions(ctx))
	assert_str(String(action.id)).is_equal(String(Interaction.WATER))


func test_building_exposes_verbs_on_child_door() -> void:
	## Generic buildings compose a Door; the player still never switches on type.
	var building: Node = auto_free(load("res://scenes/world/building.tscn").instantiate())
	add_child(building)
	var door: Node = building.get_node("Door")
	assert_bool(InteractionQuery.is_host(door)).is_true()
	assert_bool(InteractionQuery.is_host(building)).is_false()
	var vol: Node = door.get_node("InteractVolume")
	assert_object(InteractionQuery.host_from(vol)).is_same(door)
	var action: Interaction = Interaction.primary(door.get_interactions(InteractionContext.new()))
	assert_str(String(action.id)).is_equal(String(Interaction.ENTER))
	assert_bool(door.interact(action, InteractionContext.new())).is_true()


func test_context_forwards_release_occupant() -> void:
	var world := auto_free(_FakeWorld.new()) as _FakeWorld
	var ctx := InteractionContext.new()
	ctx.world = world
	ctx.release_occupant(&"yard_chair")
	assert_str(String(world.released)).is_equal("yard_chair")


func test_player_has_no_object_type_switch() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/actors/player.gd")
	assert_str(src).contains("InteractionQuery.best_in_areas")
	assert_str(src).contains("ToolUse.resolve")
	assert_bool("is Tree" in src).is_false()
	assert_bool("is Villager" in src).is_false()
	assert_bool("is Furniture" in src).is_false()
	assert_bool("ToolData.Kind" in src).is_false()
	assert_bool("has_method(\"try_interact\")" in src).is_false()
	assert_bool("has_method(\"interact_prompt\")" in src).is_false()


func test_world_scene_wires_interactables() -> void:
	var world: Node = auto_free(load("res://scenes/world/world.tscn").instantiate())
	add_child(world)
	assert_that(world.get_node_or_null("Objects/acre_sign")).is_not_null()
	assert_that(world.get_node_or_null("Objects/yard_chair")).is_not_null()
	assert_that(world.get_node_or_null("Buildings/acre_shop")).is_not_null()
	assert_that(world.get_node_or_null("Buildings/player_house")).is_not_null()
	assert_that(world.get_node_or_null("Characters/pip")).is_not_null()


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
	Clock.apply_snapshot({ "year": 2001, "month": 1, "day": 1, "hour": 12, "minute": 0 })
	assert_str(String(villager.current_activity())).is_equal("in_house")
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


func _ctx_with_tool(item_id: StringName) -> InteractionContext:
	var ctx := InteractionContext.new()
	ctx.inventory = Inventory.new()
	var data: ItemData = ItemCatalog.get_item(item_id)
	assert_that(data).is_not_null()
	assert_int(ctx.inventory.add(data, 1)).is_equal(0)
	assert_bool(ctx.inventory.equip_slot(0)).is_true()
	return ctx
