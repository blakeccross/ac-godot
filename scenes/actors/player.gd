extends CharacterBody3D

## CharacterBody3D player. Locomotion feel from `m_player_main_walk`; visual from
## generated `boy_1.glb` when the local pipeline has been run.

const GENERATED_PLAYER := "res://assets/generated/characters/player/boy_1.glb"
const TARGET_HEIGHT := 1.35
const LOOK_HEIGHT := 0.85
const INTERACT_REACH := 1.1

const ANIM_WAIT := "ply_1_wait1"
const ANIM_WALK := "ply_1_walk1"
const ANIM_RUN := "ply_1_run1"
const ANIM_DASH := "ply_1_dash1"

@onready var _mesh: Node3D = $MeshPivot
@onready var _placeholder: MeshInstance3D = $MeshPivot/PlaceholderMesh
@onready var _probe: Area3D = $MeshPivot/InteractProbe
@onready var _look: Marker3D = $CameraLook

var _motor: PlayerLocomotion = PlayerLocomotion.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _busy: bool = false
var _focus: Node = null
var _anim: AnimationPlayer
var _gait: PlayerLocomotion.Gait = PlayerLocomotion.Gait.WAIT
var _placeholder_bob: float = 0.0


func _ready() -> void:
	add_to_group("player")
	_look.position = Vector3(0.0, LOOK_HEIGHT, 0.0)
	_try_load_generated_visual()


func facing_yaw() -> float:
	return _motor.facing


func camera_look_position() -> Vector3:
	return _look.global_position


func apply_spawn(pos: Vector3, yaw: float) -> void:
	global_position = pos
	_motor.reset(yaw)
	_mesh.rotation.y = yaw


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	var wish := Vector3.ZERO
	var stick := 0.0
	if not _busy:
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		stick = clampf(input_dir.length(), 0.0, 1.0)
		wish = _camera_wish(input_dir)

	var planar: Vector3 = _motor.tick(
		delta, wish, stick, Input.is_action_pressed("sprint"), _busy
	)
	velocity.x = planar.x
	velocity.z = planar.z
	_mesh.rotation.y = _motor.facing
	move_and_slide()
	_update_animation(delta)
	_update_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if event.is_action_pressed("interact"):
		_try_interact()
		get_viewport().set_input_as_handled()


func _camera_wish(input_dir: Vector2) -> Vector3:
	if input_dir.length_squared() < 0.0001:
		return Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	var look := Vector3.FORWARD
	var right := Vector3.RIGHT
	if cam != null:
		look = -cam.global_transform.basis.z
		look.y = 0.0
		if look.length_squared() > 0.0001:
			look = look.normalized()
		right = cam.global_transform.basis.x
		right.y = 0.0
		if right.length_squared() > 0.0001:
			right = right.normalized()
	var wish := look * -input_dir.y + right * input_dir.x
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	return wish


func _update_animation(delta: float) -> void:
	var next: PlayerLocomotion.Gait = _motor.gait()
	if _anim == null:
		_placeholder_bob += delta * (8.0 if next != PlayerLocomotion.Gait.WAIT else 2.0)
		if _placeholder.visible:
			var amp: float = 0.04 if next != PlayerLocomotion.Gait.WAIT else 0.0
			_placeholder.position.y = 0.625 + sin(_placeholder_bob) * amp
		return
	if _busy:
		return
	if next == _gait and _anim.is_playing():
		_anim.speed_scale = _anim_speed(next)
		return
	_gait = next
	var clip := _resolve_clip(_clip_for(next))
	if clip.is_empty():
		return
	_ensure_loop(clip)
	_anim.speed_scale = _anim_speed(next)
	_anim.play(clip, 0.12)


func _anim_speed(gait: PlayerLocomotion.Gait) -> float:
	match gait:
		PlayerLocomotion.Gait.WAIT:
			return 1.0
		PlayerLocomotion.Gait.WALK:
			return clampf(_motor.planar_speed / PlayerLocomotion.WALK_RUN_SPEED, 0.7, 1.15)
		_:
			return clampf(_motor.planar_speed / PlayerLocomotion.RUN_SPEED, 0.85, 1.25)


func _clip_for(gait: PlayerLocomotion.Gait) -> String:
	match gait:
		PlayerLocomotion.Gait.WALK:
			return ANIM_WALK
		PlayerLocomotion.Gait.RUN:
			return ANIM_RUN
		PlayerLocomotion.Gait.DASH:
			return ANIM_DASH
		_:
			return ANIM_WAIT


