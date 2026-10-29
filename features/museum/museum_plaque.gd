extends StaticBody3D

## One museum exhibit's talk point. The original has no sign object here: each wing's actor
## checks A against its own table of points (`ac_museum_fossil` / `_picture` / `_insect` /
## `_fish`) and opens a cream window with no nameplate naming the exhibit and its donor, a page
## at a time where a case holds several. This node sits on that point.

## How the player has to stand. `CARDINAL` (`mRmTp_CheckTalkAble`, `aMP_CheckTalkAble`): the
## centre within `reach` of the point, facing within ±22.5° of the side the exhibit faces.
## `NORTH_SQUARE` (`Museum_Insect` / `Museum_Fish_Check_Talk_Distance`): the centre inside a
## ±`half` square around the sign, facing north to within 67.5°.
enum Rule { CARDINAL, NORTH_SQUARE }

## `mRmTp_DIRECT_*`: the side of the exhibit the player stands on.
enum Direct { SOUTH, EAST, NORTH, WEST }

## `mDemo_Set_talk_window_color` in all four wings.
const WINDOW_COLOR := Color8(255, 255, 205)
## The sign squares' facing limit (`DEG2SHORT_ANGLE(67.5)` / `0x3000`).
const NORTH_SQUARE_FACING := deg_to_rad(67.5)
## `direct_table` in `mRmTp_CheckTalkAble`: the player's facing, in sixteenths of a turn, to the
## side it faces from (-1: a diagonal, which never counts).
const DIRECT_BY_SECTOR: Array[int] = [
	Direct.NORTH, -1, -1, Direct.WEST, Direct.WEST, -1, -1, Direct.SOUTH,
	Direct.SOUTH, -1, -1, Direct.EAST, Direct.EAST, -1, -1, Direct.NORTH,
]

@export var label: String = "Exhibit"
var rule: Rule = Rule.CARDINAL
var direct: Direct = Direct.SOUTH
## Metres; `reach_inclusive` is the paintings' `<=` (fossils use `<`).
var reach: float = 0.0
var reach_inclusive: bool = false
var half: float = 0.0
## While the window is up the player turns toward the point (fossils) or due north (the rest),
## by `add_calc_short_angle2(fraction, max_step, 0)` a tick.
var turn_toward_point: bool = false
var turn_fraction: float = 1.0 - sqrt(0.7)
var turn_max_step: float = deg_to_rad(11.25)
## `{"name": String, "donor": MuseumBook.Donator}` per donated piece, in the order they page.
var entries: Array[Dictionary] = []


## A fossil or painting point (`mRmTp_CheckTalkAble`).
func setup_cardinal(p_label: String, p_direct: Direct, p_reach: float, inclusive: bool, toward_point: bool) -> void:
	label = p_label
	rule = Rule.CARDINAL
	direct = p_direct
	reach = p_reach
	reach_inclusive = inclusive
	turn_toward_point = toward_point
	name = "Plaque_%s" % p_label.replace(" ", "_")
	_size_volume(reach)


## An insect case or fish tank sign: `half` metres each way, 0.3 / 22.5° turn.
func setup_sign(p_label: String, p_half: float) -> void:
	label = p_label
	rule = Rule.NORTH_SQUARE
	half = p_half
	turn_toward_point = false
	turn_fraction = 0.3
	turn_max_step = deg_to_rad(22.5)
	name = "Plaque_%s" % p_label.replace(" ", "_")
	_size_volume(half * sqrt(2.0))


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("museum_set")


