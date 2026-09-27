extends GdUnitTestSuite

## Police box against `m_police_box.c`, `ac_npc_police2`, `bg_police_item`,
## `ef_room_sunshine_police` and outdoor Copper (`ac_npc_police`).


func before_test() -> void:
	Game.reset_session()


func _book(ids: Array) -> PoliceBook:
	var book := PoliceBook.new()
	for id: Variant in ids:
		book.keep_item(StringName(str(id)))
	return book


# --- PoliceBook (`m_police_box.c`) ------------------------------------------------------


func test_new_town_starts_with_one_furniture_two_shirts() -> void:
	var book := PoliceBook.new()
	book.rng.seed = 7
	book.init_town()
	assert_int(book.keep_item_sum()).is_equal(3)
	assert_bool(ItemCatalog.get_item(book.item_at(0)) is FurnitureData).is_true()
	assert_int(ItemCatalog.get_item(book.item_at(1)).category).is_equal(ItemData.Category.CLOTH)
	assert_int(ItemCatalog.get_item(book.item_at(2)).category).is_equal(ItemData.Category.CLOTH)
	for i: int in range(3, PoliceBook.STORAGE_COUNT):
		assert_that(book.item_at(i)).is_equal(&"")


func test_reset_session_inits_the_lost_and_found() -> void:
	assert_int(Game.police.keep_item_sum()).is_equal(3)


func test_emptied_box_stays_empty() -> void:
	## `mPB_police_box_init` runs once per town, never on an empty box.
	var book := _book(["net"])
	assert_int(book.claim_result(0, Inventory.new())).is_equal(PoliceBook.Claim.OK)
	assert_int(book.keep_item_sum()).is_equal(0)
	assert_array(book.keep_items()).contains_same([&""])
	assert_int(book.keep_item_sum()).is_equal(0)


func test_keep_item_writes_at_the_occupied_count() -> void:
	## A claimed gap is not refilled in place: the next item lands at index `sum`.
	var book := _book(["net", "axe", "shovel"])
	var inv := Inventory.new()
	book.claim_result(0, inv)
	assert_bool(book.keep_item(&"fishing_rod")).is_true()
	assert_that(book.item_at(0)).is_equal(&"")
	assert_that(book.item_at(1)).is_equal(&"axe")
	assert_that(book.item_at(2)).is_equal(&"fishing_rod")


func test_keep_item_full_drops_the_oldest() -> void:
	var book := PoliceBook.new()
	for i: int in PoliceBook.STORAGE_COUNT:
		book.keep_item(&"net" if i == 0 else &"axe")
	assert_bool(book.keep_item(&"shovel")).is_true()
	assert_int(book.keep_item_sum()).is_equal(PoliceBook.STORAGE_COUNT)
	assert_that(book.item_at(0)).is_equal(&"axe")
	assert_that(book.item_at(PoliceBook.STORAGE_COUNT - 1)).is_equal(&"shovel")


func test_keep_item_rejects_non_items() -> void:
	var book := PoliceBook.new()
	assert_bool(book.keep_item(&"")).is_false()
	assert_bool(book.keep_item(&"not_a_real_item")).is_false()
	assert_int(book.keep_item_sum()).is_equal(0)


func test_copy_item_buf_packs_on_exit() -> void:
	var book := _book(["net", "axe", "shovel", "fishing_rod"])
	var inv := Inventory.new()
	book.claim_result(1, inv)
	book.claim_result(2, inv)
	book.copy_item_buf()
	assert_that(book.item_at(0)).is_equal(&"net")
	assert_that(book.item_at(1)).is_equal(&"fishing_rod")
	assert_that(book.item_at(2)).is_equal(&"")


func test_claim_goes_into_an_empty_pocket_not_a_stack() -> void:
	## `mPlib_Get_space_putin_item`: the whole item takes a free pocket.
	var book := _book(["paper"])
	var inv := Inventory.new()
	var paper: ItemData = ItemCatalog.get_item(&"paper")
	inv.add(paper, 1)
	assert_int(book.claim_result(0, inv)).is_equal(PoliceBook.Claim.OK)
	assert_int(inv.count_of_occupied()).is_equal(2)
	## Stationery is kept as a 4-sheet pad.
	assert_int(inv.count_of(&"paper")).is_equal(1 + ShopGoods.PAPER_PACK)


