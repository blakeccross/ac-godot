class_name Statue
extends StaticBody3D

## The Nook statue by the station (`ac_douzou`, `DOUZOU` on the station acre's FG unit).
## Each house whose loan ended in the statue (`size_info.next_size == mHm_HOMESIZE_STATUE`,
## `aDOU_set_check`) gets one at its own offset from the actor (`xpostbl` / `zpostbl`):
## the owner's sex picks the boy or girl figure, their face the eye / mouth textures
## (`eye_tbl` / `mouth_tbl`, winter set in winter), and the house's `statue_rank` the
## size (`scltbl` on joint 2) and PRIM / ENV colours (gold, silver, bronze, jade). Reading
## it facing north within 50 GX plays `MSG_DOZOU` in a red window with the owner's name.
## Glints twinkle over it now and then (`aDOU_setEffect`, `StatueSparkle`).

const OFFSET_X_GX: Array[float] = [0.0, 200.0, -40.0, 160.0]
const OFFSET_Z_GX: Array[float] = [200.0, 200.0, 280.0, 280.0]
const RANK_SCALE: Array[float] = [1.0, 0.85, 0.7, 0.55]
const PRIM: Array[Color] = [
	Color(1.0, 1.0, 0.0), Color(200.0 / 255.0, 200.0 / 255.0, 1.0),
	Color(1.0, 100.0 / 255.0, 50.0 / 255.0), Color(0.0, 1.0, 40.0 / 255.0),
]
const ENV: Array[Color] = [
	Color(100.0 / 255.0, 30.0 / 255.0, 0.0), Color(80.0 / 255.0, 80.0 / 255.0, 100.0 / 255.0),
	Color(40.0 / 255.0, 20.0 / 255.0, 0.0), Color(0.0, 30.0 / 255.0, 30.0 / 255.0),
]
const GROUP := &"statue"
const MSG_DOZOU := 4971
const WINDOW_COLOR := Color8(185, 60, 40)
const SHADER := preload("res://shaders/statue_metal.gdshader")
const FACE_DIR := "res://assets/generated/environment/douzou/"
const FACE_TYPES := 8
## `eye_tbl` reuses boy face 7's eyes for the seventh girl face.
const GIRL_EYE_FALLBACK := {7: "b7"}
const MALE_BONES: Array[String] = ["_boy_model", "_boy_face_model", "_boy_mouth_model"]
const FEMALE_BONES: Array[String] = ["_girl_model", "_girl_face_model", "_girl_mouth_model"]

@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = false
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.FURNITURE
@export var visual_id: StringName = &"obj_s_douzou"

## Plot index of the statue shown (`douzou->arg2`), −1 when there is none.
var house_no: int = -1
var _anchor := Vector3.ZERO
var _model: Node3D = null
## `arg0_f`…: ticks to the next glint.
var _glint_wait: int = 0
var _glint_steps := FrameStepper.new(DecompTime.TICK_HZ, 8.0)
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(GROUP)
	_anchor = position
	_rng.randomize()
	refresh()


func _process(delta: float) -> void:
	if house_no < 0 or _model == null:
		return
	_glint_steps.add(delta)
	while _glint_steps.next():
		if _glint_wait > 0:
			_glint_wait -= 1
			continue
		var rank: int = clampi(_rank(), 0, 3)
		_glint_wait = StatueSparkle.next_wait(rank, _rng)
		StatueSparkle.spawn(get_parent(), global_position, rank, _rng)


func _rank() -> int:
	var house: House = Game.interiors.player_house() if Game != null and Game.interiors != null else null
	return house.statue_rank if house != null else 0


func apply_grid_yaw(_facing: WorldGrid.Facing) -> void:
	rotation.y = 0.0


func refresh_seasonal_visual() -> void:
	refresh()


## `aDOU_set_check` for the player's plot.
static func shown_for(house: House) -> bool:
	return house != null and HouseUpgrade.is_statue(house)


