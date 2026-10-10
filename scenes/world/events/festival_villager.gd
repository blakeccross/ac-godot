extends EventNpc

## A resident out at a festival (`ac_hanabi_npc0`, `ac_hanami_npc0`, `ac_tukimi_npc1`, …). The
## villager's own model, face and voice; `FestivalCrowd` says what the slot does and says.

var villager: VillagerData
var family: StringName = &""
## Slot inside the event (`npc_id - SP_NPC_EV_X_0`).
var slot: int = 0
var _data: Dictionary = {}
var _home: Vector3
var _pause: float = 0.0
var _seq: int = 0
var _term: int = -1
var _rope: Node3D
var _rope_home: Vector3
## Ball toss (`BallToss`): what this thrower is doing, the balls in hand, its basket.
var _toss_step: int = BallToss.Step.LOOK
var _toss_left: int = 0
var _toss_clock: float = 0.0
var _toss_released: bool = false
var _basket: Vector3 = Vector3.INF
var _cheer_spot: int = 0
## Foot race (`FootRace`): the phase last seen, the angle round the shrine, a trip in progress.
var _race_phase: int = -1
var _race_angle: float = 0.0
var _race_trip: int = 0
var _race_center: Vector3 = Vector3.INF
var _race_to_finish: bool = false
## `aNPC` run (≈6 GX a frame) is the field's 4.5 m/s.
const RACE_MPS_PER_GX := 0.75
## New Year's queue (`ShrineQueue`): where this villager is on its column's round.
enum Shrine { WALK, FRONT, SAISEN, OMAIRI, AFTER, BOW, BACK }
var _well: Node3D
var _sq_leg: int = 0
var _sq_state: int = Shrine.WALK
var _sq_timer: float = 0.0
var _sq_coin: bool = false
## This villager let the player in (`aHN0_talk_saisen_suru` Yes) and walks them up.
var _sq_let_in: bool = false
var _sq_thanked: bool = false
## The player passes through the line while they're in it (the walk-up threads between the
## columns).
var _sq_excepted: bool = false
var _sq_offer: BankTalk.Fixed = null
## `SAISEN1`: the coin leaves the paw at frame 33.
const SAISEN_COIN_SEC := 33.0 / 30.0


## Before `_ready`: copy the villager's looks onto the event actor.
func assign(p_villager: VillagerData, p_family: StringName, p_slot: int, p_cloth: int = -1) -> void:
	villager = p_villager
	family = p_family
	slot = p_slot
	_data = FestivalCrowd.FAMILIES.get(family, {})
	species = villager.species if villager != null else &""
	texture_set = villager.texture_set if villager != null else &""
	display_name = villager.display_name if villager != null else ""
	cloth_index = p_cloth
	var looks: int = _looks()
	sound_spec = DialogueVoice.sound_spec_for_looks(looks as VillagerPersonality.Looks)
	## Seated guests only turn their heads (`aNPC_TALK_TURN_HEAD`).
	var first: String = _clips()[0] if not _clips().is_empty() else ""
	talk_turn = not first.contains("sitdown") and not first.contains("taisou")


func _looks() -> int:
	if villager != null and villager.personality != null:
		return int(villager.personality.looks)
	return 0


func _clips() -> Array:
	return _data.get("clips", [])


func idle_clip() -> String:
	var clips: Array = _clips()
	return str(clips[0]) if not clips.is_empty() else "npc_1_wait1"


func setup() -> void:
	if family == &"tunahiki":
		_setup_tug()
	elif family == &"tamaire":
		_setup_toss()
	elif family == &"tokyoso":
		if slot == 0:
			FootRace.reset()
		_race_center = _block_unit_pos(FootRace.CENTER_UNIT)
	elif family == &"hatumode":
		_setup_shrine()
	_home = global_position
	_pause = rng().randf_range(0.5, 3.0)


