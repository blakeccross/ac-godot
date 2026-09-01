extends Node3D

## Train intro presentation. Loads pipeline GLBs (`rom_train_in`, door, Rover/`cat_1`,
## `tol_keitai_1`) and drives `IntroTrainStage` + dialogue for a 1:1 Rover act.

const DIALOGUE_ID := &"rover_intro"
const ROVER_GLB := "res://assets/generated/characters/villagers/cat_1.glb"
## Decomp ceiling lamp tint (~255, 255, 150).
const LAMP_COLOR := Color(1.0, 1.0, 0.59)
## Ceiling omni positions along the aisle (`rom_train_in` GX).
const CEILING_LIGHT_GX: Array[Vector3] = [
	Vector3(100.0, 96.0, 280.0),
	Vector3(100.0, 96.0, 320.0),
	Vector3(100.0, 96.0, 360.0),
	Vector3(100.0, 96.0, 395.0),
]
const SEAT_FILL_GX := Vector3(100.0, 50.0, 375.0)
## `rom_train_out_shineglass_modelT` — soft XLU god-rays through the glass.
const LIGHT_RAY_TUNNEL_ALPHA := 0.14
const LIGHT_RAY_DAYLIGHT_ALPHA := 0.42
## Warm tunnel palette (GC reference — cozy brown wood, yellow lamp).
const TUNNEL_AMBIENT := Color(0.68, 0.54, 0.38)
const TUNNEL_BG := Color(0.07, 0.05, 0.04)
const DAYLIGHT_AMBIENT := Color(0.72, 0.68, 0.58)

@onready var _train_host: Node3D = %TrainCar
@onready var _window_host: Node3D = %WindowScenery
@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _tunnel_fill: DirectionalLight3D = %TunnelFill
@onready var _window_sun: DirectionalLight3D = %WindowSun
@onready var _seat_fill: OmniLight3D = %SeatFill
@onready var _ceiling_lights: Node3D = %CeilingLights
@onready var _door_host: Node3D = %TrainDoor
@onready var _rover_host: Node3D = %Rover
@onready var _keitai_host: Node3D = %Keitai
@onready var _camera: Camera3D = %IntroCamera
@onready var _missing_banner: Label = %MissingBanner
@onready var _dialogue: CanvasLayer = %DialogueOverlay
@onready var _clock_label: Label = %ClockLabel
@onready var _name_modal: Control = %NameModal
@onready var _town_modal: Control = %TownModal
@onready var _clock_modal: Control = %ClockModal
@onready var _name_edit: LineEdit = %NameEdit
@onready var _town_edit: LineEdit = %TownEdit
@onready var _year: SpinBox = %YearSpin
@onready var _month: SpinBox = %MonthSpin
@onready var _day: SpinBox = %DaySpin
@onready var _hour: SpinBox = %HourSpin
@onready var _minute: SpinBox = %MinuteSpin

var _intro: IntroSequence = IntroSequence.new()
var _stage: IntroTrainStage = IntroTrainStage.new()
var _ctx: DialogueContext
var _finishing: bool = false
var _dialogue_started: bool = false
var _window_scenery: Node3D
var _train_car: Node3D
var _daylight: bool = false


func _ready() -> void:
	Game.notify_intro_ready()
	Audio.play_bgm(&"title")
	_name_modal.visible = false
	_town_modal.visible = false
	_clock_modal.visible = false
	_refresh_clock_label()
	_intro.prompt_requested.connect(_on_prompt)
	_intro.finished.connect(_on_intro_finished)
	_intro.cancelled.connect(_on_intro_cancelled)
	_stage.ready_for_talk.connect(_on_ready_for_talk)
	_stage.stage_changed.connect(_on_stage_changed)
	_bootstrap_stage()


func _process(delta: float) -> void:
	_stage.tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _finishing:
		return
	if _modal_open():
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_menu"):
		get_viewport().set_input_as_handled()
		_intro.cancel()


