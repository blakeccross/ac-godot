class_name MuseumPresenter
extends RefCounted

## Spawns museum wing exhibits from `Game.museum` bits when a museum room loads.
## Fossils rewrite FG furniture; fish/insects are live actors; paintings swap art/frame.

const PLAQUE_SCENE := preload("res://scenes/world/museum_plaque.tscn")


func present(root: Node3D, interior: Interior) -> void:
	if root == null or interior == null or interior.room == null or Game == null:
		return
	var room: Room = interior.room
	if room.kind != Room.Kind.MUSEUM:
		return
	match room.id:
		&"museum_fossil":
			present_fossils(root, interior)
		&"museum_painting":
			present_paintings(root, interior)
		&"museum_fish":
			present_fish(root, interior)
		&"museum_insect":
			present_insects(root, interior)
		_:
			pass
	if String(room.id).begins_with("museum_"):
		_add_wing_hotkeys(root)


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
	keys.set_script(load("res://scenes/world/museum_wing_keys.gd"))
	root.add_child(keys)


func present_fossils(root: Node3D, interior: Interior) -> void:
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
		_add_exhibit_collision(node)
	_add_fossil_plaques(root, interior)


func _add_fossil_plaques(root: Node3D, interior: Interior) -> void:
	## One plaque near each skeleton group / solo row.
	var book: MuseumBook = Game.museum
	var groups: Array = MuseumDisplay.FOSSIL_SETS.duplicate()
	groups.append(MuseumDisplay.FOSSIL_SOLO)
	var labels: Array[String] = [
		"Triceratops",
		"T. Rex",
		"Apatosaurus",
		"Stegosaurus",
		"Pteranodon",
		"Plesiosaur",
		"Mammoth",
		"Fossil Finds",
	]
	for gi: int in groups.size():
		var parts: Array = groups[gi] as Array
		var lines := PackedStringArray()
		var cell_sum := Vector2i.ZERO
		var n: int = 0
		for part: Variant in parts:
			var idx: int = int(part)
			cell_sum += MuseumDisplay.FOSSIL_CELLS[idx]
			n += 1
			if MuseumBook.is_donated(book.fossil_info(idx)):
				var name := String(MuseumDisplay.FOSSIL_VISUALS[idx]).replace("int_din_", "").replace("_", " ").capitalize()
				lines.append(name)
		if n <= 0:
			continue
		var avg := Vector2i(cell_sum.x / n, cell_sum.y / n + 1)
		var plaque: Node3D = PLAQUE_SCENE.instantiate() as Node3D
		plaque.position = interior.grid.cell_to_world(avg)
		if plaque.has_method("setup"):
			plaque.call("setup", labels[gi] if gi < labels.size() else "Fossils", lines)
		root.add_child(plaque)


func present_paintings(root: Node3D, interior: Interior) -> void:
	var book: MuseumBook = Game.museum
	for i: int in MuseumBook.ART_NUM:
		var donated: bool = MuseumBook.is_donated(book.art_info(i))
		var cell: Vector2i = MuseumDisplay.ART_CELLS[i]
		## `aMP_DrawOneArt`: unit-center XZ, hang at Y=40 GX (not floor).
		var gx := Vector3(
			float(cell.x) * 40.0 + 20.0, MuseumDisplay.ART_HANG_Y_GX, float(cell.y) * 40.0 + 20.0
		)
		var node := Node3D.new()
		node.name = "Art_%02d" % i
		node.add_to_group("museum_set")
		node.position = MuseumDisplay.gx_to_world(interior.grid, gx)
		root.add_child(node)
		var visual: StringName = (
			MuseumDisplay.ART_MUSEUM_VISUALS[i] if donated else MuseumDisplay.ART_MUSEUM_DUMMIES[i]
		)
		if not _attach_museum_art(node, visual):
			_add_art_placeholder(node, donated)
		## Talk only when facing south within 33 GX (`aMP_CheckTalkAbleDist`).
		var plaque: Node3D = PLAQUE_SCENE.instantiate() as Node3D
		plaque.position = MuseumDisplay.gx_to_world(
			interior.grid, Vector3(gx.x, 0.0, gx.z + 40.0)
		)
		var lines := PackedStringArray()
		if donated:
			lines.append(String(MuseumDisplay.ART_VISUALS[i]).replace("int_sum_", "").replace("_", " ").capitalize())
		if plaque.has_method("setup"):
			plaque.call("setup", "Painting %d" % (i + 1), lines)
		root.add_child(plaque)


