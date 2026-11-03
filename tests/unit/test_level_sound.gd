class_name TestLevelSound
extends GdUnitTestSuite

## A held level SE (`sAdo_OngenPos`) that its host can switch off between claps.


func test_a_quiet_source_stays_stopped() -> void:
	var host: Node3D = auto_free(Node3D.new())
	add_child(host)
	var sound := preload("res://scenes/world/level_sound.tscn").instantiate() as LevelSound
	sound.level_id = 0x2F
	sound.sounding = false
	host.add_child(sound)
	sound._process(0.016)
	assert_bool(sound.playing).is_false()


func test_clap_levels_are_rendered_when_the_pipeline_has_run() -> void:
	if not SeCatalog.has_id(&"lev_2f"):
		return
	assert_that(SeCatalog.stream_for(&"lev_2f")).is_not_null()
	assert_that(SeCatalog.stream_for(&"lev_31")).is_not_null()
