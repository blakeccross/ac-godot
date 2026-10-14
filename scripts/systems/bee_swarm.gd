class_name BeeSwarm
extends Node3D

## Bee nest swarm (`ac_bee`). Appears after a bee-tree shake, chases the player,
## and stings once in range when the player is attackable. Two seconds into the chase the net
## can take it (`catch_delay_frames`): a swing under way within 40 GX catches it outright,
## otherwise the net has to come within 24 GX; caught, it is a bee in the net
## (`aBEE_caught`, `aINS_INSECT_TYPE_BEE`).

enum Phase { APPEAR, FLY, ATTACK, DISAPPEAR }

## Attack when XZ distance under 30 GX (`aBEE_ACT_ATTACK`).
const ATTACK_GX := 30.0
const CHASE_HEIGHT_GX := 50.0
const APPEAR_SEC := 0.45
## `BGM_BEE_CHASE` (`mBGMPsComp_make_ps_happening` from the shake's `shock`).
const CHASE_BGM := &"bee_chase"
## `Player_actor_Check_end_stung_bee`: the swarm leaves once the stung timer passes 162.
const ATTACK_END_TICKS := 162.0
## `aBEE_fly_init`: frames before the net can take it.
const CATCH_DELAY_FRAMES := 60
## `Set_Item_net_catch_request_force_proc` / `_table_proc` reaches.
const FORCE_CATCH_GX := 40.0
const NET_RANGE_GX := 24.0
const BEE_ID := &"bee"
const MODEL := "res://assets/generated/environment/act_bee.glb"

var phase: Phase = Phase.APPEAR
var attackable: bool = false

var _player: Node3D
var _elapsed: float = 0.0
var _fly_time: float = 0.0
## The swarm's look: `act_bee` (or a dark ball without generated assets) under a pivot
## that carries the draw scale.
var _mesh: Node3D
var _anim: AnimationPlayer
var _clip: StringName = &""
## `start_frame`: 90 flying straight, toward 0 / 180 while it swings round to follow.
var _shape_frame: float = 90.0
## `fly_angle[0]` (+500 a frame): the specks swirl (`two_tex_scroll_dolphin`).
var _swirl: float = 0.0
var _materials: Array[StandardMaterial3D] = []
var _yaw: float = 0.0


static func find(tree: SceneTree) -> BeeSwarm:
	if tree == null:
		return null
	return tree.get_first_node_in_group("bee_swarm") as BeeSwarm


## Chasing and past `catch_delay_frames`: the net can take it.
func netable() -> bool:
	return phase == Phase.FLY and _fly_time * DecompTime.FRAME_HZ >= CATCH_DELAY_FRAMES


## `aBEE_ACT_CAUGHT` → `DISAPPEAR`: the swarm is the bee in the net now.
func caught() -> void:
	phase = Phase.DISAPPEAR
	_elapsed = 0.0
	visible = false


static func spawn(parent: Node, at: Vector3, player: Node3D) -> BeeSwarm:
	if parent == null:
		return null
	var swarm := BeeSwarm.new()
	swarm.name = "BeeSwarm"
	swarm._player = player
	parent.add_child(swarm)
	swarm.global_position = at
	return swarm


func _ready() -> void:
	add_to_group("bee_swarm")
	_mesh = Node3D.new()
	_mesh.name = "Look"
	add_child(_mesh)
	if not _attach_model():
		var ball := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.18
		sphere.height = 0.36
		ball.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.12, 0.05, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ball.material_override = mat
		_mesh.add_child(ball)
	_mesh.scale = Vector3(0.15, 0.15, 0.15)
	phase = Phase.APPEAR
	_elapsed = 0.0
	## `aBEE_appear_init`.
	Game.bee_chase = true
	if EventManager.demo_bgm == &"":
		EventManager.demo_bgm = CHASE_BGM
		Audio.play_bgm(CHASE_BGM)


func _exit_tree() -> void:
	## Gone (stung, or the scene changed): the chase is over, and so is its music.
	Game.bee_chase = false
	if EventManager.demo_bgm == CHASE_BGM:
		EventManager.demo_bgm = &""
		var world: World = World.find(get_tree())
		if world != null and is_instance_valid(world) and not world.is_queued_for_deletion():
			world.call("_play_outdoor_bgm")


## Called near the end of the shake clip (`STATUS_FOR_BEE_ATTACK` at frame 29.5).
func mark_attackable() -> void:
	attackable = true


func _process(delta: float) -> void:
	_elapsed += delta
	_scroll(delta)
	match phase:
		Phase.APPEAR:
			var t: float = clampf(_elapsed / APPEAR_SEC, 0.0, 1.0)
			_mesh.scale = _shape_scale() * lerpf(0.15, 1.0, t)
			if t >= 1.0:
				phase = Phase.FLY
		Phase.FLY:
			_fly_time += delta
			_chase(delta)
		Phase.ATTACK:
			## `aBEE_attack`: hang about until `mPlib_Check_end_stung_bee`.
			_hover(delta)
		Phase.DISAPPEAR:
			var fade: float = clampf(1.0 - _elapsed / 0.5, 0.0, 1.0)
			_mesh.scale = _shape_scale() * fade
			if fade <= 0.0:
				queue_free()


