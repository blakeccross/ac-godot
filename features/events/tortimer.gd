extends EventNpc

## Tortimer at the wishing well during the first job (`ac_npc_soncho`, `SP_NPC_SONCHO`,
## `fd_npc_land` unit 10, 10 on `mRF_BLOCKKIND_SHRINE`). Here only while the first job runs
## (`mFM_SetMoveActor`), and, once met, not while he is away on vacation
## (`mSC_LightHouse_travel_check`). He walk-wanders the rim of a 60 GX circle round where he
## was put (`aNS_actor_move`, `aNS_wander_init`).
##
## The first talk asks who you respect the most (0x3AFC; 0x3B02 during his vacation) and he
## introduces himself; after that, one of three lines (0x3AFF + RANDOM(3)). Talking to him
## is meeting him (`aNS_talk_init`: `mSC_trophy_set(mSC_SPECIAL_EVENT_ARBEIT)`).

const MSG_FIRST := 0x3AFC
const MSG_FIRST_AWAY := 0x3B02
const MSG_AGAIN := 0x3AFF
## `movement.range_radius = 60` GX round `home.position`.
const RANGE := 60.0 * FieldCatalog.GX_TO_METERS

var _home: Vector3


func _init() -> void:
	species = &"ttl"
	display_name = "Tortimer"


func _ready() -> void:
	home_yaw = rotation.y
	super._ready()
	_home = global_position
	_refresh_presence()
	if Game != null and Game.first_job != null and not Game.first_job.changed.is_connected(_refresh_presence):
		Game.first_job.changed.connect(_refresh_presence)


func _exit_tree() -> void:
	if Game != null and Game.first_job != null and Game.first_job.changed.is_connected(_refresh_presence):
		Game.first_job.changed.disconnect(_refresh_presence)


## `aNS_set_norm_talk_info`.
func make_talk() -> BankTalk:
	var msg_no: int = MSG_FIRST
	if _met():
		msg_no = MSG_AGAIN + rng().randi_range(0, 2)
	elif _away():
		msg_no = MSG_FIRST_AWAY
	return BankTalk.Fixed.new(msg_no)


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if not super.interact(action, ctx):
		return false
	if Game.first_job != null:
		Game.first_job.mark_met_tortimer()
		if Game.first_job.kind == FirstJob.Kind.INTRODUCTIONS and Game.first_job.chore_finished():
			Game.set_interact_prompt("Talk to Tom Nook")
	return true


func think(delta: float) -> void:
	if visible:
		walk_wander(delta, _wander_dest)


## He stays turned the way the talk left him.
func talk_ended(script: BankTalk) -> void:
	home_yaw = rotation.y
	super.talk_ended(script)


## `aNPC_think_wander_move_next` on his circle: a rim point he may stand on.
func _wander_dest() -> Vector3:
	var world: World = World.find(get_tree())
	if world == null or world.layout == null:
		return Vector3.INF
	for _try: int in VillagerWalk.WANDER_TRIES:
		var angle: float = rng().randf() * TAU
		var dest: Vector3 = _home + Vector3(sin(angle), 0.0, cos(angle)) * RANGE
		var cell: Vector2i = world.grid.world_to_cell(dest)
		if VillagerWalk.is_standable(world.layout, cell):
			dest.y = FieldCollision.ground_y(world.layout, cell)
			return dest
	return Vector3.INF


func _met() -> bool:
	return Game != null and Game.first_job != null and Game.first_job.tortimer_met


func _away() -> bool:
	return Game != null and Game.lighthouse.in_nights(Clock.year, Clock.month, Clock.day)


func _refresh_presence() -> void:
	## `mFM_SetMoveActor`: only during the first job, and not once met while he's away.
	var show: bool = Game != null and Game.first_job != null and Game.first_job.is_active() \
		and not (_met() and _away())
	visible = show
	collision_layer = 1 if show else 0
	var volume: Node = get_node_or_null("InteractVolume")
	if volume is CollisionObject3D:
		(volume as CollisionObject3D).collision_layer = 8 if show else 0
	if not show:
		stop_moving()
