class_name Villager
extends CharacterBody3D

## One shared villager actor. Looks, schedule, and lines come from VillagerData.
## Spatial: Model, Collision, NavigationAgent3D, InteractionArea, Animation.
## Behavior: VillagerSchedule + VillagerAI + VillagerWalk (goal acres) + VillagerMotor.

## `mQst_NextSoccer`: "Hey! It's a ball!", by looks.
const SOCCER_CALL_MSG := 0x0D8B
const IDLE_SPEED := 0.08
## Fraction of intended XZ step that must stick after BG revise; else front-wall.
## Absolute meters-per-frame thresholds break at 60 Hz (walk ≈ 0.025 m/tick).
const STUCK_FRAC := 0.35
const ANIM_WAIT := "npc_1_wait1"
const ANIM_WALK := "npc_1_walk1"
const ANIM_RUN := "npc_1_run1"
const ANIM_SIT := "npc_1_sit1"
const ANIM_FISH := "npc_1_fish1"
## `aNPC_calc_fatigue`: walk +1, run +2, wait -2 per decomp frame (60 Hz); clamp [0, 1600].
## `aNPC_check_fatigue` forces WAIT at 1600; `aNPC_act_wait` holds it until below 200.
const FATIGUE_MAX := 1600.0
const FATIGUE_REST := 200.0
const FATIGUE_WALK := 1.0
const FATIGUE_RUN := 2.0
const FATIGUE_WAIT := -2.0
## `aNPC_check_uzai_cross`: crowd radius `mFI_UNIT_BASE_SIZE` (40 GX = 2 m), both
## horizontally and vertically, plus a facing cone of ±135° (2.35619449 rad).
const ANNOY_CROWD_DIST := 2.0
const ANNOY_FACE_CONE := 2.35619449
## `max_uzai_cross`/`max_uzai_tool`: first-offense vs. after-`uzai.cross` (tighter)
## thresholds. Frame counts (600, 240 @ 60 Hz) converted to seconds.
const ANNOY_STEP_LIMIT: Array[float] = [10.0, 4.0]
const ANNOY_TOOL_LIMIT: Array[int] = [3, 1]
const ANNOY_STEP_GAIN := 2.0
const ANNOY_STEP_DECAY := 1.0
## `aNPC_set_feel_info(nactorx, feel, 1)`: the annoyed mood lasts one real-time minute.
const ANNOY_MOOD_SECONDS := 60.0
## `aNPC_ACT_REACT_TOOL` (`ac_npc_act_react_tool.c_inc`): the jump when a tool lands on the
## villager. Steps: surprise (`gyafun1`, then done), surprise2 (`gyafun2` when the player is
## in view, then stare at them), surprise while already annoyed (`gyafun2`, then done), and
## the stare itself (wait clip, 5 s, head at talk priority).
enum React { NONE = -1, SURPRISE, SURPRISE2, SURPRISE_UZAI, LOOK_PLAYER }
const REACT_CLIPS: Array[String] = ["npc_1_gyafun1", "npc_1_gyafun2", "npc_1_gyafun2", ANIM_WAIT]
const REACT_LOOK_SECONDS := 5.0
## Outdoor acts that stop the walk (`aNPC_ACT_UMB_OPEN` / `UMB_CLOSE` / `CLAP`).
enum Act { NONE, UMB_OPEN, UMB_CLOSE, CLAP, GREET }
## `aNPC_ACT_GREETING_STEP_*` (turn, approach, wait for the partner, bow, change clothes,
## wait for the partner to finish changing).
enum Greet { TURN, APPROACH, WAIT, BOW, CHANGE, HOLD }
const ANIM_UMB_OPEN := "npc_1_umb_open1"
const ANIM_UMB_CLOSE := "npc_1_umb_close1"
const ANIM_UMBRELLA := "npc_1_umbrella1"
const ANIM_CLAP := "npc_1_clap1"
## `aNPC_ACTION_TYPE_GO_OUT`: steps out of the doorway. joint_0 starts 6.8 back inside the
## house and ends on the actor, so the body stands still while the clip carries the mesh.
const ANIM_GO_OUT := "npc_1_go_out1"
## `aNPC_think_pitfall` → `aNPC_act_pitfall` (totter, drop, struggle) → `aNPC_act_revive`.
enum Pit { NONE, TOTTER, FALL, STRUGGLE, REVIVE }
const ANIM_GURATUKU := "npc_1_guratuku1"
const ANIM_OTIRU := "npc_1_otiru1"
const ANIM_MOGAKU := "npc_1_mogaku1"
const ANIM_DERU := "npc_1_deru1"
## `aNPC_act_pitfall_totter`: `chase_f(…, 1.5)` GX per frame toward the unit centre, in m/s.
const PIT_TOTTER_SPEED := 1.5 * FieldCatalog.GX_TO_METERS * DecompTime.FRAME_HZ

@export var data: VillagerData
## Indoor `ac_npc2` stand-in: always visible while the player is in this house.
@export var indoor_resident: bool = false
## Met as an event guest (`&"kamakura"`, `&"camper"`): their own greetings and trade lists.
@export var guest: StringName = &""

