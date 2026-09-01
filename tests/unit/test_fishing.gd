class_name TestFishing
extends GdUnitTestSuite

## Cast → float → nibble → bite → hook. The bite comes from a real `FishShadow` finding the
## bobber, so these drive shadows rather than winding a timer forward.


class _FacingActor extends Node3D:
	var yaw: float = 0.0

	func facing_yaw() -> float:
		return yaw


class _GridWorld extends Node:
	var grid: WorldGrid = WorldGrid.new()
	var fish: FishSchool = FishSchool.new()


## Long enough for five nibbles at the slowest size, short enough to fail a stuck shadow.
const DRIVE_CAP := 30.0
const STEP := 1.0 / 60.0

var _heard: Array[String] = []


func before_test() -> void:
	Game.reset_session()
	ItemCatalog.reload()
	FishCatalog.reload()
	FishCatalog.seed_rng(1)
	Clock.reset_to_default()
	Clock.paused = true
	Clock.month = 6
	Clock.hour = 10
	_heard.clear()
	Game.notice_posted.connect(_on_notice)


func after_test() -> void:
	Game.notice_posted.disconnect(_on_notice)
	Fishing.reset()
	Game.reset_session()
	Clock.reset_to_default()
	Clock.paused = false


func _on_notice(text: String) -> void:
	_heard.append(text)


func test_catalog_loads_fish_and_filters_windows() -> void:
	var carp: FishData = FishCatalog.get_fish(&"crucian_carp")
	var bluegill: FishData = FishCatalog.get_fish(&"bluegill")
	assert_that(carp).is_not_null()
	assert_that(bluegill).is_not_null()
	assert_int(FishCatalog.all_fish().size()).is_greater(2)
	## Noon in June: the all-slot crucian carp is in, and so is the day-only bluegill.
	var noon: Array[FishData] = FishCatalog.available(6, 12)
	assert_bool(noon.has(carp)).is_true()
	assert_bool(noon.has(bluegill)).is_true()
	## 10pm is the NIGHT slot, which the bluegill does not hold.
	assert_bool(FishCatalog.available(6, 22).has(bluegill)).is_false()
	assert_bool(FishCatalog.available(6, 22).has(carp)).is_true()
	## Out of month, even in the right slot: salmon only run in September.
	assert_bool(FishCatalog.available(1, 23).has(FishCatalog.get_fish(&"salmon"))).is_false()
	assert_bool(FishCatalog.available(9, 23).has(FishCatalog.get_fish(&"salmon"))).is_true()


func test_fish_resolve_through_item_catalog() -> void:
	var fish: ItemData = ItemCatalog.get_item(&"crucian_carp")
	assert_that(fish).is_not_null()
	assert_that(fish.category).is_equal(ItemData.Category.FISH)
	assert_int(fish.sell_price).is_greater(0)


func test_roll_only_returns_available_fish() -> void:
	var pool: Array[FishData] = FishCatalog.available(6, 12)
	for _i: int in 40:
		var picked: FishData = FishCatalog.roll(pool)
		assert_bool(pool.has(picked)).is_true()
	var empty: Array[FishData] = []
	assert_object(FishCatalog.roll(empty)).is_null()


func test_cast_needs_water_and_arcs_before_it_floats() -> void:
	var ctx: InteractionContext = _at_water()
	assert_bool(Fishing.is_active()).is_false()
	var action: Interaction = ToolUse.field_action(ctx)
	assert_str(String(action.id)).is_equal(String(Interaction.CAST))
	assert_bool(ToolUse.apply_field(action, ctx)).is_true()
	assert_bool(Fishing.is_active()).is_true()
	## `aUKI_STATUS_CAST`: the bobber is still in the air, so nothing can bite yet.
	assert_that(Fishing.state()).is_equal(Fishing.State.CAST)
	assert_float(Fishing.cast_progress()).is_less(1.0)
	assert_bool("You cast into the water." in _heard).is_true()
	_tick(ctx, Fishing.CAST_SECONDS + STEP)
	assert_that(Fishing.state()).is_equal(Fishing.State.FLOAT)
	assert_float(Fishing.cast_progress()).is_equal_approx(1.0, 0.001)


func test_cast_reaches_the_original_hundred_units() -> void:
	## `Player_actor_request_proc_index_fromReady_rod`: `sin_s(rot) * 100.0f`. A fixed 100 GX
	## along the facing, which is well past the cell in front of the player — casting used to
	## drop the bobber at the water's edge.
	assert_float(Fishing.CAST_METERS).is_equal_approx(5.0, 0.001)
	assert_float(Fishing.CAST_PROBE_METERS).is_equal_approx(0.5, 0.001)
	## Nothing may leash shorter than the cast, or the line would drop on landing.
	assert_float(Fishing.LEASH_METERS).is_greater(Fishing.CAST_METERS)

	var ctx: InteractionContext = _at_water()
	var actor: Node3D = ctx.actor as Node3D
	var start: Vector3 = actor.global_position
	_cast(ctx)
	var thrown: Vector3 = Fishing.anchor() - start
	assert_float(Vector2(thrown.x, thrown.z).length()).is_equal_approx(Fishing.CAST_METERS, 0.001)
	## Straight down the facing, not toward the nearest water.
	assert_float(thrown.z).is_greater(0.0)
	assert_float(absf(thrown.x)).is_less(0.001)


func test_cast_lands_partway_through_the_swing() -> void:
	## `cast_rod` gives the bobber its cast command on its first frame, and `ready_rod` gets
	## there at animation frame 10 — so the line is in the air while the swing is still going.
	## Waiting for the clip to end put the bobber and the swing on different beats.
	assert_float(Fishing.CAST_RELEASE_FRAME).is_equal(10.0)
	var ctx: InteractionContext = _at_water()
	var action: Interaction = ToolUse.field_action(ctx)
	assert_str(String(action.id)).is_equal(String(Interaction.CAST))
	assert_float(action.effect_frame).is_equal(Fishing.CAST_RELEASE_FRAME)

	## Everything else still lands when its clip is done.
	var shovel: ItemData = ItemCatalog.get_item(&"shovel")
	assert_int(ctx.inventory.add(shovel, 1)).is_equal(0)
	assert_bool(ctx.inventory.equip_slot(1)).is_true()
	var dig: Interaction = ToolUse.field_action(ctx)
	if dig != null:
		assert_float(dig.effect_frame).is_less(0.0)

	## And the release is genuinely inside the swing, not past the end of it.
	var player: Node3D = auto_free(load("res://scenes/actors/player.tscn").instantiate()) as Node3D
	add_child(player)
	await get_tree().process_frame
	var anim: AnimationPlayer = GeneratedVisual.find_animation_player(player)
	if anim == null:
		return
	var clip: String = player.call("_resolve_clip", "ply_1_sao_swing1")
	if clip.is_empty():
		return
	var length: float = anim.get_animation(clip).length
	assert_float(Fishing.CAST_RELEASE_FRAME / player.ANIM_FPS).is_less(length)