func _bootstrap_stage() -> void:
	var missing: PackedStringArray = IntroTrainStage.missing_assets()
	_missing_banner.visible = not missing.is_empty()
	if not missing.is_empty():
		_missing_banner.text = (
			"Missing generated train assets — run:\n"
			+ "python3 tools/build_assets.py --step convert\n"
			+ "(need rom_train_in, rom_train_out, obj_romtrain_door, cat_1, tol_keitai_1)"
		)
	_attach_visuals()
	_apply_tunnel_lighting()
	var rover_anim: AnimationPlayer = GeneratedVisual.find_animation_player(_rover_host)
	var door_anim: AnimationPlayer = GeneratedVisual.find_animation_player(_door_host)
	_stage.bind(_rover_host, rover_anim, _door_host, door_anim, _keitai_host, _camera)
	## No Rover mesh → skip walk-up so the title menu item stays testable.
	if not ResourceLoader.exists(ROVER_GLB):
		_on_ready_for_talk()


func _attach_visuals() -> void:
	if _window_host.get_parent() != _train_host:
		_window_host.reparent(_train_host, false)
	## Scenery first so OPA seats/walls in `rom_train_in` depth-occlude window quads.
	var scenery: Node3D = GeneratedVisual.attach(_window_host, &"rom_train_out")
	if scenery != null:
		_window_scenery = scenery
		_fit_train_interior(scenery, &"rom_train_out")
		_apply_scenery_materials(scenery)
	var car: Node3D = GeneratedVisual.attach(_train_host, &"rom_train_in")
	if car != null:
		_train_car = car
		_fit_train_interior(car, &"rom_train_in")
		_apply_car_materials(car)
		_apply_car_opa_wood(car)
	_place_train_lights()
	GeneratedVisual.attach(_door_host, &"obj_romtrain_door")
	GeneratedVisual.attach_villager(_rover_host, &"cat")
	GeneratedVisual.attach(_keitai_host, &"tol_keitai_1")
	_keitai_host.visible = false
	_door_host.global_position = IntroTrainStage.gx_to_meters(Vector3(140.0, 0.0, 120.0))
	## Phone rides with Rover (hand-joint bind comes later).
	if _keitai_host.get_parent() != _rover_host:
		_keitai_host.reparent(_rover_host, false)
	_keitai_host.position = Vector3(0.15, 0.55, 0.1)
	_keitai_host.rotation = Vector3.ZERO


func _fit_train_interior(pivot: Node3D, visual_id: StringName) -> void:
	## `rom_*` acre-scale verts; place at demo origin (not room AABB fit).
	var s: float = FieldCatalog.interior_uniform_scale(visual_id)
	pivot.scale = Vector3.ONE * s
	pivot.position = Vector3(0.0, FieldCatalog.interior_ground_y_offset(visual_id), 0.0)


func _place_train_lights() -> void:
	_seat_fill.global_position = IntroTrainStage.gx_to_meters(SEAT_FILL_GX)
	var lights: Array[Node] = _ceiling_lights.get_children()
	for i: int in lights.size():
		if i >= CEILING_LIGHT_GX.size():
			break
		var light: Node3D = lights[i] as Node3D
		if light == null:
			continue
		light.global_position = IntroTrainStage.gx_to_meters(CEILING_LIGHT_GX[i])


func _apply_car_opa_wood(root: Node3D) -> void:
	## Polished wood highlights on seats/walls (`rom_train_in_model` OPA).
	_apply_car_opa_wood_inner(root)