var state: VillagerState
var schedule: VillagerSchedule = VillagerSchedule.new()
var ai: VillagerAI = VillagerAI.new()
var _motor: VillagerMotor = VillagerMotor.new()
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _layer_present: int = 4
## The body tree once the model is bound (`_animator`), null without a model.
var _body_anim: BodyAnimator
var _clip: String = ""
## Acre the visible actor is wandering right now (`aNPC` `range_center` block).
var _wander_block: Vector2i = Vector2i.ZERO
## Entry point in the next acre while relocating toward `_goal_block` (INF = wandering).
var _travel_stand: Vector3 = Vector3.INF
## `aNPC_condition_info.fatigue` — sustained walk/run forces a rest wait.
var _fatigue: float = 0.0
## `aNPC_act_wait`: once fatigue hits the cap, hold the wait until it drains under 200.
var _resting: bool = false
## After an avoid hop, wait before re-steering (decomp spends frames in ACT_TURN).
var _avoid_cool: float = 0.0
## Seconds spent colliding with a structure during the current wander leg.
var _wall_time: float = 0.0
## One-time: lift the villager out of a pocket at its spawn / front door.
var _spawn_unstuck: bool = false
## Seconds left of the GO_OUT clip; the villager holds on the door threshold meanwhile.
var _going_out: float = 0.0
## Runtime-only annoyance state (`nactorx->uzai`) — never persisted; only the
## `mood` it produces (`Animal_c.mood`) lives on `state`.
var _uzai_tool: int = 0
var _react: React = React.NONE
var _react_timer: float = 0.0
var _uzai_cross: bool = false
var _uzai_step: float = 0.0
var _uzai_flag: bool = false
var _uzai_mood_left: float = 0.0
var _talk_look: Vector3 = Vector3.ZERO
var _face: NpcFace = NpcFace.new()
var _head_look: NpcHeadLook = NpcHeadLook.new()
var _pit: Pit = Pit.NONE
var _pit_cell := Vector2i(-1, -1)
var _pit_center := Vector3.ZERO
var _pit_clip: String = ""
var _pit_model_rest := Vector3.ZERO
var _act: Act = Act.NONE
## The umbrella in the right hand (`right_hand.item_type == UMBRELLA`) and its arm pose
## (`aNPC_SUB_ANIM_UMBRELLA`).
var _umbrella: HeldUmbrella = null
var _umb_carry: ToolCarry = null
var _outdoor_rng := RandomNumberGenerator.new()
## `aNPC_ACT_CHASE_INSECT` / `CHASE_GYOEI`: what's being watched, and for how much longer.
var _chase: Object = null
var _chase_fish: bool = false
var _chase_left: float = 0.0
## `palActor` / `palActorIgnoreTimer`: the villager this one is greeting.
var _pal: Node3D = null
var _pal_ignore: float = 0.0
## What the model has on (`draw.cloth_no` / `org_idx`, `right_hand.umbrella_type`).
var _drawn_cloth: String = ""
var _drawn_umb: int = -1
## Quest manager for the conversation in progress (`VillagerTalkManager`).
var _talk_manager: VillagerTalkManager
## `aNPC_check_manpu_demoCode`: the reaction clip a talk line called for, held until it ends.
var _manpu_clip: String = ""
## The loop the reaction settled into after its first clip.
var _manpu_follow: String = ""
## A popular day's call-out (`force_call_timer`): seconds before calling again, and whether
## the talk now open is one.
var _fortune_cool: float = 0.0
var _fortune_calling: bool = false
var _feel: NpcFeelGlyphs
## Where the feel glyphs sit: about a villager's head height.
const FEEL_HEAD_LIFT := 1.15
var _visual: Node3D
## Cloth-surface overrides from before an Able design was painted on: `[mesh, surface, material]`.
var _own_cloth: Array = []
## Out at a festival as an event NPC (`mNpc_SetEventNpc`): the field copy stays hidden.
var event_away: bool = false

@onready var _model: Node3D = $Model
@onready var _collision: CollisionShape3D = $Collision
@onready var _agent: NavigationAgent3D = $NavigationAgent3D
@onready var _volume: Area3D = $InteractionArea
@onready var _anim: AnimationPlayer = $Animation
@onready var _animator: BodyAnimator = $Animator
@export var mover: VillagerMover
@export var brain: VillagerBrain
@export var greeter: VillagerGreeter
@export var conversation: VillagerConversation


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("villagers")
	_layer_present = collision_layer
	_ensure_bound()
	Clock.time_changed.connect(_sync_from_clock)
	ai.action_changed.connect(brain.on_action_changed)
	ai.schedule_changed.connect(brain.on_schedule_changed)
	_motor.reset(global_position, rotation.y)
	var table: ScheduleData = data.schedule_table() if data != null else null
	var first: StringName = table.activity_now() if table != null else VillagerActivity.FIELD
	if not indoor_resident and state != null:
		## Start home when the looks table is IN_HOUSE / SLEEP (`Animal_c.is_home`).
		if first == VillagerActivity.IN_HOUSE or first == VillagerActivity.SLEEP:
			state.is_home = true
	if first == VillagerActivity.FIELD and _awaits_player_acre():
		first = _held_activity()
	_apply_presence(indoor_resident or VillagerActivity.is_present(first))
	var vis: Node3D = GeneratedVisual.attach_villager(_model, data.species if data else &"")
	_visual = vis
	if vis != null:
		var body_player: AnimationPlayer = VisualAnimation.find_animation_player(vis)
		if body_player != null:
			_animator.bind(body_player)
			_body_anim = _animator
			## Before the head look binds, so the head override lands on top of the arm pose.
			if not _body_anim.mixer_applied.is_connected(_apply_sub_anim):
				_body_anim.mixer_applied.connect(_apply_sub_anim)
		_play_clip(ANIM_WAIT, true)
		var texture_set: StringName = data.texture_set if data else &""
		VillagerTextures.apply(vis, texture_set)
		_face.bind(vis, data.species if data else &"", texture_set)
		_head_look.bind(vis, self)
		if _feel == null:
			_feel = NpcFeelGlyphs.new()
			_feel.name = "Feel"
			add_child(_feel)
			_feel.set_head_lift(FEEL_HEAD_LIFT)
		var skeletons: Array[Node] = vis.find_children("*", "Skeleton3D", true, false)
		_feel.bind_feel_joint(skeletons[0] as Skeleton3D if not skeletons.is_empty() else null)
		conversation.sync_face_mood(true)
		_apply_design_wear()
		if Game != null and Game.designs != null and not Game.designs.changed.is_connected(_apply_design_wear):
			Game.designs.changed.connect(_apply_design_wear)
	if indoor_resident:
		_motor.facing = rotation.y
	else:
		_sync_from_clock()
		_drawn_cloth = _cloth_key()
		_drawn_umb = state.umbrella_design if state != null else -1
		## `aNPC_check_force_use_umbrella`: out in the rain from the start, umbrella up.
		if state != null and not state.is_home and Game != null and Game.town.weather == &"rain":
			_take_out_umbrella(true)


func _sync_from_clock() -> void:
	if indoor_resident or event_away:
		return
	ai.sync(current_activity(), brain.hints())
	_apply_presence(ai.is_present())


func _exit_tree() -> void:
	if data != null:
		VillagerWalk.release(data.id)
	conversation.unbind_talk()
	if Clock.time_changed.is_connected(_sync_from_clock):
		Clock.time_changed.disconnect(_sync_from_clock)
	if ai.action_changed.is_connected(brain.on_action_changed):
		ai.action_changed.disconnect(brain.on_action_changed)
	if Game != null and Game.designs != null and Game.designs.changed.is_connected(_apply_design_wear):
		Game.designs.changed.disconnect(_apply_design_wear)


## An Able Sisters shirt (`RSV_CLOTH` + `cloth_original_id`, `aNPC_setup_chg_cloth`):
## paint the mannequin's design over the cloth surfaces, or put the villager's own
## shirt back when they stop wearing one.
func _apply_design_wear() -> void:
	if _visual == null or state == null or Game == null:
		return
	if Game.designs == null and state.cloth_design >= 0:
		return
	var idx: int = state.cloth_design
	## A shirt they were given or picked up (`Animal_c.cloth` other than their own).
	if idx < 0 and state.cloth_id != &"":
		var cloth: ItemData = ItemCatalog.get_item(state.cloth_id)
		var cloth_index: int = cloth.cloth_index if cloth != null else -1
		if cloth_index < 0 and String(state.cloth_id).begins_with("shirt_"):
			cloth_index = int(String(state.cloth_id).substr(6))
		if cloth_index >= 0 and (data == null or cloth_index != data.default_cloth):
			if _own_cloth.is_empty():
				_own_cloth = _cloth_overrides(_visual)
			VisualCloth.apply_cloth(_visual, cloth_index)
			return
	if idx < 0:
		if not _own_cloth.is_empty():
			for entry: Array in _own_cloth:
				var mi := entry[0] as MeshInstance3D
				if is_instance_valid(mi):
					mi.set_surface_override_material(int(entry[1]), entry[2] as Material)
			_own_cloth.clear()
		return
	if _own_cloth.is_empty():
		_own_cloth = _cloth_overrides(_visual)
	VisualCloth.apply_design(_visual, DesignTexture.build(Game.designs.shop[idx & 3]))