func _chase(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		phase = Phase.DISAPPEAR
		_elapsed = 0.0
		return
	var target: Vector3 = _player.global_position
	target.y += CHASE_HEIGHT_GX * FieldCatalog.GX_TO_METERS
	var to: Vector3 = target - global_position
	var dist_xz: float = Vector2(to.x, to.z).length()
	var speed: float = 4.5
	if dist_xz > 0.001:
		global_position += to.normalized() * speed * delta
		_shape(atan2(to.x, to.z), delta)
	## Buzz sway.
	global_position.y += sin(Time.get_ticks_msec() * 0.02) * 0.02
	if attackable and dist_xz <= ATTACK_GX * FieldCatalog.GX_TO_METERS:
		_sting()


func _hover(delta: float) -> void:
	var player := _player as Player if is_instance_valid(_player) else null
	if player == null or not player.stung or _elapsed * DecompTime.TICK_HZ > ATTACK_END_TICKS:
		phase = Phase.DISAPPEAR
		_elapsed = 0.0
		return
	var target: Vector3 = player.global_position
	target.y += CHASE_HEIGHT_GX * FieldCatalog.GX_TO_METERS
	global_position = global_position.lerp(target, clampf(delta * 3.0, 0.0, 1.0))
	global_position.y += sin(Time.get_ticks_msec() * 0.02) * 0.02


func _attach_model() -> bool:
	if not ResourceLoader.exists(MODEL):
		return false
	var packed: PackedScene = load(MODEL) as PackedScene
	var inst: Node3D = packed.instantiate() as Node3D if packed != null else null
	if inst == null:
		return false
	_mesh.add_child(inst)
	_tint_prim(inst)
	_anim = VisualAnimation.find_animation_player(inst)
	if _anim != null and not _anim.get_animation_list().is_empty():
		_clip = _anim.get_animation_list()[0]
		_anim.play(_clip)
		_anim.pause()
	return true


## `aBEE_actor_draw`: `gDPSetPrimColor(0, 0, 0, alpha)` — the intensity texture's dots are
## black bees.
func _tint_prim(root: Node) -> void:
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i: int in mi.get_surface_override_material_count():
			var mat := mi.get_active_material(i) as StandardMaterial3D
			if mat == null:
				continue
			var dark := mat.duplicate() as StandardMaterial3D
			dark.albedo_color = Color(0.0, 0.0, 0.0, mat.albedo_color.a)
			dark.texture_repeat = true
			mi.set_surface_override_material(i, dark)
			_materials.append(dark)


## `two_tex_scroll_dolphin(…, 180 sin, 180 cos, 32, 32, …)`: the texture circles (scroll
## values are quarter texels of the 32-texel tile).
func _scroll(delta: float) -> void:
	_swirl += deg_to_rad(500.0 * 360.0 / 65536.0) * delta * DecompTime.FRAME_HZ
	var texels := Vector2(sin(_swirl), cos(_swirl)) * (180.0 / 4.0)
	for mat: StandardMaterial3D in _materials:
		var tex: Texture2D = mat.albedo_texture
		if tex == null:
			continue
		## The converter lays the wrapped tile out repeated (`wrap_tiles`), so the whole
		## image repeats too.
		mat.uv1_offset = Vector3(texels.x / tex.get_width(), texels.y / tex.get_height(), 0.0)


## `aBEE_fly_move_common`: the swarm stretches out flying straight and bunches up while it
## turns (`size`, `ACTOR_DRAW_SCALE` units), drawn at `start_frame` of its clip.
func _shape_scale() -> Vector3:
	var diff: float = absf(90.0 - _shape_frame)
	var size := Vector3(0.75 + diff / 360.0, 0.75 + diff / 360.0, 1.5 - diff / 180.0) * FieldCatalog.ACTOR_DRAW_SCALE
	return size / FieldCatalog.PIPELINE_SCALE * FieldCatalog.GX_TO_METERS


## Faces where it's going and poses the clip by how hard it's turning.
func _shape(want_yaw: float, delta: float) -> void:
	var turn: float = angle_difference(_yaw, want_yaw)
	_yaw += turn * clampf(delta * 12.0, 0.0, 1.0)
	_mesh.rotation.y = _yaw
	## `90 + (player_angle_y - world.angle.y) / 30` in s16 units: about 6 frames a degree.
	var target: float = clampf(90.0 + rad_to_deg(turn) * 65536.0 / 360.0 / 30.0, 0.0, 180.0)
	_shape_frame = move_toward(_shape_frame, target, 5.0 * delta * DecompTime.FRAME_HZ)
	_mesh.scale = _shape_scale()
	if _anim != null and _clip != &"":
		_anim.seek(maxf(_shape_frame - 1.0, 0.0) / DecompTime.FRAME_HZ, true)


## `mPlib_request_main_stung_bee_type1` → `aBEE_ACT_ATTACK`.
func _sting() -> void:
	PlayerSe.bee_sting(self)
	var player := _player as Player if is_instance_valid(_player) else null
	if player == null:
		Game.sting_by_bee()
		phase = Phase.DISAPPEAR
		_elapsed = 0.0
		return
	phase = Phase.ATTACK
	_elapsed = 0.0
	player.run_stung_bee()