func test_show_off_pose_waits_for_the_catch_report() -> void:
	var overlay: CanvasLayer = (
		auto_free(load("res://scenes/ui/dialogue_overlay.tscn").instantiate()) as CanvasLayer
	)
	add_child(overlay)
	var player: Node3D = auto_free(load("res://scenes/actors/player.tscn").instantiate()) as Node3D
	add_child(player)
	await get_tree().process_frame
	var motor: PlayerLocomotion = player.get("_motor") as PlayerLocomotion
	var entry: float = PI * 0.75
	motor.facing = entry
	var beat := Fishing.ReelBeat.new(
		Fishing.REEL_SHOW,
		Fishing.ROD_LAND,
		true,
		Fishing.SHOW_HOLD_SECONDS,
		FishCatalog.get_fish(&"crucian_carp").catch_msg
	)
	player.call("_play_show", beat)

	var opened: bool = false
	for _i in 180:
		await get_tree().process_frame
		if bool(overlay.call("is_open")):
			opened = true
			break
	assert_bool(opened).override_failure_message(
		"the show-off pose never put the catch report on screen"
	).is_true()

	## The pose is still up: `notice_rod` holds `LockContinue` until the player advances, so
	## the facing must not snap back while the text is readable.
	for _i in 10:
		await get_tree().process_frame
	assert_bool(bool(overlay.call("is_open"))).is_true()
	assert_float(motor.facing).is_not_equal(entry)

	overlay.call("close")
	var restored: bool = false
	for _i in 60:
		await get_tree().process_frame
		if is_equal_approx(motor.facing, entry):
			restored = true
			break
	assert_bool(restored).override_failure_message(
		"dismissing the report left the player at %f instead of %f" % [motor.facing, entry]
	).is_true()


func test_cast_is_refused_away_from_water() -> void:
	var ctx: InteractionContext = _at_water()
	(ctx.actor as _FacingActor).yaw = -PI * 0.5
	assert_object(ToolUse.field_action(ctx)).is_null()
	assert_bool(Fishing.is_active()).is_false()


func test_line_survives_turning_away_and_offers_the_hook_verb() -> void:
	var ctx: InteractionContext = _at_water()
	_cast(ctx)
	(ctx.actor as _FacingActor).yaw = -PI * 0.5
	var action: Interaction = ToolUse.field_action(ctx)
	assert_that(action).is_not_null()
	assert_str(String(action.id)).is_equal(String(Interaction.HOOK))
	## The hook must resolve on the button frame, so it carries no player animation.
	assert_str(String(action.player_anim)).is_equal("")


func test_bobber_dips_on_a_nibble_before_the_fish_commits() -> void:
	var ctx: InteractionContext = _at_water()
	_cast(ctx)
	_settle(ctx)
	_stock(ctx, &"crucian_carp")
	## `aGTT_touch`: the fish plucks at the bobber before it takes it, so a nibble has to
	## land while the session is still floating rather than jumping straight to a bite.
	_drive_until(ctx, func() -> bool: return Fishing.nibble_count() > 0)
	assert_int(Fishing.nibble_count()).is_greater(0)
	assert_that(Fishing.state()).is_equal(Fishing.State.FLOAT)
	assert_float(Fishing.dip()).is_greater(0.0)


func test_hook_during_bite_lands_the_fish_that_bit() -> void:
	var ctx: InteractionContext = _at_water()
	_cast(ctx)
	_settle(ctx)
	var shadow: FishShadow = _stock(ctx, &"crucian_carp")
	_drive_until(ctx, func() -> bool: return Fishing.state() == Fishing.State.BITE)
	assert_that(Fishing.state()).is_equal(Fishing.State.BITE)
	var before: int = ctx.inventory.count_of_occupied()
	var out: Fishing.Outcome = Fishing.hook(ctx, _school(ctx))
	assert_bool(out.caught()).is_true()
	## The catch is the shadow that bit, not a fresh roll off the catalog.
	assert_that(out.fish).is_same(shadow.fish)
	assert_bool(Fishing.is_active()).is_false()
	assert_int(ctx.inventory.count_of(out.fish.id)).is_equal(1)
	assert_int(ctx.inventory.count_of_occupied()).is_equal(before + 1)


func test_hooking_with_nothing_on_the_line_yields_nothing() -> void:
	var ctx: InteractionContext = _at_water()
	_cast(ctx)
	_settle(ctx)
	var before: int = ctx.inventory.count_of_occupied()
	var out: Fishing.Outcome = Fishing.hook(ctx, _school(ctx))
	assert_bool(out.too_early).is_true()
	assert_object(out.fish).is_null()
	assert_bool(Fishing.is_active()).is_false()
	assert_int(ctx.inventory.count_of_occupied()).is_equal(before)


func test_missing_the_bite_window_lets_the_fish_escape() -> void:
	var ctx: InteractionContext = _at_water()
	_cast(ctx)
	_settle(ctx)
	var shadow: FishShadow = _stock(ctx, &"crucian_carp")
	_drive_until(ctx, func() -> bool: return Fishing.state() == Fishing.State.BITE)
	var before: int = ctx.inventory.count_of_occupied()
	## `aGYO_bite_time`: the fish holds on for its own species' window and then lets go.
	_tick(ctx, FishSize.bite_seconds(shadow.fish.bite_time) + 0.1)
	assert_bool(Fishing.is_active()).is_false()
	assert_bool("It got away." in _heard).is_true()
	assert_int(ctx.inventory.count_of_occupied()).is_equal(before)


func test_full_pockets_cannot_keep_the_catch() -> void:
	var ctx: InteractionContext = _at_water()
	_cast(ctx)
	_settle(ctx)
	_stock(ctx, &"crucian_carp")
	_fill_pockets(ctx.inventory)
	_drive_until(ctx, func() -> bool: return Fishing.state() == Fishing.State.BITE)
	var out: Fishing.Outcome = Fishing.hook(ctx, _school(ctx))
	assert_bool(out.pockets_full).is_true()
	assert_bool(out.caught()).is_false()
	assert_int(ctx.inventory.count_of(out.fish.id)).is_equal(0)
	assert_bool(Fishing.is_active()).is_false()