func _cloth_overrides(node: Node, acc: Array = []) -> Array:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		for i: int in mi.mesh.get_surface_count():
			if VisualCloth.is_cloth_surface(mi, i, mi.get_active_material(i)):
				acc.append([mi, i, mi.get_surface_override_material(i)])
	for child: Node in node.get_children():
		_cloth_overrides(child, acc)
	return acc


func current_activity() -> StringName:
	_ensure_bound()
	var now: StringName = schedule.advance(Clock.now_sec())
	if now == VillagerActivity.FIELD and _awaits_player_acre():
		return _held_activity()
	return now


## `aSNMgr_check_move_npc_schedule`: FIELD only moves a villager who is already
## outside (`!is_home`). One still at home has no actor until the player's acre
## spawns it (`aSNMgr_set_npc_regular`); then `aNPC_field_schedule_init_proc` starts
## at LEAVE_HOUSE and it walks out of the door. Until then it stays where it was.
func _awaits_player_acre() -> bool:
	if indoor_resident or state == null or not state.is_home:
		return false
	return not _player_in_home_acre()


func _held_activity() -> StringName:
	if ai.schedule_type == VillagerActivity.SLEEP:
		return VillagerActivity.SLEEP
	return VillagerActivity.IN_HOUSE


func _player_in_home_acre() -> bool:
	var bg: Array = _bg()
	var player: Node = get_tree().get_first_node_in_group("player") if get_tree() != null else null
	if bg.size() != 2 or not (player is Node3D):
		return false
	var grid: WorldGrid = bg[1] as WorldGrid
	var home_block: Vector2i = VillagerWalk.block_from_cell(grid.world_to_cell(_motor.home))
	var player_block: Vector2i = VillagerWalk.block_from_cell(
		grid.world_to_cell((player as Node3D).global_position)
	)
	return player_block == home_block


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if indoor_resident:
		var who: String = data.display_name if data else "Villager"
		return [Interaction.of(Interaction.TALK, "Talk to %s" % who, 20)]
	ai.sync(current_activity(), brain.hints())
	if not ai.is_talkable():
		return []
	var who_out: String = data.display_name if data else "Villager"
	return [Interaction.of(Interaction.TALK, "Talk to %s" % who_out, 20)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK:
		return false
	if not indoor_resident:
		ai.sync(current_activity(), brain.hints())
		if not ai.is_talkable():
			return false
	_ensure_bound()
	if ctx != null and ctx.actor != null:
		_talk_look = ctx.actor.global_position
	else:
		_talk_look = global_position
	## First-job delivery / open handoff before normal greetings.
	if await conversation.try_first_job_talk(ctx):
		return true
	var talk_ctx: DialogueContext = DialogueContext.from_game(data, state)
	talk_ctx.guest = guest
	var ui := DialogueOverlay.find(get_tree())
	if ui != null:
		if ui.is_open():
			ui.close()
		ai.begin_talk()
		conversation.bind_talk_end(ui)
		## Decomp `Camera2_request_main_talk(play, player, npc)` — speaker = player.
		var player: Node3D = ctx.actor as Node3D if ctx != null else null
		if player != null:
			TalkCamera.begin(player, self, get_tree())
		_talk_manager = VillagerTalk.manager(data, state, talk_ctx)
		conversation.sing_town_tune(talk_ctx)
		ui.play(VillagerTalk.conversation(data, state, talk_ctx), talk_ctx, state, Callable(), _talk_manager)
		var runner: DialogueRunner = ui.runner()
		if runner != null and _talk_manager != null:
			runner.action_requested.connect(conversation.on_talk_action.bind(ui, player))
	else:
		_face_towards(_talk_look)
		var line: String = VillagerTalk.greeting(data, state)
		var who: String = data.display_name if data else "Villager"
		Game.post_notice("%s: %s" % [who, line])
	if state != null:
		state.record_talk(VillagerTalk.day_key())
	conversation.note_first_job_talk()
	return true


func _physics_process(delta: float) -> void:
	## `aNPC_check_feel_tim`.
	if state != null:
		state.tick_feel(delta)
	if indoor_resident:
		_tick_indoor(delta)
		return
	ai.sync(current_activity(), brain.hints())
	var present: bool = ai.is_present()
	_apply_presence(present)
	conversation.tick_face(delta)
	_tick_head_look(delta)
	if not present:
		velocity = Vector3.ZERO
		ai.step(delta)
		_update_animation(delta, Vector3.ZERO)
		return
	if ai.is_talking():
		_react = React.NONE
		_head_look.fast = false
		if _pit != Pit.NONE:
			## `talk_info.turn = NONE`: they keep struggling, facing where they fell.
			velocity = Vector3.ZERO
			ai.step(delta)
			return
		conversation.hold_talk(delta)
		return
	if _pit != Pit.NONE:
		_tick_pit(delta)
		return
	if _react != React.NONE:
		_tick_react(delta)
		return
	if _pal_ignore > 0.0:
		_pal_ignore = maxf(_pal_ignore - delta, 0.0)
	greeter.pair_greetings()
	if _umbrella != null:
		_umbrella.advance(delta)
	if _umb_carry != null:
		_umb_carry.advance(delta)
	if _act != Act.NONE:
		_tick_act(delta)
		return
	if _going_out > 0.0:
		_tick_go_out(delta)
		return
	if _start_outdoor_act():
		return
	if not _spawn_unstuck:
		mover.unstick_spawn()
	var on_bg: bool = _snap_to_bg()
	if on_bg:
		velocity.y = 0.0
		motion_mode = MOTION_MODE_FLOATING
	elif not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	if ai.is_wandering():
		mover.tick_acre_travel(delta)
	mover.steer_ai()
	var aim: Vector3 = _motor.steer if _motor.has_target else global_position
	var planar: Vector3 = _motor.advance(delta, global_position, aim, ai.wants_move())
	ai.consider_arrive(global_position)
	velocity.x = planar.x
	velocity.z = planar.z
	if _model != null:
		_model.rotation.y = _motor.facing
	var before: Vector3 = global_position
	## Decomp order: position_move → BGcheck → circleRangeRevice → forward/obj → think avoid.
	move_and_slide()
	var bg: Array = _bg()
	if bg.size() == 2:
		global_position = FieldCollision.revise_xz(
			bg[0] as WorldData, bg[1] as WorldGrid, before, global_position
		)
		## `aNPC_circleRangeRevice`: clamp to the current acre's roam circle while
		## wandering it — not while relocating across acres (`range_type` BLOCK).
		if ai.is_wandering() and _travel_stand == Vector3.INF and mover.in_wander_block():
			global_position = VillagerWalk.circle_revise(
				bg[0] as WorldData, _wander_block, global_position
			)
	elif on_bg:
		_snap_to_bg()
	if _avoid_cool > 0.0:
		_avoid_cool = maxf(0.0, _avoid_cool - delta)
	## Avoid only while moving (`speed != 0` in decomp interrupt).
	var wall_flags: int = 0
	if planar.length() > IDLE_SPEED and _motor.has_target:
		wall_flags = mover.collision_flags(before, planar, delta)
		if wall_flags != 0 and _avoid_cool <= 0.0:
			mover.steer_around_wall(wall_flags)
	## Stuck watchdog: time spent trying to walk (target, not idling) without covering
	## ground. Survives the turn-in-place phases of an avoid hop, so a villager wedged
	## on its own house eventually bails to a fresh rim (`decide_next` → move_next).
	var progressing: bool = (global_position - before).length() > _motor.speed_now() * delta * STUCK_FRAC
	if (
		ai.is_wandering()
		and _travel_stand == Vector3.INF
		and _motor.has_target
		and _motor.wait_left <= 0.0
		and not progressing
	):
		_wall_time += delta
	else:
		_wall_time = 0.0
	_update_animation(delta, Vector3(velocity.x, 0.0, velocity.z))
	_tick_fatigue(delta, Vector3(velocity.x, 0.0, velocity.z))
	_tick_annoyance(delta)
	ai.step(delta)
	_check_pitfall()


func _tick_indoor(delta: float) -> void:
	## Indoor resident: always present, stand, head-look, talkable (`ac_npc2` wander wait).
	_apply_presence(true)
	conversation.tick_face(delta)
	_tick_head_look(delta)
	if ai.is_talking():
		conversation.hold_talk(delta)
		return
	velocity = Vector3.ZERO
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()
	_update_animation(delta, Vector3.ZERO)


func _tick_head_look(delta: float) -> void:
	if get_tree() == null:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	## `aNPC_check_condition_search_eye`: only the sleepy *feel* freezes the head.
	var sleepy: bool = state != null and int(state.mood) == int(VillagerState.Mood.SLEEPY)
	## `aNPC_COND_DEMO_SKIP_HEAD_LOOKAT`: asleep (`ac_npc_think_sleep`) or walking in the door
	## (`ac_npc_act_into_house`) — no player look; the head eases back to the animation.
	var kind: StringName = ai.kind()
	var skip_look: bool = kind == ActivityKind.SLEEP or ActivityKind.is_door_demo(kind)
	## The tool reaction's jumps set the same skip flag; its stare is a priority-4 request.
	if _react != React.NONE and _react != React.LOOK_PLAYER:
		skip_look = true
	## Talk requests the head at priority 4 (`aNPC_look_target`): tracked past the
	## range/cone gates and the skip flag. `head.lock_flag` is never set by talking.
	_head_look.advance(
		delta,
		player as Node3D if player is Node3D else null,
		_motor.facing,
		sleepy,
		ai.is_talking() or _react == React.LOOK_PLAYER,
		skip_look
	)


func _ensure_bound() -> void:
	var table: ScheduleData = data.schedule_table() if data != null else null
	if schedule.table != table:
		schedule.bind(table)
	if data != null:
		_motor.configure(data.personality)
		state = Game.villagers.get_or_create(data.id)
	elif state == null:
		state = VillagerState.new()


func _set_is_home(value: bool) -> void:
	_ensure_bound()
	if state != null:
		state.is_home = value


## `EventManager` borrows this villager for a festival (or hands them back).
func set_event_away(away: bool) -> void:
	if event_away == away:
		return
	event_away = away
	set_physics_process(not away)
	if away:
		_apply_presence(false)
	else:
		_sync_from_clock()


func _apply_presence(present: bool) -> void:
	visible = present
	collision_layer = _layer_present if present else 0
	if _collision != null:
		_collision.disabled = not present
	if _volume != null:
		_volume.monitorable = present
	if _agent != null:
		_agent.avoidance_enabled = false
	if not present and data != null:
		VillagerWalk.release(data.id)


func _face_towards(world_pos: Vector3) -> void:
	var to: Vector3 = world_pos - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	_motor.facing = atan2(to.x, to.z)
	if _model != null:
		_model.rotation.y = _motor.facing


func _update_animation(delta: float, planar: Vector3) -> void:
	if _body_anim == null:
		return
	var moving: bool = planar.length() > IDLE_SPEED
	## `aNPC_check_manpu_demoCode`: a reaction's first clip plays once, then its second
	## (`eff_idx2`) loops — or the first holds its last frame — until the talk resets it.
	if not _manpu_clip.is_empty():
		if _body_anim.is_playing() and (_clip == _manpu_clip or _clip == _manpu_follow):
			return
		if _clip == _manpu_clip and _manpu_follow.is_empty():
			var follow: String = NpcManpu.follow_clip(_manpu_clip)
			if follow != _manpu_clip and not _resolve_clip(follow).is_empty():
				_play_clip(follow, true)
				_manpu_follow = _clip
		return
	var want: String = _clip_for(ai.kind(), moving)
	var clip := _resolve_clip(want)
	if clip.is_empty():
		return
	if clip == _clip and _body_anim.is_playing():
		if moving:
			_body_anim.speed_scale = clampf(
				planar.length() / maxf(_motor.speed_now(), 0.4), 0.75, 1.2
			)
		else:
			_body_anim.speed_scale = 1.0
		return
	_play_clip(want, true)


func _clip_for(_kind: StringName, moving: bool) -> String:
	var mood: int = int(state.mood) if state != null else 0
	if moving:
		if _motor.gait == VillagerWalk.ACT_RUN:
			return _mood_or(NpcManpu.mood_clip(NpcManpu.MOOD_RUN, mood), ANIM_RUN)
		return _mood_or(NpcManpu.mood_clip(NpcManpu.MOOD_WALK, mood), ANIM_WALK)
	match _kind:
		ActivityKind.SIT:
			return ANIM_SIT
		ActivityKind.FISH:
			return ANIM_FISH
		_:
			var table: Array[String] = NpcManpu.MOOD_TALK if ai.is_talking() else NpcManpu.MOOD_WAIT
			return _mood_or(NpcManpu.mood_clip(table, mood), ANIM_WAIT)


## A mood pose when this villager's clips have it, else the plain one.
func _mood_or(clip: String, plain: String) -> String:
	if clip == plain or _body_anim == null:
		return plain
	return clip if _body_anim.has_animation(clip) or not _resolve_clip(clip).is_empty() else plain


## `aNPC_act_leave_house_out_of_door`: play GO_OUT on the threshold and hold until it
## stops (`aNPC_act_anm_seq`), then the walk to the yard takes over.
func begin_go_out() -> void:
	var clip := _resolve_clip(ANIM_GO_OUT)
	if clip.is_empty() or _body_anim == null:
		return
	## No blend: the villager has only just appeared, so there's no pose to blend from.
	_play_clip(ANIM_GO_OUT, false, 0.0)
	_going_out = _body_anim.get_animation(clip).length if _body_anim.has_animation(clip) else 0.0


## Debug (`leave`): back indoors at once, then out of the door again.
func replay_leave_home() -> void:
	if indoor_resident:
		return
	_apply_presence(false)
	_going_out = 0.0
	ai.leave_home_now(brain.hints())
	_apply_presence(ai.is_present())


## Test-only: no in-game callers; kept for tests.
func is_going_out() -> bool:
	return _going_out > 0.0


func _tick_go_out(delta: float) -> void:
	_going_out = maxf(_going_out - delta, 0.0)
	velocity = Vector3.ZERO
	if _model != null:
		_model.rotation.y = _motor.facing


func play_wait_anim() -> void:
	_play_clip(ANIM_WAIT, true)


func animation_player() -> BodyAnimator:
	return _body_anim


func _play_clip(suffix: String, loop: bool, blend: float = 0.12) -> void:
	var clip := _resolve_clip(suffix)
	if clip.is_empty() or _body_anim == null:
		return
	_clip = clip
	_ensure_loop(clip, loop)
	_body_anim.speed_scale = 1.0
	_body_anim.play(clip, blend)
	if _feel != null:
		_feel.set_pose(suffix)


func _resolve_clip(suffix: String) -> String:
	var player: AnimationMixer = _body_anim
	if player == null:
		player = _anim
	if player == null or suffix.is_empty():
		return ""
	if player.has_animation(suffix):
		return suffix
	for anim_name: String in player.get_animation_list():
		if anim_name.ends_with(suffix) or suffix in anim_name:
			return anim_name
	if suffix == ANIM_SIT or suffix == ANIM_FISH or suffix == ANIM_RUN:
		return _resolve_clip(ANIM_WAIT) if suffix != ANIM_WAIT else ""
	return ""


func _ensure_loop(clip: String, loop: bool) -> void:
	if _body_anim == null or not _body_anim.has_animation(clip):
		return
	var animation: Animation = _body_anim.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE


func _current_block() -> Vector2i:
	var bg: Array = _bg()
	if bg.size() != 2:
		return _wander_block
	return VillagerWalk.block_from_cell((bg[1] as WorldGrid).world_to_cell(global_position))


func _is_sleepy() -> bool:
	return (state != null and int(state.mood) == int(VillagerState.Mood.SLEEPY)) or (
		ai.kind() == ActivityKind.SLEEP
	)


func _tick_fatigue(delta: float, planar: Vector3) -> void:
	## `aNPC_calc_fatigue` once per tick: walk +1, run +2, wait -2; clamp [0, 1600].
	var rate: float = FATIGUE_WAIT
	if planar.length() > IDLE_SPEED and _motor.wait_left <= 0.0:
		rate = FATIGUE_RUN if _motor.gait == VillagerWalk.ACT_RUN else FATIGUE_WALK
	_fatigue = clampf(_fatigue + rate * delta * DecompTime.TICK_HZ, 0.0, FATIGUE_MAX)
	if _fatigue >= FATIGUE_MAX:
		_resting = true
	elif _fatigue < FATIGUE_REST:
		_resting = false


func _tick_annoyance(delta: float) -> void:
	## `aNPC_check_uzai`: a net hit already flagged `_uzai_flag` this frame;
	## otherwise crowding builds `_uzai_step`, standing off builds it back down.
	## Crossing either threshold interrupts with a scold, tightens the next
	## tier (`_uzai_cross`), and resets both counters.
	if state == null or data == null or ai.is_talking() or state.last_spoke_day == "":
		return
	if not _uzai_flag:
		## `ANNOY_STEP_LIMIT` is already frames→seconds; gain/decay are per-second — no `* 60.0` here.
		var gain: float = ANNOY_STEP_GAIN if _player_crowding() else -ANNOY_STEP_DECAY
		_uzai_step += gain * delta
	var tier: int = 1 if _uzai_cross else 0
	if _uzai_step > ANNOY_STEP_LIMIT[tier] or _uzai_tool >= ANNOY_TOOL_LIMIT[tier]:
		_trigger_annoyance()
	else:
		_uzai_step = maxf(_uzai_step, 0.0)
		_uzai_flag = false
	if _uzai_mood_left > 0.0:
		_uzai_mood_left = maxf(0.0, _uzai_mood_left - delta)
		if _uzai_mood_left == 0.0 and state.mood == VillagerState.Mood.ANGRY:
			state.mood = VillagerState.Mood.NORMAL


func _player_crowding() -> bool:
	## `aNPC_check_uzai_cross`: player within one field unit horizontally and
	## vertically, and roughly facing this villager rather than just standing near.
	if get_tree() == null:
		return false
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return false
	var to: Vector3 = global_position - player.global_position
	if Vector2(to.x, to.z).length() >= ANNOY_CROWD_DIST or absf(to.y) >= ANNOY_CROWD_DIST:
		return false
	var want_yaw: float = atan2(to.x, to.z)
	var player_yaw: float = (
		float(player.call("facing_yaw")) if player.has_method("facing_yaw") else player.rotation.y
	)
	return absf(angle_difference(player_yaw, want_yaw)) < ANNOY_FACE_CONE


## `Player_actor_CheckAndSet_UZAI_forNpc`, called from `ToolUse._apply_net` when a
## net swing's capsule lands on this villager instead of a bug. `aNPC_check_uzai` returns
## TRUE for every hit, so every villager jumps (`aNPC_ACT_REACT_TOOL`); only one who knows
## the player also counts it toward a scold.
func register_net_hit() -> void:
	_begin_react_tool()
	if state == null or state.last_spoke_day == "":
		return
	_uzai_tool += 1
	_uzai_flag = true


## `aNPC_act_react_tool_init_proc`: annoyed feel → the short jump; player in view → jump,
## then stare; else just the jump. Head chases 3× faster for the whole act.
func _begin_react_tool() -> void:
	if Game != null and Game.title_demo_active:
		return
	if ai.is_talking() or indoor_resident:
		return
	var step: React = React.SURPRISE
	if _uzai_mood_left > 0.0:
		step = React.SURPRISE_UZAI
	else:
		var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D if get_tree() else null
		if player != null and _head_look.can_look(player, _motor.facing):
			step = React.SURPRISE2
	_head_look.fast = true
	_set_react(step)


func _set_react(step: React) -> void:
	_react = step
	_react_timer = REACT_LOOK_SECONDS
	_play_clip(REACT_CLIPS[int(step)], step == React.LOOK_PLAYER)


func _end_react() -> void:
	## `aNPC_setup_react_tool_end`: head rates back to 0x200 / 0x400.
	_react = React.NONE
	_head_look.fast = false


## The act runs in place (`mv_angl` pinned to the facing); the scold can still fire under it.
func _tick_react(delta: float) -> void:
	var on_bg: bool = _snap_to_bg()
	if on_bg:
		velocity.y = 0.0
	elif not is_on_floor():
		velocity.y -= _gravity * delta
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
	var clip_done: bool = (
		_body_anim == null
		or not _body_anim.is_playing()
		or _body_anim.current_animation != _clip
	)
	match _react:
		React.SURPRISE, React.SURPRISE_UZAI:
			if clip_done:
				_end_react()
		React.SURPRISE2:
			if clip_done:
				_set_react(React.LOOK_PLAYER)
		React.LOOK_PLAYER:
			_react_timer -= delta
			if _react_timer < 0.0:
				_end_react()
	_tick_annoyance(delta)


func _trigger_annoyance() -> void:
	## `uzai.cross`: the first offense is a warning (`MILDLY_ANNOYED`); every one
	## after — thresholds already tightened — reads as the real thing.
	state.patience = (
		VillagerState.Patience.ANNOYED if _uzai_cross else VillagerState.Patience.MILDLY_ANNOYED
	)
	_uzai_tool = 0
	_uzai_cross = true
	_uzai_step = 0.0
	_uzai_flag = false
	_uzai_mood_left = ANNOY_MOOD_SECONDS
	_play_annoyance_scold()


func _play_annoyance_scold() -> void:
	## `aNPC_force_call_req_proc` + `force_call_camera_type = CAMERA2_PROCESS_TALK`:
	## a forced conversation, not a player-initiated one — same `begin_talk`/
	## `TalkCamera` wiring as `_play_first_job_line`.
	if get_tree() == null:
		return
	var talk_data: DialogueData = DialogueCatalog.conversation(&"npc_annoyed_scold")
	if talk_data == null or data == null:
		return
	var talk_ctx: DialogueContext = DialogueContext.from_game(data, state)
	var ui := DialogueOverlay.find(get_tree())
	if ui == null:
		return
	if ui.is_open():
		ui.close()
	ai.begin_talk()
	conversation.bind_talk_end(ui)
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		TalkCamera.begin(player, self, get_tree())
	conversation.sing_town_tune(talk_ctx)
	ui.play(talk_data, talk_ctx, state)


## `mQst_NextSoccer`: the ball the resident asked for reached them — they call the player
## over (`force_call_req_proc`, 0x0D8B + looks). True when the ball should stop dead.
func take_soccer_ball() -> bool:
	if Game == null or Game.quests == null or Game.residents == null or data == null or get_tree() == null:
		return false
	var slot: int = Game.residents.slot_of(data.id)
	if not Game.quests.soccer_target(slot):
		return false
	var ui := DialogueOverlay.find(get_tree())
	var looks: int = int(data.personality.looks) if data.personality != null else 0
	var talk_data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % (SOCCER_CALL_MSG + looks)))
	if ui == null or talk_data == null or ui.is_open():
		return false
	Game.quests.next_soccer(slot, Game.resident.player_name)
	var talk_ctx: DialogueContext = DialogueContext.from_game(data, state)
	ai.begin_talk()
	conversation.bind_talk_end(ui)
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		TalkCamera.begin(player, self, get_tree())
	ui.play(talk_data, talk_ctx, state)
	return true


