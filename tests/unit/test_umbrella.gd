class_name TestUmbrella
extends GdUnitTestSuite

## Umbrellas: the 32 `ITM_UMBRELLA` tools, the held umbrella's open / close scaling
## (`ac_t_umbrella.c`), Nook's daily umbrella and the under-the-umbrella rain loop.


func before_test() -> void:
	Game.reset_session()


func after_test() -> void:
	Game.reset_session()


func test_open_scales_follow_the_sector_tables() -> void:
	var a := HeldUmbrella.Action
	## Frame 0: handle not there yet, canopy a flat disc (3 × 0.15).
	var s0: Array[Vector3] = HeldUmbrella.scales(a.OPENING, 0.0)
	assert_that(s0[0]).is_equal(Vector3.ZERO)
	assert_that(s0[1]).is_equal(Vector3(3.0, 0.15, 0.15))
	## Frame 9: halfway through the handle's 7→11 sector, (0,0)→(0.5,1).
	var s9: Array[Vector3] = HeldUmbrella.scales(a.OPENING, 9.0)
	assert_float(s9[0].x).is_equal_approx(0.25, 0.0001)
	assert_float(s9[0].y).is_equal_approx(0.5, 0.0001)
	## Fully open at 26: handle 1, canopy (0.9, 1) — the table's own last point.
	var s26: Array[Vector3] = HeldUmbrella.scales(a.OPENING, 26.0)
	assert_that(s26[0]).is_equal(Vector3.ONE)
	assert_that(s26[1]).is_equal(Vector3(0.9, 1.0, 1.0))
	## Folded away at 30.
	var c30: Array[Vector3] = HeldUmbrella.scales(a.PUTAWAY, 30.0)
	assert_that(c30[0]).is_equal(Vector3.ZERO)
	assert_that(c30[1]).is_equal(Vector3(3.0, 0.15, 0.15))


func test_take_out_opens_over_26_frames() -> void:
	var umb := HeldUmbrella.new()
	umb.setup(null, HeldUmbrella.Action.TAKEOUT_BEFORE)
	assert_bool(umb.opened_fully).is_false()
	umb.tick(1.0 / 60.0)
	assert_int(umb.action).is_equal(HeldUmbrella.Action.OPENING)
	for _i: int in 50:
		umb.tick(1.0 / 60.0)
	assert_bool(umb.opened_fully).is_false()
	umb.tick(1.0 / 60.0)
	umb.tick(1.0 / 60.0)
	assert_bool(umb.opened_fully).is_true()
	umb.set_action(HeldUmbrella.Action.PUTAWAY, false)
	assert_bool(umb.opened_fully).is_false()
	for _i: int in 60:
		umb.tick(1.0 / 60.0)
	assert_bool(umb.is_closed()).is_true()


func test_the_32_umbrellas_are_tools() -> void:
	var pool: Array[StringName] = ShopBook.umbrella_pool()
	assert_int(pool.size()).is_equal(32)
	var gelato: ToolData = ItemCatalog.get_item(&"gelato_umbrella") as ToolData
	assert_object(gelato).is_not_null()
	assert_int(gelato.kind).is_equal(ToolData.Kind.UMBRELLA)
	assert_int(gelato.umbrella_index).is_equal(0)
	assert_that(gelato.visual_id).is_equal(&"tol_umb_01")
	assert_int(gelato.sell_price).is_equal(220)
	var flame: ToolData = ItemCatalog.get_item(&"flame_umbrella") as ToolData
	assert_that(flame.visual_id).is_equal(&"tol_umb_32")
	## Twirl on A (`ROTATE_UMBRELLA`).
	assert_that(gelato.field_anim).is_equal(&"ply_1_umb_rot1")


func test_nook_stocks_one_umbrella_on_its_stand() -> void:
	Game.shops.restock(ShopBook.NOOK_ID)
	var goods: Array[StringName] = Game.shops.goods(ShopBook.NOOK_ID)
	var umbrellas: Array[StringName] = []
	for id: StringName in goods:
		if id in ShopBook.umbrella_pool():
			umbrellas.append(id)
	assert_int(umbrellas.size()).is_equal(1)
	var visual: StringName = ShopDisplay.display_visual_for_item(umbrellas[0])
	assert_str(String(visual)).starts_with("obj_shop_umb")
	## Lands on the Cranny's umbrella stand cell.
	var rows: Array[Dictionary] = ShopDisplay.stock_placements_for_goods([umbrellas[0]])
	assert_that(rows[0]["cell"]).is_equal(Vector2i(1, 5))


func test_twirl_is_a_field_verb() -> void:
	var ctx := InteractionContext.new()
	ctx.inventory = Game.inventory
	Game.inventory.add(ItemCatalog.get_item(&"gelato_umbrella"), 1)
	Game.inventory.equip_slot(0)
	var action: Interaction = ToolUse.field_action(ctx)
	assert_object(action).is_not_null()
	assert_that(action.id).is_equal(&"twirl_umbrella")
	assert_bool(ToolUse.apply_field(action, ctx)).is_true()


func test_open_umbrella_swaps_the_rain_loop() -> void:
	assert_int(Weather.rain_syslev_id(Weather.Kind.RAIN, 2, true)).is_equal(0x13)
	if not SeCatalog.has_id(&"lev_13"):
		return
	Game.title_demo_active = false
	Audio.sync_rain_syslev(Weather.Kind.RAIN, 2, false, false, true)
	assert_int(Audio.syslev_id()).is_equal(0x13)
	Audio.stop_syslev()
