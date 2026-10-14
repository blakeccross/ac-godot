extends EventNpc

## Tortimer at the Groundhog Day stand (`ac_ev_speech_soncho`, `SP_NPC_EV_SPEECH_SONCHO`).
## Before 8:00 he chats (`mString_SPEECH_SONCHO_START + 1 + RANDOM(5)`); at 8:00 he gives his
## speech to a player who's there (`aESS_set_force_talk_info`, once), right after the groundhog
## (Mr. Resetti, `GroundhogResetti`) has had his say; afterwards his lines
## depend on the weather — clear means spring is near, snow means six more weeks. He faces
## the crowd throughout (`aNPC_TALK_TURN_NONE`).

const MSG_SPEECH := 0x3DB5
const EVENT_SEC := 8 * 3600
## The speech waits for the player to be this close (m).
const AUDIENCE_RANGE := 16.0
const GROUNDHOG_SCENE := "res://scenes/world/events/groundhog_resetti.tscn"
const GROUNDHOG_UNIT := Vector2i(5, 8)
## `timer = 600` ticks before the groundhog, 60 after it.
const BIRTH_WAIT_SEC := 10.0
const SPEECH_WAIT_SEC := 1.0

var _groundhog: Node3D = null
var _birth_wait: float = 0.0
var _speech_wait: float = 0.0


func _init() -> void:
	species = &"ttl"
	display_name = "Tortimer"
	talk_turn = false


static func talk_msg(sec: int, weather: StringName, rng: RandomNumberGenerator) -> int:
	if sec < EVENT_SEC:
		return MSG_SPEECH + 1 + rng.randi_range(0, 4)
	match weather:
		&"clear":
			return MSG_SPEECH + 6 + rng.randi_range(0, 4)
		&"snow":
			return MSG_SPEECH + 11 + rng.randi_range(0, 4)
	return MSG_SPEECH + 6


func make_talk() -> BankTalk:
	return BankTalk.Fixed.new(talk_msg(Clock.now_sec(), Game.weather if Game != null else &"clear", rng()))


func think(delta: float) -> void:
	if Clock.now_sec() < EVENT_SEC or Game == null or Game.events == null:
		return
	var area: Dictionary = Game.events.area(&"groundhog_day")
	var today: String = Game.events.day_key()
	if str(area.get("speech", "")) == today:
		return
	## `aGHC_birth_reset_wait` → `_birth_reset`: ten seconds after 8:00 the groundhog comes
	## up; a second after it has gone (`aGHC_soncho_speech_start_wait`), the speech.
	if str(area.get("majin", "")) != today:
		if _groundhog == null and player_distance() <= AUDIENCE_RANGE:
			_birth_wait += delta
			if _birth_wait >= BIRTH_WAIT_SEC:
				_groundhog = _spawn_groundhog()
				if _groundhog == null:
					area["majin"] = today
		return
	_speech_wait += delta
	if _speech_wait < SPEECH_WAIT_SEC or not can_call_out() or player_distance() > AUDIENCE_RANGE:
		return
	area["speech"] = today
	begin_talk(player_node(), BankTalk.Fixed.new(MSG_SPEECH), false)


## `setupActor_proc(SP_NPC_EV_MAJIN, …, shrine block, unit 5, 8)`, nudged half a unit.
func _spawn_groundhog() -> Node3D:
	var mgr: EventManager = EventManager.find(get_tree())
	var world: World = World.find(get_tree())
	if mgr == null or world == null or world.grid == null:
		return null
	var block: Vector2i = mgr.block_of("shrine")
	if block.x < 0:
		return null
	var cell: Vector2i = EventManager.block_unit_to_cell(block, GROUNDHOG_UNIT)
	var node: Node3D = (load(GROUNDHOG_SCENE) as PackedScene).instantiate() as Node3D
	## He faces the crowd, as Tortimer does.
	node.set("home_yaw", global_rotation.y)
	get_parent().add_child(node)
	var pos: Vector3 = world.grid.cell_to_world(cell) + Vector3(1.0, 0.0, 1.0)
	if world.layout != null:
		pos.y = FieldCollision.ground_y(world.layout, cell)
	node.global_position = pos
	node.connect(&"done", _on_groundhog_done)
	return node


func _on_groundhog_done() -> void:
	_groundhog = null
	_speech_wait = 0.0
	if Game != null and Game.events != null:
		Game.events.area(&"groundhog_day")["majin"] = Game.events.day_key()