## `aNPC_chk_friendship`: on a fortune day the villager keeps away from the player or comes
## looking for them (`VillagerFortune`). True while it owns the steering.
func _tick_fortune() -> bool:
	if Game == null or Game.title_demo_active or data == null or get_tree() == null:
		return false
	var destiny: int = Game.destiny()
	if destiny != Game.Destiny.POPULAR and destiny != Game.Destiny.UNPOPULAR:
		return false
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return false
	var delta: float = get_physics_process_delta_time()
	_fortune_cool = maxf(_fortune_cool - delta, 0.0)
	var to: Vector3 = player.global_position - global_position
	var distance: float = Vector2(to.x, to.z).length()
	var bg: Array = _bg()
	var same_block: bool = bg.size() == 2 and VillagerWalk.block_from_cell(
		(bg[1] as WorldGrid).world_to_cell(player.global_position)
	) == _current_block()
	var looks: int = int(data.personality.looks) if data.personality != null else 0
	var step: int = VillagerFortune.step(destiny, looks, Game.resident.player_gender, same_block, distance)
	match step:
		VillagerFortune.Step.NONE:
			return false
		VillagerFortune.Step.AVOID_RUN, VillagerFortune.Step.AVOID_WALK:
			var gait: StringName = VillagerWalk.ACT_RUN if step == VillagerFortune.Step.AVOID_RUN else VillagerWalk.ACT_WALK
			_motor.set_target(VillagerFortune.away_from(global_position, player.global_position), gait, 0.2, global_position, _motor.facing)
		VillagerFortune.Step.SEEK_RUN, VillagerFortune.Step.SEEK_WALK:
			var gait2: StringName = VillagerWalk.ACT_RUN if step == VillagerFortune.Step.SEEK_RUN else VillagerWalk.ACT_WALK
			_motor.set_target(player.global_position, gait2, VillagerFortune.SEEK_WALK, global_position, _motor.facing)
		VillagerFortune.Step.SEEK_WAIT:
			if _motor.has_target:
				_motor.arrive()
			_motor.turn_toward(delta, global_position, player.global_position)
	if step >= VillagerFortune.Step.SEEK_RUN and _fortune_cool <= 0.0 \
			and VillagerFortune.can_call(distance, to.y):
		_fortune_call(player, looks)
	return true


