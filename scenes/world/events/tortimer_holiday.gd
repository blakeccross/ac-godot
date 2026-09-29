extends EventNpc

## Tortimer out for a holiday (`ac_ev_soncho2`, `SP_NPC_EV_SONCHO2`, skeleton `ttl_1`): at
## the wishing-well acre for most holidays (`soncho_start`), wandering for the fishing
## tourneys and the fireworks (`sonchowandar_start`, `aES2_wander_init`). On Halloween he
## wears the pumpkin head (`SP_NPC_SONCHO_D079`, `pkn_1`). `TortimerHoliday` talks.

const WANDER_RADIUS := 5
const WANDER_PAUSE := Vector2(3.0, 7.0)

## `mSC_EVENT_*`.
var holiday: int = 0
var wander: bool = false
var _pause: float = 0.0
var _home_cell: Vector2i


func _init() -> void:
	species = &"ttl"
	display_name = "Tortimer"


func setup() -> void:
	var world: World = World.find(get_tree())
	_home_cell = world.grid.world_to_cell(global_position) if world != null else Vector2i.ZERO


func make_talk() -> BankTalk:
	var record: Dictionary = Game.events.area(&"soncho_record") if Game != null and Game.events != null else {}
	var t := TortimerHoliday.new(holiday, record, Game.inventory if Game != null else null, rng())
	t.female = Game != null and String(Game.player_gender) == "female"
	return t


func think(delta: float) -> void:
	if not wander:
		return
	_pause -= delta
	if _pause > 0.0:
		return
	_pause = rng().randf_range(WANDER_PAUSE.x, WANDER_PAUSE.y)
	var mgr: EventManager = EventManager.find(get_tree())
	if mgr == null:
		return
	for _i: int in 8:
		var c: Vector2i = _home_cell + Vector2i(rng().randi_range(-WANDER_RADIUS, WANDER_RADIUS), rng().randi_range(-WANDER_RADIUS, WANDER_RADIUS))
		if mgr.npc_can_stand(c):
			move_to(mgr.cell_position(c))
			return