func present_fish(root: Node3D, interior: Interior) -> void:
	_spawn_fish_tanks(root, interior)
	var book: MuseumBook = Game.museum
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("museum_fish_%s" % Game.town_name)
	for i: int in MuseumBook.FISH_NUM:
		if not MuseumBook.is_donated(book.fish_info(i)):
			continue
		var fish: FishData = FishCatalog.get_fish(MuseumDisplay.fish_id_at(i))
		if fish == null:
			continue
		var actor: MuseumFishActor = MuseumFishActor.create(fish, i, interior.grid, rng)
		if actor == null:
			continue
		var visual: MuseumFishVisual = MuseumFishVisual.create(actor)
		if visual == null:
			continue
		visual.name = "Fish_%02d" % i
		visual.add_to_group("museum_set")
		root.add_child(visual)
	for gi: int in MuseumDisplay.FISH_PLAQUE_GROUPS.size():
		var group: Array = MuseumDisplay.FISH_PLAQUE_GROUPS[gi] as Array
		var lines := PackedStringArray()
		for idx_v: Variant in group:
			var idx: int = int(idx_v)
			if not MuseumBook.is_donated(book.fish_info(idx)):
				continue
			var fish: FishData = FishCatalog.get_fish(MuseumDisplay.fish_id_at(idx))
			if fish != null:
				lines.append(fish.display_name)
		var plaque: Node3D = PLAQUE_SCENE.instantiate() as Node3D
		plaque.position = MuseumDisplay.gx_to_world(interior.grid, MuseumDisplay.FISH_PLAQUE_POS[gi])
		if plaque.has_method("setup"):
			plaque.call("setup", "Tank %s" % char(65 + gi), lines)
		root.add_child(plaque)


func _spawn_fish_tanks(root: Node3D, interior: Interior) -> void:
	## `Museum_Fish_Suisou_draw`: tanks 0–3 = `obj_suisou1` at `suisou_pos` × 0.01;
	## tank 4 = `obj_museum5` at field scale with no translate (verts already in acre space).
	## Glass authored with min Y at the water-line (40 GX); shell floors snap that to 0,
	## so ground-align the mesh bottom onto the walkable floor.
	var grid: WorldGrid = interior.grid
	for i: int in 4:
		var node := Node3D.new()
		node.name = "Tank_%d" % i
		node.add_to_group("museum_set")
		var gx: Vector3 = MuseumDisplay.TANK_POS_GX[i]
		node.position = MuseumDisplay.gx_to_world(grid, Vector3(gx.x, 0.0, gx.z))
		root.add_child(node)
		var pivot: Node3D = GeneratedVisual.attach(node, &"obj_suisou1")
		if pivot != null:
			GeneratedVisual.align_actor_to_height_gx(pivot, 0.0)
		_add_tank_collision(node, MuseumDisplay.TANK_HALF_GX)
	var sea := Node3D.new()
	sea.name = "Tank_4"
	sea.add_to_group("museum_set")
	## Acre-space mesh (`Matrix_scale(0.0625)`, no translate) — same origin/datum as
	## `rom_museum5`. Do not AABB-snap; `_fit` applies `acre_ground_y_offset`.
	sea.position = Vector3(grid.origin.x, 0.0, grid.origin.z)
	root.add_child(sea)
	GeneratedVisual.attach(sea, &"obj_museum5")
	var sea_center: Vector3 = MuseumDisplay.gx_to_world(grid, MuseumDisplay.TANK_POS_GX[4])
	_add_tank_collision(sea, MuseumDisplay.SEA_TANK_HALF_GX, sea_center - sea.position)


