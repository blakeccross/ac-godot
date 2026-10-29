class_name MuseumPresenter
extends RefCounted

## Spawns museum wing exhibits from `Game.museum` bits when a museum room loads.
## Fossils rewrite FG furniture; fish/insects are live actors; paintings swap art/frame.

## A donated insect in its case is the field's `Bug` scene in display mode.
const BUG_SCENE := preload("res://features/bugs/bug.tscn")
const PLAQUE_SCENE := preload("res://features/museum/museum_plaque.tscn")
const SUNSHINE_SCENE := preload("res://features/shops/police_box/police_sunshine.tscn")


func present(root: Node3D, interior: IndoorSession) -> void:
	if root == null or interior == null or interior.room == null or Game == null:
		return
	var room: Room = interior.room
	if room.kind != Room.Kind.MUSEUM:
		return
	match room.id:
		&"museum_entrance":
			present_sunshine(root, interior)
		&"museum_fossil":
			present_fossils(root, interior)
		&"museum_painting":
			present_paintings(root, interior)
		&"museum_fish":
			present_fish(root, interior)
		&"museum_insect":
			present_insects(root, interior)
			present_sunshine(root, interior)
		_:
			pass
	if String(room.id).begins_with("museum_"):
		_add_wing_hotkeys(root)


## Window beams for the entrance hall and the insect wing (`MuseumDisplay.*_SUNSHINE_GX`),
## one `police_sunshine.tscn` per actor, even actors west. Idempotent; they survive a
## re-populate as authored fixtures.
func present_sunshine(root: Node3D, interior: IndoorSession) -> void:
	if root == null or interior == null or interior.room == null or interior.grid == null:
		return
	var insect: bool = interior.room.id == &"museum_insect"
	var actors: Array[Vector3] = (
		MuseumDisplay.INSECT_SUNSHINE if insect else MuseumDisplay.ENTRANCE_SUNSHINE
	)
	for i: int in actors.size():
		var left: bool = i % 2 == 0
		var node_name := "Sunshine_%d" % i
		var node: Node3D = root.get_node_or_null(node_name) as Node3D
		if node == null:
			node = SUNSHINE_SCENE.instantiate() as Node3D
			node.name = node_name
			node.add_to_group("authored_fixture")
			node.set("left", left)
			node.set("cull", false)
			if insect:
				node.set("visual", MuseumDisplay.INSECT_SUNSHINE_VISUAL)
			else:
				node.set("visual", MuseumDisplay.ENTRANCE_SUNSHINE_VISUAL)
				node.set("stained_glass", true)
			root.add_child(node)
		node.position = WorldGrid.room_point(
			interior.grid, MuseumDisplay.sunshine_anchor(actors[i], left, insect)
		)


func _add_wing_hotkeys(root: Node3D) -> void:
	## Dev / complete-museum harness: 1–5 jump between wings.
	## Authored `museum_complete.tscn` already owns `MuseumWingKeys`.
	if Engine.get_main_loop() is SceneTree:
		var tree := Engine.get_main_loop() as SceneTree
		if not tree.get_nodes_in_group("museum_complete_stage").is_empty():
			return
	if root.get_node_or_null("MuseumWingKeys") != null:
		return
	var keys := Node.new()
	keys.name = "MuseumWingKeys"
	keys.set_script(load("res://features/museum/museum_wing_keys.gd"))
	root.add_child(keys)


func present_fossils(root: Node3D, interior: IndoorSession) -> void:
	var book: MuseumBook = Game.museum
	for i: int in MuseumBook.FOSSIL_NUM:
		var donated: bool = MuseumBook.is_donated(book.fossil_info(i))
		var visual: StringName = (
			MuseumDisplay.FOSSIL_VISUALS[i] if donated else MuseumDisplay.FOSSIL_DUMMIES[i]
		)
		var cell: Vector2i = MuseumDisplay.FOSSIL_CELLS[i]
		var facing: WorldGrid.Facing = MuseumDisplay.FOSSIL_FACINGS[i] as WorldGrid.Facing
		var foot: Vector2i = MuseumDisplay.fossil_footprint(i)
		var node := Node3D.new()
		node.name = "Fossil_%02d" % i
		node.add_to_group("museum_set")
		node.position = interior.grid.furniture_world(cell, foot, facing)
		node.rotation.y = WorldGrid.yaw_for_furniture(facing)
		root.add_child(node)
		GeneratedVisual.attach(node, visual)
	_add_fossil_collision(root, interior)
	_add_fossil_plaques(root, interior)


