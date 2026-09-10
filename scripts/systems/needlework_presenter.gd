class_name NeedleworkPresenter
extends RefCounted

## Furnishes the Able Sisters interior: the animated sewing machine + fabric, the
## 4 clothing mannequins + 4 umbrella stands, Mabel & Sable, the back-wall clock,
## and solid hulls for the shell's baked west counter / east fabric boxes.
##
## Decomp: `ac_needlework_indoor.c` (`manekin_pos` / `umbrella_pos`),
## `ac_npc_needlework.c` (sisters), `ac_misin.c` (machine + dustcloth),
## `HOUSE_CLOCK` / `obj_clock_tailor`. The static machine body / table / register /
## boxes are baked into the `rom_tailor` shell.

const ABLE_FIXTURE_SCENE := preload("res://scenes/world/interiors/able_fixture.tscn")
const MABEL_SCENE := preload("res://scenes/world/interiors/mabel.tscn")
const SABLE_SCENE := preload("res://scenes/world/interiors/sable.tscn")
const CLOCK_SCRIPT := preload("res://scenes/world/interiors/needlework_clock.gd")
const CLOTH_SCRIPT := preload("res://scenes/world/interiors/sewing_cloth.gd")

## Exact `ac_needlework_indoor.c` tables (`manekin_pos` z=100, `umbrella_pos` z=180,
## 40 GX apart). `rom_tailor` keeps the acre origin, so these map straight through
## `gx_to_world`. (`y=40` in decomp is a model-draw offset; `attach` foot-snaps.)
const MANNEQUIN_GX: Array = [
	Vector3(180, 0, 100), Vector3(220, 0, 100), Vector3(260, 0, 100), Vector3(300, 0, 100),
]
const UMBRELLA_GX: Array = [
	Vector3(180, 0, 180), Vector3(220, 0, 180), Vector3(260, 0, 180), Vector3(300, 0, 180),
]
## Sable sits north of the shell's baked machine (`_schedule.c_inc` x=87, z≈home.z+13,
## facing south); `NEEDLEWORK_MABEL_GX` is Mabel's roam home near the door.
const SABLE_GX := Vector3(87, 0, 108)
const MABEL_GX := Vector3(210, 0, 250)
## The animated `obj_misin` overlay onto the shell's static machine head (raw
## `obj_misin` verts land ~2.5 m high / a touch west — tuned visually).
const MISIN_OFFSET := Vector3(0.8, -2.25, 0.0)
## Back-wall pendulum clock centre (`needlework_clock.gd` recentres the AABB on the
## host). `aHC_position_data[SCENE_NEEDLEWORK]` is `{0,0,0}` (unplaced) in decomp.
const CLOCK_GX := Vector3(200.0, 46.0, 46.0)
const CLOTH_SCALE := 0.34


func present(root: Node3D, interior: Interior) -> void:
	if root == null or interior == null or interior.grid == null:
		return
	var grid: WorldGrid = interior.grid
	_furniture_collision(root)
	_sewing_machine(root, grid)
	_clock(root, grid)
	for i in MANNEQUIN_GX.size():
		if root.get_node_or_null("Mannequin_%d" % i) != null:
			continue
		var m: Node3D = ABLE_FIXTURE_SCENE.instantiate() as Node3D
		m.name = "Mannequin_%d" % i
		m.set("slot", i)
		m.set("kind", 0)
		m.position = MuseumDisplay.gx_to_world(grid, MANNEQUIN_GX[i])
		root.add_child(m)
		InteriorShadow.add(m, Vector2(0.62, 0.62), 0.34)
	for i in UMBRELLA_GX.size():
		if root.get_node_or_null("UmbrellaStand_%d" % i) != null:
			continue
		var u: Node3D = ABLE_FIXTURE_SCENE.instantiate() as Node3D
		u.name = "UmbrellaStand_%d" % i
		u.set("slot", DesignBook.CLOTH_SLOTS + i)
		u.set("kind", 1)
		u.position = MuseumDisplay.gx_to_world(grid, UMBRELLA_GX[i])
		root.add_child(u)
		InteriorShadow.add(u, Vector2(0.7, 0.7), 0.34)
	if root.get_node_or_null("Sable") == null:
		var sable: Node3D = SABLE_SCENE.instantiate() as Node3D
		sable.position = MuseumDisplay.gx_to_world(grid, SABLE_GX)
		root.add_child(sable)
		InteriorShadow.add(sable, Vector2(0.7, 0.58), 0.4)
	if root.get_node_or_null("Mabel") == null:
		var mabel: Node3D = MABEL_SCENE.instantiate() as Node3D
		mabel.position = MuseumDisplay.gx_to_world(grid, MABEL_GX)
		root.add_child(mabel)
		InteriorShadow.add(mabel, Vector2(0.7, 0.58), 0.4)


