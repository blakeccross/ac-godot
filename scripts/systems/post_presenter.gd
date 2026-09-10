class_name PostPresenter
extends RefCounted

## Furnishes the post office: Pelly / Phyllis at the desk, an invisible hull for
## the baked counter, the left-side e-Terminal, and one letter prop per stored
## piece of mail (`aPG_actor_ct`, `POST_OFFICE_actor_data`, `bPTI_actor_draw`).
## Mail piles join the `"authored_fixture"`-free set so `refresh_public_set`
## rebuilds them.

const POST_GIRL_SCENE := preload("res://scenes/world/interiors/post_girl.tscn")
const POST_DESK_SCRIPT := preload("res://scenes/world/interiors/post_desk.gd")
const POST_TERMINAL_SCRIPT := preload("res://scenes/world/interiors/post_terminal.gd")


func present(root: Node3D, interior: Interior) -> void:
	if root == null or interior == null or interior.grid == null:
		return
	_post_girl(root, interior)
	_desk(root, interior)
	_terminal(root, interior)
	_mail_piles(root, interior)


func _post_girl(root: Node3D, interior: Interior) -> void:
	var pos: Vector3 = PostDisplay.gx_to_world(interior.grid, PostDisplay.POST_GIRL_STAND_GX)
	var yaw: float = WorldGrid.yaw_for_facing(PostDisplay.POST_GIRL_FACING)
	var existing: Node3D = root.get_node_or_null("PostGirl") as Node3D
	if existing != null:
		existing.position = pos
		existing.rotation.y = yaw
		return
	var girl: Node3D = POST_GIRL_SCENE.instantiate() as Node3D
	girl.name = "PostGirl"
	girl.position = pos
	girl.rotation.y = yaw
	root.add_child(girl)


func _desk(root: Node3D, interior: Interior) -> void:
	## Invisible hull for the baked counter — GLB has no collision. Talk forwards to clerk.
	var half: Vector3 = PostDisplay.DESK_HALF_GX * FieldCatalog.GX_TO_METERS
	var pos: Vector3 = PostDisplay.gx_to_world(interior.grid, PostDisplay.DESK_CENTER_GX)
	pos.y = half.y
	var existing: StaticBody3D = root.get_node_or_null("PostDesk") as StaticBody3D
	if existing != null:
		existing.position = pos
		return
	var body := StaticBody3D.new()
	body.name = "PostDesk"
	body.set_script(POST_DESK_SCRIPT)
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = half * 2.0
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)


func _terminal(root: Node3D, interior: Interior) -> void:
	## Left-side eTM (`POST_OFFICE_actor_data` PTerminal at GX {60,0,240}).
	var pos: Vector3 = PostDisplay.gx_to_world(interior.grid, PostDisplay.PTERMINAL_GX)
	var existing: StaticBody3D = root.get_node_or_null("PostTerminal") as StaticBody3D
	if existing != null:
		existing.position = pos
		return
	var body := StaticBody3D.new()
	body.name = "PostTerminal"
	body.set_script(POST_TERMINAL_SCRIPT)
	body.position = pos
	root.add_child(body)


func _mail_piles(root: Node3D, interior: Interior) -> void:
	## `bPTI_actor_draw` — one letter prop per stored piece of mail, max 5.
	if Game == null or Game.post == null:
		return
	for old: Node in root.get_children():
		if String(old.name).begins_with("MailPile_"):
			old.queue_free()
	var sum: int = mini(Game.post.get_keep_mail_sum(), PostDisplay.MAIL_PILE_X_GX.size())
	for i: int in sum:
		var host := Node3D.new()
		host.name = "MailPile_%d" % i
		host.position = PostDisplay.gx_to_world(interior.grid, PostDisplay.mail_pile_gx(i))
		root.add_child(host)
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.35, 0.08, 0.25)
		box.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.92, 0.88, 0.78)
		box.material_override = mat
		box.position.y = 0.04
		host.add_child(box)