## `aNPC_force_talk_request` → `aNPC_set_talk_info_talk_request_check`: "It's really you!"
func _fortune_call(player: Node3D, looks: int) -> void:
	var ui := DialogueOverlay.find(get_tree())
	if ui == null or ui.is_open() or (player is Player and (player as Player).is_busy()):
		return
	var talk_data: DialogueData = DialogueCatalog.conversation(
		StringName("msg_%d" % VillagerFortune.call_msg(looks, _outdoor_rng))
	)
	if talk_data == null:
		return
	_fortune_calling = true
	_fortune_cool = VillagerFortune.CALL_COOLDOWN_SEC
	var talk_ctx: DialogueContext = DialogueContext.from_game(data, state)
	ai.begin_talk()
	conversation.bind_talk_end(ui)
	TalkCamera.begin(player, self, get_tree())
	ui.play(talk_data, talk_ctx, state)


## ---------------------------------------------------------------- outdoor acts

## `aNPC_think_chk_interrupt_proc`: umbrella (`aNPC_ctrl_umbrella` + `aNPC_chk_right_hand`),
## then a clap while the player shows a catch.
func _start_outdoor_act() -> bool:
	if Game == null or Game.title_demo_active:
		return false
	## `aNPC_COND_DEMO_SKIP_ITEM`: nothing comes out while walking out of the door.
	if ActivityKind.is_door_demo(ai.kind()):
		return false
	## `aNPC_chk_talk_start`: a partner found this frame comes first.
	if _pal != null:
		return greeter.begin_greeting()
	var raining: bool = Game.town.weather == &"rain"
	if raining and _umbrella == null:
		var now: float = Time.get_ticks_msec() / 1000.0
		if VillagerOutdoor.claim_umbrella(self, now, _outdoor_rng):
			if _take_out_umbrella(false):
				return true
			VillagerOutdoor.release_umbrella(self, now, _outdoor_rng)
	elif not raining and _umbrella != null and current_activity() != VillagerActivity.SLEEP:
		_put_away_umbrella()
		return true
	var player := get_tree().get_first_node_in_group("player") as Node3D if get_tree() != null else null
	if player != null and _motor.gait != VillagerWalk.ACT_RUN:
		var catching: bool = bool(player.get("catch_showing"))
		if VillagerOutdoor.wants_clap(global_position, _motor.facing, player.global_position, catching, _mood_normal()):
			_act = Act.CLAP
			_motor.arrive()
			_play_clip(ANIM_CLAP, true)
			return true
	return false


