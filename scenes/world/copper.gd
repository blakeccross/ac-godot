extends StaticBody3D

## Copper outside the police station (`ac_npc_police` / `SP_NPC_POLICE`, skeleton `plc_1`).
## Stands guard facing south two units east of the station (`fd_npc_land_actable`).
##
## - Walking out of the police box, he speaks first (0x0771, `aPOL_talk_request` with
##   `last_scene_no == SCENE_POLICE_BOX`), once per return to town.
## - Otherwise A opens his time-of-day menu (`CopperTalk`).
## - Each time his wait finishes (`aPOL_think_main_proc`): 06:00–07:00 in fair weather,
##   with the player not in front of him, 5% to do morning exercises (`TAISOU1/2/7`,
##   looping 2 / 4 / 1 times, cut short once the player comes into view); 02:00–04:00 with
##   the player ≥ 60 GX away, 5% to doze (`WAIT_NEMU1` ×5, then a start `GYAFUN1`; waking
##   early if the player comes within 60 GX). After a talk he turns back to face south.

const SPECIES := &"plc"
const ANIM_WAIT := "npc_1_wait1"
const ANIM_WALK := "npc_1_walk1"
## `aPOL_taisou_act_init_proc`: clip and loop count.
const TAISOU_ANIMS: Array[String] = ["npc_1_taisou1", "npc_1_taisou2", "npc_1_taisou7"]
const TAISOU_LOOPS: Array[int] = [2, 4, 1]
const ANIM_NEMU := "npc_1_wait_nemu1"
const ANIM_GYAFUN := "npc_1_gyafun1"
const NEMU_LOOPS := 5
const SPECIAL_CHANCE := 0.05
## `DEG2SHORT_ANGLE2(67.5f)`: the player counts as "in front" inside this.
const FRONT_ANGLE := deg_to_rad(67.5)
const NEMU_WAKE_GX := 60.0
## Default wait length when the clip is missing (one `aNPC_ACT_WAIT` cycle).
const WAIT_CYCLE_FALLBACK := 2.0
## `aNPC_ACT_TURN` at the turn-in-place rate (0x0800 × 30 → 337.5°/s).
const TURN_RATE := deg_to_rad(11.25) * 30.0

enum Mode { WAIT, TURN, TAISOU, NEMU, GYAFUN }

var mode: Mode = Mode.WAIT
var _model: Node3D
var _body_anim: AnimationPlayer
var _face: NpcFace = NpcFace.new()
var _talking: bool = false
var _clip: String = ""
var _timer: float = 0.0
var _loops_left: int = 0
## `exit_greeting`: the walk-out greeting has played for this return to town.
var _exit_greeted: bool = false
var _home_yaw: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 1
	collision_mask = 0
	_rng.randomize()
	_home_yaw = WorldGrid.yaw_for_facing(WorldGrid.Facing.SOUTH)
	rotation.y = _home_yaw
	_ensure_collision()
	_ensure_visual()
	_ensure_interact()
	_set_mode(Mode.WAIT)


func _process(delta: float) -> void:
	var uttering: bool = false
	if _talking and get_tree() != null:
		uttering = DialogueOverlay.uttering_in(get_tree())
	_face.tick(delta, uttering)


func _physics_process(delta: float) -> void:
	var away: bool = aerobics_running() and not _talking
	if away == visible:
		_set_away(away)
	if away:
		return
	if _talking:
		_face_player()
		return
	var player: Node3D = Player.find(get_tree()) if get_tree() != null else null
	if _wants_exit_greeting() and _player_free(player):
		_exit_greeted = true
		_begin_talk(player, true)
		return
	_timer -= delta
	match mode:
		Mode.WAIT:
			if _timer <= 0.0:
				_think(player)
		Mode.TURN:
			if _turn_home(delta):
				_set_mode(Mode.WAIT)
		Mode.TAISOU:
			if _player_in_front(player):
				_set_mode(Mode.WAIT)
			elif _timer <= 0.0:
				_loops_left -= 1
				if _loops_left <= 0:
					_set_mode(Mode.WAIT)
				else:
					_timer = _clip_seconds(_clip)
		Mode.NEMU:
			if _player_dist_gx(player) < NEMU_WAKE_GX:
				_set_mode(Mode.WAIT)
			elif _timer <= 0.0:
				_loops_left -= 1
				if _loops_left <= 0:
					_set_mode(Mode.GYAFUN)
				else:
					_timer = _clip_seconds(_clip)
		Mode.GYAFUN:
			if _timer <= 0.0:
				_set_mode(Mode.WAIT)