func _apply_car_opa_wood_inner(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			return
		if String(mesh_instance.name).to_lower().contains("modelt"):
			return
		for i: int in mesh_instance.mesh.get_surface_count():
			var mat: Material = mesh_instance.get_active_material(i)
			if not mat is StandardMaterial3D:
				continue
			var std := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			std.roughness = 0.78
			std.metallic = 0.0
			std.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
			mesh_instance.set_surface_override_material(i, std)
	for child: Node in node.get_children():
		_apply_car_opa_wood_inner(child)


func _apply_car_materials(root: Node3D, daylight: bool = _daylight) -> void:
	## Only touch the XLU pass (`*_modelT`); leave OPA seat/wall textures imported.
	_apply_car_materials_inner(root, daylight)


func _apply_scenery_materials(root: Node3D, daylight: bool = false) -> void:
	_apply_scenery_materials_inner(root, daylight)


func _apply_car_materials_inner(node: Node, daylight: bool) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			return
		var node_label := String(mesh_instance.name).to_lower()
		if not node_label.contains("modelt"):
			return
		for i: int in mesh_instance.mesh.get_surface_count():
			var mat: Material = mesh_instance.get_active_material(i)
			if not mat is StandardMaterial3D:
				continue
			var label := _surface_label(mesh_instance, i, mat)
			var src := mat as StandardMaterial3D
			var std := src.duplicate() as StandardMaterial3D
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			if _is_light_ray_surface(label):
				_apply_light_ray_surface(std, daylight)
				mesh_instance.set_surface_override_material(i, std)
			elif _is_lamp_cone_surface(label, std):
				_apply_lamp_cone_surface(std)
				mesh_instance.set_surface_override_material(i, std)
			elif _is_train_lamp_surface(label, std):
				_apply_lamp_surface(std)
				mesh_instance.set_surface_override_material(i, std)
			elif _is_train_glass_surface(label, std):
				_apply_glass_surface(std)
				mesh_instance.set_surface_override_material(i, std)
	for child: Node in node.get_children():
		_apply_car_materials_inner(child, daylight)


func _apply_scenery_materials_inner(node: Node, daylight: bool) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.sorting_offset = -1.0
		if mesh_instance.mesh == null:
			return
		var node_label := String(mesh_instance.name).to_lower()
		if not node_label.contains("modelt"):
			return
		for i: int in mesh_instance.mesh.get_surface_count():
			var mat: Material = mesh_instance.get_active_material(i)
			if not mat is StandardMaterial3D:
				continue
			var label := _surface_label(mesh_instance, i, mat)
			var src := mat as StandardMaterial3D
			var std := src.duplicate() as StandardMaterial3D
			std.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			std.cull_mode = BaseMaterial3D.CULL_DISABLED
			if _is_light_ray_surface(label):
				_apply_light_ray_surface(std, daylight)
				mesh_instance.set_surface_override_material(i, std)
			else:
				_apply_xlu_scenery_surface(std)
				mesh_instance.set_surface_override_material(i, std)
	for child: Node in node.get_children():
		_apply_scenery_materials_inner(child, daylight)


func _surface_label(mesh_instance: MeshInstance3D, surface: int, mat: Material) -> String:
	var bits: PackedStringArray = PackedStringArray()
	if mat != null:
		bits.append(String(mat.resource_name).to_lower())
		if mat is StandardMaterial3D:
			var std := mat as StandardMaterial3D
			if std.albedo_texture != null:
				bits.append(std.albedo_texture.resource_path.get_file().to_lower())
	if mesh_instance.mesh is ArrayMesh:
		bits.append((mesh_instance.mesh as ArrayMesh).surface_get_name(surface).to_lower())
	bits.append(String(mesh_instance.name).to_lower())
	return " ".join(bits)


func _is_light_ray_surface(label: String) -> bool:
	return (
		"shineglass" in label
		or "shine_glass" in label
		or "lightray" in label
		or "light_ray" in label
	)


func _is_lamp_cone_surface(label: String, std: StandardMaterial3D) -> bool:
	if _is_light_ray_surface(label):
		return false
	return (
		"modelt" in label
		and std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		and ("light" in label or "lamp" in label)
	)


func _is_train_lamp_surface(label: String, std: StandardMaterial3D) -> bool:
	if _is_light_ray_surface(label):
		return false
	if "light_model" in label or "lightt_model" in label or "lamp" in label:
		return true
	if "light" in label and "highlight" not in label and "flight" not in label:
		return true
	return std.emission_enabled or std.emission_energy_multiplier > 0.05


func _is_train_glass_surface(label: String, std: StandardMaterial3D) -> bool:
	if "glass" in label:
		return true
	return std.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and "modelt" in label


func _apply_light_ray_surface(std: StandardMaterial3D, daylight: bool) -> void:
	## Window shine (`rom_train_out_shineglass_modelT`): soft haze, geometry shows through.
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	std.cull_mode = BaseMaterial3D.CULL_DISABLED
	std.render_priority = 1
	var alpha: float = LIGHT_RAY_DAYLIGHT_ALPHA if daylight else LIGHT_RAY_TUNNEL_ALPHA
	std.albedo_color = Color(1.0, 0.96, 0.82, alpha)
	if std.albedo_texture == null:
		std.emission_enabled = true
		std.emission = Color(1.0, 0.94, 0.76)
		std.emission_energy_multiplier = 0.6 if daylight else 0.35


func _apply_lamp_cone_surface(std: StandardMaterial3D) -> void:
	## Downward cone under the ceiling fixture.
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	std.render_priority = 1
	std.albedo_color = Color(LAMP_COLOR, 0.32)
	std.emission_enabled = true
	std.emission = LAMP_COLOR
	std.emission_energy_multiplier = 1.2


func _apply_xlu_scenery_surface(std: StandardMaterial3D) -> void:
	## Clouds / trees beyond the glass — keep baked CI textures, alpha blend.
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	std.render_priority = -1
	if std.albedo_color.a <= 0.01:
		std.albedo_color.a = 0.95


func _apply_lamp_surface(std: StandardMaterial3D) -> void:
	std.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	std.albedo_color = LAMP_COLOR
	std.emission_enabled = true
	std.emission = LAMP_COLOR
	std.emission_energy_multiplier = 3.5


func _apply_glass_surface(std: StandardMaterial3D) -> void:
	std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	std.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	std.render_priority = 1
	std.albedo_color.a = minf(maxf(std.albedo_color.a, 0.2), 0.35)
	std.roughness = 0.05
	std.metallic = 0.0


func _set_omni_group_energy(group: Node3D, energy: float) -> void:
	for child: Node in group.get_children():
		if child is OmniLight3D:
			(child as OmniLight3D).light_energy = energy


func _refresh_train_materials() -> void:
	if _train_car != null:
		_apply_car_materials(_train_car, _daylight)
	if _window_scenery != null:
		_apply_scenery_materials(_window_scenery, _daylight)


func _apply_tunnel_lighting() -> void:
	_daylight = false
	_tunnel_fill.visible = true
	_tunnel_fill.light_color = Color(1.0, 0.9, 0.68)
	_tunnel_fill.light_energy = 0.32
	_window_sun.visible = false
	_seat_fill.light_color = Color(1.0, 0.92, 0.72)
	_seat_fill.light_energy = 0.95
	_set_ceiling_light_energies(1.25, 0.55)
	_refresh_train_materials()
	var env: Environment = _world_env.environment
	if env != null:
		env.ambient_light_color = TUNNEL_AMBIENT
		env.ambient_light_energy = 0.92
		env.background_color = TUNNEL_BG
		env.tonemap_exposure = 1.08
		env.glow_enabled = true
		env.glow_intensity = 0.35
		env.glow_bloom = 0.08


func _apply_daylight() -> void:
	## `aNGD_sitdown` sets `sunlight_flag` TRUE — train leaves the tunnel.
	_daylight = true
	_window_sun.visible = true
	_window_sun.light_color = Color(1.0, 0.96, 0.82)
	_window_sun.light_energy = 0.95
	_tunnel_fill.light_energy = 0.14
	_seat_fill.light_energy = 0.75
	_set_ceiling_light_energies(1.05, 0.45)
	_refresh_train_materials()
	var env: Environment = _world_env.environment
	if env != null:
		env.ambient_light_color = DAYLIGHT_AMBIENT
		env.ambient_light_energy = 1.0
		env.background_color = Color(0.45, 0.58, 0.72)
		env.tonemap_exposure = 1.12
		env.glow_intensity = 0.45
		env.glow_bloom = 0.1


func _set_ceiling_light_energies(primary: float, secondary: float) -> void:
	var lights: Array[Node] = _ceiling_lights.get_children()
	for i: int in lights.size():
		if not lights[i] is OmniLight3D:
			continue
		var light := lights[i] as OmniLight3D
		light.light_color = Color(1.0, 0.94, 0.68)
		light.light_energy = primary if i == 0 else secondary


func _on_stage_changed(action: StringName) -> void:
	if action == &"sitdown":
		_apply_daylight()


func _on_ready_for_talk() -> void:
	if _dialogue_started:
		return
	_dialogue_started = true
	_start_dialogue()


func _start_dialogue() -> void:
	DialogueCatalog.reset()
	var data: DialogueData = DialogueCatalog.conversation(DIALOGUE_ID)
	_ctx = DialogueContext.from_game()
	_ctx.speaker_name = "Rover"
	_ctx.vars = {}
	_ctx.vars["answer_flags"] = 0
	if _dialogue.has_method("play"):
		_dialogue.play(data, _ctx)
	var runner: DialogueRunner = _dialogue.runner() if _dialogue.has_method("runner") else null
	if runner != null and not runner.event_fired.is_connected(_on_dialogue_event):
		runner.event_fired.connect(_on_dialogue_event)


func _on_dialogue_event(event: Dictionary) -> void:
	_intro.handle_event(event)
	var op := String(event.get("op", event.get("type", "")))
	match op:
		"rover_sit":
			_stage.cue_sit()
		"rover_phone":
			_stage.cue_phone()
		"rover_phone_done":
			_stage.end_phone_talk()
		"rover_return":
			_stage.cue_return_sit()


func _on_prompt(kind: StringName) -> void:
	match kind:
		&"clock":
			_open_clock()
		&"name":
			_open_name()
		&"town":
			_open_town()


func _modal_open() -> bool:
	return _name_modal.visible or _town_modal.visible or _clock_modal.visible


func _hide_dialogue_box() -> void:
	if _dialogue.has_method("is_open") and _dialogue.is_open():
		var root: Control = _dialogue.get_node_or_null("%Root") as Control
		if root != null:
			root.visible = false


func _show_dialogue_box() -> void:
	var root: Control = _dialogue.get_node_or_null("%Root") as Control
	if root != null:
		root.visible = true


func _open_name() -> void:
	_hide_dialogue_box()
	_name_edit.text = _intro.player_name
	_name_modal.visible = true
	_name_edit.grab_focus()
	_name_edit.caret_column = _name_edit.text.length()


func _open_town() -> void:
	_hide_dialogue_box()
	_town_edit.text = _intro.town_name
	_town_modal.visible = true
	_town_edit.grab_focus()
	_town_edit.caret_column = _town_edit.text.length()


func _open_clock() -> void:
	_hide_dialogue_box()
	_year.value = Clock.year
	_month.value = Clock.month
	_day.value = Clock.day
	_hour.value = Clock.hour
	_minute.value = Clock.minute
	_clock_modal.visible = true
	_year.grab_focus()


func _on_name_submit() -> void:
	if not _intro.set_player_name(_name_edit.text):
		_name_edit.placeholder_text = "Enter a name"
		return
	_ctx.player_name = _intro.player_name
	_ctx.set_var("player_name", _intro.player_name)
	_name_modal.visible = false
	_resume_prompt()


func _on_town_submit() -> void:
	if not _intro.set_town_name(_town_edit.text):
		_town_edit.placeholder_text = "Enter a town"
		return
	_ctx.town_name = _intro.town_name
	_ctx.set_var("town_name", _intro.town_name)
	_town_modal.visible = false
	_resume_prompt()


func _on_clock_submit() -> void:
	Clock.apply_snapshot(
		{
			"year": int(_year.value),
			"month": int(_month.value),
			"day": int(_day.value),
			"hour": int(_hour.value),
			"minute": int(_minute.value),
			"second": 0,
		}
	)
	_ctx.year = Clock.year
	_ctx.month = Clock.month
	_ctx.day = Clock.day
	_ctx.hour = Clock.hour
	_ctx.minute = Clock.minute
	_ctx.weekday = Clock.weekday()
	_refresh_clock_label()
	_clock_modal.visible = false
	_resume_prompt()


func _resume_prompt() -> void:
	_show_dialogue_box()
	var runner: DialogueRunner = _dialogue.runner() if _dialogue.has_method("runner") else null
	if runner != null:
		runner.resume_after_prompt()


func _refresh_clock_label() -> void:
	_clock_label.text = "Train · %s" % Clock.format_clock()


func _on_intro_finished(identity: Dictionary) -> void:
	if _finishing:
		return
	_finishing = true
	if _dialogue.has_method("close"):
		_dialogue.close()
	call_deferred("_finish_deferred", identity)


func _finish_deferred(identity: Dictionary) -> void:
	Game.finish_intro_sequence(identity)


func _on_intro_cancelled() -> void:
	if _finishing:
		return
	_finishing = true
	if _dialogue.has_method("close"):
		_dialogue.close()
	call_deferred("_abort_deferred")


func _abort_deferred() -> void:
	Game.abort_intro_sequence()