## `mMmd_MuseumFossilProcess_MakeFgData` puts every slot into the room's FG as furniture — the
## fossil once donated, its dummy pedestal before — so all 25 footprints are solid (`ac_my_room`
## furniture), donated or not.
func _add_fossil_collision(root: Node3D, interior: IndoorSession) -> void:
	var terrain: Node3D = root.get_parent().get_node_or_null("Terrain") as Node3D if root.get_parent() != null else null
	if terrain == null:
		return
	var blocked: Dictionary = {}
	for i: int in MuseumBook.FOSSIL_NUM:
		var facing: WorldGrid.Facing = MuseumDisplay.FOSSIL_FACINGS[i] as WorldGrid.Facing
		for cell: Vector2i in interior.grid.footprint_cells(MuseumDisplay.FOSSIL_CELLS[i], MuseumDisplay.fossil_footprint(i), facing):
			blocked[cell] = InteriorUnitCollision.WALL
	InteriorUnitCollision.add_hulls(terrain, interior.grid, "MuseumFossilCol", blocked)


func _add_fossil_plaques(root: Node3D, interior: IndoorSession) -> void:
	## `Museum_Fossil_Actor_move`: one talk point per fossil (`aMF_fossil_data_table`).
	var book: MuseumBook = Game.museum
	for i: int in MuseumBook.FOSSIL_NUM:
		var row: Array = MuseumDisplay.FOSSIL_TALK[i] as Array
		var plaque := PLAQUE_SCENE.instantiate() as Node3D
		plaque.position = WorldGrid.room_point(
			interior.grid, Vector3((float(row[0]) + 0.5) * MuseumDisplay.UNIT, 0.0, (float(row[1]) + 0.5) * MuseumDisplay.UNIT)
		)
		root.add_child(plaque)
		plaque.call("setup_cardinal", "Fossil %d" % (i + 1), int(row[2]), MuseumDisplay.FOSSIL_TALK_REACH, false, true)
		plaque.set("entries", _entries([[_item_name(MuseumDisplay.FOSSIL_VISUALS[i]), book.fossil_info(i)]]))