## `aPOL_actor_ct`: Copper leads the aerobics at the shrine instead (`SP_NPC_EV_TAISOU_0`),
## so the one at the station is gone while either aerobics event runs.
static func aerobics_running() -> bool:
	if Game == null or Game.events == null:
		return false
	return Game.events.is_active(&"morning_aerobics") or Game.events.is_active(&"sports_fair_aerobics")


func _set_away(away: bool) -> void:
	visible = not away
	collision_layer = 0 if away else 1
	if not away:
		_set_mode(Mode.WAIT)


## `aPOL_think_main_proc`, at the end of each action.
func _think(player: Node3D) -> void:
	if absf(angle_difference(rotation.y, _home_yaw)) > 0.001:
		_set_mode(Mode.TURN)
		return
	var hour: int = Clock.hour if Clock != null else 12
	var raining: bool = Game != null and Game.weather == &"rain"
	if not raining and hour == 6:
		if not _player_in_front(player) and _rng.randf() < SPECIAL_CHANCE:
			_set_mode(Mode.TAISOU)
			return
	elif hour >= 2 and hour < 4:
		if _player_dist_gx(player) >= NEMU_WAKE_GX and _rng.randf() < SPECIAL_CHANCE:
			_set_mode(Mode.NEMU)
			return
	_set_mode(Mode.WAIT)


func _set_mode(next: Mode) -> void:
	mode = next
	match next:
		Mode.WAIT:
			_play_clip(ANIM_WAIT, true)
			_timer = _clip_seconds(_clip)
		Mode.TURN:
			_play_clip(ANIM_WALK, true)
		Mode.TAISOU:
			var idx: int = _rng.randi_range(0, TAISOU_ANIMS.size() - 1)
			_loops_left = TAISOU_LOOPS[idx]
			_play_clip(TAISOU_ANIMS[idx], true)
			_timer = _clip_seconds(_clip)
		Mode.NEMU:
			_loops_left = NEMU_LOOPS
			_play_clip(ANIM_NEMU, true)
			_timer = _clip_seconds(_clip)
		Mode.GYAFUN:
			_play_clip(ANIM_GYAFUN, false)
			_timer = _clip_seconds(_clip)


func _turn_home(delta: float) -> bool:
	var diff: float = angle_difference(rotation.y, _home_yaw)
	var step: float = TURN_RATE * delta
	if absf(diff) <= step:
		rotation.y = _home_yaw
		return true
	rotation.y += signf(diff) * step
	return false


func _player_in_front(player: Node3D) -> bool:
	if player == null:
		return false
	var to: Vector3 = player.global_position - global_position
	if to.x * to.x + to.z * to.z < 0.000001:
		return true
	return absf(angle_difference(rotation.y, atan2(to.x, to.z))) <= FRONT_ANGLE


func _player_dist_gx(player: Node3D) -> float:
	if player == null:
		return INF
	var to: Vector3 = player.global_position - global_position
	return Vector2(to.x, to.z).length() / FieldCatalog.GX_TO_METERS


func _wants_exit_greeting() -> bool:
	return not _exit_greeted and Game != null and Game.last_room_id == &"police_box" and not Game.is_indoors()


func _player_free(player: Node3D) -> bool:
	var p: Player = player as Player
	if p == null or p.is_busy() or p.is_door_entering():
		return false
	return not DialogueOverlay.open_in(get_tree())


