class_name TestNeedleworkInterior
extends GdUnitTestSuite

const SCENE := "res://scenes/world/interiors/needlework.tscn"

## Able Sisters interior build (`NeedleworkPresenter`).


func test_room_keeps_acre_origin_and_gx_positions_land_inside() -> void:
	var room: Room = InteriorCatalog.room_template(&"needlework")
	## `rom_tailor` keeps the acre origin so `ac_needlework_indoor.c` GX maps directly.
	assert_bool(VisualFit.shell_keeps_acre_origin(&"rom_tailor")).is_true()
	assert_vector(room.inner_origin).is_equal(Vector2i(1, 1))
	assert_vector(room.inner_size).is_equal(Vector2i(8, 6))
	var session := IndoorSession.new()
	session.bind(room)
	var grid := session.grid
	## every mannequin / umbrella-stand GX maps onto walkable floor
	for gx: Vector3 in NeedleworkPresenter.MANNEQUIN_GX + NeedleworkPresenter.UMBRELLA_GX:
		var cell := grid.world_to_cell(MuseumDisplay.gx_to_world(grid, gx))
		assert_bool(room.is_inner(cell)).override_failure_message(
			"GX %s -> cell %s is off-floor" % [gx, cell]
		).is_true()
	## mannequins sit north of the umbrella stands, which sit north of the spawn
	var man_z := MuseumDisplay.gx_to_world(grid, NeedleworkPresenter.MANNEQUIN_GX[0]).z
	var umb_z := MuseumDisplay.gx_to_world(grid, NeedleworkPresenter.UMBRELLA_GX[0]).z
	var spawn_z := grid.cell_to_world(room.spawn_cell).z
	assert_bool(man_z < umb_z).is_true()
	assert_bool(umb_z < spawn_z).is_true()

	## Decomp: you enter AND leave at the door. The spawn is the exit cell (the
	## `rom_tailor.col.json` porch), and the whole room is NORTH of it, so walking
	## in never re-crosses the strip. (`block_auto_enter_doors` disarms the
	## spawn-on-exit until the player steps off.)
	var spawn_cell := grid.world_to_cell(MuseumDisplay.gx_to_world(grid, InteriorCatalog.ABLE_SPAWN_GX))
	assert_bool(room.is_exit_cell(spawn_cell)).is_true()
	assert_int(room.door_cell.y).is_equal(room.inner_origin.y + room.inner_size.y)  ## porch row, just south of the last inner row
	## every display / Sable / Mabel sits strictly north of the exit strip
	for gx: Vector3 in ([NeedleworkPresenter.SABLE_GX, NeedleworkPresenter.MABEL_GX]
			+ NeedleworkPresenter.MANNEQUIN_GX + NeedleworkPresenter.UMBRELLA_GX):
		var c := grid.world_to_cell(MuseumDisplay.gx_to_world(grid, gx))
		assert_bool(c.y < room.door_cell.y).override_failure_message("%s at cell %s not north of exit" % [gx, c]).is_true()


func test_the_scene_places_sisters_and_displays_on_the_decomp_tables() -> void:
	var session := IndoorSession.new()
	session.bind(InteriorCatalog.room_template(&"needlework"))
	var grid: WorldGrid = session.grid
	if not _deps_exist(SCENE):
		return  ## `rom_tailor.glb` not generated (no disc)
	var scene: Node3D = auto_free(load(SCENE).instantiate())
	var root: Node3D = scene.get_node("Furniture")
	var at := func(node_name: String) -> Vector3:
		return (root.get_node(node_name) as Node3D).position
	assert_vector(at.call("Sable")).is_equal_approx(
		MuseumDisplay.gx_to_world(grid, NeedleworkPresenter.SABLE_GX), Vector3.ONE * 0.01)
	assert_vector(at.call("Mabel")).is_equal_approx(
		MuseumDisplay.gx_to_world(grid, NeedleworkPresenter.MABEL_GX), Vector3.ONE * 0.01)
	assert_vector(at.call("NeedleworkClock")).is_equal_approx(
		MuseumDisplay.gx_to_world(grid, NeedleworkPresenter.CLOCK_GX), Vector3.ONE * 0.01)
	for i in 4:
		var mannequin: Node = root.get_node("Mannequin_%d" % i)
		var stand: Node = root.get_node("UmbrellaStand_%d" % i)
		assert_vector(at.call("Mannequin_%d" % i)).is_equal_approx(
			MuseumDisplay.gx_to_world(grid, NeedleworkPresenter.MANNEQUIN_GX[i]), Vector3.ONE * 0.01)
		assert_vector(at.call("UmbrellaStand_%d" % i)).is_equal_approx(
			MuseumDisplay.gx_to_world(grid, NeedleworkPresenter.UMBRELLA_GX[i]), Vector3.ONE * 0.01)
		assert_int(mannequin.get("slot")).is_equal(i)
		assert_int(mannequin.get("kind")).is_equal(0)
		assert_int(stand.get("slot")).is_equal(DesignBook.CLOTH_SLOTS + i)
		assert_int(stand.get("kind")).is_equal(1)
		assert_object(mannequin.get_node_or_null("BlobShadow")).is_not_null()
	## the machine overlay sits on the grid origin (its verts are acre GX from the NW corner)
	assert_float(at.call("SewingMachine").x - grid.origin.x).is_less(1.0)
	## the presenter only adds the hulls and beams, and a second pass adds nothing
	NeedleworkPresenter.new().present(root, session)
	var count: int = root.get_child_count()
	NeedleworkPresenter.new().present(root, session)
	assert_int(root.get_child_count()).is_equal(count)