## `aNPC_chk_pitfall`: a normal villager on a unit holding a buried pitfall falls in.
func _check_pitfall() -> void:
	if _pit != Pit.NONE or guest != &"" or indoor_resident:
		return
	var bg: Array = _bg()
	if bg.size() != 2:
		return
	var grid := bg[1] as WorldGrid
	var cell: Vector2i = grid.world_to_cell(global_position)
	if not grid.is_in_bounds(cell) or not BuriedUse.is_pitfall(grid.occupant_at(cell)):
		return
	var world := World.find(get_tree())
	if BuriedUse.spring_pitfall(world, grid, cell) == null and not Game.town.is_hole(HoleUse.persist_id(cell)):
		return
	_pit = Pit.TOTTER
	_pit_cell = cell
	_pit_center = grid.cell_corner(cell) + Vector3(grid.cell_size, 0.0, grid.cell_size) * 0.5
	_pit_center.y = global_position.y
	_pit_model_rest = _model.position if _model != null else Vector3.ZERO
	## `aNPC_think_pitfall_init_proc`: immovable, feel `PITFALL` until they are out.
	if state != null:
		state.mood = VillagerState.Mood.PITFALL
		state.feel_time = 0.0
	_motor.arrive()
	velocity = Vector3.ZERO
	_pit_clip = _pit_one_shot(ANIM_GURATUKU)


