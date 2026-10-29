extends EventNpc

## Tortimer out for a holiday (`ac_ev_soncho2`, `SP_NPC_EV_SONCHO2`, skeleton `ttl_1`): at
## the wishing-well acre for most holidays and his vacations (`soncho_start`), in a random
## acre for the fishing tourneys and the fireworks (`sonchowandar_start`), or at his spot on
## a festival's map. On Halloween he wears the pumpkin head (`SP_NPC_SONCHO_D079`, `pkn_1`).
## `TortimerHoliday` talks.
##
## `aES2_wait` sets him going: wherever he is, he walk-wanders the acre like a villager
## (`aES2_wander_init`, `aNPC_SCHEDULE_TYPE_WALK_WANDER`: the rim of the circle round the
## acre centre). At the Sports Fair he keeps to his game instead: turned to the lead runner
## while the foot race runs (`aES2_look_runner`), pacing round the shrine at the ball toss
## (`aES2_bskt_*`), clapping or watching the tug-of-war (`aES2_tug_of_war`), or standing by.

enum Station { WANDER, FOOT_RACE, BALL_TOSS, TUG_OF_WAR, STAND }

## `aES2_set_move_pos` round the shrine (`mFI_SetOyasiroPos`), in units: walk to the first
## point, face the second and wait, walk to the third, face the fourth and wait, again.
const BASKET_ROUND: Array[Vector2i] = [Vector2i(4, -3), Vector2i(5, 1), Vector2i(-3, -3), Vector2i(-4, 1)]
const UNIT := 40.0 * FieldCatalog.GX_TO_METERS
## `timer = 300` ticks: the wait at a ball-toss corner, and each tug-of-war beat.
const STATION_WAIT := 300.0 * DecompTime.TICK_SEC
const CLIP_CLAP := "npc_1_clap1"

## `mSC_EVENT_*` (or `TortimerHoliday.JAN_VACATION` / `FEB_VACATION`).
var holiday: int = 0
var station: Station = Station.WANDER
## `soncho->item`, picked once when he sets out (`aES2_wait`).
var item: StringName = &""
var _block: Vector2i = Vector2i(-1, -1)
var _shrine: Vector3 = Vector3.INF
var _round_step: int = 0
var _station_timer: float = 0.0


func _init() -> void:
	species = &"ttl"
	display_name = "Tortimer"


func setup() -> void:
	var world: World = World.find(get_tree())
	if world != null:
		_block = TownSpace.block_of_cell(world.grid.world_to_cell(global_position))
	var female: bool = Game != null and String(Game.resident.player_gender) == "female"
	if not TortimerHoliday.is_vacation(holiday):
		var pick := TortimerHoliday.new(holiday, {}, null, rng())
		pick.female = female
		item = pick.trophy_item()
	if station == Station.BALL_TOSS:
		var well: WishingWell = WishingWell.find(get_tree())
		if well != null:
			_shrine = well.global_position
	if station == Station.TUG_OF_WAR:
		_tug_beat()


func make_talk() -> BankTalk:
	var record: Dictionary = Game.events.area(&"soncho_record") if Game != null and Game.events != null else {}
	var t := TortimerHoliday.new(holiday, record, Game.inventory if Game != null else null, rng())
	t.female = Game != null and String(Game.resident.player_gender) == "female"
	t.item = item
	t.lighthouse = Game.lighthouse if Game != null else null
	return t


func think(delta: float) -> void:
	match station:
		Station.WANDER:
			walk_wander(delta, _wander_dest)
		Station.FOOT_RACE:
			_look_runner(delta)
		Station.BALL_TOSS:
			_basket_round(delta)
		Station.TUG_OF_WAR:
			_station_timer -= delta
			if _station_timer <= 0.0:
				_tug_beat()


## He stays turned the way the talk left him (`aES2_setup_think_proc` picks up from there).
func talk_ended(script: BankTalk) -> void:
	home_yaw = rotation.y
	super.talk_ended(script)


## `aNPC_think_wander_move_next`: a rim point round the acre centre.
func _wander_dest() -> Vector3:
	var world: World = World.find(get_tree())
	if world == null or world.layout == null or _block.x < 0:
		return Vector3.INF
	return VillagerWalk.wander_in_block(world.layout, _block, global_position, rng(), world.grid)


## `aES2_look_runner`: while the race runs, `aNPC_ACT_TURN2` to the first runner.
func _look_runner(delta: float) -> void:
	var race := get_parent().get_node_or_null(^"FootRace") as FootRace
	if race == null or race.phase != FootRace.Phase.RACE:
		return
	var runner: Node3D = race.runner(0)
	if runner == null:
		return
	var to: Vector3 = runner.global_position - global_position
	if to.length_squared() > 0.0001:
		turn_to(atan2(to.x, to.z), delta)


## `aES2_bskt_turn_*` / `_move_*` / `_timer_next`: turn to a corner, walk there, turn to the
## next and wait, then the far corner the same way.
func _basket_round(delta: float) -> void:
	if _shrine == Vector3.INF or is_moving():
		return
	var pair: int = (_round_step / 4) % 2
	match _round_step % 4:
		0, 2:
			var target: Vector3 = _round_point(BASKET_ROUND[pair * 2 + (_round_step % 4) / 2])
			var to: Vector3 = target - global_position
			if to.length_squared() < 0.0001 or turn_to(atan2(to.x, to.z), delta):
				_round_step += 1
				if _round_step % 4 == 3:
					_station_timer = STATION_WAIT
		1:
			_round_step += 1
			move_to(_round_point(BASKET_ROUND[pair * 2]))
		3:
			_station_timer -= delta
			if _station_timer <= 0.0:
				_round_step = (_round_step + 1) % 8


func _round_point(units: Vector2i) -> Vector3:
	var p: Vector3 = _shrine + Vector3(units.x, 0.0, units.y) * UNIT
	var world: World = World.find(get_tree())
	if world != null and world.layout != null:
		var cell: Vector2i = world.grid.world_to_cell(p)
		if world.layout.is_in_bounds(cell):
			p.y = FieldCollision.ground_y(world.layout, cell)
	return p


## `aES2_tug_of_war_init`: claps or watches for the next 300 ticks, even odds.
func _tug_beat() -> void:
	_station_timer = STATION_WAIT
	play_clip(CLIP_CLAP if rng().randf() < 0.5 else idle_clip(), true)
