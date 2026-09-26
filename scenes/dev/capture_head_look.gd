extends Node3D

## Villager head look-at (`NpcHeadLook`) on a real species GLB playing its wait clip, turned
## to a non-zero facing so the neck's world rotation matters. Shoots the head tracking a
## target left, right, above and below, plus the no-target neutral.
##
##   $GODOT_BIN --path . res://scenes/dev/capture_head_look.tscn
##
## Output: `res://recordings/head_look/*.png`

const OUT_DIR := "res://recordings/head_look"
const SPECIES := &"bea"
const FACING := 0.6

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	get_viewport().size = Vector2i(640, 480)
	get_tree().root.size = Vector2i(640, 480)
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var actor := Node3D.new()
	add_child(actor)
	var model := Node3D.new()
	actor.add_child(model)
	var vis: Node3D = GeneratedVisual.attach_villager(model, SPECIES)
	if vis == null:
		print("HEAD: no villager GLB")
		get_tree().quit()
		return
	model.rotation.y = FACING
	var anim: AnimationPlayer = VisualAnimation.find_animation_player(vis)
	for n: String in anim.get_animation_list():
		if n.ends_with("npc_1_wait1"):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
			anim.play(n)
			break
	var look := NpcHeadLook.new()
	print("HEAD bound=", look.bind(vis, actor))
	var target := Node3D.new()
	add_child(target)
	var fwd := Vector3(sin(FACING), 0.0, cos(FACING))
	var right := Vector3(cos(FACING), 0.0, -sin(FACING))
	## Front camera at head height, looking back at the villager's face.
	_camera.position = fwd * 4.0 + Vector3(0.0, 1.2, 0.0)
	_camera.look_at(Vector3(0.0, 1.0, 0.0))
	var cases: Array = [
		["none", Vector3.ZERO, false],
		["left", fwd * 2.0 - right * 2.5, true],
		["right", fwd * 2.0 + right * 2.5, true],
		["above", fwd * 1.5 + Vector3(0.0, 2.5, 0.0), true],
		["below", fwd * 1.5 + Vector3(0.0, -2.0, 0.0), true],
	]
	for c: Array in cases:
		target.position = c[1]
		for _i in 90:
			look.tick(DecompTime.TICK_SEC, target if c[2] else null, FACING, false, true)
			await get_tree().physics_frame
		print("HEAD %s yaw=%.1f pitch=%.1f neck=%s" % [
			c[0], rad_to_deg(look._yaw), rad_to_deg(look._pitch),
			look._neck_world_rot() * (180.0 / PI)
		])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, c[0]])
		## Side view (from the villager's screen-right) for the pitch cases.
		_camera.position = right * 4.0 + Vector3(0.0, 1.2, 0.0)
		_camera.look_at(Vector3(0.0, 1.0, 0.0))
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_side.png" % [OUT_DIR, c[0]])
		_camera.position = fwd * 4.0 + Vector3(0.0, 1.2, 0.0)
		_camera.look_at(Vector3(0.0, 1.0, 0.0))
	get_tree().quit()
