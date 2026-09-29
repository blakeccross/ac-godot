extends Node3D

## Villager umbrella (`aNPC_ACT_UMB_OPEN` + `aNPC_SUB_ANIM_UMBRELLA`) on a real species GLB:
## mid-open, then open while waiting and walking with the `UMBRELLA1` arm pose.
##
##   $GODOT_BIN --path . res://scenes/dev/capture_villager_umbrella.tscn
##
## Output: `res://.tmp_captures/villager_umbrella/*.png`

const OUT_DIR := "res://.tmp_captures/villager_umbrella"
const SPECIES := &"bea"
const FACING := 0.6

@onready var _camera: Camera3D = $Camera3D
var _carry: ToolCarry
var _skeleton: Skeleton3D


func _ready() -> void:
	get_viewport().size = Vector2i(640, 480)
	get_tree().root.size = Vector2i(640, 480)
	call_deferred("_run")


func _play(anim: AnimationPlayer, leaf: String, loop: bool) -> void:
	for n: String in anim.get_animation_list():
		if n.ends_with(leaf):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
			anim.play(n)
			return


func _shoot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, name])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var model := Node3D.new()
	add_child(model)
	var vis: Node3D = GeneratedVisual.attach_villager(model, SPECIES)
	if vis == null:
		print("UMB: no villager GLB")
		get_tree().quit()
		return
	model.rotation.y = FACING
	var anim: AnimationPlayer = VisualAnimation.find_animation_player(vis)
	_skeleton = HeldTool.find_skeleton(vis)
	var attach: Node3D = HeldTool.bind(_skeleton, &"tol_umb_04")
	var umb := HeldUmbrella.new()
	umb.setup(attach.get_child(0) as Node3D, HeldUmbrella.Action.TAKEOUT_BEFORE)
	_carry = ToolCarry.build_part(anim, _skeleton, "npc_1_umbrella1", VillagerOutdoor.SUB_ANIM_JOINTS)
	print("UMB carry=", _carry != null)
	anim.mixer_applied.connect(_apply)
	var fwd := Vector3(sin(FACING), 0.0, cos(FACING))
	var right := Vector3(cos(FACING), 0.0, -sin(FACING))
	_camera.position = fwd * 5.0 + right * 1.5 + Vector3(0.0, 2.0, 0.0)
	_camera.look_at(Vector3(0.0, 1.2, 0.0))
	var use_carry := false
	_play(anim, "npc_1_umb_open1", false)
	for i in 40:
		umb.tick(DecompTime.TICK_SEC)
		await get_tree().physics_frame
	await _shoot("opening")
	for i in 60:
		umb.tick(DecompTime.TICK_SEC)
		await get_tree().physics_frame
	_play(anim, "npc_1_wait1", true)
	_active = true
	for i in 30:
		umb.tick(DecompTime.TICK_SEC)
		await get_tree().physics_frame
	await _shoot("open_wait")
	_play(anim, "npc_1_walk1", true)
	for i in 20:
		await get_tree().physics_frame
	await _shoot("open_walk")
	_camera.position = right * 5.0 + Vector3(0.0, 2.0, 0.0)
	_camera.look_at(Vector3(0.0, 1.2, 0.0))
	await _shoot("open_walk_side")
	get_tree().quit()


var _active := false


func _apply() -> void:
	if _active and _carry != null:
		_carry.apply(_skeleton)
