class_name TestToolCarry
extends GdUnitTestSuite

## How the player holds tools: straight off the hand bone, carry clip layered on the arms
## (`Player_actor_Item_draw`, `BOY_part_data`).


func test_carry_pose_rides_only_on_locomotion() -> void:
	assert_bool(ToolCarry.rides_on("ply_1_wait1")).is_true()
	assert_bool(ToolCarry.rides_on("ply_1_walk1")).is_true()
	assert_bool(ToolCarry.rides_on("ply_1_axe_swing1")).is_false()
	assert_bool(ToolCarry.rides_on("ply_1_umb_open1")).is_false()
	## AXE table: both arms; NET table: the right arm only.
	assert_array(ToolCarry.PART_JOINTS[ToolData.CarryPart.AXE]).contains_exactly([14, 15, 16, 17, 18, 19, 20])
	assert_array(ToolCarry.PART_JOINTS[ToolData.CarryPart.NET]).contains_exactly([17, 18, 19, 20])


func test_carry_builds_from_the_player_clip() -> void:
	if not ResourceLoader.exists("res://assets/generated/characters/player/boy_1.glb"):
		return
	var body: Node3D = auto_free((load("res://assets/generated/characters/player/boy_1.glb") as PackedScene).instantiate())
	add_child(body)
	var anim: AnimationPlayer = VisualAnimation.find_animation_player(body)
	var skeleton: Skeleton3D = HeldTool.find_skeleton(body)
	var carry: ToolCarry = ToolCarry.build(anim, skeleton, ItemCatalog.get_item(&"axe") as ToolData)
	assert_object(carry).is_not_null()
	## All seven arm joints are driven — from a track, or the rest pose when the writer dropped it.
	assert_int(carry.tracks.size() + carry.rest.size()).is_equal(7)
	var net_carry: ToolCarry = ToolCarry.build(anim, skeleton, ItemCatalog.get_item(&"net") as ToolData)
	assert_int(net_carry.tracks.size() + net_carry.rest.size()).is_equal(4)
	## Tools hang straight off the hand bone (`right_hand_mtx`), no extra rotation.
	var attach: Node3D = HeldTool.bind(skeleton, &"tol_axe_1")
	if attach != null and attach.get_child_count() > 0:
		assert_that((attach.get_child(0) as Node3D).basis).is_equal(Basis.IDENTITY)