static func face_texture_symbol(winter: bool, female: bool, face: int) -> String:
	var season := "w" if winter else "s"
	var key := "%s%d" % ["g" if female else "b", clampi(face, 0, FACE_TYPES - 1) + 1]
	if female and GIRL_EYE_FALLBACK.has(face + 1):
		key = str(GIRL_EYE_FALLBACK[face + 1])
	return "obj_%s_douzou_%s_tex_pic_i4" % [season, key]


## `mouth_tbl`: boys 1/4/8 and girls 5 take the second mouth.
static func mouth_texture_symbol(winter: bool, female: bool, face: int) -> String:
	var boy_m2: Array[int] = [0, 3, 7]
	var girl_m2: Array[int] = [4]
	var second: bool = (face in girl_m2) if female else (face in boy_m2)
	return "obj_%s_douzou_%sm%d_tex_pic_i4" % ["w" if winter else "s", "g" if female else "b", 2 if second else 1]


func refresh() -> void:
	if _model != null:
		_model.queue_free()
		_model = null
	var house: House = Game.interiors.player_house() if Game != null and Game.interiors != null else null
	var owned: StringName = PlayerHouse.owned_building_id()
	house_no = PlayerHouse.plot_of(String(owned)) if owned != &"" and shown_for(house) else -1
	var shown := house_no >= 0
	collision_layer = 1 if shown else 0
	if shown:
		add_to_group("interactable")
	elif is_in_group("interactable"):
		remove_from_group("interactable")
	if not shown:
		return
	position = _anchor + Vector3(OFFSET_X_GX[house_no], 0.0, OFFSET_Z_GX[house_no]) * FieldCatalog.GX_TO_METERS
	var winter: bool = Clock.season() == ClockService.Season.WINTER
	visual_id = &"obj_w_douzou" if winter else &"obj_s_douzou"
	_model = GeneratedVisual.instantiate_raw(visual_id)
	if _model == null:
		return
	_model.name = "Figure"
	add_child(_model)
	var female: bool = Game.player_gender == IntroSequence.GENDER_FEMALE
	_dress(_model, clampi(house.statue_rank, 0, 3), winter, female, Game.player_face)
	HostCollision.apply_box(self, footprint, HostCollision.CELL, 2.0)


func _dress(root: Node, rank: int, winter: bool, female: bool, face: int) -> void:
	for player: Node in root.find_children("*", "AnimationPlayer", true, false):
		(player as AnimationPlayer).stop()
	var eye: Texture2D = _load_face(face_texture_symbol(winter, female, face))
	var mouth: Texture2D = _load_face(mouth_texture_symbol(winter, female, face))
	for node: Node in root.find_children("*", "Skeleton3D", true, false):
		var skel := node as Skeleton3D
		for i: int in skel.get_bone_count():
			if skel.get_bone_name(i).ends_with("_boy_model"):
				skel.set_bone_pose_scale(i, Vector3.ONE * RANK_SCALE[rank])
		var hidden := _bones(skel, FEMALE_BONES if not female else MALE_BONES)
		for mi_node: Node in skel.find_children("*", "MeshInstance3D", true, false):
			var mi := mi_node as MeshInstance3D
			mi.mesh = _without_bones(mi.mesh, mi.skin, skel, hidden)
			_paint(mi, rank, eye, mouth)


static func _load_face(symbol: String) -> Texture2D:
	var path := FACE_DIR + symbol + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func _bones(skel: Skeleton3D, suffixes: Array[String]) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i: int in skel.get_bone_count():
		for s: String in suffixes:
			if skel.get_bone_name(i).ends_with(s):
				out.append(i)
	return out