func test_landing_a_fish_queues_a_pull_then_a_lift() -> void:
	var ctx: InteractionContext = _at_water()
	_cast(ctx)
	_settle(ctx)
	_stock(ctx, &"crucian_carp")
	_drive_until(ctx, func() -> bool: return Fishing.state() == Fishing.State.BITE)
	var out: Fishing.Outcome = Fishing.hook(ctx, _school(ctx))
	assert_bool(out.caught()).is_true()
	## `vib_rod`, `fly_rod`, `notice_rod`: pull the rod over, swing the fish up out of the
	## water, then hold it up to the camera.
	var beats: Array[Fishing.ReelBeat] = Fishing.take_reel_beats()
	assert_int(beats.size()).is_equal(3)
	assert_str(String(beats[0].player_anim)).is_equal(String(Fishing.REEL_PULL))
	assert_str(String(beats[0].tool_anim)).is_equal(String(Fishing.ROD_PULL))
	assert_str(String(beats[1].player_anim)).is_equal(String(Fishing.REEL_LAND))
	assert_str(String(beats[1].tool_anim)).is_equal(String(Fishing.ROD_LAND))
	assert_str(String(beats[2].player_anim)).is_equal(String(Fishing.REEL_SHOW))
	## Only the show-off beat turns and only it outlasts its own clip.
	assert_bool(beats[0].face_camera).is_false()
	assert_bool(beats[1].face_camera).is_false()
	assert_bool(beats[2].face_camera).is_true()
	assert_float(beats[2].hold).is_equal_approx(Fishing.SHOW_HOLD_SECONDS, 0.0001)
	## The catch report rides on the show-off beat rather than being posted on the button
	## frame, because the pose has to stay up for as long as the text does.
	assert_int(beats[2].catch_msg).is_equal(FishCatalog.get_fish(&"crucian_carp").catch_msg)
	assert_bool(_heard.has(FishCatalog.catch_text(beats[2].catch_msg))).is_false()
	## Draining is one-shot, so the reel cannot replay on the next interaction.
	assert_int(Fishing.take_reel_beats().size()).is_equal(0)


func test_empty_line_queues_a_single_empty_reel() -> void:
	var ctx: InteractionContext = _at_water()
	_cast(ctx)
	_settle(ctx)
	Fishing.hook(ctx, _school(ctx))
	var beats: Array[Fishing.ReelBeat] = Fishing.take_reel_beats()
	assert_int(beats.size()).is_equal(1)
	assert_str(String(beats[0].player_anim)).is_equal(String(Fishing.REEL_EMPTY))
	assert_str(String(beats[0].tool_anim)).is_equal(String(Fishing.ROD_EMPTY))


func test_full_pockets_still_lift_the_fish_into_view() -> void:
	var ctx: InteractionContext = _at_water()
	_cast(ctx)
	_settle(ctx)
	_stock(ctx, &"crucian_carp")
	_fill_pockets(ctx.inventory)
	_drive_until(ctx, func() -> bool: return Fishing.state() == Fishing.State.BITE)
	var out: Fishing.Outcome = Fishing.hook(ctx, _school(ctx))
	assert_bool(out.pockets_full).is_true()
	## You landed it, so you watch it come up and get held up before it is refused.
	var beats: Array[Fishing.ReelBeat] = Fishing.take_reel_beats()
	assert_int(beats.size()).is_equal(3)
	assert_bool(beats[2].face_camera).is_true()
	## The report is still the species line; `notice_rod` chains the pockets-full message
	## onto it rather than replacing it.
	assert_int(beats[2].catch_msg).is_equal(FishCatalog.get_fish(&"crucian_carp").catch_msg)
	assert_bool(beats[2].pockets_full).is_true()


func test_dropping_the_line_queues_no_reel() -> void:
	var ctx: InteractionContext = _at_water()
	_cast(ctx)
	_settle(ctx)
	Fishing.cancel(_school(ctx))
	assert_int(Fishing.take_reel_beats().size()).is_equal(0)
	## Hooking with no session open is a no-op, not an empty reel.
	Fishing.hook(ctx, _school(ctx))
	assert_int(Fishing.take_reel_beats().size()).is_equal(0)


func test_reel_clips_exist_on_the_pipeline_meshes() -> void:
	if FieldCatalog.mesh_paths(&"tol_sao_1").is_empty():
		return
	var rod: Node3D = auto_free(GeneratedVisual.instantiate_raw(&"tol_sao_1"))
	assert_that(rod).is_not_null()
	var anim: AnimationPlayer = GeneratedVisual.find_animation_player(rod)
	assert_that(anim).is_not_null()
	var clips: String = " ".join(anim.get_animation_list())
	for wanted: StringName in [Fishing.ROD_PULL, Fishing.ROD_LAND, Fishing.ROD_EMPTY]:
		assert_bool(String(wanted) in clips).override_failure_message(
			"rod GLB is missing %s; got %s" % [wanted, clips]
		).is_true()


func test_player_resolves_every_reel_clip() -> void:
	var player: Node3D = auto_free(load("res://scenes/actors/player.tscn").instantiate()) as Node3D
	add_child(player)
	await get_tree().process_frame
	var anim: AnimationPlayer = GeneratedVisual.find_animation_player(player)
	if anim == null or anim.get_animation_list().is_empty():
		return
	## `_resolve_clip` matches the pipeline's `ply_1_*` names loosely, so a missing clip
	## silently falls back to a timer and the reel looks like nothing happened.
	for wanted: StringName in [
		Fishing.REEL_PULL, Fishing.REEL_LAND, Fishing.REEL_EMPTY, Fishing.REEL_SHOW
	]:
		var resolved: String = player.call("_resolve_clip", String(wanted))
		assert_str(resolved).override_failure_message(
			"player cannot resolve %s; has %s" % [wanted, anim.get_animation_list()]
		).is_not_empty()


func test_player_turns_to_the_camera_for_the_show_off_pose() -> void:
	var player: Node3D = auto_free(load("res://scenes/actors/player.tscn").instantiate()) as Node3D
	add_child(player)
	await get_tree().process_frame
	var motor: PlayerLocomotion = player.get("_motor") as PlayerLocomotion
	assert_that(motor).is_not_null()
	## Facing away from the camera, the way you stand when the water is behind the player.
	var entry: float = PI * 0.75
	motor.facing = entry
	var beat := Fishing.ReelBeat.new(
		Fishing.REEL_SHOW, Fishing.ROD_LAND, true, Fishing.SHOW_HOLD_SECONDS
	)
	player.call("_play_show", beat)

	var away: float = absf(angle_difference(entry, Fishing.SHOW_YAW))
	var turned: bool = false
	for _i in 20:
		await get_tree().process_frame
		if absf(angle_difference(motor.facing, Fishing.SHOW_YAW)) < away - 0.001:
			turned = true
			break
	assert_bool(turned).override_failure_message(
		"the show-off pose never turned the player toward the camera"
	).is_true()

	## And the pose is really on screen, not just a timer running the turn: `_play_show` falls
	## back to a bare wait when a clip cannot be resolved, which would look like nothing.
	var anim: AnimationPlayer = GeneratedVisual.find_animation_player(player)
	if anim != null and not anim.get_animation_list().is_empty():
		assert_str(anim.current_animation).contains(String(Fishing.REEL_SHOW))

	## And once the pose is over the facing comes back: the original threads the pre-catch
	## angle through `notice_rod` into `putaway_rod`, so you end up looking at the water again
	## rather than stuck square-on to the camera.
	var restored: bool = false
	for _i in 240:
		await get_tree().process_frame
		if is_equal_approx(motor.facing, entry):
			restored = true
			break
	assert_bool(restored).override_failure_message(
		"the show-off pose left the player facing %f instead of %f" % [motor.facing, entry]
	).is_true()


