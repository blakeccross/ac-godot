class_name TestToolUse
extends GdUnitTestSuite

## Tools are data + ToolUse. The player must not switch on Shovel vs Axe.


class _FacingActor extends Node3D:
	var yaw: float = 0.0

	func facing_yaw() -> float:
		return yaw


class _GridWorld extends Node:
	var grid: WorldGrid = WorldGrid.new()


func before_test() -> void:
	Game.reset_session()
	ItemCatalog.reload()
	Clock.reset_to_default()
	Clock.paused = true


func after_test() -> void:
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func test_catalog_tools_are_tool_data() -> void:
	var shovel: ToolData = ItemCatalog.get_item(&"shovel") as ToolData
	var rod: ToolData = ItemCatalog.get_item(&"fishing_rod") as ToolData
	var net: ToolData = ItemCatalog.get_item(&"net") as ToolData
	var axe: ToolData = ItemCatalog.get_item(&"axe") as ToolData
	var can: ToolData = ItemCatalog.get_item(&"watering_can") as ToolData
	assert_that(shovel).is_not_null()
	assert_that(shovel.kind).is_equal(ToolData.Kind.SHOVEL)
	assert_that(rod.kind).is_equal(ToolData.Kind.FISHING_ROD)
	assert_that(net.kind).is_equal(ToolData.Kind.NET)
	assert_that(axe.kind).is_equal(ToolData.Kind.AXE)
	assert_that(can.kind).is_equal(ToolData.Kind.WATERING_CAN)
	assert_bool(axe.equippable).is_true()
	assert_int(axe.max_stack).is_equal(1)
	assert_that(axe.visual_id).is_equal(&"tol_axe_1")
	assert_that(shovel.visual_id).is_equal(&"tol_scoop_1")
	assert_that(net.visual_id).is_equal(&"tol_net_1")
	assert_that(rod.visual_id).is_equal(&"tol_sao_1")
	assert_that(can.visual_id).is_equal(&"")
	assert_that(shovel.field_anim).is_equal(&"ply_1_dig1")
	assert_that(net.field_anim).is_equal(&"ply_1_net_swing1")
	assert_that(rod.field_anim).is_equal(&"ply_1_sao_swing1")
	assert_that(net.hold_anim).is_equal(&"ply_1_kamae_wait_m1")
	assert_that(net.visual_hold_anim).is_equal(&"kamae_main_m1")
	assert_that(net.visual_use_anim).is_equal(&"net_swing1")
	assert_that(rod.visual_hold_anim).is_equal(&"sao_wait1")
	assert_that(rod.visual_use_anim).is_equal(&"sao_swing1")


func test_kind_follows_equipment() -> void:
	var ctx := InteractionContext.new()
	ctx.inventory = Inventory.new()
	assert_that(ToolUse.kind(ctx)).is_equal(ToolData.Kind.NONE)
	assert_bool(ToolUse.has(ctx, ToolData.Kind.AXE)).is_false()
	_equip(ctx, &"axe")
	assert_that(ToolUse.kind(ctx)).is_equal(ToolData.Kind.AXE)
	assert_bool(ToolUse.has(ctx, ToolData.Kind.AXE)).is_true()
	ctx.inventory.unequip()
	assert_that(ToolUse.kind(ctx)).is_equal(ToolData.Kind.NONE)


func test_net_field_action_needs_no_host() -> void:
	var ctx := _equipped(&"net")
	var action: Interaction = ToolUse.field_action(ctx)
	assert_that(action).is_not_null()
	assert_str(String(action.id)).is_equal(String(Interaction.SWING_NET))
	assert_str(action.prompt).is_equal("Swing net")
	var heard: Array[String] = []
	var on_notice: Callable = func(text: String) -> void: heard.append(text)
	Game.notice_posted.connect(on_notice)
	assert_bool(ToolUse.apply_field(action, ctx)).is_true()
	Game.notice_posted.disconnect(on_notice)
	assert_bool("You swing the net." in heard).is_true()


func test_axe_has_no_field_verb() -> void:
	var ctx := _equipped(&"axe")
	assert_object(ToolUse.field_action(ctx)).is_null()


func test_watering_can_has_no_field_verb() -> void:
	var ctx := _equipped(&"watering_can")
	assert_object(ToolUse.field_action(ctx)).is_null()


func test_rod_casts_only_at_water() -> void:
	var world := auto_free(_GridWorld.new()) as _GridWorld
	world.grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	world.grid.set_terrain(Vector2i(8, 9), WorldGrid.Terrain.WATER)
	var actor := auto_free(_FacingActor.new()) as _FacingActor
	add_child(actor)
	actor.global_position = world.grid.cell_to_world(Vector2i(8, 8))
	var ctx := _equipped(&"fishing_rod")
	ctx.actor = actor
	ctx.world = world
	var action: Interaction = ToolUse.field_action(ctx)
	assert_that(action).is_not_null()
	assert_str(String(action.id)).is_equal(String(Interaction.CAST))
	assert_bool(ToolUse.apply_field(action, ctx)).is_true()
	actor.yaw = -PI * 0.5
	assert_object(ToolUse.field_action(ctx)).is_null()


