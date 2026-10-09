class_name EventNpc
extends StaticBody3D

## A special NPC the event manager puts in town (`ac_ev_*`, `ac_npc_totakeke`, …). Shared
## presentation for all of them — the species GLB, face, clips, turning to the player,
## `DEMONPC0` reactions (`aNPC_check_manpu_demoCode`) — and the talk: a `BankTalk` from
## `make_talk()` run over the disc messages. Subclasses set the species / name and override
## `make_talk()`, `idle_clip()` and `think()`.

const TURN_RATE := deg_to_rad(11.25) * 30.0
const WAIT_CYCLE_FALLBACK := 2.0
## `aNPC_ACT_WALK` pace (≈ 1.5 m/s); presenters pass their own for runs.
const WALK_SPEED := 1.5

## Event this NPC belongs to (`mEv_EVENT_*` id); set by `EventManager`.
var event_id: StringName = &""
## Index inside the event (`mEv_place_data_c` id).
var place_index: int = 0
## Skeleton / species GLB prefix (`boa`, `end`, `seg`, …).
var species: StringName = &""
## Villager texture set (`squ01`, …) for villagers borrowed by a festival; empty for specials.
var texture_set: StringName = &""
## A shirt to wear (`cloth_index`, e.g. the sports-fair gym clothes); -1 keeps the model's own.
var cloth_index: int = -1
var display_name: String = ""
## Message-window voice (`aNPC_draw_data_c.voice_type` stands in as a sound spec).
var sound_spec: int = 4
var talk_label: String = ""
## Where the manager placed it; `home_yaw` is the facing it returns to after a talk.
var home_yaw: float = 0.0
var talking: bool = false
var talk: BankTalk
## Whether the body turns to the player while talking (`aNPC_TALK_TURN_HEAD` keeps it still).
var talk_turn: bool = true

var _model: Node3D
var _body_anim: AnimationPlayer
var _face: NpcFace = NpcFace.new()
var _feel: NpcFeelGlyphs
var _clip: String = ""
var _clip_timer: float = 0.0
var _manpu_clip: String = ""
var _turning_home: bool = false
var _move_target: Vector3 = Vector3.INF
var _move_speed: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("event_npc")
	collision_layer = 1
	collision_mask = 0
	_rng.randomize()
	rotation.y = home_yaw
	_ensure_collision()
	_ensure_visual()
	_ensure_interact()
	play_clip(idle_clip(), true)
	setup()


## Subclass hook after the visual exists.
func setup() -> void:
	pass


## Clip while nothing else plays.
func idle_clip() -> String:
	return "npc_1_wait1"


## The talk script; null means no talk.
func make_talk() -> BankTalk:
	return null


## Per-frame behaviour while not talking.
func think(_delta: float) -> void:
	pass


## Whether A talks right now (`talk_request` gating).
func can_talk() -> bool:
	return visible


func _process(delta: float) -> void:
	var uttering: bool = false
	if talking and get_tree() != null:
		uttering = DialogueOverlay.uttering_in(get_tree())
	_face.tick(delta, uttering)


func _physics_process(delta: float) -> void:
	_clip_timer -= delta
	if talking:
		if talk_turn:
			_turn_towards_player(delta)
		if not _manpu_clip.is_empty() and _clip_timer <= 0.0 and _clip == _manpu_clip:
			_manpu_clip = ""
			if _feel != null:
				_feel.release()
			play_clip(talk_clip(), true)
		return
	if _turning_home:
		if turn_to(home_yaw, delta):
			_turning_home = false
		return
	if _move_target != Vector3.INF:
		_step_move(delta)
		return
	think(delta)


## Clip while listening / talking.
func talk_clip() -> String:
	return idle_clip()


## --- Movement ------------------------------------------------------------------------------


## Walk (or run) to `target` on the ground; `arrived()` fires when there.
func move_to(target: Vector3, speed: float = WALK_SPEED, clip: String = "npc_1_walk1") -> void:
	_move_target = target
	_move_speed = speed
	play_clip(clip, true)


func is_moving() -> bool:
	return _move_target != Vector3.INF


func stop_moving() -> void:
	_move_target = Vector3.INF


func arrived() -> void:
	play_clip(idle_clip(), true)


