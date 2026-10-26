extends EventNpc

## The visitor with a present outside the house (`ac_present_npc`). Waits until the player
## has stepped out (`aPST_wait`), speaks on its own (`aPST_talk_request`), hands the present
## over during the talk, then turns to the path between the houses and runs off along it
## (`aPST_exit_turn`, `aPST_exit`). The player stands and waits from the talk until the
## visitor is gone (`aPRD_present_wait`, `aPRD_retire_npc_wait`). A villager comes under
## their umbrella when it rains (`aPST_make_umbrella`).

enum Think { WAIT, TALK, EXIT_TURN, EXIT }

const RUN_SPEED := 3.0
## Lengths in metres, from the decomp's GX.
const GX := FieldCatalog.GX_TO_METERS
## `aPST_schedule_init_proc` `set_data`: where the visitor stands for each house
## (`mHS_get_arrange_idx`), field positions (GX) in metres.
const SET: Array[Vector2] = [
	Vector2(2180.0, 1540.0) * GX, Vector2(2300.0, 1540.0) * GX, Vector2(2180.0, 1820.0) * GX, Vector2(2300.0, 1820.0) * GX,
]
## `aPST_exit_turn_init` / `aPST_exit` `moveX` / `moveZ`: up the path between the houses
## for the north pair, down it for the south pair. The turn faces the first point.
const EXIT_NORTH: Array[Vector2] = [Vector2(2240.0, 1300.0) * GX, Vector2(2240.0, 1220.0) * GX]
const EXIT_SOUTH: Array[Vector2] = [Vector2(2240.0, 1900.0) * GX, Vector2(2240.0, 1980.0) * GX]

## `PresentVisit.Kind`.
var kind: int = PresentVisit.Kind.NONE
var villager: VillagerData
var think_state: Think = Think.WAIT
## `mHS_get_arrange_idx`: which of the four house plots this visit is at.
var house_index: int = 0
var _exit_points: Array[Vector3] = []
var _umbrella: HeldUmbrella
var _umb_carry: ToolCarry


func _ready() -> void:
	super._ready()
	if villager != null and Game.town.weather == &"rain":
		_open_umbrella()


func _process(delta: float) -> void:
	super._process(delta)
	if _umbrella != null:
		_umbrella.advance(delta)
	if _umb_carry != null:
		_umb_carry.advance(delta)


## `aTOL_ACTION_S_TAKEOUT`: already open, the arm on `aNPC_SUB_ANIM_UMBRELLA`.
func _open_umbrella() -> void:
	var skeleton: Skeleton3D = HeldTool.find_skeleton(model())
	var visual_id: StringName = VillagerOutdoor.umbrella_visual(villager, null)
	if skeleton == null or visual_id == &"" or _body_anim == null:
		return
	var attach: Node3D = HeldTool.bind(skeleton, visual_id)
	if attach == null or attach.get_child_count() == 0:
		return
	_umbrella = HeldUmbrella.new()
	_umbrella.setup(attach.get_child(0) as Node3D, HeldUmbrella.Action.OPEN_NOW)
	_umb_carry = ToolCarry.build_part(_body_anim, skeleton, Villager.ANIM_UMBRELLA, VillagerOutdoor.SUB_ANIM_JOINTS)
	_body_anim.mixer_applied.connect(_apply_umbrella_arm)


func _apply_umbrella_arm() -> void:
	var skeleton: Skeleton3D = HeldTool.find_skeleton(model())
	if _umb_carry != null and skeleton != null:
		_umb_carry.apply(skeleton)


## Before `_ready`: who comes, and their looks.
func assign(p_kind: int, p_villager: VillagerData) -> void:
	kind = p_kind
	villager = p_villager
	if villager != null:
		species = villager.species
		texture_set = villager.texture_set
		display_name = villager.display_name
		sound_spec = DialogueVoice.sound_spec_for_looks(_looks() as VillagerPersonality.Looks)
	else:
		species = &"ttl"
		display_name = "Tortimer"


