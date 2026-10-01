extends StaticBody3D

## The wishing well (`ac_shrine`). Speak to it from the front (within 22.5° of where it faces,
## `aSHR_talk_check`) for `WishingWellTalk`: the town's rating, or a quest item thrown in.
## A town perfect for fifteen days running calls up the well's spirit with the golden axe
## (`aSHR_make_hem` → `ac_npc_hem`).

## `aSHR_set_talk_info`: no name, a terracotta window.
const WINDOW_COLOR := Color8(205, 80, 40)
const FRONT_CONE := deg_to_rad(22.5)

@export var occupant_id: StringName = &"wishing_well"
@export var footprint: Vector2i = Vector2i(2, 2)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.BUILDING
@export var visual_id: StringName = &"obj_s_shrine"
@export var label: String = "Wishing Well"
@export var door_verb: StringName = &""

var _talk: WishingWellTalk


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("wishing_well")
	GeneratedVisual.attach(self, visual_id)
	HostCollision.apply_building(self, visual_id, footprint, HostCollision.CELL)


func apply_grid_yaw(facing: WorldGrid.Facing) -> void:
	rotation.y = WorldGrid.yaw_for_facing(facing)


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, visual_id)


func _in_front(actor: Node3D) -> bool:
	if actor == null:
		return true
	var to: Vector3 = actor.global_position - global_position
	var yaw_to: float = atan2(to.x, to.z)
	return absf(wrapf(yaw_to - global_rotation.y, -PI, PI)) < FRONT_CONE


func get_interactions(ctx: InteractionContext) -> Array[Interaction]:
	if _talk != null or (ctx != null and not _in_front(ctx.actor as Node3D)):
		return []
	return [Interaction.of(Interaction.TALK, "Talk to the wishing well", 14)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK or _talk != null:
		return false
	var ui := DialogueOverlay.find(get_tree())
	if ui == null:
		return false
	var world: Node = ctx.world if ctx != null and ctx.world != null else World.find(get_tree())
	_talk = WishingWellTalk.new(world, Game.inventory)
	var dctx: DialogueContext = DialogueContext.from_game()
	dctx.speaker_name = ""
	dctx.voice_mode = DialogueVoice.Mode.CLICK
	dctx.window_color = WINDOW_COLOR
	_talk.context = dctx
	_talk.prepare()
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % _talk.start_msg()))
	if data == null:
		_talk = null
		return false
	if ui.is_open():
		ui.close()
	var player: Node3D = ctx.actor as Node3D if ctx != null else null
	ui.play(data, dctx, null, Callable(), _talk)
	var runner: DialogueRunner = ui.runner()
	if runner != null:
		runner.action_requested.connect(
			func(step: Dictionary) -> void: TalkActions.handle(step, ui, self, player)
		)
	await ui.closed
	var summon: bool = _talk.summon_spirit
	_talk = null
	if summon:
		WellSpirit.appear(self, player)
	return true