## The volume only has to reach the player's forward probe when the rule passes.
func _size_volume(radius: float) -> void:
	var shape_node := get_node_or_null("InteractVolume/CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(radius, 0.5) + 0.5
	shape_node.shape = sphere


static func direct_for_yaw(yaw: float) -> int:
	return DIRECT_BY_SECTOR[int(floor(fposmod(yaw, TAU) / TAU * 16.0)) % 16]


func can_talk(at: Vector3, yaw: float) -> bool:
	var d := Vector2(at.x - global_position.x, at.z - global_position.z)
	match rule:
		Rule.NORTH_SQUARE:
			return (
				absf(d.x) < half and absf(d.y) < half
				and absf(angle_difference(yaw, PI)) < NORTH_SQUARE_FACING
			)
		_:
			if direct_for_yaw(yaw) != int(direct):
				return false
			return d.length() <= reach if reach_inclusive else d.length() < reach


func get_interactions(ctx: InteractionContext) -> Array[Interaction]:
	var actor := ctx.actor as Node3D if ctx != null else null
	if actor == null or not actor.has_method("facing_yaw"):
		return []
	if not can_talk(actor.global_position, float(actor.call("facing_yaw"))):
		return []
	return [Interaction.of(Interaction.TALK, "Read", 20)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK:
		return false
	var ui := DialogueOverlay.find(get_tree())
	var talk := ExhibitTalk.new()
	talk.entries = entries
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % talk.start_msg()))
	if ui == null or data == null:
		return false
	var ctx_d: DialogueContext = DialogueContext.from_game()
	ctx_d.speaker_name = ""
	ctx_d.voice_mode = DialogueVoice.Mode.CLICK
	ctx_d.window_color = WINDOW_COLOR
	talk.context = ctx_d
	var player := ctx.actor as Player if ctx != null else null
	var open := [true]
	ui.closed.connect(func() -> void: open[0] = false, CONNECT_ONE_SHOT)
	ui.play(data, ctx_d, null, Callable(), talk)
	while open[0] and is_inside_tree() and player != null and is_instance_valid(player):
		var dt: float = get_process_delta_time()
		var target: float = PI
		if turn_toward_point:
			var to := global_position - player.global_position
			target = atan2(to.x, to.z)
		player.set_facing(
			MathUtil.short_angle2(
				player.facing_yaw(), target, turn_fraction, turn_max_step, 0.0, dt * DecompTime.TICK_HZ
			)
		)
		await get_tree().process_frame
	return true


## `Museum_*_GetMsgNo` / the fossil and picture talk: every page names the piece and its donor;
## a page with more to come asks to read on.
class ExhibitTalk extends BankTalk:
	const MSG_DONATED := 12191
	const MSG_FORMER := 12192
	const MSG_EMPTY := 12193
	const MSG_DONATED_MORE := 12194
	const MSG_FORMER_MORE := 12195

	var entries: Array[Dictionary] = []
	var page: int = 0

	func start_msg() -> int:
		return MSG_EMPTY if entries.is_empty() else msg_for(0)

	## `insect_caught_by` 1–4 is a resident; anyone else (moved away) gets the former-resident page.
	func msg_for(index: int) -> int:
		var resident: bool = _resident_slot(index) >= 0
		if index < entries.size() - 1:
			return MSG_DONATED_MORE if resident else MSG_FORMER_MORE
		return MSG_DONATED if resident else MSG_FORMER

	func entered(msg_no: int) -> void:
		if msg_no == MSG_EMPTY or page >= entries.size() or context == null:
			return
		context.set_item_str(0, PoliceTalk.with_article(str(entries[page].get("name", ""))))
		var slot: int = _resident_slot(page)
		if slot >= 0:
			while context.frees.size() < 1:
				context.frees.append("")
			context.frees[0] = Game.roster.name_of(slot)

	func picked(msg_no: int, index: int) -> int:
		if (msg_no == MSG_DONATED_MORE or msg_no == MSG_FORMER_MORE) and index == 0:
			page += 1
			return msg_for(page)
		return -1

	func _resident_slot(index: int) -> int:
		var donor: int = int(entries[index].get("donor", MuseumBook.Donator.NONE))
		if donor >= MuseumBook.Donator.PLAYER1 and donor <= MuseumBook.Donator.PLAYER4:
			return donor - MuseumBook.Donator.PLAYER1
		return -1