func _step_move(delta: float) -> void:
	var to: Vector3 = _move_target - global_position
	to.y = 0.0
	var dist: float = to.length()
	var step: float = _move_speed * delta
	if dist <= step or dist < 0.01:
		global_position = Vector3(_move_target.x, global_position.y, _move_target.z)
		_move_target = Vector3.INF
		arrived()
		return
	turn_to(atan2(to.x, to.z), delta)
	global_position += to / dist * step
	var world: World = World.find(get_tree()) if get_tree() != null else null
	if world != null and world.layout != null:
		var cell: Vector2i = world.grid.world_to_cell(global_position)
		if world.layout.is_in_bounds(cell):
			global_position.y = FieldCollision.ground_y(world.layout, cell)


## Turn at the NPC turn rate; true once facing `yaw`.
func turn_to(yaw: float, delta: float) -> bool:
	var diff: float = angle_difference(rotation.y, yaw)
	var step: float = TURN_RATE * delta
	if absf(diff) <= step:
		rotation.y = yaw
		return true
	rotation.y += signf(diff) * step
	return false


func _turn_towards_player(delta: float) -> void:
	var player := Player.find(get_tree())
	if player is Node3D:
		var to: Vector3 = (player as Node3D).global_position - global_position
		to.y = 0.0
		if to.length_squared() > 0.0001:
			turn_to(atan2(to.x, to.z), delta)


func player_node() -> Node3D:
	return Player.find(get_tree()) as Node3D if get_tree() != null else null


## Whether this NPC may start a talk itself (`mDemo_TYPE_SPEAK` requests wait for a free
## window and a player who isn't in the middle of something).
func can_call_out() -> bool:
	if talking or get_tree() == null:
		return false
	var ui := DialogueOverlay.find(get_tree())
	if ui == null or ui.is_open():
		return false
	var p := player_node() as Player
	return p != null and not p.is_busy()


func player_distance() -> float:
	var p: Node3D = player_node()
	if p == null:
		return INF
	var to: Vector3 = p.global_position - global_position
	return Vector2(to.x, to.z).length()


## --- Talk ----------------------------------------------------------------------------------


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if not can_talk() or talking:
		return []
	var label: String = talk_label if talk_label != "" else "Talk to %s" % display_name
	return [Interaction.of(Interaction.TALK, label, 20)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK or Game == null or talking or not can_talk():
		return false
	var listener: Node3D = ctx.actor as Node3D if ctx != null else null
	return begin_talk(listener)


func make_context() -> DialogueContext:
	var ctx: DialogueContext = DialogueContext.from_game()
	ctx.speaker_name = display_name
	ctx.voice_mode = DialogueVoice.Mode.ANIMALESE
	ctx.sound_spec = sound_spec
	if ctx.rng == null:
		ctx.rng = RandomNumberGenerator.new()
		ctx.rng.randomize()
	return ctx


## Open the message window on `talk` (or a fresh `make_talk()`).
func begin_talk(listener: Node3D, script: BankTalk = null, turn_player: bool = true) -> bool:
	var ui := DialogueOverlay.find(get_tree())
	if ui == null:
		return false
	talk = script if script != null else make_talk()
	if talk == null:
		return false
	var ctx: DialogueContext = make_context()
	talk.context = ctx
	talk.prepare()
	var first: int = talk.start_msg()
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % first)) if first >= 0 else null
	if data == null:
		talk = null
		return false
	if ui.is_open():
		ui.close()
	talking = true
	stop_moving()
	_turning_home = false
	play_clip(talk_clip(), true)
	if listener != null:
		TalkCamera.begin(listener, self, get_tree(), turn_player)
	if not ui.closed.is_connected(_on_talk_closed):
		ui.closed.connect(_on_talk_closed, CONNECT_ONE_SHOT)
	if not ui.event_fired.is_connected(_on_talk_event):
		ui.event_fired.connect(_on_talk_event)
	ui.play(data, ctx, null, Callable(), talk)
	var runner: DialogueRunner = ui.runner()
	if runner != null:
		runner.action_requested.connect(_on_talk_action.bind(ui, listener))
	return true


func _on_talk_action(action: Dictionary, ui: DialogueOverlay, player: Node3D) -> void:
	await TalkActions.handle(action, ui, self, player)


