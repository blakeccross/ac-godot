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
	_home = global_position
	_pause = rng().randf_range(0.5, 3.0)


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
	var alt_event: StringName = _data.get("alt_event", &"")
	var alt: bool = alt_event != &"" and Game != null and Game.events != null and Game.events.is_active(alt_event)
	var term: int = FestivalCrowd.term_of(family, Clock.now_sec())
	var n: int = FestivalCrowd.talk_msg(family, _looks(), slot, rng(), alt, term)
	return BankTalk.Fixed.new(n) if n >= 0 else null


func talk_ended(script: BankTalk) -> void:
	super.talk_ended(script)
	play_clip(idle_clip(), true)


func think(delta: float) -> void:
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
		return true
	if term == FestivalCrowd.Countdown.AFTER:
		_data = _data.duplicate()
		_data["clips"] = ["npc_1_wait_ki1"]
		return false
	if slot == 0 and player_distance() < 16.0 and not talking:
		begin_talk(player_node(), BankTalk.Fixed.new(FestivalCrowd.countdown_force_msg(_looks(), term)))
		return true
	return false