func test_sable_sews_at_the_machine() -> void:
	var sable: Node = auto_free(load("res://scenes/world/interiors/sable.tscn").instantiate())
	add_child(sable)
	var ap: AnimationPlayer = _find_anim(sable)
	assert_that(ap).is_not_null()
	assert_bool(ap.is_playing()).is_true()
	## faces south (+Z, yaw 0) toward the player / the work — decomp `head.lock_flag`
	assert_float(sable.rotation.y).is_equal_approx(0.0, 0.05)

	## placed just north of the baked machine head (world ≈ (-12.5, _, -9.0))
	var room: Room = InteriorCatalog.room_template(&"needlework")
	var session := IndoorSession.new()
	session.bind(room)
	var pos := MuseumDisplay.gx_to_world(session.grid, NeedleworkPresenter.SABLE_GX)
	assert_bool(room.is_inner(session.grid.world_to_cell(pos))).is_true()
	assert_float(pos.z).is_equal_approx(-10.5, 1.2)
	assert_float(pos.x).is_equal_approx(-11.7, 1.0)


func test_mabel_roams_and_collides_with_the_world() -> void:
	var mabel: Node = load("res://scenes/world/interiors/mabel.tscn").instantiate()
	add_child(mabel)
	auto_free(mabel)
	## `CharacterBody3D` so she can roam / follow the player (`aNNW_MY_PROC_*`).
	assert_bool(mabel is CharacterBody3D).is_true()
	## masks the world (furniture / walls) so she can't walk through it
	assert_int((mabel as CharacterBody3D).collision_mask & 1).is_equal(1)
	## on the character layer (4) — the player collides with her (immovable, like decomp)
	assert_int((mabel as CharacterBody3D).collision_layer & 4).is_equal(4)


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r:
			return r
	return null


func test_starter_shop_designs_are_distinct() -> void:
	var book := DesignBook.new()
	var seen: Dictionary = {}
	for i in 8:
		var key: int = hash(book.shop[i].pixels)
		assert_bool(seen.has(key)).override_failure_message(
			"shop design %d ('%s') is not visually distinct" % [i, book.shop[i].name]
		).is_false()
		seen[key] = true
	assert_bool(book.shop[0].pixels == DesignPattern.blank().pixels).is_false()


func test_design_texture_renders_32x32_rgba() -> void:
	var d := DesignPattern.generate(DesignPattern.Motif.CHECK, 3, 2, 9)
	var img := DesignTexture.image(d)
	assert_int(img.get_width()).is_equal(32)
	assert_int(img.get_height()).is_equal(32)
	assert_float(img.get_pixel(0, 0).a).is_equal(1.0)


func test_blocked_units_match_the_rom_tailor_bg() -> void:
	var blocked: Dictionary = NeedleworkPresenter.blocked_units()
	if blocked.is_empty():
		return  ## `rom_tailor.col.json` not generated (no disc)
	## `rom_tailor` raises only these units inside the shop floor.
	var want: Array[Vector2i] = [
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 3), Vector2i(2, 3),
		Vector2i(2, 5), Vector2i(2, 6), Vector2i(8, 6),
	]
	assert_int(blocked.size()).is_equal(want.size())
	for cell: Vector2i in want:
		assert_bool(blocked.has(cell)).is_true()
	## Sable's spot beside the machine is floor.
	assert_bool(blocked.has(Vector2i(2, 2))).is_false()



