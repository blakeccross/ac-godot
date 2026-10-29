extends EventNpc

## Tortimer by the river, thinking about the second bridge (`ac_ev_soncho`,
## `SP_NPC_EV_SONCHO`). He talks the bridge over (`TortimerBridgeTalk`); the acre he stands in
## is where it would go.

## `Common_Get(spnpc_first_talk_flags)` bit `EV_SONCHO`: not saved, so the first talk since
## the game was started opens with the time-of-day line, however often the town reloads.
static var talked: bool = false


func _init() -> void:
	species = &"ttl"
	display_name = "Tortimer"


func make_talk() -> BankTalk:
	var world: World = World.find(get_tree())
	var cell: Vector2i = world.grid.world_to_cell(global_position) if world != null else Vector2i.ZERO
	var t := TortimerBridgeTalk.new(TownSpace.block_of_cell(cell), not talked,
		EventDates.ordinal(Clock.year, Clock.month, Clock.day), Clock.hour, rng())
	talked = true
	return t
