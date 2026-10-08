extends EventNpc

## The visitor with a present outside the house (`ac_present_npc`). Waits until the player
## has stepped out (`aPST_wait`), speaks on its own (`aPST_talk_request`), hands the present
## over during the talk, then turns away and runs off (`aPST_exit_turn`, `aPST_exit`). A
## villager comes under their umbrella when it rains (`aPST_make_umbrella`).

enum Think { WAIT, TALK, EXIT }

const RUN_SPEED := 3.0
## How far it runs before it is gone.
const EXIT_RUN := 10.0

## `PresentVisit.Kind`.
var kind: int = PresentVisit.Kind.NONE
var villager: VillagerData
var think_state: Think = Think.WAIT
var _exit_time: float = 0.0
var _umbrella: HeldUmbrella
var _umb_carry: ToolCarry


func _ready() -> void:
	super._ready()
	if villager != null and Game.weather == &"rain":
		_open_umbrella()


func _process(delta: float) -> void:
	super._process(delta)
	if _umbrella != null:
		_umbrella.tick(delta)
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
		Think.EXIT:
			_exit_time -= delta
			if _exit_time <= 0.0 or not is_moving():
				_retire()
				queue_free()


func talk_ended(_script: BankTalk) -> void:
	_leave()


## `aPRD_retire_npc_wait`: once Tortimer has gone, the player holds up the golden rod or
## net (`mPlib_request_main_demo_get_golden_item2_type1`).
func _retire() -> void:
	if kind != PresentVisit.Kind.GOLDEN_ROD and kind != PresentVisit.Kind.GOLDEN_NET:
		return
	var p := player_node() as Player
	if p != null:
		p.get_golden_item(PresentVisit.present_for(kind))


## Away from the door, the way it came.
func _leave() -> void:
	think_state = Think.EXIT
	collision_layer = 0
	var away := Vector3(sin(home_yaw), 0.0, cos(home_yaw))
	_exit_time = EXIT_RUN / RUN_SPEED + 1.0
	move_to(global_position - away * EXIT_RUN, RUN_SPEED, "npc_1_run1")


## Put the visitor `PresentVisit.STAND_GX` in front of `stand` along `yaw`, facing back.
static func spawn(parent: Node, kind: int, stand: Vector3, yaw: float) -> Node3D:
	var packed: PackedScene = load("res://scenes/world/present_npc.tscn") as PackedScene
	if packed == null or parent == null or kind == PresentVisit.Kind.NONE:
		return null
	var npc := packed.instantiate()
	var who: VillagerData = null
	if kind == PresentVisit.Kind.BIRTHDAY:
		who = VillagerCatalog.get_villager(Game.birthday_present_npc)
		if who == null:
			return null
	npc.call("assign", kind, who)
	npc.set("home_yaw", yaw + PI)
	parent.add_child(npc)
	(npc as Node3D).global_position = stand + Vector3(sin(yaw), 0.0, cos(yaw)) * PresentVisit.STAND_GX * FieldCatalog.GX_TO_METERS
	return npc