func in_pitfall() -> bool:
	return _pit != Pit.NONE


func _tick_pit(delta: float) -> void:
	velocity = Vector3.ZERO
	match _pit:
		Pit.TOTTER:
			var step: float = PIT_TOTTER_SPEED * delta
			var to := Vector3(_pit_center.x - global_position.x, 0.0, _pit_center.z - global_position.z)
			if to.length() > step:
				global_position += to.normalized() * step
			else:
				global_position.x = _pit_center.x
				global_position.z = _pit_center.z
				if not _pit_playing():
					_pit = Pit.FALL
					_pit_clip = _pit_chain(ANIM_OTIRU)
		Pit.FALL:
			if not _pit_playing():
				_pit = Pit.STRUGGLE
				_pit_clip = _pit_chain(ANIM_MOGAKU, true)
		Pit.REVIVE:
			if not _pit_playing():
				_end_pit()
	ai.step(delta)


func _begin_revive() -> void:
	_pit = Pit.REVIVE
	BuriedUse.close_pit(World.find(get_tree()), _pit_cell)
	_pit_clip = _pit_chain(ANIM_DERU)


func _end_pit() -> void:
	_pit = Pit.NONE
	_pit_cell = Vector2i(-1, -1)
	if _model != null:
		_model.position = _pit_model_rest
	if state != null and state.mood == VillagerState.Mood.PITFALL:
		state.set_feel(0, 0)
	_clip = ""
	_play_clip(ANIM_WAIT, true)
	if _body_anim != null:
		_body_anim.play(_resolve_clip(ANIM_WAIT), 0.0)


func _pit_playing() -> bool:
	return _body_anim != null and _body_anim.is_playing() and _body_anim.current_animation == _pit_clip


func _pit_one_shot(leaf: String, loop: bool = false, blend: float = 0.12) -> String:
	var clip := _resolve_clip(leaf)
	if clip.is_empty() or _body_anim == null:
		return ""
	_clip = clip
	_ensure_loop(clip, loop)
	_body_anim.speed_scale = 1.0
	_body_anim.play(clip, blend)
	return clip


## Like the player's pit: each clip's root travel (`AnimationMove`) is carried on the model so
## the next clip starts where the last one left the body.
func _pit_chain(leaf: String, loop: bool = false) -> String:
	var before: Vector3 = _pit_root()
	var clip: String = _pit_one_shot(leaf, loop, 0.0)
	if clip.is_empty() or _model == null:
		return clip
	_body_anim.seek(0.0, true)
	var after: Vector3 = _pit_root()
	if before != Vector3.INF and after != Vector3.INF:
		_model.position += before - after
	return clip


func _pit_root() -> Vector3:
	if _model == null:
		return Vector3.INF
	var skeletons: Array[Node] = _model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return Vector3.INF
	var skeleton := skeletons[0] as Skeleton3D
	var bone: int = skeleton.find_bone("joint_0")
	if bone < 0:
		return Vector3.INF
	return to_local(skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin)


func _mood_normal() -> bool:
	return state == null or state.mood == VillagerState.Mood.NORMAL


## `aNPC_takeout_right_item` → `aNPC_ACT_UMB_OPEN`. `instant` is `aTOL_ACTION_S_TAKEOUT`:
## already open, no clip.
func _take_out_umbrella(instant: bool) -> bool:
	var visual_id: StringName = VillagerOutdoor.umbrella_visual(data, state)
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_visual)
	if visual_id == &"" or skeleton == null:
		return false
	var attach: Node3D = HeldTool.bind(skeleton, visual_id)
	if attach == null or attach.get_child_count() == 0:
		return false
	_umbrella = HeldUmbrella.new()
	_umbrella.setup(
		attach.get_child(0) as Node3D,
		HeldUmbrella.Action.OPEN_NOW if instant else HeldUmbrella.Action.TAKEOUT_BEFORE
	)
	HeldUmbrella.paint_canopy(attach.get_child(0) as Node3D, VillagerOutdoor.umbrella_design_texture(state))
	_umb_carry = ToolCarry.build_part(_body_anim, skeleton, ANIM_UMBRELLA, VillagerOutdoor.SUB_ANIM_JOINTS)
	if instant:
		return true
	_act = Act.UMB_OPEN
	_motor.arrive()
	_play_clip(ANIM_UMB_OPEN, false)
	return true