## Every `aGYO_TYPE_*` up to `aGYO_TYPE_NUM` should be on the shelf. The five non-fish
## entries past it (whale, can, boot, tire, the second salmon) are junk-on-the-line and
## `Fishing` has no path that pulls them up, so they are deliberately absent.
func test_every_species_is_in_the_creatures_folder() -> void:
	var fish: Array[FishData] = FishCatalog.all_fish()
	assert_int(fish.size()).is_equal(40)
	var ids: Dictionary = {}
	for one: FishData in fish:
		assert_str(String(one.id)).override_failure_message("a fish has no id").is_not_empty()
		assert_bool(ids.has(one.id)).override_failure_message(
			"duplicate fish id %s" % one.id
		).is_false()
		ids[one.id] = true
		assert_str(one.display_name).is_not_empty()
		assert_str(one.description).is_not_empty()
		assert_int(one.sell_price).is_greater(0)
		assert_int(one.rarity_weight).is_greater(0)
		assert_that(one.category).is_equal(ItemData.Category.FISH)
		## Every species names a `dl_a` GLB and it has to be on disk, or the show-off pose
		## quietly holds nothing.
		for pose: StringName in [&"a", &"b"]:
			var path: String = one.model_pose(pose)
			assert_bool(ResourceLoader.exists(path)).override_failure_message(
				"%s points at a missing model: %s" % [one.id, path]
			).is_true()
		## Every species has its own catch report, pun and all.
		assert_int(one.catch_msg).is_greater(0)
		assert_str(FishCatalog.catch_text(one.catch_msg)).override_failure_message(
			"%s has no catch message at %d" % [one.id, one.catch_msg]
		).is_not_empty()
	## Spot-check the ends of the size table against `gyoei_type[]`.
	assert_that(FishCatalog.get_fish(&"arapaima").size_class).is_equal(FishData.SizeClass.XXL)
	assert_that(FishCatalog.get_fish(&"bitterling").size_class).is_equal(FishData.SizeClass.XXS)


## `aSOG_gyoei_time_no` buckets the clock into four, and a fish can hold a non-adjacent
## pair of them: the piranha takes at midday and again in the small hours.
func test_time_slots_can_be_non_adjacent() -> void:
	var piranha: FishData = FishCatalog.get_fish(&"piranha")
	assert_that(piranha).is_not_null()
	assert_bool(piranha.is_available(7, 12)).is_true()
	assert_bool(piranha.is_available(7, 23)).is_true()
	## The gap between them: 4am is MORNING, 6pm is EVENING, and it holds neither.
	assert_bool(piranha.is_available(7, 5)).is_false()
	assert_bool(piranha.is_available(7, 18)).is_false()
	assert_that(FishData.slot_for_hour(23)).is_equal(FishData.TimeSlot.NIGHT)
	assert_that(FishData.slot_for_hour(2)).is_equal(FishData.TimeSlot.NIGHT)
	assert_that(FishData.slot_for_hour(6)).is_equal(FishData.TimeSlot.MORNING)
	assert_that(FishData.slot_for_hour(12)).is_equal(FishData.TimeSlot.DAY)
	assert_that(FishData.slot_for_hour(18)).is_equal(FishData.TimeSlot.EVENING)


## `r_month` / `s_month` / `p_month` are separate tables, so a sea fish must not turn up in
## the river the player is actually standing next to.
func test_water_kind_keeps_sea_fish_out_of_the_river() -> void:
	var snapper: FishData = FishCatalog.get_fish(&"red_snapper")
	var carp: FishData = FishCatalog.get_fish(&"crucian_carp")
	var crawfish: FishData = FishCatalog.get_fish(&"crawfish")
	var river: Array[FishData] = FishCatalog.available(6, 12, WaterBodies.Kind.RIVER)
	assert_bool(river.has(carp)).is_true()
	assert_bool(river.has(snapper)).is_false()
	assert_bool(river.has(crawfish)).is_false()
	var ocean: Array[FishData] = FishCatalog.available(6, 12, WaterBodies.Kind.OCEAN)
	assert_bool(ocean.has(snapper)).is_true()
	assert_bool(ocean.has(carp)).is_false()
	assert_bool(FishCatalog.available(6, 12, WaterBodies.Kind.POND).has(crawfish)).is_true()
	## No body in hand means no filter, which is what the plain two-argument call does.
	var anywhere: Array[FishData] = FishCatalog.available(6, 12)
	assert_bool(anywhere.has(snapper)).is_true()
	assert_bool(anywhere.has(carp)).is_true()


## `aSOG_add_kaseki_range_data` splices the coelacanth in only while it rains, outside day.
func test_the_coelacanth_waits_for_rain() -> void:
	var fossil: FishData = FishCatalog.get_fish(&"coelacanth")
	assert_that(fossil).is_not_null()
	assert_bool(fossil.needs_rain).is_true()
	for hour: int in [0, 6, 12, 18]:
		assert_bool(fossil.is_available(6, hour, false)).is_false()
	assert_bool(fossil.is_available(6, 12, true)).is_false()
	assert_bool(fossil.is_available(6, 0, true)).is_true()
	assert_bool(fossil.is_available(6, 20, true)).is_true()
	assert_bool(FishCatalog.available(6, 12, WaterBodies.Kind.OCEAN, false).has(fossil)).is_false()
	assert_bool(FishCatalog.available(6, 0, WaterBodies.Kind.OCEAN, true).has(fossil)).is_true()


