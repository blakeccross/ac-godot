extends Node3D

## Loads the real outdoor field, plants fish on river water, and screenshots that view.
##
##   $GODOT_BIN --path . res://scenes/dev/fish_in_water_proof.tscn

const OUT := "res://.tmp_psel_debug/fish_in_water.png"


func _ready() -> void:
	await _run()
	get_tree().quit()


func _run() -> void:
	Clock.paused = true
	Clock.month = 6
	Clock.hour = 12
	Game.world_mode = WorldData.Mode.GENERATED
	Game.world_seed = 42

	var world: Node3D = load("res://scenes/world/world.tscn").instantiate() as Node3D
	add_child(world)
	for _i in 45:
		await get_tree().process_frame

	for child: Node in world.get_children():
		if child is CanvasItem and String(child.name).contains("Hud"):
			(child as CanvasItem).visible = false
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false

	var grid: WorldGrid = world.get("grid") as WorldGrid
	var school: FishSchool = world.get("fish") as FishSchool
	assert(school != null and school.has_water())

	var water_cell := _pick_open_river_cell(grid, school)
	var water_pos: Vector3 = grid.cell_to_world(water_cell)
	var surface_y: float = school.surface_at(water_pos)
	var body: WaterBodies.Body = WaterBodies.body_at(school.bodies, water_cell)
	print("water_cell=", water_cell, " surface_y=", surface_y, " kind=", body.kind, " body_size=", body.size())

	school.clear()
	school.auto_spawn = false
	var pool: Array[FishData] = FishCatalog.available(6, 12, body.kind)
	assert(not pool.is_empty())
	var big: FishData = pool[0]
	for fish: FishData in pool:
		if int(fish.size_class) > int(big.size_class):
			big = fish
	## Two XL shadows centered in frame.
	school.spawn(big, body, water_pos + Vector3(-1.2, 0.0, 0.0))
	school.spawn(big, body, water_pos + Vector3(1.4, 0.0, 0.8))
	print("forced_shadows=", school.shadow_count(), " species=", big.id)

	## Stop the follow cam from yanking the view back to the player.
	var follow: Camera3D = world.get_node_or_null("FollowCamera") as Camera3D
	if follow != null:
		follow.current = false
		follow.set_process(false)
		follow.set_physics_process(false)

	var cam := Camera3D.new()
	cam.name = "ProofCam"
	cam.fov = 30.0
	cam.current = true
	world.add_child(cam)
	## Steep look: water fills most of the frame, bank along the bottom edge.
	cam.global_position = Vector3(water_pos.x, surface_y + 11.0, water_pos.z + 9.0)
	cam.look_at(Vector3(water_pos.x, surface_y, water_pos.z - 0.5))

	for _i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image: Image = get_viewport().get_texture().get_image()
	var abs_out: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
	image.save_png(abs_out)
	print("saved ", abs_out, " size=", image.get_width(), "x", image.get_height())


func _pick_open_river_cell(grid: WorldGrid, school: FishSchool) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score := -1
	for body: WaterBodies.Body in school.bodies:
		if body.kind != WaterBodies.Kind.RIVER:
			continue
		for cell: Vector2i in body.cells:
			if cell.x < 8 or cell.y < 8:
				continue
			if cell.x > grid.columns - 9 or cell.y > grid.rows - 9:
				continue
			var neighbors := 0
			for n: Vector2i in grid.neighbors4(cell):
				if body.contains(n):
					neighbors += 1
			var score: int = neighbors * 20 + mini(body.size(), 80)
			if score > best_score:
				best_score = score
				best = cell
	if best.x >= 0:
		return best
	## Fall back: any inland water.
	for body: WaterBodies.Body in school.bodies:
		for cell: Vector2i in body.cells:
			if cell.x >= 8 and cell.y >= 8 and cell.x < grid.columns - 8 and cell.y < grid.rows - 8:
				return cell
	return school.bodies[0].cells[0]
