extends EventNpc

## Gulliver (`ac_ev_dozaemon`, `SP_NPC_EV_DOZAEMON`, skeleton `seg_1`): one weekday a week he
## lies at the waterline of a beach acre (`downing_start`, `make_actor_in_seaside_block`).
## Asleep (`GETUP_WAIT_SEG1`, twitching `PIKU_SEG1` when spoken to) until a talk wakes him;
## he gets up (`GETUP_SEG1`), speaks first, then wanders the beach. Once woken he is gone
## the next time the field loads (`aEDZ_actor_ct`, `WAKEUP`), and after his gift he stays
## away for the week (`dozaemon_completed`).

enum Think { ASLEEP, GETTING_UP, WANDER }

const WANDER_RADIUS := 4
const WANDER_PAUSE := Vector2(2.0, 5.0)

var think_state: Think = Think.ASLEEP
var _pause: float = 0.0
var _home_cell: Vector2i


func _init() -> void:
	species = &"seg"
	display_name = "Gulliver"


func setup() -> void:
	_home_cell = _cell()
	play_clip(idle_clip(), true)


func _area() -> Dictionary:
	return Game.events.area(&"dozaemon") if Game != null and Game.events != null else {}


func idle_clip() -> String:
	return "npc_1_getup_wait_seg1" if think_state == Think.ASLEEP else "npc_1_wait1"


func talk_clip() -> String:
	return "npc_1_piku_seg1" if think_state == Think.ASLEEP else "npc_1_wait1"


func make_talk() -> BankTalk:
	var mode: GulliverTalk.Mode = GulliverTalk.Mode.ASLEEP if think_state == Think.ASLEEP else GulliverTalk.Mode.WANDER
	return GulliverTalk.new(mode, _area(), Game.inventory if Game != null else null, rng())


func _turn_towards_player(delta: float) -> void:
	## `talk_info.turn = aNPC_TALK_TURN_NONE` while he lies there.
	if think_state == Think.ASLEEP:
		return
	super._turn_towards_player(delta)


func talk_ended(script: BankTalk) -> void:
	var g := script as GulliverTalk
	if g != null and g.mode == GulliverTalk.Mode.ASLEEP and g.wakes:
		## `aEDZ_THINK_OKIAGARU`: stand up, then speak first.
		think_state = Think.GETTING_UP
		play_clip("npc_1_getup_seg1", false)
		return
	if think_state != Think.ASLEEP:
		think_state = Think.WANDER


func think(delta: float) -> void:
	match think_state:
		Think.GETTING_UP:
			if clip_done():
				think_state = Think.WANDER
				play_clip("npc_1_wait1", true)
				begin_talk(player_node(), GulliverTalk.new(GulliverTalk.Mode.WOKEN, _area(), Game.inventory if Game != null else null, rng()))
		Think.WANDER:
			_pause -= delta
			if _pause <= 0.0:
				_pause = rng().randf_range(WANDER_PAUSE.x, WANDER_PAUSE.y)
				_wander_step()


func _cell() -> Vector2i:
	var world: World = World.find(get_tree()) if get_tree() != null else null
	return world.grid.world_to_cell(global_position) if world != null else Vector2i.ZERO


func _wander_step() -> void:
	var mgr: EventManager = EventManager.find(get_tree())
	if mgr == null:
		return
	for _i: int in 8:
		var c: Vector2i = _home_cell + Vector2i(rng().randi_range(-WANDER_RADIUS, WANDER_RADIUS), rng().randi_range(-WANDER_RADIUS, WANDER_RADIUS))
		if mgr.npc_can_stand(c):
			move_to(mgr.cell_position(c))
			return