func _looks() -> int:
	return int(villager.personality.looks) if villager != null and villager.personality != null else 0


func can_talk() -> bool:
	return false


func make_talk() -> BankTalk:
	return PresentVisit.Talk.new(kind, _looks(), rng())


func think(delta: float) -> void:
	match think_state:
		Think.WAIT:
			if can_call_out():
				think_state = Think.TALK
				if not begin_talk(player_node()):
					_leave()
		Think.EXIT_TURN:
			_hold_player()
			var to: Vector3 = _exit_points[0] - global_position
			if turn_to(atan2(to.x, to.z), delta):
				think_state = Think.EXIT
				_run_next()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	## `move_to` runs instead of `think` while the run goes; the player stays held all the way.
	if think_state == Think.EXIT:
		_hold_player()


## `ExitTimeout`: gone even if a run leg never ends (blocked).
func _on_exit_timeout() -> void:
	_retire()


func talk_ended(_script: BankTalk) -> void:
	_leave()


## `aPRD_present_wait_init` (`mPlib_request_main_demo_wait_type1`): the player stands still
## while the visitor leaves.
func _hold_player() -> void:
	var p := player_node() as Player
	if p != null and not p.is_busy():
		p.set_busy(true)


## `aPST_exit`: on to the next point, or gone after the last.
func _run_next() -> void:
	if _exit_points.is_empty():
		_retire()
		return
	move_to(_exit_points.pop_front(), RUN_SPEED, "npc_1_run1")


func arrived() -> void:
	super.arrived()
	if think_state == Think.EXIT:
		_run_next()


## `aPRD_retire_npc_wait`, once the visitor is gone: the player is let go, and for Tortimer's
## visit the trophy is set and the player holds up the golden rod or net
## (`mPlib_request_main_demo_get_golden_item2_type1`).
func _retire() -> void:
	if is_queued_for_deletion():
		return
	stop_moving()
	queue_free()
	var p := player_node() as Player
	if p != null:
		p.set_busy(false)
	if kind != PresentVisit.Kind.GOLDEN_ROD and kind != PresentVisit.Kind.GOLDEN_NET:
		return
	PresentVisit.retire(kind)
	if p != null:
		p.reports.get_golden_item(PresentVisit.present_for(kind))


## `aPST_exit_turn_init`: turn to the path between the houses, then run along it.
func _leave() -> void:
	think_state = Think.EXIT_TURN
	collision_layer = 0
	($ExitTimeout as Timer).start()
	_hold_player()
	_exit_points = exit_points(global_position, house_index)


## The exit run in world space: the decomp's points as offsets from the visitor's stand, so
## they follow the stand wherever the house plot is.
static func exit_points(stand: Vector3, house: int) -> Array[Vector3]:
	var from: Vector2 = SET[clampi(house, 0, 3)]
	var points: Array[Vector3] = []
	## The north pair stand at z 1540 GX.
	for to: Vector2 in (EXIT_NORTH if from.y <= SET[0].y else EXIT_SOUTH):
		var d: Vector2 = to - from
		points.append(Vector3(stand.x + d.x, stand.y, stand.z + d.y))
	return points


## Put the visitor `PresentVisit.STAND` in front of `stand` along `yaw`, facing back.
static func spawn(parent: Node, kind: int, stand: Vector3, yaw: float, house: int = 0) -> Node3D:
	var packed: PackedScene = load("res://features/events/present_npc.tscn") as PackedScene
	if packed == null or parent == null or kind == PresentVisit.Kind.NONE:
		return null
	var npc := packed.instantiate()
	var who: VillagerData = null
	if kind == PresentVisit.Kind.BIRTHDAY:
		who = VillagerCatalog.get_villager(Game.resident.birthday_present_npc)
		if who == null:
			return null
	npc.call("assign", kind, who)
	npc.set("home_yaw", yaw + PI)
	npc.set("house_index", house)
	parent.add_child(npc)
	(npc as Node3D).global_position = stand + Vector3(sin(yaw), 0.0, cos(yaw)) * PresentVisit.STAND
	return npc