## `{"name", "donor"}` for each donated `[name, donator]` pair, in order.
static func _entries(pairs: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pair: Variant in pairs:
		var donor: int = int((pair as Array)[1])
		if MuseumBook.is_donated(donor):
			out.append({"name": str((pair as Array)[0]), "donor": donor})
	return out


## Fossils and paintings are furniture keyed by their model (`FTR_DINO_START + i·4`, `FTR_SUM_ART01`).
static func _item_name(visual_id: StringName) -> String:
	var item: ItemData = ItemCatalog.get_item(visual_id)
	if item == null:
		item = ItemCatalog.furniture_for_visual(visual_id)
	return item.display_name if item != null else String(visual_id)


func present_paintings(root: Node3D, interior: IndoorSession) -> void:
	var book: MuseumBook = Game.museum
	for i: int in MuseumBook.ART_NUM:
		var donated: bool = MuseumBook.is_donated(book.art_info(i))
		var cell: Vector2i = MuseumDisplay.ART_CELLS[i]
		## `aMP_DrawOneArt`: unit-center XZ, hang at Y=40 GX (not floor).
		var at := Vector3(
			(float(cell.x) + 0.5) * MuseumDisplay.UNIT, MuseumDisplay.ART_HANG_Y, (float(cell.y) + 0.5) * MuseumDisplay.UNIT
		)
		var node := Node3D.new()
		node.name = "Art_%02d" % i
		node.add_to_group("museum_set")
		node.position = WorldGrid.room_point(interior.grid, at)
		root.add_child(node)
		var visual: StringName = (
			MuseumDisplay.ART_MUSEUM_VISUALS[i] if donated else MuseumDisplay.ART_MUSEUM_DUMMIES[i]
		)
		if not _attach_museum_art(node, visual):
			GeneratedVisual.mark_missing(
				node, visual, Color(0.9, 0.85, 0.7) if donated else Color(0.55, 0.38, 0.22), Vector3(1.2, 1.4, 0.08)
			)
		## `aMP_CheckTalkAbleDist`: (x·40 + 60, z·40 + 40) GX, read from the south within 33 GX.
		var plaque: Node3D = PLAQUE_SCENE.instantiate() as Node3D
		plaque.position = WorldGrid.room_point(
			interior.grid, Vector3(float(cell.x) * MuseumDisplay.UNIT, 0.0, float(cell.y) * MuseumDisplay.UNIT) + MuseumDisplay.ART_TALK_OFFSET
		)
		root.add_child(plaque)
		plaque.call("setup_cardinal", "Painting %d" % (i + 1), 0, MuseumDisplay.ART_TALK_REACH, true, false)
		plaque.set("entries", _entries([[_item_name(MuseumDisplay.ART_VISUALS[i]), book.art_info(i)]]))


func present_fish(root: Node3D, interior: IndoorSession) -> void:
	_spawn_fish_tanks(root, interior)
	var book: MuseumBook = Game.museum
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("museum_fish_%s" % Game.town.town_name)
	## One tank-wide system moves every fish before they draw (`Museum_Fish_Actor_move`).
	var school := MuseumFishSchool.new()
	school.name = "FishSchool"
	school.add_to_group("museum_set")
	root.add_child(school)
	for i: int in MuseumBook.FISH_NUM:
		if not MuseumBook.is_donated(book.fish_info(i)):
			continue
		var fish: FishData = FishCatalog.get_fish(MuseumDisplay.fish_id_at(i))
		if fish == null:
			continue
		var actor: MuseumFishActor = MuseumFishActor.create(fish, i, rng)
		if actor == null:
			continue
		school.add(actor)
		var visual: MuseumFishVisual = MuseumFishVisual.create(actor)
		if visual == null:
			continue
		visual.name = "Fish_%02d" % i
		visual.add_to_group("museum_set")
		root.add_child(visual)
	## `Museum_Fish_Talk_process`: a sign per tank, paging its donated fish.
	for gi: int in MuseumDisplay.FISH_PLAQUE_GROUPS.size():
		var pairs: Array = []
		for idx_v: Variant in MuseumDisplay.FISH_PLAQUE_GROUPS[gi] as Array:
			var idx: int = int(idx_v)
			var fish: FishData = FishCatalog.get_fish(MuseumDisplay.fish_id_at(idx))
			pairs.append([fish.display_name if fish != null else "", book.fish_info(idx)])
		var plaque: Node3D = PLAQUE_SCENE.instantiate() as Node3D
		var at: Vector3 = MuseumDisplay.FISH_PLAQUE_POS[gi]
		plaque.position = WorldGrid.room_point(interior.grid, Vector3(at.x, 0.0, at.z))
		root.add_child(plaque)
		plaque.call("setup_sign", "Tank %s" % char(65 + gi), MuseumDisplay.SIGN_TALK_HALF)
		plaque.set("entries", _entries(pairs))


func _spawn_fish_tanks(root: Node3D, interior: IndoorSession) -> void:
	## `Museum_Fish_Suisou_draw`: tanks 0–3 = `obj_suisou1` at `suisou_pos` × 0.01;
	## tank 4 = `obj_museum5` at field scale with no translate (verts already in acre space).
	## Glass authored with min Y at the water-line (40 GX); shell floors snap that to 0,
	## so ground-align the mesh bottom onto the walkable floor.
	var grid: WorldGrid = interior.grid
	for i: int in 4:
		var node := Node3D.new()
		node.name = "Tank_%d" % i
		node.add_to_group("museum_set")
		var tank: Vector3 = MuseumDisplay.TANK_POS[i]
		node.position = WorldGrid.room_point(grid, Vector3(tank.x, 0.0, tank.z))
		root.add_child(node)
		var pivot: Node3D = GeneratedVisual.attach(node, &"obj_suisou1")
		if pivot != null:
			VisualFit.align_actor_to_height(pivot, 0.0)
	var sea := Node3D.new()
	sea.name = "Tank_4"
	sea.add_to_group("museum_set")
	## Acre-space mesh (`Matrix_scale(0.0625)`, no translate) — same origin/datum as
	## `rom_museum5`. Do not AABB-snap; `_fit` applies `acre_ground_y_offset`.
	sea.position = Vector3(grid.origin.x, 0.0, grid.origin.z)
	root.add_child(sea)
	GeneratedVisual.attach(sea, &"obj_museum5")
	_add_tank_decor(root, grid)


## Plants in every tank, the lily on tank 1, and the vent bubbles
## (`kusa_pos` / `hasu_pos` / `suisou_awa_pos`).
func _add_tank_decor(root: Node3D, grid: WorldGrid) -> void:
	## Draw Y is absolute GX with the floor at 0. The shell has already lifted that
	## floor to world 0, so the host sits one water-line below the walkable floor.
	var drop := MuseumDisplay.tank_world_y(0.0)
	for i: int in MuseumDisplay.PLANT_POS.size():
		var visual := StringName(MuseumDisplay.PLANT_VISUAL[i])
		if FieldCatalog.mesh_paths(visual).is_empty():
			continue
		var gx: Vector3 = MuseumDisplay.PLANT_POS[i]
		var host := Node3D.new()
		host.name = "Decor_kusa_%02d" % i
		host.add_to_group("museum_set")
		host.position = WorldGrid.room_point(
			grid, Vector3(gx.x * FieldCatalog.GX_TO_METERS, drop, gx.z * FieldCatalog.GX_TO_METERS)
		)
		root.add_child(host)
		var pivot: Node3D = GeneratedVisual.attach(host, visual)
		_play_sway(pivot, MuseumDisplay.PLANT_START_FRAME[i], MuseumDisplay.plant_speed_scale(i))
	if not FieldCatalog.mesh_paths(&"obj_museum5_hasu").is_empty():
		var lily := Node3D.new()
		lily.name = "Decor_hasu"
		lily.add_to_group("museum_set")
		var at: Vector3 = MuseumDisplay.LILY_POS
		lily.position = WorldGrid.room_point(
			grid, Vector3(at.x * FieldCatalog.GX_TO_METERS, drop, at.z * FieldCatalog.GX_TO_METERS)
		)
		lily.rotation.y = MuseumDisplay.LILY_YAW
		root.add_child(lily)
		var lily_pivot: Node3D = GeneratedVisual.attach(lily, &"obj_museum5_hasu")
		_play_sway(lily_pivot, 0.0, MuseumDisplay.ckf_to_speed_scale(0.5))
	if not FieldCatalog.mesh_paths(&"ef_museum5_awa1").is_empty():
		var bubbles := Node3D.new()
		bubbles.name = "TankBubbles"
		bubbles.add_to_group("museum_set")
		bubbles.set_script(load("res://features/museum/museum_bubbles.gd"))
		bubbles.set("room_origin", grid.origin)
		root.add_child(bubbles)


## cKF sway. `start_frame` is a keyframe index; the clip is keyed at 30 fps.
func _play_sway(pivot: Node3D, start_frame: float, speed_scale: float) -> void:
	if pivot == null:
		return
	var anim := VisualAnimation.find_animation_player(pivot)
	if anim == null:
		return
	var clips := anim.get_animation_list()
	if clips.is_empty():
		return
	var clip := clips[0]
	var res := anim.get_animation(clip)
	if res != null:
		res.loop_mode = Animation.LOOP_LINEAR
	anim.speed_scale = speed_scale
	anim.play(clip)
	anim.seek(start_frame / 30.0, true)


func present_insects(root: Node3D, interior: IndoorSession) -> void:
	var book: MuseumBook = Game.museum
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("museum_insect_%s" % Game.town.town_name)
	for i: int in MuseumBook.INSECT_NUM:
		if not MuseumBook.is_donated(book.insect_info(i)):
			continue
		var bug: BugData = BugCatalog.get_by_type(i)
		if bug == null:
			continue
		var actor: MuseumInsectActor = MuseumInsectActor.create(bug, interior.grid, rng)
		if actor == null:
			continue
		var visual := BUG_SCENE.instantiate() as Bug
		visual.name = "Insect_%02d" % i
		visual.add_to_group("museum_set")
		root.add_child(visual)
		visual.setup_display(actor)
	## `Museum_Insect_Talk_process`: a sign per case, paging its donated insects.
	for gi: int in MuseumDisplay.INSECT_PLAQUE_GROUPS.size():
		var pairs: Array = []
		for idx_v: Variant in MuseumDisplay.INSECT_PLAQUE_GROUPS[gi] as Array:
			var idx: int = int(idx_v)
			var bug: BugData = BugCatalog.get_by_type(idx)
			pairs.append([bug.display_name if bug != null else "", book.insect_info(idx)])
		var plaque: Node3D = PLAQUE_SCENE.instantiate() as Node3D
		var at: Vector3 = MuseumDisplay.INSECT_PLAQUE_POS[gi]
		plaque.position = WorldGrid.room_point(interior.grid, Vector3(at.x, 0.0, at.z))
		root.add_child(plaque)
		plaque.call("setup_sign", "Case %d" % (gi + 1), MuseumDisplay.SIGN_TALK_HALF)
		plaque.set("entries", _entries(pairs))


func _attach_museum_art(node: Node3D, visual_id: StringName) -> bool:
	## Host is already at `aMP_DrawOneArt` cell-center + Y=40 GX. Keep authored
	## mesh XZ offsets (wall depth) and let `_fit_actor` rest the frame bottom on
	## the hang line — do not AABB-recenter or undo the origin snap.
	return GeneratedVisual.attach(node, visual_id) != null