## `aTNN0_birth` / `aTNN1_think_init_proc`: the referee steps aside and lays the rope; the
## pullers take their places along it, facing in.
func _setup_tug() -> void:
	var gx := FieldCatalog.GX_TO_METERS
	if slot == 0:
		TugOfWar.reset()
		_rope = Node3D.new()
		_rope.name = "TugRope"
		get_parent().add_child(_rope)
		_rope_home = global_position + Vector3(TugOfWar.ROPE_OFS_GX.x, 0.0, TugOfWar.ROPE_OFS_GX.y) * gx
		_rope.global_position = _rope_home
		GeneratedVisual.attach(_rope, &"tol_rope_1")
		global_position += Vector3(TugOfWar.REFEREE_OFS_GX.x, 0.0, TugOfWar.REFEREE_OFS_GX.y) * gx
		play_clip(TugOfWar.CLIP_REFEREE, true)
		return
	var ofs: Vector2 = TugOfWar.puller_offset(slot)
	global_position += Vector3(ofs.x, 0.0, ofs.y) * gx
	home_yaw = deg_to_rad(90.0 * float(TugOfWar.dir_of(slot)))
	rotation.y = home_yaw


func _exit_tree() -> void:
	if _well != null:
		ShrineQueue.members -= 1
		if ShrineQueue.members <= 0:
			ShrineQueue.reset()
	if _rope != null and is_instance_valid(_rope):
		_rope.queue_free()
	## The cheerleader clears the balls away when the ball toss ends.
	if family == &"tamaire" and slot == 0 and get_tree() != null:
		for ball: Node in get_tree().get_nodes_in_group(&"toss_ball"):
			ball.queue_free()


func _block_unit_pos(unit: Vector2i) -> Vector3:
	var mgr: EventManager = EventManager.find(get_tree())
	if mgr == null or mgr.world == null:
		return Vector3.INF
	var block: Vector2i = TownSpace.block_of_cell(mgr.world.grid.world_to_cell(global_position))
	return mgr.cell_position(EventManager.block_unit_to_cell(block, unit))


## One frame of the foot race (`aTKN0_*` for the starter, `aTKN1_*` for the runners).
func _race(delta: float) -> void:
	FootRace.advance(delta)
	var phase: int = FootRace.phase
	var entered: bool = phase != _race_phase
	_race_phase = phase
	if slot == 0:
		_race_starter(phase, entered, delta)
		return
	if not FootRace.racing(slot):
		if entered and phase == FootRace.Phase.RACE:
			play_clip(FootRace.CLIP_CLAP, true)
		elif entered and phase == FootRace.Phase.WARMUP:
			if global_position.distance_to(_home) > 0.5:
				move_to(_home, WALK_SPEED)
			else:
				play_clip("npc_1_wait1", true)
		return
	var lane: int = FootRace.lane_of(slot)
	match phase:
		FootRace.Phase.WARMUP:
			if entered:
				if global_position.distance_to(_home) > 0.5:
					move_to(_home, WALK_SPEED)
				else:
					play_clip(FootRace.CLIP_WARMUP, true)
			elif not is_moving() and clip_done():
				play_clip(FootRace.CLIP_WARMUP, true)
		FootRace.Phase.READY:
			if entered:
				move_to(_race_point(FootRace.finish_offset(lane)), 3.0, FootRace.CLIP_RUN)
			elif not is_moving() and clip_done():
				turn_to(PI * 0.5, delta)
				play_clip(FootRace.CLIP_READY, true)
		FootRace.Phase.RACE:
			if entered:
				var to: Vector3 = global_position - _race_center
				_race_angle = atan2(-to.z, to.x)
				_race_to_finish = false
				_race_trip = 0
			if FootRace.finish[lane] != 0 or is_moving():
				return
			if _race_trip == 1:
				if clip_done():
					_race_trip = 2
					play_clip(FootRace.CLIP_GETUP, false)
				return
			if _race_trip == 2:
				if not clip_done():
					return
				_race_trip = 0
			if _race_to_finish:
				FootRace.cross(lane)
				play_clip("npc_1_wait1", true)
				return
			if FootRace.done_laps(lane):
				_race_to_finish = true
				move_to(_race_point(FootRace.finish_offset(lane)), 3.0, FootRace.CLIP_RUN)
				return
			if rng().randf() < FootRace.TRIP_CHANCE:
				_race_trip = 1
				play_clip(FootRace.CLIP_TRIP, false)
				return
			var leg: Array = FootRace.next_leg(lane, _race_angle, rng())
			_race_angle = float(leg[1])
			move_to(_race_point(leg[0] as Vector2), float(leg[2]) * RACE_MPS_PER_GX, FootRace.CLIP_RUN)
		FootRace.Phase.GOAL:
			if entered or (not is_moving() and clip_done()):
				play_clip(FootRace.CLIP_WIN if FootRace.finish[lane] == 1 else FootRace.CLIP_LOSE, true)


