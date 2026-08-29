extends CharacterBody3D

## CharacterBody3D player. Locomotion feel from `m_player_main_walk`; visual from
## generated `boy_1.glb` when the local pipeline has been run. Equipped tools
## parent to HAND (`HeldTool`). Collision is a cylinder (original actor is a
## circle in XZ, radius ~18 GX) so the bottom hemisphere of a capsule cannot
## catch on wall lids.

const GENERATED_PLAYER := "res://assets/generated/characters/player/boy_1.glb"
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
var _hold_anim: StringName = &""
var _tool_hold_anim: StringName = &""
var _tool_use_anim: StringName = &""


func _ready() -> void:
	add_to_group("player")
	_look.position = Vector3(0.0, LOOK_HEIGHT, 0.0)
	_try_load_generated_visual()
	Game.inventory.equipment_changed.connect(_on_equipment_changed)
	_on_equipment_changed(Game.inventory.equipment_id)


func _exit_tree() -> void:
	if Game.inventory.equipment_changed.is_connected(_on_equipment_changed):
		Game.inventory.equipment_changed.disconnect(_on_equipment_changed)


func facing_yaw() -> float:
	return _motor.facing


func camera_look_position() -> Vector3:
	return _look.global_position


func apply_spawn(pos: Vector3, yaw: float) -> void:
	global_position = pos
	_motor.reset(yaw)
	_mesh.rotation.y = yaw
	_snap_to_bg()


func _physics_process(delta: float) -> void:
	var bg: Array = _bg()
	var on_bg: bool = _snap_to_bg()
	if on_bg:
		velocity.y = 0.0
		motion_mode = MOTION_MODE_FLOATING
	elif not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	var wish := Vector3.ZERO
	var stick := 0.0
	var menu_open: bool = _inventory_open()
	if not _busy and not menu_open:
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		stick = clampf(input_dir.length(), 0.0, 1.0)
		wish = _camera_wish(input_dir)

	var planar: Vector3 = _motor.tick(
		delta, wish, stick, Input.is_action_pressed("sprint") and not menu_open, _busy or menu_open
	)
	velocity.x = planar.x
	velocity.z = planar.z
	_mesh.rotation.y = _motor.facing
	var before: Vector3 = global_position
	move_and_slide()
	if bg.size() == 2:
		global_position = FieldCollision.revise_xz(
			bg[0] as WorldData, bg[1] as WorldGrid, before, global_position
		)
	elif on_bg:
		_snap_to_bg()
	_update_animation(delta)
	_update_focus()


func _bg() -> Array:
	if get_tree() == null:
		return []
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		return []
	var data: Variant = world.get("layout")
	var grid: Variant = world.get("grid")
	if not (data is WorldData) or not (grid is WorldGrid):
		return []
	return [data, grid]


func _snap_to_bg() -> bool:
	## `mCoBG_BgCheckControll` / `GetBgY_AngleS_FromWpos`: feet on the heightfield at this XZ.
	var bg: Array = _bg()
	if bg.is_empty():
		return false
	var y: float = FieldCollision.ground_y_at(bg[0] as WorldData, bg[1] as WorldGrid, global_position)
	if not FieldCollision.has_floor(y):
		return false
	floor_snap_length = 0.0
	floor_block_on_wall = false
	global_position.y = y
	return true


func _inventory_open() -> bool:
	if get_tree() == null:
		return false
	var ui: Node = get_tree().get_first_node_in_group("inventory_ui")
	return ui != null and ui.has_method("is_open") and bool(ui.call("is_open"))


func _unhandled_input(event: InputEvent) -> void:
	if _busy or _inventory_open():
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
			if _hold_anim != &"" and not _resolve_clip(String(_hold_anim)).is_empty():
				return String(_hold_anim)
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
	var hit: InteractionQuery = _resolve_interact()
	var next: Node = hit.host if hit else null
	var prompt := ""
	if hit != null and hit.action != null:
		prompt = hit.action.prompt
	if next == _focus:
		Game.set_interact_prompt(prompt)
		return
	_focus = next
	Game.set_interact_prompt(prompt)