func test_claim_with_full_pockets_keeps_the_item() -> void:
	var book := _book(["net"])
	var inv := Inventory.new()
	var axe: ItemData = ItemCatalog.get_item(&"axe")
	for _i: int in Inventory.POCKET_SLOTS:
		inv.add(axe, 1)
	assert_int(book.claim_result(0, inv)).is_equal(PoliceBook.Claim.POCKETS_FULL)
	assert_that(book.item_at(0)).is_equal(&"net")


func test_claim_ticket_stacks_on_a_ticket() -> void:
	## `mPlib_Get_space_putin_item_forTICKET`.
	var book := _book(["ticket_01"])
	var inv := Inventory.new()
	var axe: ItemData = ItemCatalog.get_item(&"axe")
	inv.add(ItemCatalog.get_item(&"ticket_01"), 1)
	for _i: int in Inventory.POCKET_SLOTS - 1:
		inv.add(axe, 1)
	assert_int(book.claim_result(0, inv)).is_equal(PoliceBook.Claim.OK)
	assert_int(inv.count_of(&"ticket_01")).is_equal(2)


func test_keep_all_items_takes_keepables_and_drops_oldest() -> void:
	## `mPB_keep_all_item_in_block`.
	var book := PoliceBook.new()
	for _i: int in 18:
		book.keep_item(&"net")
	var acre: Array[StringName] = [&"axe", &"", &"shovel", &"not_a_real_item", &"fishing_rod"]
	var taken: Array[StringName] = book.keep_all_items(acre)
	assert_array(taken).contains_exactly([&"axe", &"shovel", &"fishing_rod"])
	assert_int(book.keep_item_sum()).is_equal(PoliceBook.STORAGE_COUNT)
	assert_that(book.item_at(17)).is_equal(&"axe")
	assert_that(book.item_at(18)).is_equal(&"shovel")
	assert_that(book.item_at(19)).is_equal(&"fishing_rod")


func test_force_set_only_grows_small_boxes() -> void:
	## `mPB_MAX_GROW_SIZE`: more than five kept → never adds.
	var book := PoliceBook.new()
	for _i: int in 6:
		book.keep_item(&"net")
	for _i: int in 50:
		book.force_set_keep_item()
	assert_int(book.keep_item_sum()).is_equal(6)
	## Five or fewer: the coin flip adds one about half the time.
	var small := PoliceBook.new()
	small.rng.seed = 3
	var adds := 0
	for _i: int in 40:
		if small.force_set_keep_item():
			adds += 1
		small.clear()
	assert_int(adds).is_between(8, 32)


func test_force_set_category_tables() -> void:
	## `roll <= prob_table[i]`: goods 0–85, tool 86–90, flower 91–95, umbrella 96–99.
	assert_int(PoliceBook.pick_bucket(PoliceBook.CATEGORY_PROB, 0)).is_equal(PoliceBook.CATEGORY_GOODS)
	assert_int(PoliceBook.pick_bucket(PoliceBook.CATEGORY_PROB, 85)).is_equal(PoliceBook.CATEGORY_GOODS)
	assert_int(PoliceBook.pick_bucket(PoliceBook.CATEGORY_PROB, 86)).is_equal(PoliceBook.CATEGORY_ITEM)
	assert_int(PoliceBook.pick_bucket(PoliceBook.CATEGORY_PROB, 91)).is_equal(PoliceBook.CATEGORY_FLOWER)
	assert_int(PoliceBook.pick_bucket(PoliceBook.CATEGORY_PROB, 96)).is_equal(PoliceBook.CATEGORY_UMBRELLA)
	assert_int(PoliceBook.pick_bucket(PoliceBook.GOODS_PROB, 35)).is_equal(0)
	assert_int(PoliceBook.pick_bucket(PoliceBook.GOODS_PROB, 36)).is_equal(1)
	assert_int(PoliceBook.pick_bucket(PoliceBook.GOODS_PROB, 89)).is_equal(3)
	assert_int(PoliceBook.pick_bucket(PoliceBook.GOODS_PROB, 99)).is_equal(4)


