class_name TestFurnitureOneLiner
extends GdUnitTestSuite


func before_test() -> void:
	ItemCatalog.reload()


func test_the_three_pieces_speak() -> void:
	for visual: StringName in FurnitureOneLiner.LINES:
		var data: FurnitureData = ItemCatalog.furniture_for_visual(visual)
		assert_that(data).is_not_null()
		assert_bool(FurnitureOneLiner.has(data)).is_true()


func test_ordinary_furniture_stays_quiet() -> void:
	var chair: FurnitureData = ItemCatalog.get_item(&"wood_chair") as FurnitureData
	assert_bool(FurnitureOneLiner.has(chair)).is_false()
	assert_bool(FurnitureOneLiner.has(null)).is_false()


func test_each_line_is_a_real_message() -> void:
	for visual: StringName in FurnitureOneLiner.LINES:
		var msg: int = int(FurnitureOneLiner.LINES[visual]["msg"])
		assert_that(DialogueCatalog.conversation(StringName("msg_%d" % msg))).is_not_null()


func test_a_tap_offers_a_use_verb() -> void:
	var script := GDScript.new()
	script.source_code = "extends Node\nvar data\nvar occupant_id: StringName = &\"\"\n"
	script.reload()
	var host := Node.new()
	host.set_script(script)
	host.set("data", ItemCatalog.furniture_for_visual(&"int_ike_k_otome01"))
	var offers: Array[Interaction] = FurnitureUse.actions(host, null)
	assert_bool(offers.any(func(a: Interaction) -> bool: return a.id == Interaction.TOGGLE)).is_true()
	assert_int(offers.filter(func(a: Interaction) -> bool: return a.id == Interaction.TOGGLE).size()).is_equal(1)
	host.free()