## `aUKI_catch` puts `uki_pos` (and so the hooked fish) at `left_hand_pos` while the bobber
## goes to the right hand, so the catch really is in the player's other hand.
func test_the_catch_hangs_off_the_free_hand() -> void:
	var player: Node3D = auto_free(load("res://scenes/actors/player.tscn").instantiate()) as Node3D
	add_child(player)
	await get_tree().process_frame
	var skeleton: Skeleton3D = HeldTool.find_skeleton(player.get("_mesh") as Node)
	assert_that(skeleton).is_not_null()
	assert_bool(HeldCatch.is_held(skeleton)).is_false()

	var carp: FishData = FishCatalog.get_fish(&"crucian_carp")
	var attach: Node3D = HeldCatch.bind(skeleton, carp)
	assert_that(attach).is_not_null()
	assert_bool(HeldCatch.is_held(skeleton)).is_true()
	## The converted skeleton does not use the plain `joint_16` name, so the bind falls back
	## to the index. Either way it has to land on `mPlayer_JOINT_LARM2`.
	var bone: String = (attach as BoneAttachment3D).bone_name
	assert_str(bone).is_equal(skeleton.get_bone_name(HeldCatch.ARM_BONE_INDEX))
	assert_str(bone.to_lower()).contains("larm2")

	## `Player_actor_draw_After_Larm2` does not hold the catch at the joint: it runs
	## `Matrix_Position_VecX(1100.0f)` off that matrix and calls the result `left_hand_pos`.
	## The left chain ends at the elbow — no hand joint, which is why the original computes
	## one — so binding straight to the bone puts the forearm and fist through the fish.
	var hand: Node3D = attach.get_node_or_null(HeldCatch.HAND_NAME) as Node3D
	assert_that(hand).is_not_null()
	var reach: float = hand.position.length()
	assert_float(reach).is_greater(0.0)
	## As long as the right arm's own hand segment, since that is the joint the left side is
	## missing. Read off the rig because 1100 is in the original's model units.
	var right: float = (
		skeleton.get_bone_global_pose(HeldCatch.RHAND_INDEX).origin
		- skeleton.get_bone_global_pose(HeldCatch.RARM2_INDEX).origin
	).length()
	assert_float(reach).is_equal_approx(right, 0.0001)
	## And it continues the arm rather than pointing off at an angle: the offset should carry
	## the catch further from the shoulder, not sideways out of the hand.
	var shoulder: int = skeleton.get_bone_parent(HeldCatch.ARM_BONE_INDEX)
	var elbow_at: Vector3 = skeleton.get_bone_global_pose(HeldCatch.ARM_BONE_INDEX).origin
	var along: Vector3 = (
		elbow_at - skeleton.get_bone_global_pose(shoulder).origin
	).normalized()
	var offset: Vector3 = skeleton.get_bone_global_pose(HeldCatch.ARM_BONE_INDEX).basis * hand.position
	assert_float(offset.normalized().dot(along)).is_equal_approx(1.0, 0.001)

	## Both draw poses are loaded and exactly one is on screen: `aGYO_actor_draw_fish` flips
	## between `dl_a` and `dl_b`, so the model has to hold both and show one.
	var visual: HeldFish = HeldCatch.held_fish(skeleton)
	assert_that(visual).is_not_null()
	assert_int(visual.get_child_count()).is_equal(2)
	var lit: int = 0
	for child in visual.get_children():
		if (child as Node3D).visible:
			lit += 1
	assert_int(lit).is_equal(1)
	assert_int(visual.shown_pose()).is_equal(0)

	## `aGTT_comeback` gives the fish actor a flat `0.01` whatever the species, which is the
	## ordinary actor draw scale, so the hold is the pipeline's own conversion of it rather
	## than anything calibrated per fish. Held in world terms, so the rig's own scale is
	## divided back out and the local scale is not the answer on its own.
	assert_float(visual.longest_axis()).is_greater(0.0)
	var world: float = visual.global_transform.basis.get_scale().y
	assert_float(world).is_equal_approx(FieldCatalog.actor_uniform_scale(), 0.0001)
	## Uniform across the roster: a scale that varied by species would mean it was guessed.
	for other: StringName in [&"arapaima", &"killifish"]:
		var swap: HeldFish = auto_free(HeldFish.create(FishCatalog.get_fish(other)))
		add_child(swap)
		await get_tree().process_frame
		assert_float(swap.global_transform.basis.get_scale().y).is_equal_approx(
			FieldCatalog.actor_uniform_scale(), 0.0001
		)

	## The catch goes through the same material pass as every other generated mesh. Without it
	## the imported material keeps culling backfaces, and since the fish is billboarded into
	## the camera rather than oriented by its hand, it can end up presenting the absent side.
	for mesh: MeshInstance3D in visual.call("_meshes", visual):
		var surfaces: int = mesh.mesh.get_surface_count() if mesh.mesh != null else 0
		assert_int(surfaces).is_greater(0)
		for i: int in surfaces:
			var mat: Material = mesh.get_active_material(i)
			assert_that(mat).is_not_null()
			if mat is BaseMaterial3D:
				assert_int((mat as BaseMaterial3D).cull_mode).is_equal(
					BaseMaterial3D.CULL_DISABLED
				)

	HeldCatch.unbind(skeleton)
	assert_bool(HeldCatch.is_held(skeleton)).is_false()
	## No model, no attachment, and no crash: the junk-on-the-line beat carries a null fish.
	assert_that(HeldCatch.bind(skeleton, null)).is_null()


## `aGYO_actor_draw_fish` flips between two poses on `aGYO_anime_ptn`'s cadence, so a held
## fish should not be a still model.
func test_the_held_fish_flaps_between_its_two_poses() -> void:
	var visual: HeldFish = auto_free(HeldFish.create(FishCatalog.get_fish(&"crucian_carp")))
	assert_that(visual).is_not_null()
	add_child(visual)
	## `aGYO_frame_ptn1` reaches its `b` entries a few frames in, so the pose must change and
	## then come back rather than latching.
	var seen: Dictionary = {}
	for _i in 120:
		await get_tree().process_frame
		seen[visual.shown_pose()] = true
	assert_bool(seen.has(0)).override_failure_message("the held fish never showed pose a").is_true()
	assert_bool(seen.has(1)).override_failure_message("the held fish never showed pose b").is_true()

	## A species with `aGYO_anime_ptn == NONE` holds still. Nothing in the roster uses it, so
	## check the table drives the choice rather than every fish flapping the same way.
	var fast: FishData = FishCatalog.get_fish(&"crucian_carp")
	var slow: FishData = FishCatalog.get_fish(&"carp")
	assert_int(fast.model_flap).is_equal(HeldFish.FLAP_FAST)
	assert_int(slow.model_flap).is_equal(HeldFish.FLAP_SLOW)


## The report text is the game's own, out of the extracted message bank rather than written
## by us. Pin a couple of the puns so a bad message-number mapping cannot pass quietly.
func test_the_catch_report_is_the_games_own_text() -> void:
	assert_int(FishCatalog.get_fish(&"crucian_carp").catch_msg).is_equal(0x1327)
	assert_str(FishCatalog.catch_text(0x1327)).contains("Carpe diem")
	assert_str(FishCatalog.catch_text(FishCatalog.get_fish(&"dace").catch_msg)).contains(
		"Daces wild"
	)
	assert_str(FishCatalog.catch_text(FishCatalog.get_fish(&"pond_smelt").catch_msg)).contains(
		"POND smelt bad"
	)
	## `Player_actor_Get_sakana_msg_num` switches base at type 0x20, so the crawfish is the
	## first fish on the second block and a mis-transcribed switch would show up here.
	assert_int(FishCatalog.get_fish(&"crawfish").catch_msg).is_equal(0x2FC9)
	assert_str(FishCatalog.catch_text(0x2FC9)).contains("pincers")


