class_name Islander
extends RefCounted

## The island's one resident (`Save_Get(island).animal`). The disc picks them when the town is made
## (`mISL_init` → `mNpc_DecideIslandNpc`: a random pick among the `mNpc_GROW_ISLANDER` animals, 18 of
## them) and they never move to town; a Game Boy Advance island would bring its own, which is not here.

## The unit of the cottage's yard the islander stands in, south of the door (`Cottage_npc_rewrite_door`
## sets the exit 60 GX south of the home position).
const YARD_FROM_COTTAGE := Vector2i(1, 4)


## `mNpc_DecideIslandNpc`: one of the islanders, the same one for the same town seed.
static func decide(seed_value: int) -> StringName:
	var pool: Array[VillagerData] = []
	for v: VillagerData in VillagerCatalog.all_villagers():
		if v.islander:
			pool.append(v)
	if pool.is_empty():
		return &""
	pool.sort_custom(func(a: VillagerData, b: VillagerData) -> bool: return a.npc_index < b.npc_index)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("islander:%d" % seed_value)
	return pool[rng.randi_range(0, pool.size() - 1)].id


## This town's islander, decided (and kept in the save) the first time it is asked for.
static func id() -> StringName:
	if Game.town.islander_id.is_empty():
		Game.town.islander_id = String(decide(Game.town.world_seed))
	return StringName(Game.town.islander_id)


static func data() -> VillagerData:
	return VillagerCatalog.get_villager(id())


## `Cottage_demo_speak_go_out`: knocking while the islander sleeps is answered from inside
## (`MSG_ISLANDER_NOENTRY_SLEEPING1` + their looks), in the dull red of a muffled voice.
const SLEEPING_MSG := 11007
const SLEEPING_WINDOW := Color8(145, 60, 40)


## The message for a closed door, or -1 when the door is for opening: the islander is at home
## and asleep (`Cottage_npc_check_go_out`).
static func sleeping_msg(entry: StringName) -> int:
	if entry != &"cottage_npc":
		return -1
	var who: VillagerData = data()
	if who == null or not Game.villagers.get_or_create(who.id).is_home:
		return -1
	var table: ScheduleData = who.schedule_table()
	if table == null or table.activity_now() != VillagerActivity.SLEEP:
		return -1
	return SLEEPING_MSG + (int(who.personality.looks) if who.personality != null else 0)
