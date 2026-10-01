extends StaticBody3D

## A finished snowman (`ac_psnowman`): the body ball with the head on top at
## `0.6 × (r_body + r_head)`. Talk to it for its line (`MSG_2209 + …`, by how well it was
## made). Keep walking into it and it topples (`mRlib_PSnowmanBreakCheck`: the push builds
## up past 200), which also counts against a snowman request in that acre.

const BODY_VISUAL := &"act_darumaB"
const HEAD_VISUAL := &"act_darumaA"
const BREAK_AT := 200.0
## Scale relative to `GeneratedVisual`'s 0.01 actor draw (see `snowball.gd`).
const VISUAL_PER_SCALE := 100.0
const SWING_AT := 20.0
## `mRlib_PSnowmanTouchCheck`: within one unit either way.
const TOUCH := 40.0 * SnowmanRules.GX
## `aPSM_actor_draw` tilts the head forward (`0xF380`).
const HEAD_TILT := -0x0C80 * TAU / 65536.0

@export var occupant_id: StringName = &""
@export var slot: int = -1
@export var head: float = 0.5
@export var body: float = 0.5
@export var score: int = SnowmanRules.Result.OK

var _push: float = 0.0
var _steps := FrameStepper.new(DecompTime.TICK_HZ, 8.0)
var _head: Node3D
var _talking: bool = false
var _down: bool = false


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("snowman")
	var rb: float = SnowmanRules.radius_m(body)
	var rh: float = SnowmanRules.radius_m(head)
	var body_node := $Body as Node3D
	body_node.position.y = rb
	body_node.scale = Vector3.ONE * SnowmanRules.actor_scale(body) * VISUAL_PER_SCALE
	GeneratedVisual.attach(body_node, BODY_VISUAL)
	_head = $Head as Node3D
	_head.position.y = rb + (rh + rb) * 0.6
	_head.rotation.x = HEAD_TILT
	_head.scale = Vector3.ONE * SnowmanRules.actor_scale(head) * VISUAL_PER_SCALE
	GeneratedVisual.attach(_head, HEAD_VISUAL)
	## Sized to this snowman: its own copies of the shapes.
	var col := $CollisionShape3D as CollisionShape3D
	var shape := (col.shape as CylinderShape3D).duplicate() as CylinderShape3D
	shape.radius = rb
	shape.height = rb * 2.0 + rh * 2.0
	col.shape = shape
	col.position.y = shape.height * 0.5
	var vcol := $InteractVolume/CollisionShape3D as CollisionShape3D
	var box := (vcol.shape as BoxShape3D).duplicate() as BoxShape3D
	box.size = Vector3(rb * 2.0 + 0.6, 1.4, rb * 2.0 + 0.6)
	vcol.shape = box


func message() -> int:
	return SnowmanRules.snowman_msg(Game.snowman_msg_id, maxi(slot, 0), score)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if _talking or _down:
		return []
	return [Interaction.of(Interaction.TALK, "Talk to the snowman", 12)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK or _talking or _down:
		return false
	say(message(), ctx.actor as Node3D if ctx != null else null)
	return true


## One of the snowman's lines (`mDemo_Set_msg_num`).
func say(msg: int, player: Node3D = null) -> void:
	var ui := DialogueOverlay.find(get_tree())
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % msg))
	if ui == null or data == null:
		return
	if ui.is_open():
		ui.close()
	_talking = true
	var dctx: DialogueContext = DialogueContext.from_game()
	dctx.speaker_name = "Snowman"
	if player != null and player.has_method("begin_talk_face"):
		player.call("begin_talk_face", self)
	ui.play(data, dctx)
	await ui.closed
	if player != null and is_instance_valid(player) and player.has_method("end_talk_face"):
		player.call("end_talk_face")
	_talking = false


func _physics_process(delta: float) -> void:
	if _down or _talking:
		return
	var player := Player.find(get_tree())
	if player == null:
		return
	_steps.add(delta)
	while _steps.next():
		if _break_tick(player):
			topple()
			return
	if _head != null:
		_head.rotation.z = sin(Time.get_ticks_msec() * 0.02) * 0.15 if _push > SWING_AT else lerpf(_head.rotation.z, 0.0, 0.2)


## `mRlib_PSnowmanBreakCheck` for one tick.
func _break_tick(player: Player) -> bool:
	var d: Vector3 = global_position - player.global_position
	if absf(d.x) < TOUCH and absf(d.z) < TOUCH and absf(d.y) < TOUCH:
		var dir := Vector2(d.x, d.z)
		if dir.length() > 0.001:
			var want := Vector2(player.move_intent.x, player.move_intent.z) * PlayerLocomotion.ORIG_WALK
			var into: float = dir.normalized().dot(want)
			if into > 0.0:
				_push += into * 0.5
			else:
				_push = _calc0(_push)
			return _push > BREAK_AT
	_push = _calc0(_push)
	return false


## `add_calc0(speed, 1 − √0.7, 10)`.
static func _calc0(v: float) -> float:
	var step: float = clampf(v * (1.0 - sqrt(0.7)), -10.0, 10.0)
	return v - step


## `aPSMAN_MakeBreakEffect`: it falls apart and the slot is free again.
func topple() -> void:
	if _down:
		return
	_down = true
	var world := World.find(get_tree())
	var cell: Vector2i = world.grid.world_to_cell(global_position) if world != null and world.grid != null else Vector2i.ZERO
	SnowmanUse.knocked_down(slot, cell, world)
	var t := create_tween()
	t.set_parallel(true)
	for child: Node in get_children():
		if child is Node3D and not child is CollisionShape3D and not child is Area3D:
			t.tween_property(child, "scale", (child as Node3D).scale * 0.01, 0.25)
	t.chain().tween_callback(queue_free)
