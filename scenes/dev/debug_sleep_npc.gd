extends Node

## Print sleep NPC transform after seated preview bootstrap.


func _ready() -> void:
	Clock.paused = true
	Game.reset_session()
	var intro: Node3D = load("res://scenes/ui/intro_train.tscn").instantiate() as Node3D
	intro.preview_seated_daylight = true
	intro.preview_dialogue_text = "Thanks again!"
	add_child(intro)
	await get_tree().create_timer(3.0).timeout
	var sleep: Node3D = intro.get_node("%SleepPassenger") as Node3D
	var vis: Node3D = sleep.get_node_or_null("GeneratedVisual") as Node3D
	print("sleep global_pos=", sleep.global_position, " rot_y=", sleep.rotation.y)
	var anim: AnimationPlayer = GeneratedVisual.find_animation_player(sleep)
	if anim != null:
		print("anim playing=", anim.is_playing(), " clip=", anim.current_animation)
	if vis != null:
		print("vis local_pos=", vis.position, " scale=", vis.scale, " visible=", vis.visible)
		var aabb := GeneratedVisual.local_aabb(vis)
		print("vis local_aabb=", aabb)
		var foot_y: float = aabb.position.y * vis.scale.y + vis.position.y
		print("vis scaled min_y=", foot_y)
		_print_meshes(vis)
	var cam: Camera3D = intro.get_node("%IntroCamera") as Camera3D
	if cam != null:
		print("cam global_pos=", cam.global_position, " rot=", cam.global_rotation_degrees)
	get_tree().quit()


func _print_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			print(" mesh ", mi.name, " vis=", mi.visible, " global=", mi.global_position)
	for child: Node in node.get_children():
		_print_meshes(child)