## The rare three open on a reaction and then name the fish, so the report has to be able to
## run more than one page — which is why it plays a conversation instead of a single string.
func test_the_rare_fish_reports_run_to_two_pages() -> void:
	for id: StringName in [&"stringfish", &"coelacanth", &"arapaima"]:
		var fish: FishData = FishCatalog.get_fish(id)
		var data: DialogueData = DialogueCatalog.conversation(
			StringName("msg_%d" % fish.catch_msg)
		)
		assert_that(data).override_failure_message("%s has no conversation" % id).is_not_null()
		data.ensure_loaded()
		var first: Dictionary = data.node(data.start)
		assert_str(String(first.get("next", ""))).override_failure_message(
			"%s's report is a single page" % id
		).is_not_empty()
	assert_str(FishCatalog.catch_text(FishCatalog.get_fish(&"arapaima").catch_msg)).contains("WOW")


## The show-off beat has to carry the fish, or the pose has nothing to hold up.
func test_the_show_off_beat_carries_the_fish() -> void:
	var carp: FishData = FishCatalog.get_fish(&"crucian_carp")
	var out := Fishing.Outcome.new()
	out.fish = carp
	out.catch_msg = carp.catch_msg
	var beats: Array[Fishing.ReelBeat] = Fishing.reel_beats(out)
	assert_int(beats.size()).is_equal(3)
	assert_that(beats[2].fish).is_equal(carp)
	## The earlier beats are the rod coming up out of the water; nothing is in hand yet.
	assert_that(beats[0].fish).is_null()
	assert_that(beats[1].fish).is_null()
	## And an empty line holds nothing at all.
	assert_that(Fishing.reel_beats(Fishing.Outcome.new())[0].fish).is_null()


func test_the_pose_holds_the_fish_until_the_report_closes() -> void:
	var player: Node3D = auto_free(load("res://scenes/actors/player.tscn").instantiate()) as Node3D
	add_child(player)
	await get_tree().process_frame
	var skeleton: Skeleton3D = HeldTool.find_skeleton(player.get("_mesh") as Node)
	var beat := Fishing.ReelBeat.new(
		Fishing.REEL_SHOW,
		Fishing.ROD_LAND,
		true,
		Fishing.SHOW_HOLD_SECONDS,
		0,
		FishCatalog.get_fish(&"crucian_carp")
	)
	player.call("_play_show", beat)

	var held: bool = false
	for _i in 60:
		await get_tree().process_frame
		if HeldCatch.is_held(skeleton):
			held = true
			break
	assert_bool(held).override_failure_message(
		"the show-off pose never put the fish in the player's hand"
	).is_true()

	## With no message the pose ends on its own clip, then hands off to the putaway, and the
	## fish goes away with that. Waited out on the clock rather than on a frame count: the
	## beats use real-time timers and a headless run burns frames far faster than seconds.
	assert_bool(await _settles(func() -> bool: return not HeldCatch.is_held(skeleton))).override_failure_message(
		"the fish stayed in the player's hand after the pose ended"
	).is_true()


## `Player_actor_request_proc_index_fromNotice_rod` case 0x39: the dismissed report hands off
## to `putaway_rod`, which plays `PUTAWAY_T1` before the player is free again. Without it the
## catch simply vanished out of a raised hand.
func test_the_catch_is_put_away_once_the_report_is_done() -> void:
	var player: Node3D = auto_free(load("res://scenes/actors/player.tscn").instantiate()) as Node3D
	add_child(player)
	await get_tree().process_frame
	var anim: AnimationPlayer = player.get("_anim") as AnimationPlayer
	assert_that(anim).is_not_null()

	## The clip has to be in the converted bank, or the beat silently degrades to a snap back
	## to idle: `PLAYER_CORE_ANIMS` names each one and nothing else pulls this one in.
	var putaway: String = player.call("_resolve_clip", String(Fishing.PUTAWAY))
	assert_str(putaway).override_failure_message(
		"ply_1_putaway_t1 is not in the player GLB — add it to PLAYER_CORE_ANIMS and reconvert"
	).is_not_empty()
	assert_bool(anim.has_animation(putaway)).is_true()

	var skeleton: Skeleton3D = HeldTool.find_skeleton(player.get("_mesh") as Node)
	var beat := Fishing.ReelBeat.new(
		Fishing.REEL_SHOW,
		Fishing.ROD_LAND,
		true,
		Fishing.SHOW_HOLD_SECONDS,
		0,
		FishCatalog.get_fish(&"crucian_carp")
	)
	player.call("_play_show", beat)

	## The fish rides the hand down rather than blinking out as the pose breaks, so it should
	## still be in hand on the frame the putaway starts.
	## Carried in an array because a lambda captures a local `bool` by value, so a flag set
	## inside the closure never reaches the assertion.
	var held_through: Array[bool] = [false]
	var played: bool = await _settles(
		func() -> bool:
			if anim.current_animation != putaway:
				return false
			held_through[0] = held_through[0] or HeldCatch.is_held(skeleton)
			return true
	)
	assert_bool(played).override_failure_message(
		"the pose never handed off to putaway_rod"
	).is_true()
	assert_bool(held_through[0]).override_failure_message(
		"the catch was released before the putaway animation started"
	).is_true()

	## And it is gone by the time the player is idle again.
	assert_bool(await _settles(func() -> bool: return not HeldCatch.is_held(skeleton))).override_failure_message(
		"the catch outlived the putaway animation"
	).is_true()


func test_casting_on_top_of_a_fish_scares_it_off() -> void:
	var ctx: InteractionContext = _at_water()
	var school: FishSchool = _school(ctx)
	## `uki->hit_water_flag && target_dist < escape_dist`: land the bobber on its head, so
	## the fish sits exactly where the cast is about to come down.
	var shadow: FishShadow = school.spawn(
		FishCatalog.get_fish(&"crucian_carp"), school.bodies[0], ToolUse.cast_point(ctx)
	)
	assert_that(shadow).is_not_null()
	_cast(ctx)
	_tick(ctx, Fishing.CAST_SECONDS + STEP * 3.0)
	assert_that(shadow.action).is_equal(FishShadow.Action.ESCAPE)


func test_walking_away_drops_the_line() -> void:
	var ctx: InteractionContext = _at_water()
	_cast(ctx)
	var actor := ctx.actor as _FacingActor
	actor.global_position += Vector3(0.0, 0.0, -Fishing.LEASH_METERS - 2.0)
	Fishing.tick(0.1, _school(ctx))
	assert_bool(Fishing.is_active()).is_false()
	assert_bool("Your line went slack." in _heard).is_true()