func _query_focus() -> InteractionQuery:
	if _probe == null:
		return null
	return InteractionQuery.best_in_areas(
		_probe.get_overlapping_areas(),
		_motor.facing_point(global_position, INTERACT_REACH),
		_make_context()
	)


func _resolve_interact() -> InteractionQuery:
	return ToolUse.resolve(_query_focus(), _make_context())


func _make_context() -> InteractionContext:
	var ctx := InteractionContext.new()
	ctx.actor = self
	ctx.inventory = Game.inventory
	var tree := get_tree()
	if tree != null:
		ctx.world = tree.get_first_node_in_group("world")
	return ctx


func _try_interact() -> void:
	var hit: InteractionQuery = _resolve_interact()
	if hit == null or hit.action == null:
		return
	_focus = hit.host
	_busy = hit.action.locks_player
	await _play_action(hit.action.player_anim)
	var ctx: InteractionContext = _make_context()
	if hit.host != null and is_instance_valid(hit.host):
		hit.host.interact(hit.action, ctx)
	else:
		ToolUse.apply_field(hit.action, ctx)
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
	HeldTool.play(HeldTool.find_skeleton(_mesh), _tool_use_anim, false)
	_anim.play(clip, 0.08)
	await _anim.animation_finished
	HeldTool.play(HeldTool.find_skeleton(_mesh), _tool_hold_anim, true)


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
	_scale_visual(body)
	_apply_preview_materials(body)
	_anim = _find_animation_player(body)
	if _anim != null:
		var wait_clip := _resolve_clip(ANIM_WAIT)
		if not wait_clip.is_empty():
			_ensure_loop(wait_clip)
			_anim.play(wait_clip)


func _on_equipment_changed(_item_id: StringName) -> void:
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_mesh)
	HeldTool.unbind(skeleton)
	_hold_anim = &""
	_tool_hold_anim = &""
	_tool_use_anim = &""
	var tool: ToolData = _equipped_tool()
	if tool != null and tool.visual_id != &"":
		HeldTool.bind(skeleton, tool.visual_id)
		_hold_anim = tool.hold_anim
		_tool_hold_anim = tool.visual_hold_anim
		_tool_use_anim = tool.visual_use_anim
		HeldTool.play(skeleton, _tool_hold_anim, true)
	if not _busy:
		_replay_gait_clip()


func _equipped_tool() -> ToolData:
	if Game.inventory == null or Game.inventory.equipment_id == &"":
		return null
	return ItemCatalog.get_item(Game.inventory.equipment_id) as ToolData


func _replay_gait_clip() -> void:
	if _anim == null:
		return
	var gait: PlayerLocomotion.Gait = _motor.gait()
	_gait = gait
	var clip := _resolve_clip(_clip_for(gait))
	if clip.is_empty():
		return
	_ensure_loop(clip)
	_anim.speed_scale = _anim_speed(gait)
	_anim.play(clip, 0.12)


func _scale_visual(body: Node3D) -> void:
	var s: float = FieldCatalog.actor_uniform_scale()
	body.scale = Vector3.ONE * s
	var aabb := _mesh_aabb(body)
	if aabb.size.y <= 0.001:
		return
	body.position.y = -aabb.position.y * s


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
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 1
		for i: int in surface_count:
			var mat: Material = mesh_instance.get_active_material(i)
			if mat == null:
				mat = StandardMaterial3D.new()
			if mat is StandardMaterial3D:
				var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				std.vertex_color_use_as_albedo = false
				std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				## Pipeline bakes REPEAT/MIRROR into the PNG and remaps UVs to 0–1;
				## keep clamp so U never sticks to the shirt texture's right edge.
				std.texture_repeat = false
				std.cull_mode = BaseMaterial3D.CULL_DISABLED
				std.roughness = 1.0
				std.metallic = 0.0
				mesh_instance.set_surface_override_material(i, std)
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