func test_random_grow_items_are_real_items() -> void:
	var book := PoliceBook.new()
	book.rng.seed = 11
	for _i: int in 200:
		var id: StringName = book.random_grow_item()
		if id == &"":
			continue
		assert_object(ItemCatalog.get_item(id)).is_not_null()
	## The flower roll never reaches the ninth bag.
	assert_int(PoliceBook.GROW_FLOWER_BAG_COUNT).is_equal(8)


func test_renew_tops_up_once_per_renewal() -> void:
	Game.police.clear()
	Game.police.rng.seed = 5
	var before: int = Game.police.keep_item_sum()
	Game._on_field_renewed(30)
	assert_int(Game.police.keep_item_sum() - before).is_less_equal(1)


func test_legacy_save_without_police_inits() -> void:
	var snap: Dictionary = Game.to_save()
	snap.erase("police")
	Game.police.clear()
	Game.apply_snapshot(snap)
	assert_int(Game.police.keep_item_sum()).is_equal(3)


# --- Layout (`FG_TYPE_POLICE_INDOOR`, `bg_police_item`) --------------------------------


func test_rsv_cells_read_from_the_fg_template() -> void:
	var items := PackedInt32Array()
	items.resize(FgCatalog.ITEMS_PER_ACRE)
	for slot: int in PoliceBook.STORAGE_COUNT:
		## Put slot N at unit (N % 8 + 1, N / 8 * 2 + 1), in reverse scan order.
		var cell := Vector2i(slot % 8 + 1, slot / 8 * 2 + 1)
		items[cell.y * 16 + cell.x] = PoliceDisplay.RSV_POLICE_ITEM_0 + slot
	var cells: Array[Vector2i] = PoliceDisplay.cells_from_fg(items)
	assert_int(cells.size()).is_equal(PoliceBook.STORAGE_COUNT)
	assert_that(cells[0]).is_equal(Vector2i(1, 1))
	assert_that(cells[9]).is_equal(Vector2i(2, 3))
	## Missing any slot → fall back to the authored table.
	items[1 * 16 + 1] = 0
	assert_int(PoliceDisplay.cells_from_fg(items).size()).is_equal(0)


func test_lost_found_cells_have_twenty_slots() -> void:
	assert_int(PoliceDisplay.lost_found_cells().size()).is_equal(PoliceBook.STORAGE_COUNT)
	assert_vector(PoliceDisplay.unit_center_gx(Vector2i(4, 6))).is_equal(PoliceDisplay.BOOKER_STAND_GX)


func test_presenter_places_one_card_per_kept_item() -> void:
	Game.police.clear()
	Game.police.keep_item(&"net")
	Game.police.keep_item(&"axe")
	var room: Room = InteriorCatalog.room_template(&"police_box")
	var session := IndoorSession.new()
	session.bind(room)
	var root := Node3D.new()
	auto_free(root)
	add_child(root)
	PolicePresenter.new().present(root, session)
	assert_object(root.get_node_or_null("LostFound_0")).is_not_null()
	assert_object(root.get_node_or_null("LostFound_1")).is_not_null()
	assert_object(root.get_node_or_null("LostFound_2")).is_null()
	assert_object(root.get_node_or_null("Booker")).is_not_null()
	assert_object(root.get_node_or_null("SunshineL")).is_not_null()
	assert_object(root.get_node_or_null("SunshineR")).is_not_null()
	var card: Node3D = root.get_node("LostFound_1") as Node3D
	var want: Vector3 = PoliceDisplay.gx_to_world(
		session.grid, PoliceDisplay.unit_center_gx(PoliceDisplay.cell_for_slot(1))
	)
	assert_float(card.position.x).is_equal_approx(want.x, 0.001)
	assert_float(card.position.z).is_equal_approx(want.z, 0.001)


func test_raised_units_are_the_shelves_desk_and_locker() -> void:
	var raised: Dictionary = PoliceDisplay.raised_units()
	if raised.is_empty():
		return  ## `police_indoor.col.json` not generated (no disc)
	## Every lost-and-found unit sits on a shelf 20 GX above the floor.
	for cell: Vector2i in PoliceDisplay.lost_found_cells():
		assert_float(float(raised.get(cell, 0.0))).is_equal(20.0)
	## Walkways between the shelf rows stay flat.
	assert_bool(raised.has(Vector2i(4, 2))).is_false()
	assert_bool(raised.has(PoliceDisplay.BOOKER_STAND_UT)).is_false()