func _add_tank_collision(host: Node3D, half_gx: Vector3, local_center: Vector3 = Vector3.ZERO) -> void:
	## Opaque glass boxes so the player cannot walk through tanks.
	var body := StaticBody3D.new()
	body.name = "TankCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = local_center + Vector3(0.0, 1.2, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(
		maxf(half_gx.x * 2.0 * FieldCatalog.GX_TO_METERS, 1.0),
		2.4,
		maxf(half_gx.z * 2.0 * FieldCatalog.GX_TO_METERS, 1.0)
	)
	shape.shape = box
	body.add_child(shape)
	host.add_child(body)


func _add_exhibit_collision(host: Node3D) -> void:
	## Pedestal / skeleton hull from the attached mesh AABB.
	if host == null or host.get_node_or_null("ExhibitCollision") != null:
		return
	var body := StaticBody3D.new()
	body.name = "ExhibitCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var aabb: AABB = GeneratedVisual.local_aabb(host)
	if aabb.size == Vector3.ZERO:
		box.size = Vector3(1.6, 2.0, 1.6)
		body.position = Vector3(0.0, 1.0, 0.0)
	else:
		box.size = Vector3(
			maxf(aabb.size.x, 1.0), maxf(aabb.size.y, 1.0), maxf(aabb.size.z, 1.0)
		)
		body.position = aabb.position + aabb.size * 0.5
	shape.shape = box
	body.add_child(shape)
	host.add_child(body)


func present_insects(root: Node3D, interior: Interior) -> void:
	var book: MuseumBook = Game.museum
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("museum_insect_%s" % Game.town_name)
	for i: int in MuseumBook.INSECT_NUM:
		if not MuseumBook.is_donated(book.insect_info(i)):
			continue
		var bug: BugData = BugCatalog.get_by_type(i)
		if bug == null:
			continue
		var actor: MuseumInsectActor = MuseumInsectActor.create(bug, interior.grid, rng)
		if actor == null:
			continue
		var visual: MuseumInsectVisual = MuseumInsectVisual.create(actor)
		if visual == null:
			continue
		visual.name = "Insect_%02d" % i
		visual.add_to_group("museum_set")
		root.add_child(visual)
	for gi: int in MuseumDisplay.INSECT_PLAQUE_GROUPS.size():
		var group: Array = MuseumDisplay.INSECT_PLAQUE_GROUPS[gi] as Array
		var lines := PackedStringArray()
		for idx_v: Variant in group:
			var idx: int = int(idx_v)
			if not MuseumBook.is_donated(book.insect_info(idx)):
				continue
			var bug: BugData = BugCatalog.get_by_type(idx)
			if bug != null:
				lines.append(bug.display_name)
		var plaque: Node3D = PLAQUE_SCENE.instantiate() as Node3D
		plaque.position = MuseumDisplay.gx_to_world(interior.grid, MuseumDisplay.INSECT_PLAQUE_POS[gi])
		if plaque.has_method("setup"):
			plaque.call("setup", "Case %d" % (gi + 1), lines)
		root.add_child(plaque)


func _attach_visual(node: Node3D, visual_id: StringName) -> bool:
	var path := "res://assets/generated/furniture/%s.glb" % String(visual_id)
	if not ResourceLoader.exists(path):
		return false
	GeneratedVisual.attach(node, visual_id)
	return node.get_child_count() > 0


func _attach_museum_art(node: Node3D, visual_id: StringName) -> bool:
	## Host is already at `aMP_DrawOneArt` cell-center + Y=40 GX. Keep authored
	## mesh XZ offsets (wall depth) and let `_fit_actor` rest the frame bottom on
	## the hang line — do not AABB-recenter or undo the origin snap.
	return GeneratedVisual.attach(node, visual_id) != null


func _add_art_placeholder(node: Node3D, filled: bool) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 1.4, 0.08)
	mesh.mesh = box
	## BoxMesh is centered; lift by half-height so the bottom sits on hang Y.
	mesh.position.y = box.size.y * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.38, 0.22) if not filled else Color(0.9, 0.85, 0.7)
	mesh.material_override = mat
	node.add_child(mesh)
