extends EventNpc

## Jack on Halloween night (`ac_ev_pumpkin`, `SP_NPC_HALLOWEEN`, skeleton `pkn_1`). Found in a
## free acre; after a talk he slips away to another (`halloween_behind` → `walk_actor_at_wade`,
## here once the player is out of sight). Talked to again in the same acre he only chats.

const LEAVE_DISTANCE := 20.0

var _leave: bool = false


func _init() -> void:
	species = &"pkn"
	display_name = "Jack"


func _area() -> Dictionary:
	return Game.events.area(&"halloween") if Game != null and Game.events != null else {}


func _player_block() -> Vector2i:
	var p: Node3D = player_node()
	var world: World = World.find(get_tree())
	if p == null or world == null:
		return Vector2i(-1, -1)
	return EventManager.cell_to_block(world.grid.world_to_cell(p.global_position))


func make_talk() -> BankTalk:
	var t := TrickOrTreatTalk.new(true, 0, Game.inventory if Game != null else null, rng())
	var a: Dictionary = _area()
	var block: Vector2i = _player_block()
	t.same_acre = str(a.get("date", "")) == Game.events.day_key() and a.get("block", Vector2i(-2, -2)) == block
	a["date"] = Game.events.day_key()
	a["block"] = block
	return t


func talk_ended(script: BankTalk) -> void:
	super.talk_ended(script)
	var t := script as TrickOrTreatTalk
	if t != null and not t.same_acre:
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