## `aNPC_putaway_right_item` → `aNPC_ACT_UMB_CLOSE`.
func _put_away_umbrella() -> void:
	if _umbrella == null:
		return
	_umbrella.set_action(HeldUmbrella.Action.PUTAWAY)
	_act = Act.UMB_CLOSE
	_motor.arrive()
	_play_clip(ANIM_UMB_CLOSE, false)


func _drop_umbrella() -> void:
	HeldTool.unbind(HeldTool.find_skeleton(_visual))
	_umbrella = null
	_umb_carry = null


## The act runs in place like the react (`mv_angl` pinned).
func _tick_act(delta: float) -> void:
	var on_bg: bool = _snap_to_bg()
	if on_bg:
		velocity.y = 0.0
	elif not is_on_floor():
		velocity.y -= _gravity * delta
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
	var clip_done: bool = (
		_body_anim == null or not _body_anim.is_playing() or _body_anim.current_animation != _clip
	)
	match _act:
		Act.UMB_OPEN:
			if clip_done:
				VillagerOutdoor.release_umbrella(self, Time.get_ticks_msec() / 1000.0, _outdoor_rng)
				_act = Act.NONE
		Act.UMB_CLOSE:
			if clip_done and (_umbrella == null or _umbrella.is_closed()):
				_drop_umbrella()
				_act = Act.NONE
		Act.GREET:
			greeter.tick_greeting(delta)
			return
		Act.CLAP:
			## `aNPC_act_clap_main_proc`: until the player puts the catch away.
			var player := get_tree().get_first_node_in_group("player") as Node3D
			if player != null:
				_motor.turn_toward(delta, global_position, player.global_position)
				if _model != null:
					_model.rotation.y = _motor.facing
			if player == null or not bool(player.get("catch_showing")):
				_act = Act.NONE
	if _act == Act.NONE:
		_play_clip(ANIM_WAIT, true)
	_tick_annoyance(delta)


## ---------------------------------------------------------------- greetings


func _cloth_key() -> String:
	if state == null:
		return ""
	return "%d:%s" % [state.cloth_design, String(VillagerTalkManager.worn_cloth(data, state))]


## `aNPC_anime_proc` part table: the sub-animation drives the right arm and head root over
## every main clip except the umbrella's own.
func _apply_sub_anim() -> void:
	if _umb_carry == null or _act == Act.UMB_OPEN or _act == Act.UMB_CLOSE:
		return
	var skeleton: Skeleton3D = HeldTool.find_skeleton(_visual)
	if skeleton != null:
		_umb_carry.apply(skeleton)


## `aNPC_check_insect_and_gyoei` (while walking) and `aNPC_act_chase_insect` (up to a
## minute): walk / run over, then watch. True while it owns the steering.
func _tick_chase() -> bool:
	if _chase == null:
		var walking: bool = _motor.has_target and _motor.gait != VillagerWalk.ACT_WAIT
		if not walking or not _mood_normal() or _resting:
			return false
		## `aNPC_check_ball` comes first: the ball ahead is run after.
		var ball: FieldBall = FieldBall.find(get_tree())
		if ball != null and ball.chaseable() and FieldBall.chase_from(global_position, ball.global_position):
			_chase = ball
			_chase_fish = false
			_chase_left = VillagerOutdoor.CHASE_SECONDS
		else:
			var found: Dictionary = VillagerOutdoor.chase_target(global_position, brain.fish_pairs(), brain.bug_pairs())
			if found.is_empty():
				return false
			_chase = found["target"]
			_chase_fish = bool(found["fish"])
			_chase_left = VillagerOutdoor.CHASE_SECONDS
	if _chase is FieldBall:
		return _tick_ball_chase(_chase as FieldBall)
	var target_pos: Vector3 = _chase_position()
	var delta: float = get_physics_process_delta_time()
	_chase_left -= delta
	if target_pos == Vector3.INF or _chase_left <= 0.0 or not _mood_normal():
		_chase = null
		_motor.arrive()
		return false
	match VillagerOutdoor.chase_step(global_position, _motor.facing, target_pos, _chase_fish):
		VillagerOutdoor.ChaseStep.WAIT:
			if _motor.has_target:
				_motor.arrive()
		VillagerOutdoor.ChaseStep.TURN:
			if _motor.has_target:
				_motor.arrive()
			_motor.turn_toward(delta, global_position, target_pos)
		VillagerOutdoor.ChaseStep.WALK:
			_motor.set_target(target_pos, VillagerWalk.ACT_WALK, VillagerOutdoor.INSECT_NEAR * 0.5, global_position, _motor.facing)
		VillagerOutdoor.ChaseStep.RUN:
			_motor.set_target(target_pos, VillagerWalk.ACT_RUN, VillagerOutdoor.INSECT_NEAR * 0.5, global_position, _motor.facing)
	return true


## `aNPC_ACT_RUN` / `aNPC_ACT_TYPE_SEARCH` at the ball: run into it (the kick is the ball's).
func _tick_ball_chase(ball: FieldBall) -> bool:
	_chase_left -= get_physics_process_delta_time()
	if not is_instance_valid(ball) or not ball.chaseable() or _chase_left <= 0.0 or not _mood_normal():
		_chase = null
		_motor.arrive()
		return false
	var to := Vector2(ball.global_position.x - global_position.x, ball.global_position.z - global_position.z)
	if to.length() >= FieldBall.CHASE * 1.5:
		_chase = null
		_motor.arrive()
		return false
	if to.length() < FieldCollision.ACTOR_RADIUS:
		_chase = null
		_motor.arrive()
		return false
	_motor.set_target(ball.global_position, VillagerWalk.ACT_RUN, 0.05, global_position, _motor.facing)
	return true


func _chase_position() -> Vector3:
	if _chase == null or not is_instance_valid(_chase):
		return Vector3.INF
	if _chase_fish:
		var shadow := _chase as FishShadow
		return shadow.position if shadow != null and not shadow.finished else Vector3.INF
	var bug := _chase as BugActor
	for pair: Array in brain.bug_pairs():
		if pair[0] == bug:
			return pair[1]
	return Vector3.INF


func _looks() -> VillagerPersonality.Looks:
	if data != null and data.personality != null:
		return data.personality.looks
	return VillagerPersonality.Looks.LAZY


func _bg() -> Array:
	if get_tree() == null:
		return []
	var world := World.find(get_tree())
	if world == null:
		return []
	var world_data: Variant = world.layout
	var grid: Variant = world.grid
	if not (world_data is WorldData) or not (grid is WorldGrid):
		return []
	return [world_data, grid]


func _snap_to_bg() -> bool:
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