## Between legs a runner keeps running; the next leg starts this frame.
func arrived() -> void:
	if _well != null:
		_arrive_leg()
		return
	if family == &"tokyoso" and FootRace.phase == FootRace.Phase.RACE and FootRace.racing(slot) and not _race_to_finish:
		return
	super.arrived()


func _race_point(offset_gx: Vector2) -> Vector3:
	return _race_center + Vector3(offset_gx.x, 0.0, offset_gx.y) * FieldCatalog.GX_TO_METERS


## `aTKN0`: load and raise the pistol while they take the line, fire, then watch the leader.
func _race_starter(phase: int, entered: bool, delta: float) -> void:
	match phase:
		FootRace.Phase.READY:
			if entered:
				play_clip(FootRace.CLIP_LOAD, false)
			elif clip_done():
				play_clip(FootRace.CLIP_SET, true)
		FootRace.Phase.RACE:
			if entered:
				play_clip(FootRace.CLIP_FIRE, false)
				Audio.play_se(&"53", self)
			elif clip_done():
				play_clip("npc_1_wait1", true)
		_:
			if entered:
				play_clip("npc_1_wait1", true)


func _basket_at(team: int) -> Vector3:
	var mgr: EventManager = EventManager.find(get_tree())
	if mgr == null or mgr.world == null:
		return Vector3.INF
	var block: Vector2i = TownSpace.block_of_cell(mgr.world.grid.world_to_cell(global_position))
	return mgr.cell_position(EventManager.block_unit_to_cell(block, BallToss.BASKET_UNITS[team]))


func _setup_toss() -> void:
	_basket = _basket_at(BallToss.team_of(slot)) if slot > 0 else Vector3.INF
	_toss_step = BallToss.Step.LOOK
	_toss_clock = rng().randf_range(0.5, 3.0)
	play_clip(BallToss.CLIP_LOOK if slot > 0 else BallToss.CLIP_CLAP, true)


## One frame of the ball toss (`aTMN1_*` for throwers, `aTMN0_*` for the cheerleader).
func _toss(delta: float) -> void:
	if slot == 0:
		_cheer(delta)
		return
	if _basket == Vector3.INF:
		return
	match _toss_step:
		BallToss.Step.RUN:
			if not is_moving():
				_toss_step = BallToss.Step.PICK
				play_clip(BallToss.CLIP_PICK, false)
		BallToss.Step.PICK:
			if clip_done():
				_toss_left = BallToss.BALLS
				_toss_step = BallToss.Step.TURN
		BallToss.Step.TURN:
			var to: Vector3 = _basket - global_position
			if turn_to(atan2(to.x, to.z), delta):
				_throw()
		BallToss.Step.THROW:
			_toss_clock += delta
			if not _toss_released and _toss_clock >= BallToss.RELEASE_FRAME / DecompTime.FRAME_HZ:
				_toss_released = true
				_release_ball()
			if clip_done():
				_toss_left -= 1
				if _toss_left > 0:
					_throw()
				else:
					_toss_step = BallToss.Step.WATCH
					_toss_clock = BallToss.WATCH_FRAMES / DecompTime.FRAME_HZ
					play_clip("npc_1_wait1", true)
		BallToss.Step.WATCH:
			_toss_clock -= delta
			if _toss_clock <= 0.0:
				_toss_step = BallToss.Step.LOOK
				_toss_clock = BallToss.LOOK_FRAMES / DecompTime.FRAME_HZ
				play_clip(BallToss.CLIP_LOOK, true)
		BallToss.Step.LOOK:
			_toss_clock -= delta
			if _toss_clock <= 0.0:
				var spot: Vector2 = BallToss.next_spot(
					Vector2(_basket.x, _basket.z) / FieldCatalog.GX_TO_METERS,
					Vector2(global_position.x, global_position.z) / FieldCatalog.GX_TO_METERS, rng())
				_toss_step = BallToss.Step.RUN
				move_to(Vector3(spot.x, 0.0, spot.y) * FieldCatalog.GX_TO_METERS + Vector3(0.0, global_position.y, 0.0), 3.0, BallToss.CLIP_RUN)


