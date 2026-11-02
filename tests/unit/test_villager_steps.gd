class_name TestVillagerSteps
extends GdUnitTestSuite

## `aNPC_anime_se_proc`'s tables: when a villager's feet land and what its animations sound.

func test_the_walk_lands_a_foot_on_frames_one_and_nine() -> void:
	var entry: Dictionary = VillagerSteps.table().get("npc_1_walk1", {})
	assert_array(entry.get("l", [])).is_equal([1.0])
	assert_array(entry.get("r", [])).is_equal([9.0])


func test_marks_count_clip_time_from_keyframe_one() -> void:
	var marks: Dictionary = VillagerSteps.marks(func(name: String) -> String: return name)
	var walk: Array = marks[&"npc_1_walk1"]
	assert_array(walk).is_equal([[0.0, VillagerSteps.STEP_L], [8.0, VillagerSteps.STEP_R]])


func test_animation_sounds_carry_their_se_number() -> void:
	var marks: Dictionary = VillagerSteps.marks(func(name: String) -> String: return name)
	var eat: Array = marks[&"npc_1_get_eat1"]
	assert_int(eat.size()).is_equal(4)
	assert_str(String(eat[0][1])).is_equal("se_113")
	assert_str(String(VillagerSteps.sound_of(&"se_113"))).is_equal("113")
	assert_str(String(VillagerSteps.sound_of(VillagerSteps.STEP_L))).is_equal("")


func test_a_tumble_has_its_own_thud_and_no_footstep() -> void:
	var marks: Dictionary = VillagerSteps.marks(func(name: String) -> String: return name)
	assert_bool(marks.has(&"npc_1_kokeru1")).is_false()


func test_clips_the_model_lacks_are_left_out() -> void:
	var marks: Dictionary = VillagerSteps.marks(func(_name: String) -> String: return "")
	assert_bool(marks.is_empty()).is_true()


func test_a_villager_wears_the_step_marks_on_its_walk() -> void:
	var villager := auto_free(load("res://features/villagers/villager.tscn").instantiate()) as Villager
	villager.data = VillagerCatalog.get_villager(&"filbert")
	add_child(villager)
	var anim: Animation = villager._animator.get_animation(StringName(villager._resolve_clip("npc_1_walk1")))
	assert_object(anim).is_not_null()
	var keys: int = 0
	for i: int in anim.get_track_count():
		if anim.track_get_type(i) == Animation.TYPE_METHOD:
			keys += anim.track_get_key_count(i)
	assert_int(keys).is_equal(2)
