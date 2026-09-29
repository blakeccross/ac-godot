extends EventNpc

## Jingle on Toy Day (`ac_ev_santa`, `SP_NPC_SANTA`, skeleton `snt_1`), in a free acre; after
## each talk he moves on (`christmas_behind` → `walk_actor_at_wade`), here once the player
## is out of sight. `JingleTalk` keeps the wish list.

const LEAVE_DISTANCE := 20.0

var _leave: bool = false


func _init() -> void:
	species = &"snt"
	display_name = "Jingle"


func _area() -> Dictionary:
	if Game == null or Game.events == null:
		return {}
	var a: Dictionary = Game.events.area(&"toy_day_jingle")
	if int(a.get("year", 0)) != Clock.year:
		a.clear()
		a["year"] = Clock.year
	return a


func make_talk() -> BankTalk:
	var t := JingleTalk.new(_area(), Game.inventory if Game != null else null, rng())
	var p: Node3D = player_node()
	var world: World = World.find(get_tree())
	if p != null and world != null:
		t.block = EventManager.cell_to_block(world.grid.world_to_cell(p.global_position))
	t.cloth = Game.cloth_id if Game != null else &""
	return t


func talk_ended(script: BankTalk) -> void:
	super.talk_ended(script)
	_leave = true


func think(_delta: float) -> void:
	if not _leave or player_distance() < LEAVE_DISTANCE:
		return
	var mgr: EventManager = EventManager.find(get_tree())
	if mgr == null:
		return
	var cell: Vector2i = mgr.search_free_unit(event_id, rng().randi_range(0, 996), 1)
	if cell.x < 0:
		return
	_leave = false
	global_position = mgr.cell_position(cell)
	mgr.remember(event_id, 0, cell)
