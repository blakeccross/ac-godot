class_name TestHandOver
extends GdUnitTestSuite

## Give / receive clip wiring for first-job hand-offs.


func test_clip_constants() -> void:
	assert_str(HandOver.NPC_TRANSFER).is_equal("npc_1_transfer1")
	assert_str(HandOver.PLY_GET_PULL).is_equal("ply_1_get_pull1")
	assert_str(HandOver.PLY_TRANSFER).is_equal("ply_1_transfer1")
	assert_str(HandOver.NPC_GET_RETURN).is_equal("npc_1_get_return1")
	assert_str(HandOver.NPC_GET_PULL_WAIT).is_equal("npc_1_get_pull_wait1")


func test_gift_display_ids() -> void:
	var job := FirstJob.new()
	job.setup_change_cloth()
	assert_that(job.gift_display_item()).is_equal(FirstJob.UNIFORM_ID)
	job.setup_plant_flower()
	assert_that(job.gift_display_item()).is_equal(&"flower")
	Game.villagers.get_or_create(&"filbert")
	assert_bool(job.setup_deliver_furniture(Game.inventory)).is_true()
	assert_that(job.gift_display_item()).is_equal(FirstJob.FURNITURE_ID)


func test_hand_over_visuals() -> void:
	## Same `obj_item_*` cards `handOverItem` / `mNT_get_itemTableNo` draw.
	assert_that(HandOverItem.visual_for(FirstJob.UNIFORM_ID)).is_equal(&"obj_item_cloth")
	assert_that(HandOverItem.visual_for(&"flower")).is_equal(&"obj_item_seed")
	assert_that(HandOverItem.visual_for(FirstJob.FURNITURE_ID)).is_equal(&"obj_item_leaf")
	assert_that(HandOverItem.visual_for(FirstJob.PAPER_ID)).is_equal(&"obj_item_paper")
	assert_that(HandOverItem.visual_for(FirstJob.CARPET_ID)).is_equal(&"obj_item_carpet")
	assert_that(HandOverItem.visual_for(FirstJob.AXE_ID)).is_equal(&"obj_item_axe")
	assert_bool(FieldCatalog.mesh_paths(&"obj_item_leaf").is_empty()).is_false()
	assert_bool(FieldCatalog.mesh_paths(&"obj_item_cloth").is_empty()).is_false()


func test_transfer_scale_keys() -> void:
	## Hidden until frame 17, full size by frame 35 (`aHOI_calc_scale` transfer).
	assert_float(HandOverItem._lerp_scale(HandOverItem.TRANSFER_SCALE, 0.0)).is_equal_approx(0.0, 0.001)
	assert_float(HandOverItem._lerp_scale(HandOverItem.TRANSFER_SCALE, 17.0)).is_equal_approx(0.0, 0.001)
	assert_float(HandOverItem._lerp_scale(HandOverItem.TRANSFER_SCALE, 35.0)).is_equal_approx(1.0, 0.001)
	assert_float(HandOverItem._lerp_scale(HandOverItem.PUTAWAY_SCALE, 13.0)).is_equal_approx(0.0, 0.001)
	var mid: Vector3 = HandOverItem._lerp_pos(HandOverItem.TRANSFER_KEYS, 24.0)
	assert_float(mid.x).is_greater(9.0)
	assert_float(mid.x).is_less(14.0)


func test_resolve_finds_baked_clips() -> void:
	## Smoke-check that GeneratedVisual can see transfer/get on baked meshes.
	var nook := Node3D.new()
	add_child(nook)
	var vis: Node3D = GeneratedVisual.attach_villager(nook, &"rcn")
	assert_that(vis).is_not_null()
	assert_bool(HandOver.has_npc_transfer(nook)).is_true()
	## `aCR_TALK_RETURN_DEMO_*` (Blathers un-taking a rejected item) resolves too, along
	## with the examining hold (`default_animation = aNPC_ANIM_GET_PULL_WAIT1`).
	var clips: PackedStringArray = VisualAnimation.find_animation_player(nook).get_animation_list()
	var has_get_return := false
	var has_get_pull_wait := false
	for clip: String in clips:
		if clip.ends_with(HandOver.NPC_GET_RETURN):
			has_get_return = true
		if clip.ends_with(HandOver.NPC_GET_PULL_WAIT):
			has_get_pull_wait = true
	assert_bool(has_get_return).is_true()
	assert_bool(has_get_pull_wait).is_true()
	nook.queue_free()