## Solid hulls for the `rom_tailor` shell's baked furniture — the blocked FG-cell
## runs in `rom_tailor.col.json` (cells (1-2, 1-6) west, cell (8, 6) south-east).
## `_add_shell_collision` only builds the floor slab + perimeter walls.
func _furniture_collision(root: Node3D) -> void:
	if root.get_node_or_null("NeedleworkFurnitureCol") != null:
		return
	var box := StaticBody3D.new()
	box.name = "NeedleworkFurnitureCol"
	box.collision_layer = 1
	box.collision_mask = 0
	root.add_child(box)
	var slabs := [
		[Vector3(2.0, 1.1, 6.0), Vector3(-12.0, 1.1, -8.0)],   ## west counter run
		[Vector3(1.0, 0.9, 1.0), Vector3(1.0, 0.9, -3.0)],     ## south-east fabric boxes
	]
	for slab: Array in slabs:
		var shape := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = (slab[0] as Vector3) * 2.0
		shape.shape = b
		shape.position = slab[1]
		box.add_child(shape)


## `ac_misin.c`: `obj_misin` verts are drawn `Matrix_translate(0) * Matrix_scale(0.01)`
## — authored in acre GX from the block NW corner, same datum as the kept-acre shell.
## Instantiate raw (no actor foot-snap), scale to metres, park at the grid origin,
## loop the "obj_misin" clip (needle bob + belt scroll).
func _sewing_machine(root: Node3D, grid: WorldGrid) -> void:
	var paths: PackedStringArray = FieldCatalog.mesh_paths(&"obj_misin")
	if paths.is_empty():
		return
	var packed: PackedScene = load(paths[0]) as PackedScene
	if packed == null:
		return
	var inst: Node = packed.instantiate()
	if not (inst is Node3D):
		return
	var pivot := Node3D.new()
	pivot.name = "SewingMachine"
	pivot.add_child(inst)
	root.add_child(pivot)
	GeneratedVisual._apply_materials(pivot)
	GeneratedVisual._disable_shadows(pivot)
	pivot.scale = Vector3.ONE * FieldCatalog.actor_uniform_scale_for(&"obj_misin")
	pivot.position = grid.origin + MISIN_OFFSET
	var anim: AnimationPlayer = GeneratedVisual.find_animation_player(pivot)
	if anim != null and anim.get_animation_list().size() > 0:
		var clip: String = anim.get_animation_list()[0]
		var a: Animation = anim.get_animation(clip)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR
		anim.play(clip)
	_sewing_cloth(root)


## The patterned fabric on the machine bed (`obj_misin_cloth` / `aMSN_DustCloth_c`).
## `SewingCloth` (does the RotateY) → `Pivot` (slid by `-target_pos`) → quad (flat
## on the bed, local-centre corrected).
func _sewing_cloth(root: Node3D) -> void:
	var paths: PackedStringArray = FieldCatalog.mesh_paths(&"obj_misin_cloth")
	if paths.is_empty():
		return
	var packed: PackedScene = load(paths[0]) as PackedScene
	if packed == null:
		return
	var inst: Node = packed.instantiate()
	if not (inst is Node3D):
		return
	var node := Node3D.new()
	node.name = "SewingCloth"
	node.set_script(CLOTH_SCRIPT)
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	node.add_child(pivot)
	var quad := inst as Node3D
	pivot.add_child(quad)
	quad.scale = Vector3.ONE * CLOTH_SCALE
	quad.position = Vector3(0.0, -5.3 * CLOTH_SCALE, 0.0)
	## Machine bed centre (`obj_misin` needle ≈ world (-11.9, 0.9, -9)); rides ~1 cm above.
	node.position = Vector3(-11.9, 0.95, -9.0)
	root.add_child(node)  ## after children so the script's `_ready` sees Pivot
	var tex := DesignTexture.build(DesignPattern.generate(DesignPattern.Motif.CHECK, 8, 2, 15))
	for mi in _mesh_instances(node):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mi.set_surface_override_material(0, mat)
	GeneratedVisual._disable_shadows(node)


## Back-wall pendulum clock (`HOUSE_CLOCK` / `obj_clock_tailor`).
func _clock(root: Node3D, grid: WorldGrid) -> void:
	if root.get_node_or_null("NeedleworkClock") != null:
		return
	if FieldCatalog.mesh_paths(&"obj_clock_tailor").is_empty():
		return
	var host := Node3D.new()
	host.name = "NeedleworkClock"
	host.set_script(CLOCK_SCRIPT)
	host.position = MuseumDisplay.gx_to_world(grid, CLOCK_GX)
	root.add_child(host)


func _mesh_instances(n: Node, acc: Array = []) -> Array:
	if n is MeshInstance3D:
		acc.append(n)
	for c in n.get_children():
		_mesh_instances(c, acc)
	return acc