func _throw() -> void:
	_toss_step = BallToss.Step.THROW
	_toss_clock = 0.0
	_toss_released = false
	play_clip(BallToss.CLIP_THROW, false)


## Frame 15 of `TAMANAGE1`: a ball leaves the hand (`eEC_EFFECT_TAMAIRE`).
func _release_ball() -> void:
	var ball := TossBall.new()
	ball.team = BallToss.team_of(slot)
	ball.basket = _basket
	ball.add_to_group(&"toss_ball")
	get_parent().add_child(ball)
	var to: Vector3 = _basket - global_position
	ball.global_position = global_position + Vector3(0.0, 40.0 * FieldCatalog.GX_TO_METERS, 0.0)
	ball.launch(atan2(to.x, to.z), BallToss.launch_rise(rng()), BallToss.launch_speed(rng()))


## `aTMN0`: the cheerleader walks between the teams and claps at each stop.
func _cheer(delta: float) -> void:
	_toss_clock -= delta
	if is_moving() or _toss_clock > 0.0:
		return
	if _toss_step == BallToss.Step.RUN:
		_toss_step = BallToss.Step.LOOK
		_toss_clock = rng().randf_range(2.0, 4.0)
		play_clip(BallToss.CLIP_CLAP, true)
		return
	var red: Vector3 = _basket_at(0)
	var white: Vector3 = _basket_at(1)
	if red == Vector3.INF:
		return
	var mid: Vector3 = (red + white) * 0.5
	var spots: Array[Vector3] = [mid + Vector3(0.0, 0.0, 3.0), white + Vector3(-1.5, 0.0, 1.5), mid + Vector3(0.0, 0.0, 3.0), red + Vector3(1.5, 0.0, 1.5)]
	_cheer_spot = (_cheer_spot + 1) % spots.size()
	_toss_step = BallToss.Step.RUN
	move_to(spots[_cheer_spot], WALK_SPEED)


## One frame of the tug: the shared rope moves, the pullers move with it and pick their next
## heave when a clip ends; the referee keeps the rope where it is pulled to.
func _tug(delta: float) -> void:
	TugOfWar.advance(delta, rng())
	var gx := FieldCatalog.GX_TO_METERS
	if slot == 0:
		if _rope != null:
			_rope.global_position = _rope_home + Vector3(TugOfWar.rope * gx, 0.0, 0.0)
		return
	global_position.x = _home.x + TugOfWar.rope_base * gx
	if clip_done():
		play_clip(TugOfWar.clip_for(TugOfWar.dir_of(slot)), false)


func make_context() -> DialogueContext:
	var state: VillagerState = null
	if Game != null and villager != null and Game.villagers.has_id(villager.id):
		state = Game.villagers.get_or_create(villager.id)
	var ctx: DialogueContext = DialogueContext.from_game(villager, state)
	if ctx.rng == null:
		ctx.rng = RandomNumberGenerator.new()
		ctx.rng.randomize()
	return ctx