func test_presenter_adds_shelf_hulls_and_clock() -> void:
	if PoliceDisplay.raised_units().is_empty():
		return
	var room: Room = InteriorCatalog.room_template(&"police_box")
	var session := IndoorSession.new()
	session.bind(room)
	var root := Node3D.new()
	auto_free(root)
	add_child(root)
	PolicePresenter.new().present(root, session)
	var col: StaticBody3D = root.get_node_or_null("PoliceFurnitureCol") as StaticBody3D
	assert_object(col).is_not_null()
	## Back shelf row: one 8-unit hull, 1 m tall.
	var back: BoxShape3D = (col.get_child(0) as CollisionShape3D).shape as BoxShape3D
	assert_vector(back.size).is_equal(Vector3(16.0, 1.0, 2.0))
	if not FieldCatalog.mesh_paths(PoliceDisplay.CLOCK_VISUAL).is_empty():
		assert_object(root.get_node_or_null("PoliceClock")).is_not_null()


# --- Booker (`ac_npc_police2`) ----------------------------------------------------------


func test_booker_zone_grid() -> void:
	## `aPOL2_get_zone`: uz clamps to 2…6; ux splits at >1 / >4 / >7.
	assert_int(PoliceDisplay.zone_for_gx(Vector3(20.0, 0.0, 20.0))).is_equal(0)
	assert_int(PoliceDisplay.zone_for_gx(Vector3(100.0, 0.0, 100.0))).is_equal(1)
	assert_int(PoliceDisplay.zone_for_gx(Vector3(220.0, 0.0, 140.0))).is_equal(6)
	assert_int(PoliceDisplay.zone_for_gx(Vector3(340.0, 0.0, 380.0))).is_equal(19)
	assert_int(PoliceDisplay.zone_for_gx(PoliceDisplay.BOOKER_STAND_GX)).is_equal(17)
	assert_vector(PoliceDisplay.zone_waypoint_gx(19)).is_equal(Vector3(340.0, 0.0, 300.0))


func test_booker_next_zone_routes_round_shelves() -> void:
	## Open rows (0/2/4): same row → step toward the player's column.
	assert_int(PoliceDisplay.next_zone(3, 0)).is_equal(1)
	## Two rows away from a middle column: step out to the nearer side aisle first.
	assert_int(PoliceDisplay.next_zone(9, 1)).is_equal(0)
	assert_int(PoliceDisplay.next_zone(10, 2)).is_equal(3)
	## Side aisle: walk straight down/up.
	assert_int(PoliceDisplay.next_zone(16, 0)).is_equal(4)
	## Shelf rows (1/3): a different row moves along z from the aisles.
	assert_int(PoliceDisplay.next_zone(0, 4)).is_equal(0)
	## Same shelf row, other column: the coin picks this row or the next.
	assert_int(PoliceDisplay.next_zone(7, 5, 0)).is_equal(5)
	assert_int(PoliceDisplay.next_zone(7, 5, 1)).is_equal(9)
	## Adjacent row, open row source: sideways toward the target column.
	assert_int(PoliceDisplay.next_zone(6, 9)).is_equal(10)


func test_booker_talk_messages() -> void:
	assert_int(PoliceTalk.greet_msg(0)).is_equal(0x0784)
	assert_int(PoliceTalk.greet_msg(3)).is_equal(0x0785)
	assert_int(PoliceTalk.talk_msg(2, false)).is_equal(0x077D)
	assert_int(PoliceTalk.talk_msg(0, false)).is_equal(0x0786)
	assert_int(PoliceTalk.talk_msg(0, true)).is_equal(0x0787)
	assert_str(PoliceTalk.with_article("Axe")).is_equal("an Axe")
	assert_str(PoliceTalk.with_article("Net")).is_equal("a Net")