func _resolve_clip(suffix: String) -> String:
	if _anim == null or suffix.is_empty():
		return ""
	if _anim.has_animation(suffix):
		return suffix
	for anim_name: String in _anim.get_animation_list():
		if anim_name.ends_with(suffix) or suffix in anim_name:
			return anim_name
	if suffix == ANIM_DASH:
		return _resolve_clip(ANIM_RUN)
	return ""


func _update_focus() -> void:
	var hit: InteractionQuery = _query_focus()
	var next: Node = hit.host if hit else null
	if next == _focus:
		if hit != null:
			Game.set_interact_prompt(hit.action.prompt)
		return
	_focus = next
	if hit != null:
		Game.set_interact_prompt(hit.action.prompt)
	else:
		Game.set_interact_prompt("")


func _query_focus() -> InteractionQuery:
	if _probe == null:
		return null
	return InteractionQuery.best_in_areas(
		_probe.get_overlapping_areas(),
		_motor.facing_point(global_position, INTERACT_REACH),
		_make_context()
	)


func _make_context() -> InteractionContext:
	var ctx := InteractionContext.new()
	ctx.actor = self
	ctx.inventory = Game.inventory
	var tree := get_tree()
	if tree != null:
		ctx.world = tree.get_first_node_in_group("world")
	return ctx


func _try_interact() -> void:
	var hit: InteractionQuery = _query_focus()
	if hit == null or hit.host == null or hit.action == null:
		return
	_focus = hit.host
	_busy = hit.action.locks_player
	await _play_action(hit.action.player_anim)
	if is_instance_valid(hit.host):
		hit.host.interact(hit.action, _make_context())
	_busy = false
	_gait = PlayerLocomotion.Gait.WAIT
	_update_focus()


func _play_action(clip_name: StringName) -> void:
	if clip_name == &"":
		return
	var clip := _resolve_clip(String(clip_name))
	if _anim == null or clip.is_empty():
		await get_tree().create_timer(0.12).timeout
		return
	_anim.speed_scale = 1.0
	_anim.play(clip, 0.08)
	await _anim.animation_finished


func _try_load_generated_visual() -> void:
	if not ResourceLoader.exists(GENERATED_PLAYER):
		return
	var packed: PackedScene = load(GENERATED_PLAYER) as PackedScene
	if packed == null:
		return
	var visual: Node = packed.instantiate()
	if not (visual is Node3D):
		visual.queue_free()
		return
	var body := visual as Node3D
	_placeholder.visible = false
	_mesh.add_child(body)
	_scale_visual_to_height(body)
	_apply_preview_materials(body)
	_anim = _find_animation_player(body)
	if _anim != null:
		var wait_clip := _resolve_clip(ANIM_WAIT)
		if not wait_clip.is_empty():
			_ensure_loop(wait_clip)
			_anim.play(wait_clip)


func _scale_visual_to_height(body: Node3D) -> void:
	var aabb := _mesh_aabb(body)
	if aabb.size.y <= 0.001:
		body.scale = Vector3.ONE * 0.3
		return
	var factor: float = TARGET_HEIGHT / aabb.size.y
	body.scale = Vector3.ONE * factor
	body.position.y = -aabb.position.y * factor


func _ensure_loop(clip: String) -> void:
	if _anim == null or not _anim.has_animation(clip):
		return
	var animation: Animation = _anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _apply_preview_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mat := mesh_instance.get_active_material(0)
		if mat == null:
			mat = StandardMaterial3D.new()
			mesh_instance.set_surface_override_material(0, mat)
		if mat is StandardMaterial3D:
			var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			std.vertex_color_use_as_albedo = false
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh_instance.set_surface_override_material(0, std)
	for child in node.get_children():
		_apply_preview_materials(child)


func _mesh_aabb(node: Node) -> AABB:
	var merged := AABB()
	var started := false
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			merged = mi.transform * mi.mesh.get_aabb()
			started = true
	for child in node.get_children():
		var child_aabb := _mesh_aabb(child)
		if child_aabb.size == Vector3.ZERO:
			continue
		if child is Node3D:
			child_aabb = (child as Node3D).transform * child_aabb
		if started:
			merged = merged.merge(child_aabb)
		else:
			merged = child_aabb
			started = true
	return merged