func _on_talk_event(event: Dictionary) -> void:
	if not talking:
		return
	var op := str(event.get("op", ""))
	if op != "manpu":
		return
	var key := str(event.get("name", event.get("code", "")))
	cue_manpu(key)


## `aNPC_check_manpu_demoCode`: a reaction clip, a face and a feel glyph.
func cue_manpu(key: String) -> void:
	_face.set_emote(NpcManpu.emote_for(key), NpcManpu.mouth_hold_for(key))
	if NpcManpu.is_reset(key):
		_manpu_clip = ""
		play_clip(talk_clip(), true)
		return
	var clip: String = NpcManpu.clip_for(key)
	if resolve_clip(clip).is_empty():
		return
	play_clip(clip, false)
	_manpu_clip = _clip
	if _feel != null:
		_feel.play_for_manpu(key)


func _on_talk_closed() -> void:
	talking = false
	_manpu_clip = ""
	if _feel != null:
		_feel.release()
	TalkCamera.end(get_tree())
	var ui := DialogueOverlay.find(get_tree())
	if ui != null and ui.event_fired.is_connected(_on_talk_event):
		ui.event_fired.disconnect(_on_talk_event)
	_face.set_emote(NpcFaceAnim.Emote.NORMAL)
	var finished_talk: BankTalk = talk
	talk = null
	play_clip(idle_clip(), true)
	talk_ended(finished_talk)


## After the window closes. Default: turn back to the home facing.
func talk_ended(_script: BankTalk) -> void:
	_turning_home = true
	if Game != null and Game.events != null and event_id != &"":
		Game.events.mark_talked(event_id)


## --- Presentation --------------------------------------------------------------------------


func _ensure_collision() -> void:
	if get_node_or_null("CollisionShape3D") != null:
		return
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.8
	cyl.height = 1.8
	shape.shape = cyl
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
	box.size = Vector3(1.8, 2.0, 1.8)
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
	var vis: Node3D = GeneratedVisual.attach_villager(_model, species) if species != &"" else null
	if vis == null:
		var mesh := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.4
		capsule.height = 1.4
		mesh.mesh = capsule
		mesh.position.y = 0.9
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.7, 0.5, 0.3)
		mesh.material_override = mat
		_model.add_child(mesh)
	else:
		_body_anim = VisualAnimation.find_animation_player(vis)
		if texture_set != &"":
			VillagerTextures.apply(vis, texture_set)
		if cloth_index >= 0:
			VisualCloth.apply_cloth(vis, cloth_index)
		_face.bind(vis, species, texture_set)
	_feel = NpcFeelGlyphs.new()
	_feel.name = "Feel"
	add_child(_feel)


func model() -> Node3D:
	return _model


## Play `suffix` (`npc_1_wait1`, …); returns its length in seconds.
func play_clip(suffix: String, loop: bool) -> float:
	var clip := resolve_clip(suffix)
	if clip.is_empty():
		_clip = suffix
		_clip_timer = WAIT_CYCLE_FALLBACK
		return WAIT_CYCLE_FALLBACK
	_clip = clip
	var animation: Animation = _body_anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_body_anim.speed_scale = 1.0
	_body_anim.play(clip, 0.12)
	_clip_timer = clip_seconds(clip)
	return _clip_timer


## `HandOver` puts the NPC back to its hold after passing an item.
func play_wait_anim() -> void:
	play_clip(talk_clip() if talking else idle_clip(), true)


func current_clip() -> String:
	return _clip


func clip_done() -> bool:
	return _clip_timer <= 0.0


func clip_seconds(clip: String) -> float:
	if _body_anim != null and _body_anim.has_animation(clip):
		var animation: Animation = _body_anim.get_animation(clip)
		if animation != null and animation.length > 0.0:
			return animation.length
	return WAIT_CYCLE_FALLBACK


func resolve_clip(suffix: String) -> String:
	if _body_anim == null or suffix.is_empty():
		return ""
	if _body_anim.has_animation(suffix):
		return suffix
	for anim_name: String in _body_anim.get_animation_list():
		if anim_name.ends_with(suffix):
			return anim_name
	return ""


## --- Helpers for talk scripts --------------------------------------------------------------


func rng() -> RandomNumberGenerator:
	return _rng