func test_booker_talk_graph_plays_each_message() -> void:
	for msg: int in PoliceTalk.MSG_KEYS.keys():
		var ctx := DialogueContext.new()
		ctx.item0 = "a Net"
		var data: DialogueData = PoliceTalk.conversation(msg, ctx)
		assert_object(data).is_not_null()
		if String(data.id).begins_with("msg_"):
			continue
		var runner := DialogueRunner.new()
		runner.start(data, ctx)
		assert_bool(runner.line.is_empty()).is_false()


func test_booker_claim_event_moves_item_to_pockets() -> void:
	Game.police.clear()
	Game.police.keep_item(&"net")
	Game.inventory.clear()
	var ctx := DialogueContext.new()
	PoliceTalk.fill_claim(ctx, &"net")
	var data: DialogueData = PoliceTalk.conversation(PoliceTalk.MSG_CLAIM, ctx)
	var runner := DialogueRunner.new()
	runner.event_fired.connect(func(event: Dictionary) -> void: PoliceTalk.apply_event(event, ctx, 0))
	runner.start(data, ctx)
	assert_bool(runner.waiting_choice).is_true()
	assert_str(runner.line).contains("a Net")
	runner.choose(0)
	assert_int(Game.inventory.count_of(&"net")).is_equal(1)
	assert_that(Game.police.item_at(0)).is_equal(&"")
	assert_str(str(ctx.get_var(PoliceTalk.VAR_CLAIM, ""))).is_equal("ok")


func test_booker_claim_full_pockets_line() -> void:
	Game.police.clear()
	Game.police.keep_item(&"net")
	Game.inventory.clear()
	var axe: ItemData = ItemCatalog.get_item(&"axe")
	for _i: int in Inventory.POCKET_SLOTS:
		Game.inventory.add(axe, 1)
	var ctx := DialogueContext.new()
	PoliceTalk.fill_claim(ctx, &"net")
	var runner := DialogueRunner.new()
	runner.event_fired.connect(func(event: Dictionary) -> void: PoliceTalk.apply_event(event, ctx, 0))
	runner.start(PoliceTalk.conversation(PoliceTalk.MSG_CLAIM, ctx), ctx)
	runner.choose(0)
	assert_str(str(ctx.get_var(PoliceTalk.VAR_CLAIM, ""))).is_equal("full")
	assert_that(Game.police.item_at(0)).is_equal(&"net")


func test_booker_scene_is_a_character_waiting_outside_the_room() -> void:
	var packed: PackedScene = load("res://scenes/world/interiors/booker.tscn") as PackedScene
	var booker: Node = packed.instantiate()
	auto_free(booker)
	add_child(booker)
	assert_bool(booker is CharacterBody3D).is_true()
	## Not entered through the door (no live room) → WAIT, not GREET.
	assert_int(int(booker.get("act"))).is_equal(1)


# --- Window sunshine (`ef_room_sunshine_police`) ---------------------------------------


func test_sunshine_alpha_curve() -> void:
	assert_int(PoliceDisplay.sunshine_alpha(0)).is_equal(120)
	assert_int(PoliceDisplay.sunshine_alpha(43200)).is_equal(255)
	assert_int(PoliceDisplay.sunshine_alpha(43200, true)).is_equal(153)
	assert_int(PoliceDisplay.sunshine_alpha(14400)).is_equal(0)
	assert_int(PoliceDisplay.sunshine_alpha(72000)).is_equal(0)


func test_sunshine_beams_switch_windows() -> void:
	## Right (east) window in the morning, left (west) in the afternoon.
	assert_float(PoliceDisplay.sunshine_left_x(9 * 3600)).is_equal(0.0)
	assert_float(PoliceDisplay.sunshine_right_x(9 * 3600)).is_less(0.0)
	assert_float(PoliceDisplay.sunshine_right_x(15 * 3600)).is_equal(0.0)
	assert_float(PoliceDisplay.sunshine_left_x(15 * 3600)).is_greater(0.0)
	## Full stretch 1.5 as the beam flattens out at the ends of the span.
	assert_float(PoliceDisplay.sunshine_left_x(72000 - 1)).is_equal_approx(1.5, 0.001)
	assert_float(PoliceDisplay.sunshine_right_x(14400)).is_equal_approx(-1.5, 0.001)
	assert_float(PoliceDisplay.sunshine_left_x(43200)).is_equal(0.0)