func make_talk() -> BankTalk:
	if _well != null:
		_sq_offer = null
		if _sq_state == Shrine.FRONT and ShrineQueue.can_offer(slot):
			_sq_offer = BankTalk.Fixed.new(ShrineQueue.offer_msg(_looks()))
			return _sq_offer
		return BankTalk.Fixed.new(ShrineQueue.talk_msg(_looks(), slot, rng()))
	var alt_event: StringName = _data.get("alt_event", &"")
	var alt: bool = alt_event != &"" and Game != null and Game.events != null and Game.events.is_active(alt_event)
	var term: int = FestivalCrowd.term_of(family, Clock.now_sec())
	var n: int = FestivalCrowd.talk_msg(family, _looks(), slot, rng(), alt, term)
	return BankTalk.Fixed.new(n) if n >= 0 else null


func talk_ended(script: BankTalk) -> void:
	super.talk_ended(script)
	if _well != null:
		if _sq_offer != null and script == _sq_offer and _sq_offer.chosen == 0:
			ShrineQueue.queue_player(slot)
			_sq_let_in = true
		_sq_offer = null
		if _sq_state == Shrine.SAISEN or _sq_state == Shrine.OMAIRI or _sq_state == Shrine.BOW:
			return
	play_clip(idle_clip(), true)


func can_talk() -> bool:
	if _well != null:
		return visible and (_sq_state == Shrine.FRONT or _sq_state == Shrine.BACK or _sq_state == Shrine.AFTER)
	return super.can_talk()


## --- New Year's queue (`ac_hatumode_npc0`) ---------------------------------------------


func _setup_shrine() -> void:
	_well = get_tree().get_first_node_in_group("wishing_well") as Node3D if get_tree() != null else null
	if _well == null:
		return
	if ShrineQueue.members <= 0:
		ShrineQueue.reset()
	ShrineQueue.members += 1
	_sq_leg = ShrineQueue.start_leg(slot)
	if _sq_leg == ShrineQueue.LEG_FRONT:
		ShrineQueue.take_front(slot)
	elif _sq_leg == ShrineQueue.LEG_OFFER:
		ShrineQueue.step_up(slot)
		ShrineQueue.turn = ShrineQueue.column_of(slot)
	global_position = _sq_world(_sq_leg)
	_arrive_leg()


func _sq_world(leg: int) -> Vector3:
	var at: Vector3 = ShrineQueue.to_world(_well, ShrineQueue.point_of(ShrineQueue.column_of(slot), leg))
	var world: World = World.find(get_tree()) if get_tree() != null else null
	at.y = _well.global_position.y
	if world != null and world.layout != null:
		var cell: Vector2i = world.grid.world_to_cell(at)
		if world.layout.is_in_bounds(cell):
			at.y = FieldCollision.ground_y(world.layout, cell)
	return at


## `aHN0_move_init`: run to the next point of the round.
func _sq_go(leg: int) -> void:
	_sq_leg = leg
	_sq_state = Shrine.WALK
	if leg == ShrineQueue.LEG_FRONT:
		ShrineQueue.take_front(slot)
	elif leg == ShrineQueue.LEG_OFFER:
		ShrineQueue.step_up(slot)
	move_to(_sq_world(leg), ShrineQueue.RUN_SPEED, ShrineQueue.CLIP_RUN)


func _arrive_leg() -> void:
	match _sq_leg:
		ShrineQueue.LEG_OFFER:
			## `aHN0_saisen_init`: a coin, then the prayer, facing the well.
			rotation.y = ShrineQueue.facing_well(_well)
			_sq_state = Shrine.SAISEN
			_sq_coin = false
			_sq_timer = 0.0
			play_clip(ShrineQueue.CLIP_SAISEN, false)
		ShrineQueue.LEG_BACK:
			## `aHN0_turn_aisatu_init`: turn to the other column and bow.
			var across: Vector3 = ShrineQueue.to_world(_well, Vector2(0.0, 180.0)) - global_position
			rotation.y = atan2(across.x, across.z)
			_sq_state = Shrine.BOW
			var bow: String = ShrineQueue.BOW_CLIPS[clampi(_looks(), 0, 5)]
			if bow.is_empty() or play_clip(bow, false) <= 0.0:
				_sq_state = Shrine.BACK
				play_clip("npc_1_wait1", true)
		ShrineQueue.LEG_FRONT:
			_sq_state = Shrine.FRONT
			play_clip("npc_1_wait1", true)
		_:
			_sq_go(ShrineQueue.next_leg(_sq_leg))