func test_authored_town_river_is_castable_near_spawn() -> void:
	var data: WorldData = WorldGenerator.authored_test_town()
	data.bake()
	## Stand on the west bank and face east into the channel.
	var bank := Vector2i(10, 11)
	assert_that(data.terrain_at(bank)).is_not_equal(WorldGrid.Terrain.WATER)
	## Four cells across, so a full-reach cast comes down in open water rather than on the
	## far bank. The channel runs most of the map, a few steps east of where a save spawns.
	for dx: int in 4:
		assert_that(data.terrain_at(Vector2i(11 + dx, 11))).is_equal(WorldGrid.Terrain.WATER)
	assert_that(data.terrain_at(Vector2i(12, 4))).is_equal(WorldGrid.Terrain.WATER)
	assert_that(data.terrain_at(Vector2i(12, 14))).is_equal(WorldGrid.Terrain.WATER)
	assert_int(absi(data.player_spawn().cell.x - bank.x)).is_less(4)
	## Nothing sits in the channel: a tree there would block the cast.
	for placement: ObjectPlacement in data.objects:
		if placement != null:
			assert_that(data.terrain_at(placement.cell)).is_not_equal(WorldGrid.Terrain.WATER)

	## And the cast is actually offered from the bank at the real 100 GX reach, which is what
	## the width above is for: the terrain spot checks alone would not catch a short channel.
	var world := auto_free(_GridWorld.new()) as _GridWorld
	world.grid.configure_from_world(data)
	var actor := auto_free(_FacingActor.new()) as _FacingActor
	add_child(actor)
	actor.global_position = world.grid.cell_to_world(bank)
	actor.yaw = PI * 0.5
	var ctx := InteractionContext.new()
	ctx.inventory = Inventory.new()
	ctx.actor = actor
	ctx.world = world
	assert_int(ctx.inventory.add(ItemCatalog.get_item(&"fishing_rod"), 1)).is_equal(0)
	assert_bool(ctx.inventory.equip_slot(0)).is_true()
	var action: Interaction = ToolUse.field_action(ctx)
	assert_that(action).is_not_null()
	assert_str(String(action.id)).is_equal(String(Interaction.CAST))

	## Some fish is always in season, so a first cast always has something to offer.
	for hour: int in 24:
		assert_bool(FishCatalog.available(1, hour).is_empty()).is_false()


func test_authored_town_river_reads_as_one_flowing_body() -> void:
	var data: WorldData = WorldGenerator.authored_test_town()
	var grid := WorldGrid.new()
	data.bake()
	grid.configure_from_world(data)
	var bodies: Array[WaterBodies.Body] = WaterBodies.find(grid)
	assert_int(bodies.size()).is_equal(1)
	## Two cells wide and thirteen long: a river, not a pond, so fish hold facing upstream.
	assert_that(bodies[0].kind).is_equal(WaterBodies.Kind.RIVER)
	assert_bool(bodies[0].flows).is_true()
	assert_that(WaterBodies.size_ceiling(bodies[0])).is_equal(FishData.SizeClass.XL)


func test_cast_spawns_a_bobber_and_drops_it_with_the_line() -> void:
	var ctx: InteractionContext = _at_water()
	var effects := Node3D.new()
	effects.name = "Effects"
	(ctx.world as Node).add_child(effects)
	_cast(ctx)
	assert_int(effects.get_child_count()).is_equal(1)
	var bobber: Node = effects.get_child(0)
	Fishing.cancel(_school(ctx))
	assert_bool(Fishing.is_active()).is_false()
	await get_tree().process_frame
	assert_bool(is_instance_valid(bobber)).is_false()


func test_bobber_uses_the_pipeline_uki_over_its_placeholder() -> void:
	var bobber: Node3D = auto_free(load("res://scenes/world/bobber.tscn").instantiate()) as Node3D
	add_child(bobber)
	await get_tree().process_frame
	var pivot: Node3D = bobber.get_node_or_null("Float") as Node3D
	assert_that(pivot).is_not_null()
	## The ripple is a separate water effect, so it must survive the attach that hides the
	## placeholder float.
	assert_bool((bobber.get_node("Ripple") as MeshInstance3D).visible).is_true()
	if FieldCatalog.mesh_paths(&"tol_uki_1").is_empty():
		return
	assert_that(pivot.get_node_or_null("GeneratedVisual")).is_not_null()
	assert_bool((pivot.get_node("MeshInstance3D") as MeshInstance3D).visible).is_false()


func test_bobber_tilt_eases_to_each_proc_target() -> void:
	var script: GDScript = load("res://scenes/world/bobber.gd")
	## `add_calc_short_angle2` takes the short way round and never overshoots.
	var pitch: float = script.PITCH_FLAT
	for _i in 200:
		pitch = MLib.short_angle2(pitch, 0.0, script.SETTLE_FRACTION, script.SETTLE_MAX_STEP)
	assert_float(pitch).is_equal_approx(0.0, 0.0001)
	## From upright to yanked-under is a quarter turn down, not three quarters up.
	var first: float = MLib.short_angle2(
		0.0, script.PITCH_PULLED, script.CAST_FRACTION, script.CAST_MAX_STEP
	)
	assert_float(first).is_less(0.0)
	## The step clamp bounds how fast the cast can flatten it.
	var clamped: float = MLib.short_angle2(0.0, PI, script.CAST_FRACTION, script.CAST_MAX_STEP)
	assert_float(absf(clamped)).is_less_equal(script.CAST_MAX_STEP + 0.0001)


func test_show_off_turn_settles_facing_the_camera() -> void:
	## The follow camera sits on +Z and yaw 0 looks down +Z, so `Movement_Notice_rod`'s target
	## of angle 0 is square-on to the camera.
	assert_float(Fishing.SHOW_YAW).is_equal(0.0)
	## Turning from behind converges, and gets there inside the 42-frame hold rather than
	## still swinging round when the pose ends.
	var yaw: float = PI * 0.95
	var frames: int = 0
	while not is_equal_approx(yaw, Fishing.SHOW_YAW) and frames < 600:
		yaw = MLib.short_angle2(
			yaw,
			Fishing.SHOW_YAW,
			Fishing.SHOW_TURN_FRACTION,
			Fishing.SHOW_TURN_MAX_STEP,
			Fishing.SHOW_TURN_MIN_STEP
		)
		frames += 1
	assert_float(yaw).is_equal_approx(Fishing.SHOW_YAW, 0.0001)
	assert_int(frames).is_less(int(Fishing.SHOW_HOLD_SECONDS * Fishing.SHOW_TURN_HZ))
	## `maxStep` bounds the first step of a half turn.
	var capped: float = MLib.short_angle2(
		PI * 0.5,
		Fishing.SHOW_YAW,
		Fishing.SHOW_TURN_FRACTION,
		Fishing.SHOW_TURN_MAX_STEP,
		Fishing.SHOW_TURN_MIN_STEP
	)
	assert_float(absf(PI * 0.5 - capped)).is_less_equal(Fishing.SHOW_TURN_MAX_STEP + 0.0001)