## The joint callback drops the other figure's shapes (`*joint_shape = NULL`); here the
## figures share one skinned mesh, so drop the triangles bound to those joints.
static func _without_bones(mesh: Mesh, skin: Skin, skel: Skeleton3D, hidden: PackedInt32Array) -> Mesh:
	if mesh == null or hidden.is_empty():
		return mesh
	## Skin binds index joints; map them to skeleton bones by name via the skin.
	var hidden_binds := {}
	if skin != null:
		for b: int in skin.get_bind_count():
			var bone: int = skin.get_bind_bone(b)
			if bone < 0:
				bone = skel.find_bone(skin.get_bind_name(b))
			if hidden.has(bone):
				hidden_binds[b] = true
	else:
		for b: int in hidden:
			hidden_binds[b] = true
	var out := ArrayMesh.new()
	for s: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var per: int = bones.size() / maxi(verts.size(), 1)
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if index.is_empty():
			index.resize(verts.size())
			for i: int in verts.size():
				index[i] = i
		var kept := PackedInt32Array()
		for t: int in range(0, index.size(), 3):
			var drop := false
			for k: int in 3:
				var v: int = index[t + k]
				if per > 0 and hidden_binds.has(_main_bone(bones, weights, v, per)):
					drop = true
					break
			if not drop:
				kept.append_array([index[t], index[t + 1], index[t + 2]])
		if kept.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = kept
		var flags: int = mesh.surface_get_format(s) & ~Mesh.ARRAY_FORMAT_INDEX
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
		out.surface_set_name(out.get_surface_count() - 1, mesh.surface_get_name(s))
	return out


static func _main_bone(bones: PackedInt32Array, weights: PackedFloat32Array, v: int, per: int) -> int:
	var best := -1
	var best_w := -1.0
	for k: int in per:
		var w: float = weights[v * per + k] if v * per + k < weights.size() else 0.0
		if w > best_w:
			best_w = w
			best = bones[v * per + k]
	return best


func _paint(mi: MeshInstance3D, rank: int, eye: Texture2D, mouth: Texture2D) -> void:
	if mi.mesh == null:
		return
	for s: int in mi.mesh.get_surface_count():
		var src: Material = mi.mesh.surface_get_material(s)
		var tag: String = (src.resource_name if src != null else "") + mi.mesh.surface_get_name(s)
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("prim_color", PRIM[rank])
		mat.set_shader_parameter("env_color", ENV[rank])
		if tag.contains("face"):
			mat.set_shader_parameter("decal", true)
			mat.set_shader_parameter("tex", eye)
		elif tag.contains("mouth"):
			mat.set_shader_parameter("decal", true)
			mat.set_shader_parameter("tex", mouth)
		elif tag.contains("metal") or tag.contains("name"):
			if src is BaseMaterial3D:
				mat.set_shader_parameter("tex", (src as BaseMaterial3D).albedo_texture)
		else:
			continue  ## The pedestal keeps its own material.
		mi.set_surface_override_material(s, mat)


func get_interactions(ctx: InteractionContext) -> Array[Interaction]:
	if house_no < 0 or not _facing_statue(ctx):
		return []
	return [Interaction.of(Interaction.READ, "Read plaque", 6)]


## `aDOU_wait`: A only while the player faces north (|angle| >= 0x6000), within 50 GX
## and in front of the statue (±0x1800 from its south).
func _facing_statue(ctx: InteractionContext) -> bool:
	var player: Node3D = ctx.actor if ctx != null else null
	if player == null:
		return true
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() > 50.0 * FieldCatalog.GX_TO_METERS:
		return false
	if absf(atan2(to_player.x, to_player.z)) > float(0x1800) / 65536.0 * TAU:
		return false
	return absf(wrapf(player.global_rotation.y, -PI, PI)) >= float(0x6000) / 65536.0 * TAU


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.READ or house_no < 0:
		return false
	var ui := DialogueOverlay.find(get_tree())
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % MSG_DOZOU))
	if ui == null or data == null:
		Game.post_notice("A statue of %s." % Game.player_name)
		return true
	var ctx: DialogueContext = DialogueContext.from_game()
	ctx.speaker_name = ""
	ctx.voice_mode = DialogueVoice.Mode.CLICK
	ctx.window_color = WINDOW_COLOR
	ctx.frees = PackedStringArray([Game.player_name])
	ui.play(data, ctx)
	return true