func _shrine(delta: float) -> void:
	_sq_let_through()
	if is_moving():
		return
	_sq_timer += delta
	match _sq_state:
		Shrine.SAISEN:
			if not _sq_coin and _sq_timer >= SAISEN_COIN_SEC:
				_sq_coin = true
				WellCoin.toss(get_parent(), global_position, _well.global_position.y, rng())
			if clip_done():
				_sq_state = Shrine.OMAIRI
				play_clip(ShrineQueue.CLIP_OMAIRI, false)
		Shrine.OMAIRI:
			if clip_done():
				_sq_state = Shrine.AFTER
				_sq_timer = 0.0
				play_clip("npc_1_wait1", true)
		Shrine.AFTER:
			if _sq_timer >= ShrineQueue.AFTER_SEC:
				ShrineQueue.step_down(slot)
				_sq_go(ShrineQueue.next_leg(ShrineQueue.LEG_OFFER))
		Shrine.BOW:
			if clip_done():
				_sq_state = Shrine.BACK
				play_clip("npc_1_wait1", true)
		Shrine.BACK:
			if ShrineQueue.can_take_front(slot):
				_sq_go(ShrineQueue.LEG_FRONT)
		Shrine.FRONT:
			turn_to(ShrineQueue.facing_well(_well), delta)
			if _sq_let_in:
				_lead_player()
			elif ShrineQueue.may_step_up(slot):
				_sq_go(ShrineQueue.LEG_OFFER)


## `aHN0_player_move` / `aHN0_kasasimai` / `aHN0_sanpai_wait`: walk the player to wait behind
## the well, up to it when their turn comes, then — once they've prayed — thank them and go
## round without praying.
func _lead_player() -> void:
	var player := player_node() as Player
	match ShrineQueue.player_state:
		ShrineQueue.PlayerState.QUEUED:
			if player == null:
				return
			if ShrineQueue.player_may_step_up():
				ShrineQueue.offering_by = ShrineQueue.PLAYER
				ShrineQueue.player_state = ShrineQueue.PlayerState.UP
				_player_offering(player)
				return
			var wait: Vector3 = ShrineQueue.to_world(_well, ShrineQueue.PLAYER_WAIT)
			wait.y = player.global_position.y
			player.begin_demo_walk(wait, ShrineQueue.PLAYER_WALK_SPEED, 0.05)
		ShrineQueue.PlayerState.DONE:
			if not _sq_thanked:
				if not can_call_out():
					return
				_sq_thanked = true
				begin_talk(player, BankTalk.Fixed.new(ShrineQueue.thanks_msg(_looks(), rng())))
				return
			_sq_let_in = false
			ShrineQueue.front_by[ShrineQueue.column_of(slot)] = -1
			_sq_go(ShrineQueue.next_leg(ShrineQueue.LEG_OFFER))


func _sq_let_through() -> void:
	var player := player_node() as Player
	if player == null:
		return
	var want: bool = ShrineQueue.player_state == ShrineQueue.PlayerState.QUEUED \
		or ShrineQueue.player_state == ShrineQueue.PlayerState.UP
	if want == _sq_excepted:
		return
	_sq_excepted = want
	if want:
		player.add_collision_exception_with(self)
	else:
		player.remove_collision_exception_with(self)


func _player_offering(player: Player) -> void:
	var stand: Array = _well.call("visit_stand")
	var at: Vector3 = stand[0]
	at.y = player.global_position.y
	player.begin_demo_walk(at, ShrineQueue.PLAYER_WALK_SPEED, 0.05)
	while is_inside_tree() and is_instance_valid(player):
		var to: Vector3 = at - player.global_position
		if Vector2(to.x, to.z).length() <= 0.08:
			break
		await get_tree().physics_frame
	if is_instance_valid(player):
		player.end_demo_walk()
	var ui := DialogueOverlay.find(get_tree()) if is_inside_tree() else null
	if ui != null and is_instance_valid(player) and is_instance_valid(_well):
		await _well.call("offer_wish", ui, player)
	ShrineQueue.step_down(ShrineQueue.PLAYER)
	ShrineQueue.player_state = ShrineQueue.PlayerState.DONE