func test_min_step_keeps_a_turn_from_stalling_short() -> void:
	## With `minStep == 0` the proportional step rounds away and the value snaps, which is
	## what the bobber's tilt wants.
	assert_float(MLib.short_angle2(0.0, 1e-9, 0.5, 1.0)).is_equal(1e-9)
	## `notice_rod` passes 50, so a turn this close still moves by exactly that floor instead
	## of creeping in ever-smaller fractions.
	var near: float = Fishing.SHOW_TURN_MIN_STEP * 0.5
	var stepped: float = MLib.short_angle2(
		near, 0.0, 0.0001, Fishing.SHOW_TURN_MAX_STEP, Fishing.SHOW_TURN_MIN_STEP
	)
	## The floor overshoots what is left, so it lands on the target rather than past it.
	assert_float(stepped).is_equal(0.0)


func test_world_owns_a_school_and_an_effects_node_that_finds_it() -> void:
	var world: Node3D = auto_free(load("res://scenes/world/world.tscn").instantiate()) as Node3D
	add_child(world)
	await get_tree().process_frame
	var school: FishSchool = world.get("fish") as FishSchool
	assert_that(school).is_not_null()
	## The authored town has a river, so a fresh field always has somewhere to put fish.
	assert_bool(school.has_water()).is_true()
	var effects: Node = world.get_node_or_null("Effects/FishShadows")
	assert_that(effects).is_not_null()
	assert_that(effects.call("school")).is_same(school)
	## Driven by hand rather than by frames: a headless delta is not wall clock, so waiting
	## on `_process` to cover `SPAWN_INTERVAL` would be a coin flip.
	var sense := FishShadow.Sense.new()
	var grid: WorldGrid = world.get("grid") as WorldGrid
	sense.player_position = grid.cell_to_world(school.bodies[0].cells[0])
	for _i: int in 60:
		school.tick(0.1, sense)
	assert_int(school.shadow_count()).is_equal(FishSchool.MAX_SHADOWS)
	for shadow: FishShadow in school.shadows:
		assert_that(shadow.fish).is_not_null()
		assert_float(shadow.shadow_extent().y).is_greater(0.0)


func test_fishing_is_not_an_autoload() -> void:
	var src := FileAccess.get_file_as_string("res://project.godot")
	assert_bool("fishing.gd" in src).is_false()
	assert_bool("fish_catalog.gd" in src).is_false()
	assert_bool("fish_school.gd" in src).is_false()
	assert_bool("fish_shadow.gd" in src).is_false()


## Pumps frames until `check` passes or the clock runs out. The reel beats wait on real-time
## timers, so a frame budget is the wrong unit: headless gets through hundreds of frames in
## the time one 0.7s beat takes, and a loop counting frames gives up long before the beat.
func _settles(check: Callable, seconds: float = 8.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if check.call():
			return true
		await get_tree().process_frame
	return check.call()


func _at_water() -> InteractionContext:
	var world := auto_free(_GridWorld.new()) as _GridWorld
	world.grid.configure(16, 16, 2.0, Vector3(-16, 0, -16))
	## A pond with room to swim in: a single cell leaves a shadow pinned to the bank. It also
	## has to reach past `Fishing.CAST_METERS` so the bobber lands in open water with room
	## for a fish beyond it, and stay off the grid edge so it stays a pond and not an ocean.
	for x: int in range(6, 12):
		for z: int in range(9, 15):
			world.grid.set_terrain(Vector2i(x, z), WorldGrid.Terrain.WATER)
	world.fish.configure(world.grid, 0.0)
	world.fish.seed_rng(7)
	## These tests place their own fish; a self-stocking school would race them.
	world.fish.auto_spawn = false
	var actor := auto_free(_FacingActor.new()) as _FacingActor
	add_child(actor)
	actor.global_position = world.grid.cell_to_world(Vector2i(8, 8))
	var ctx := InteractionContext.new()
	ctx.inventory = Inventory.new()
	ctx.actor = actor
	ctx.world = world
	var rod: ItemData = ItemCatalog.get_item(&"fishing_rod")
	assert_that(rod).is_not_null()
	assert_int(ctx.inventory.add(rod, 1)).is_equal(0)
	assert_bool(ctx.inventory.equip_slot(0)).is_true()
	return ctx


func _school(ctx: InteractionContext) -> FishSchool:
	return (ctx.world as _GridWorld).fish


func _cast(ctx: InteractionContext) -> void:
	var action: Interaction = ToolUse.field_action(ctx)
	assert_that(action).is_not_null()
	assert_bool(ToolUse.apply_field(action, ctx)).is_true()
	assert_bool(Fishing.is_active()).is_true()


## Run the bobber out of its arc so fish can start reacting to it.
func _settle(ctx: InteractionContext) -> void:
	_tick(ctx, Fishing.CAST_SECONDS + STEP * 2.0)
	assert_that(Fishing.state()).is_equal(Fishing.State.FLOAT)


## Put a known fish a cell away from the bobber, inside its search cone.
func _stock(ctx: InteractionContext, id: StringName) -> FishShadow:
	var school: FishSchool = _school(ctx)
	var fish: FishData = FishCatalog.get_fish(id)
	assert_that(fish).is_not_null()
	## A cell out from wherever the bobber actually landed, which is inside
	## `aGYO_search_area` for an eager fish. Measured off the anchor rather than a fixed cell
	## so it keeps tracking `Fishing.CAST_METERS`.
	var spot: Vector3 = Fishing.anchor() + Vector3(0.0, 0.0, ctx.world.grid.cell_size)
	var shadow: FishShadow = school.spawn(fish, school.bodies[0], spot)
	assert_that(shadow).is_not_null()
	return shadow


func _tick(ctx: InteractionContext, seconds: float) -> void:
	var school: FishSchool = _school(ctx)
	var actor := ctx.actor as Node3D
	var elapsed: float = 0.0
	while elapsed < seconds:
		var sense := FishShadow.Sense.new()
		sense.player_position = actor.global_position
		Fishing.fill_sense(sense)
		school.tick(STEP, sense)
		Fishing.tick(STEP, school)
		elapsed += STEP


func _drive_until(ctx: InteractionContext, done: Callable) -> void:
	var elapsed: float = 0.0
	while elapsed < DRIVE_CAP:
		if done.call():
			return
		_tick(ctx, STEP)
		elapsed += STEP
	fail("shadow never reached the expected state within %.0fs" % DRIVE_CAP)


func _fill_pockets(inventory: Inventory) -> void:
	var filler: ItemData = ItemCatalog.get_item(&"apple")
	assert_that(filler).is_not_null()
	while inventory.empty_slot_count() > 0:
		assert_int(inventory.add(filler, filler.max_stack)).is_equal(0)
	assert_int(inventory.empty_slot_count()).is_equal(0)
