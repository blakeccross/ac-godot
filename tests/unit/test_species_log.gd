class_name TestSpeciesLog
extends GdUnitTestSuite

## `SpeciesLog` (`mIV_set_collect_itemNo` "obtained once" bitfield) + the encyclopedia
## catalog order/icons for the pockets submenu.


func test_records_only_known_species_once() -> void:
	var log := SpeciesLog.new()
	assert_bool(log.record(&"koi")).is_true()
	assert_bool(log.record(&"koi")).is_false()
	assert_bool(log.has(&"koi")).is_true()
	## Not a fish or bug — ignored.
	assert_bool(log.record(&"axe")).is_false()
	assert_bool(log.has(&"axe")).is_false()


func test_page_counts_split_fish_and_insect() -> void:
	var log := SpeciesLog.new()
	log.record(&"koi")
	log.record(&"sea_bass")
	log.record(&"firefly")
	assert_int(log.page_count(&"fish")).is_equal(2)
	assert_int(log.page_count(&"insect")).is_equal(1)
	assert_int(log.page_total(&"fish")).is_equal(40)
	assert_int(log.page_total(&"insect")).is_equal(40)


func test_save_round_trips() -> void:
	var log := SpeciesLog.new()
	log.record(&"koi")
	log.record(&"mantis")
	var restored := SpeciesLog.new()
	restored.apply_snapshot(log.to_save())
	assert_bool(restored.has(&"koi")).is_true()
	assert_bool(restored.has(&"mantis")).is_true()
	assert_int(restored.page_count(&"fish")).is_equal(1)


func test_catalog_order_matches_decomp_head() -> void:
	## `mIV_fish_collect_list` / `mIV_insect_collect_list` first + last entries.
	assert_int(EncyclopediaCatalog.FISH.size()).is_equal(40)
	assert_int(EncyclopediaCatalog.INSECT.size()).is_equal(40)
	assert_str(EncyclopediaCatalog.id_for(&"fish", 0)).is_equal("crucian_carp")
	assert_str(EncyclopediaCatalog.id_for(&"fish", 39)).is_equal("arapaima")
	assert_str(EncyclopediaCatalog.id_for(&"insect", 0)).is_equal("common_butterfly")
	assert_str(EncyclopediaCatalog.id_for(&"insect", 39)).is_equal("bagworm")
	assert_str(EncyclopediaCatalog.icon_for(&"fish", 0)).is_equal("inv_mwin_01funa_tex")
	assert_str(EncyclopediaCatalog.kind_of(&"koi")).is_equal("fish")
	assert_str(EncyclopediaCatalog.kind_of(&"mantis")).is_equal("insect")
	assert_str(EncyclopediaCatalog.kind_of(&"axe")).is_equal("")


func test_every_catalog_id_and_icon_resolves() -> void:
	var seen: Dictionary = {}
	for kind: StringName in [&"fish", &"insect"]:
		for row: Dictionary in EncyclopediaCatalog.page(kind):
			var id: String = String(row["id"])
			assert_bool(ResourceLoader.exists("res://data/creatures/%s.tres" % id)).override_failure_message(
				"missing creature: %s" % id
			).is_true()
			assert_bool(seen.has(id)).override_failure_message("duplicate id %s" % id).is_false()
			seen[id] = true
			assert_bool(InventoryChrome.load_tex(String(row["icon"])) != null).override_failure_message(
				"missing icon: %s" % row["icon"]
			).is_true()


func test_catch_registers_in_species_log() -> void:
	Game.species_log.clear()
	var koi: ItemData = load("res://data/creatures/koi.tres")
	Game.inventory.add(koi, 1)
	assert_bool(Game.species_log.has(&"koi")).is_true()
	Game.species_log.clear()