func test_window_light_only_in_daytime() -> void:
	assert_float(PoliceDisplay.window_light_target(3 * 3600)).is_equal(0.0)
	assert_float(PoliceDisplay.window_light_target(9 * 3600)).is_equal(1.0)
	assert_float(PoliceDisplay.window_light_target(19 * 3600)).is_equal(0.0)
	## The noon blink and the wrapped `s16` blink at 05:47:44.
	assert_float(PoliceDisplay.window_light_target(43200 + 60)).is_equal(0.0)
	assert_float(PoliceDisplay.window_light_target(20864)).is_equal(0.0)
	assert_float(PoliceDisplay.window_light_target(20864 + 200)).is_equal(1.0)


func test_sunshine_anchor_offsets() -> void:
	assert_vector(PoliceDisplay.sunshine_anchor_gx(PoliceDisplay.SUNSHINE_L_GX, true)).is_equal(
		Vector3(38.0, -39.0, 200.0)
	)
	assert_vector(PoliceDisplay.sunshine_anchor_gx(PoliceDisplay.SUNSHINE_R_GX, false)).is_equal(
		Vector3(360.0, -39.0, 200.0)
	)


# --- Copper (`ac_npc_police`) -----------------------------------------------------------


func test_copper_time_of_day_menu() -> void:
	assert_int(CopperTalk.time_index(3)).is_equal(3)
	assert_int(CopperTalk.time_index(5)).is_equal(0)
	assert_int(CopperTalk.time_index(12)).is_equal(1)
	assert_int(CopperTalk.time_index(17)).is_equal(2)


func test_copper_event_hint() -> void:
	var events := EventCalendar.new()
	assert_int(int(CopperTalk.hint(events, true, 5, 1, 12)["msg"])).is_equal(0x2C2D)
	assert_int(int(CopperTalk.hint(events, false, 5, 1, 12)["msg"])).is_equal(0x2C37)
	events.special_type = &"artist"
	events.special_dates["special1"] = EventDates.md(5, 10)
	events.special_dates["special3"] = 6
	assert_int(CopperTalk.special_state(events, 5, 1, 12)).is_equal(CopperTalk.Special.LATER)
	assert_int(int(CopperTalk.hint(events, false, 5, 1, 12)["msg"])).is_equal(0x2C2A)
	assert_int(CopperTalk.special_state(events, 5, 10, 3)).is_equal(CopperTalk.Special.TODAY)
	assert_int(int(CopperTalk.hint(events, false, 5, 10, 3)["msg"])).is_equal(0x2C34)
	events.special_type = &"shop_sale"
	events.special_dates["special3"] = 14
	assert_int(CopperTalk.special_state(events, 5, 10, 14)).is_equal(CopperTalk.Special.ACTIVE)
	assert_int(int(CopperTalk.hint(events, false, 5, 10, 14)["msg"])).is_equal(0x2C21)


func test_copper_talk_graph() -> void:
	for entry: String in ["exit", "menu"]:
		var ctx := DialogueContext.new()
		ctx.hour = 12
		CopperTalk.fill(ctx, entry == "exit")
		var data: DialogueData = DialogueCatalog.conversation(CopperTalk.CONVERSATION_ID)
		var runner := DialogueRunner.new()
		runner.start(data, ctx)
		assert_bool(runner.line.is_empty()).is_false()
		if entry == "menu":
			assert_bool(runner.waiting_choice).is_true()
			runner.choose(1)
			assert_str(runner.line).contains(str(Game.police.keep_item_sum()))


func test_copper_stands_two_units_east_of_the_station() -> void:
	var data: WorldData = WorldGenerator.generate(WorldGenerator.DEFAULT_SEED)
	var police: BuildingPlacement = null
	for b: BuildingPlacement in data.buildings:
		if b != null and b.id == &"police":
			police = b
	assert_object(police).is_not_null()
	var copper: ObjectPlacement = null
	for o: ObjectPlacement in data.objects:
		if o != null and o.kind == &"copper":
			copper = o
	assert_object(copper).is_not_null()
	assert_that(copper.cell).is_equal(StructureOffset.police_home_cell(police) + Vector2i(2, 0))