## --- Talk --------------------------------------------------------------------------------


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if not visible:
		return []
	return [Interaction.of(Interaction.TALK, "Talk to Copper", 20)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK or Game == null or _talking:
		return false
	var listener: Node3D = ctx.actor as Node3D if ctx != null else null
	return _begin_talk(listener, false)


func _begin_talk(listener: Node3D, exit_greeting: bool) -> bool:
	var ctx: DialogueContext = DialogueContext.from_game()
	ctx.speaker_name = "Copper"
	CopperTalk.fill(ctx, exit_greeting)
	var data: DialogueData = CopperTalk.conversation(exit_greeting)
	var ui := DialogueOverlay.find(get_tree())
	if ui == null or data == null:
		return false
	if ui.is_open():
		ui.close()
	_talking = true
	_set_mode(Mode.WAIT)
	if listener != null:
		## `mDemo_Set_talk_turn(FALSE)` on the walk-out greeting: the player keeps facing.
		TalkCamera.begin(listener, self, get_tree(), not exit_greeting)
	if not ui.closed.is_connected(_on_talk_closed):
		ui.closed.connect(_on_talk_closed, CONNECT_ONE_SHOT)
	ui.play(data, ctx)
	return true


func _on_talk_closed() -> void:
	_talking = false
	TalkCamera.end(get_tree())
	_timer = 0.0


func _face_player() -> void:
	var player := Player.find(get_tree())
	if player is Node3D:
		var to: Vector3 = (player as Node3D).global_position - global_position
		to.y = 0.0
		if to.length_squared() > 0.0001:
			rotation.y = atan2(to.x, to.z)


## --- Presentation ------------------------------------------------------------------------


func _ensure_collision() -> void:
	if get_node_or_null("CollisionShape3D") != null:
		return
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.8, 1.0)
	shape.shape = box
	shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(shape)


func _ensure_interact() -> void:
	if get_node_or_null("InteractVolume") != null:
		return
	var volume := Area3D.new()
	volume.name = "InteractVolume"
	volume.collision_layer = 8
	volume.collision_mask = 0
	volume.monitoring = false
	volume.monitorable = true
	volume.set_script(load("res://scenes/world/interact_volume.gd"))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 2.0, 1.6)
	shape.shape = box
	shape.position = Vector3(0.0, 1.0, 0.0)
	volume.add_child(shape)
	add_child(volume)


func _ensure_visual() -> void:
	if get_node_or_null("Model") != null:
		return
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var vis: Node3D = GeneratedVisual.attach_villager(_model, SPECIES)
	if vis == null:
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.4
		capsule.height = 1.4
		mesh.mesh = capsule
		mesh.position.y = 0.9
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.35, 0.6)
		mesh.material_override = mat
		_model.add_child(mesh)
		return
	_body_anim = VisualAnimation.find_animation_player(vis)
	_face.bind(vis, SPECIES)


func _play_clip(suffix: String, loop: bool) -> void:
	if _body_anim == null:
		_clip = suffix
		return
	var clip := _resolve_clip(suffix)
	if clip.is_empty():
		_clip = suffix
		return
	_clip = clip
	var animation: Animation = _body_anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_body_anim.speed_scale = 1.0
	_body_anim.play(clip, 0.12)


func _clip_seconds(clip: String) -> float:
	if _body_anim != null and _body_anim.has_animation(clip):
		var animation: Animation = _body_anim.get_animation(clip)
		if animation != null and animation.length > 0.0:
			return animation.length
	return WAIT_CYCLE_FALLBACK


func _resolve_clip(suffix: String) -> String:
	if _body_anim == null or suffix.is_empty():
		return ""
	if _body_anim.has_animation(suffix):
		return suffix
	for anim_name: String in _body_anim.get_animation_list():
		if anim_name.ends_with(suffix):
			return anim_name
	return ""