func test_shovel_digs_empty_ground() -> void:
	var world := auto_free(_GridWorld.new()) as _GridWorld
	world.grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	var actor := auto_free(_FacingActor.new()) as _FacingActor
	add_child(actor)
	actor.global_position = world.grid.cell_to_world(Vector2i(8, 8))
	var ctx := _equipped(&"shovel")
	ctx.actor = actor
	ctx.world = world
	var action: Interaction = ToolUse.field_action(ctx)
	assert_that(action).is_not_null()
	assert_str(String(action.id)).is_equal(String(Interaction.DIG))
	var heard: Array[String] = []
	var on_notice: Callable = func(text: String) -> void: heard.append(text)
	Game.notice_posted.connect(on_notice)
	assert_bool(ToolUse.apply_field(action, ctx)).is_true()
	Game.notice_posted.disconnect(on_notice)
	assert_bool("You dig a hole." in heard).is_true()
	var pid: StringName = HoleUse.persist_id(Vector2i(8, 9))
	assert_bool(Game.is_hole(pid)).is_true()
	assert_str(String(world.grid.occupant_at(Vector2i(8, 9)))).is_equal(String(pid))
	assert_object(ToolUse.field_action(ctx)).is_null()
	world.grid.remove(pid)
	Game.clear_hole(pid)
	world.grid.place(&"rock", Vector2i(8, 9), Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
	assert_object(ToolUse.field_action(ctx)).is_null()


func test_resolve_prefers_net_over_weaker_host() -> void:
	var ctx := _equipped(&"net")
	var hit := InteractionQuery.new()
	hit.host = auto_free(Node.new())
	hit.action = Interaction.of(Interaction.SHAKE, "Shake", 10)
	var resolved: InteractionQuery = ToolUse.resolve(hit, ctx)
	assert_object(resolved.host).is_null()
	assert_str(String(resolved.action.id)).is_equal(String(Interaction.SWING_NET))
	hit.action = Interaction.of(Interaction.TALK, "Talk", 20)
	resolved = ToolUse.resolve(hit, ctx)
	assert_object(resolved.host).is_same(hit.host)
	assert_str(String(resolved.action.id)).is_equal(String(Interaction.TALK))


func test_player_does_not_switch_on_tool_kind() -> void:
	var src := FileAccess.get_file_as_string("res://scenes/actors/player.gd")
	assert_str(src).contains("ToolUse.resolve")
	assert_str(src).contains("ToolUse.apply_field")
	assert_str(src).contains("HeldTool.bind")
	assert_bool("ToolData.Kind" in src).is_false()
	assert_bool("is Tree" in src).is_false()


func test_held_tool_binds_hand_attachment() -> void:
	if FieldCatalog.mesh_paths(&"tol_axe_1").is_empty():
		return
	var skel := auto_free(Skeleton3D.new()) as Skeleton3D
	add_child(skel)
	for i: int in 21:
		skel.add_bone("joint_%d" % i)
		if i > 0:
			skel.set_bone_parent(i, i - 1)
	var attach: Node3D = HeldTool.bind(skel, &"tol_axe_1")
	assert_that(attach).is_not_null()
	assert_str(attach.name).is_equal(HeldTool.ATTACH_NAME)
	assert_str((attach as BoneAttachment3D).bone_name).is_equal(HeldTool.HAND_BONE)
	assert_that(skel.get_node_or_null(HeldTool.ATTACH_NAME)).is_same(attach)
	HeldTool.bind(skel, &"tol_scoop_1")
	assert_int(_held_tool_count(skel)).is_equal(1)
	HeldTool.unbind(skel)
	assert_that(skel.get_node_or_null(HeldTool.ATTACH_NAME)).is_null()


func _held_tool_count(skeleton: Skeleton3D) -> int:
	var n := 0
	for child in skeleton.get_children():
		if child.name == HeldTool.ATTACH_NAME:
			n += 1
	return n


func _equipped(item_id: StringName) -> InteractionContext:
	var ctx := InteractionContext.new()
	ctx.inventory = Inventory.new()
	_equip(ctx, item_id)
	return ctx


func _equip(ctx: InteractionContext, item_id: StringName) -> void:
	var data: ItemData = ItemCatalog.get_item(item_id)
	assert_that(data).is_not_null()
	assert_int(ctx.inventory.add(data, 1)).is_equal(0)
	assert_bool(ctx.inventory.equip_slot(0)).is_true()
