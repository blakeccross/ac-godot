extends SceneTree
func _init() -> void:
	print("START")
	var packed: PackedScene = load("res://assets/generated/characters/villagers/rcn_1.glb")
	print("packed=", packed)
	if packed == null:
		quit(); return
	var root = packed.instantiate()
	var anim: AnimationPlayer = null
	var stack = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is AnimationPlayer:
			anim = n; break
		for c in n.get_children(): stack.append(c)
	print("count=", anim.get_animation_list().size() if anim else -1)
	if anim:
		for want in ["npc_1_smile1", "npc_1_hate1", "npc_1_wait1"]:
			print(want, "=", anim.has_animation(want))
	quit()