func think(delta: float) -> void:
	if _well != null and not talking:
		_shrine(delta)
		return
	if family == &"tunahiki" and not talking:
		_tug(delta)
		return
	if family == &"tamaire" and not talking:
		_toss(delta)
		return
	if family == &"tokyoso" and not talking:
		_race(delta)
		return
	if _data.is_empty():
		return
	if _data.has("term") and _tick_term():
		return
	_pause -= delta
	if _pause > 0.0 and not clip_done():
		return
	if _pause > 0.0:
		return
	if int(_data.get("mode", FestivalCrowd.Mode.CYCLE)) == FestivalCrowd.Mode.WANDER:
		_wander()
	else:
		_cycle()


## `aHN1_setupAction`: the next clip, looped a few times; the aerobics run in order.
func _cycle() -> void:
	var clips: Array = _clips()
	if clips.is_empty():
		return
	var clip: String
	if bool(_data.get("sequence", false)):
		clip = str(clips[_seq % clips.size()])
		_seq += 1
		_pause = play_clip(clip, false)
		return
	clip = str(clips[rng().randi_range(0, clips.size() - 1)])
	var secs: float = play_clip(clip, true)
	_pause = secs * float(rng().randi_range(1, 3))


## `aHN0_think_main_proc`: a short walk inside the spot's circle, then a pause (or a cheer).
func _wander() -> void:
	var clips: Array = _clips()
	if rng().randf() < 0.3 and clips.size() > 1:
		_pause = play_clip(str(clips[rng().randi_range(1, clips.size() - 1)]), false)
		return
	var radius: float = float(_data.get("radius", 2))
	var mgr: EventManager = EventManager.find(get_tree())
	var angle: float = rng().randf() * TAU
	var dist: float = rng().randf_range(0.5, radius)
	var target: Vector3 = _home + Vector3(sin(angle), 0.0, cos(angle)) * dist
	if mgr != null and mgr.world != null and not mgr.npc_can_stand(mgr.world.grid.world_to_cell(target)):
		_pause = 1.0
		return
	move_to(target, WALK_SPEED * 0.6, str(_data.get("walk", "npc_1_walk1")))
	_pause = rng().randf_range(2.0, 5.0)


## `eEC_EFFECT_HANABI_SWITCH` at midnight (`aCD0_set_term`): one volley over the pond.
func _new_year_fireworks() -> void:
	var mgr: EventManager = EventManager.find(get_tree())
	if mgr == null:
		return
	var block: Vector2i = mgr.block_of("pool")
	if block.x < 0:
		return
	var center: Vector2i = EventManager.block_unit_to_cell(block, Vector2i(8, 8))
	var fw := Fireworks.new()
	fw.name = "Fireworks"
	fw.pond_center = Fireworks.pond_land(mgr, block)
	fw.looping = false
	fw.finale = true
	mgr.add_actor(event_id, fw, center, 0.0, 0)


## `aCD0_set_term`: a new term. At midnight everyone pulls their party popper; npc0 calls out
## each earlier term to a player in the pond acre (`aCD0_force_talk_request`).
func _tick_term() -> bool:
	var term: int = FestivalCrowd.term_of(family, Clock.now_sec())
	if term == _term:
		return false
	var first: bool = _term < 0
	_term = term
	if family != &"countdown" or first:
		return false
	if term == FestivalCrowd.Countdown.NEW_YEAR:
		_pause = play_clip("npc_1_cracker_fire1", false)
		if slot == 0:
			_new_year_fireworks()
		return true
	if term == FestivalCrowd.Countdown.AFTER:
		_data = _data.duplicate()
		_data["clips"] = ["npc_1_wait_ki1"]
		return false
	if slot == 0 and player_distance() < 16.0 and can_call_out():
		begin_talk(player_node(), BankTalk.Fixed.new(FestivalCrowd.countdown_force_msg(_looks(), term)))
		return true
	return false
