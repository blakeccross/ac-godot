class_name TestHandOver
extends GdUnitTestSuite

## Give / receive clip wiring for first-job hand-offs.


func test_clip_constants() -> void:
	assert_str(HandOver.NPC_TRANSFER).is_equal("npc_1_transfer1")
	assert_str(HandOver.PLY_GET_PULL).is_equal("ply_1_get_pull1")
	assert_str(HandOver.PLY_TRANSFER).is_equal("ply_1_transfer1")


func test_gift_display_ids() -> void:
	var job := FirstJob.new()
	job.setup_change_cloth()
	assert_that(job.gift_display_item()).is_equal(FirstJob.UNIFORM_ID)
	job.setup_plant_flower()
	assert_that(job.gift_display_item()).is_equal(&"flower")
	Game.villagers.get_or_create(&"filbert")
	assert_bool(job.setup_deliver_furniture(Game.inventory)).is_true()
	assert_that(job.gift_display_item()).is_equal(FirstJob.FURNITURE_ID)


func test_resolve_finds_baked_clips() -> void:
	## Smoke-check that GeneratedVisual can see transfer/get on baked meshes.
	var nook := Node3D.new()
	add_child(nook)
	var vis: Node3D = GeneratedVisual.attach_villager(nook, &"rcn")
	assert_that(vis).is_not_null()
	assert_bool(HandOver.has_npc_transfer(nook)).is_true()
	nook.queue_free()