func test_window_sunbeams_follow_ef_room_sunshine() -> void:
	## `ROOM_SUNSHINE` arg 2 / 3: the constructor nets −2 / 0 X and lifts 1.1 GX.
	assert_vector(WindowSunshine.anchor_gx(WindowSunshine.NEEDLEWORK[0], true)) \
		.is_equal(Vector3(38.0, 1.1, 160.0))
	assert_vector(WindowSunshine.anchor_gx(WindowSunshine.NEEDLEWORK[1], false)) \
		.is_equal(Vector3(360.0, 1.1, 160.0))
	## Morning: only the east beam, reaching full length (1.5) at 04:00.
	assert_float(WindowSunshine.stretch(8 * 3600, true)).is_equal(0.0)
	assert_float(WindowSunshine.stretch(4 * 3600, false)).is_equal_approx(1.5, 0.001)
	assert_float(WindowSunshine.stretch(8 * 3600, false)).is_greater(0.0)
	## Afternoon: only the west beam, growing from noon.
	assert_float(WindowSunshine.stretch(15 * 3600, false)).is_equal(0.0)
	assert_float(WindowSunshine.stretch(15 * 3600, true)).is_greater(0.0)


func test_present_adds_both_window_sunbeams() -> void:
	var session := IndoorSession.new()
	session.bind(InteriorCatalog.room_template(&"needlework"))
	var root := Node3D.new()
	auto_free(root)
	add_child(root)
	NeedleworkPresenter.new().present(root, session)
	var left: Node3D = root.get_node_or_null("SunshineL") as Node3D
	var right: Node3D = root.get_node_or_null("SunshineR") as Node3D
	assert_object(left).is_not_null()
	assert_object(right).is_not_null()
	assert_bool(left.get("left")).is_true()
	assert_bool(right.get("left")).is_false()
	assert_float(right.position.x).is_greater(left.position.x)
## `mPr_FOREIGNER`: Sable treats a visitor as a stranger and doesn't count the day.
func test_sable_keeps_her_count_for_residents_only() -> void:
	var sable: Node = auto_free(load("res://scenes/world/interiors/sable.tscn").instantiate())
	add_child(sable)
	Game.designs.sable_days = 6
	Game.designs.sable_last_date = ""
	Game.foreigner = true
	sable.call("_begin_talk", InteractionContext.new())
	assert_int(Game.designs.sable_days).is_equal(6)
	assert_int(int(sable.get("_story_row"))).is_less(5)
	assert_bool(bool(sable.get("_turns_to_player"))).is_false()
	sable.call("_end_talk")
	Game.foreigner = false
	Game.reset_session()


func test_displays_carry_their_bodies_and_reach_in_the_scene() -> void:
	var mannequin: StaticBody3D = auto_free(load("res://scenes/world/interiors/able_fixture.tscn").instantiate())
	var stand: StaticBody3D = auto_free(load("res://scenes/world/interiors/umbrella_stand.tscn").instantiate())
	for display: StaticBody3D in [mannequin, stand]:
		assert_int(display.collision_layer).is_equal(PhysicsLayers.WORLD)
		assert_int(display.collision_mask).is_equal(0)
		assert_bool(display.is_in_group("interactable")).is_true()
		var reach: Area3D = display.get_node("InteractVolume") as Area3D
		assert_int(reach.collision_layer).is_equal(PhysicsLayers.INTERACT)
	assert_int(mannequin.get("kind")).is_equal(0)
	assert_int(stand.get("kind")).is_equal(1)
	## an umbrella stand is much shorter than a dress form
	var body_h := func(display: Node) -> float:
		return ((display.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D).size.y
	assert_float(body_h.call(stand)).is_less(body_h.call(mannequin))


## False when a dependency (the shell GLB) is not generated (no disc): Godot would
## load the scene with later nodes cut loose from their parents.
static func _deps_exist(path: String) -> bool:
	for dep: String in ResourceLoader.get_dependencies(path):
		if not ResourceLoader.exists(dep.get_slice("::", dep.get_slice_count("::") - 1)):
			return false
	return true
