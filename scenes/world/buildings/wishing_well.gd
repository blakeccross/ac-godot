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
## Busy with a New Year's visit (`ac_hatumode_control`).
var _visiting: bool = false

const NEW_YEAR := &"new_years_day"
## `aHTC_request`: "Will you throw money into the wishing well?" with 50 Bells, else
## straight to "That is acceptable…"; Yes → "Thank you." (`mSP_get_sell_price(50)`).
const MSG_ASK := 4396
const MSG_THANKS := 4397
const MSG_NO_MONEY := 4398
const OFFERING := 50
## `aHTC_set_talk_info_local`: no name, a red window.
const NEW_YEAR_WINDOW := Color8(255, 60, 40)
## `aHTC_inori` / `aHTC_saisen`: the player stands 20 GX across and 85 out from the well's
## anchor unit — the middle of its front, 65 GX out from the centre — facing it.
const VISIT_STAND_GX := 65.0


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
	if _visiting:
		return []
	## With villagers queueing, a wish is made by taking a place in the line
	## (`aHTC_wait` only starts on the queue's signal).
	if ShrineQueue.members > 0 and Game.events != null and Game.events.is_active(NEW_YEAR):
		return []
	if _talk != null or (ctx != null and not _in_front(ctx.actor as Node3D)):
		return []
	return [Interaction.of(Interaction.TALK, "Talk to the wishing well", 14)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK or _talk != null:
		return false
	var ui := DialogueOverlay.find(get_tree())
	if ui == null:
		return false
	if Game.events != null and Game.events.is_active(NEW_YEAR):
		return await _new_year_visit(ui, ctx)
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


## Where the player stands to make a New Year's wish, and the way they face.
func visit_stand() -> Array:
	var fwd := Vector3(sin(global_rotation.y), 0.0, cos(global_rotation.y))
	var stand: Vector3 = global_position + fwd * VISIT_STAND_GX * FieldCatalog.GX_TO_METERS
	return [stand, atan2(-fwd.x, -fwd.z)]


## `ac_hatumode_control`: the New Year's offering. With 50 Bells the well asks; paying throws
## a coin in before the prayer, declining (or too little) prays without.
func _new_year_visit(ui: DialogueOverlay, ctx: InteractionContext) -> bool:
	return await offer_wish(ui, ctx.actor as Player if ctx != null else null)


## `aHTC_request` … `aHTC_inori_end` for `player` standing at the well (also the queue's
## turn for a player let in by a villager).
func offer_wish(ui: DialogueOverlay, player: Player) -> bool:
	_visiting = true
	var inv: Inventory = Game.inventory
	var can_pay: bool = inv != null and inv.wallet >= OFFERING
	var dctx: DialogueContext = DialogueContext.from_game()
	dctx.speaker_name = ""
	dctx.voice_mode = DialogueVoice.Mode.CLICK
	dctx.window_color = NEW_YEAR_WINDOW
	var data: DialogueData = DialogueCatalog.conversation(
		StringName("msg_%d" % (MSG_ASK if can_pay else MSG_NO_MONEY))
	)
	if data == null:
		_visiting = false
		return false
	if ui.is_open():
		ui.close()
	ui.play(data, dctx)
	var runner: DialogueRunner = ui.runner()
	await ui.closed
	var toss: bool = can_pay and runner != null and runner.last_choice_index == 0
	if toss:
		inv.set_wallet(inv.wallet - OFFERING)
	if player != null and is_instance_valid(player):
		var stand: Array = visit_stand()
		var at: Vector3 = stand[0]
		at.y = player.global_position.y
		await player.shrine_visit(at, float(stand[1]), toss, global_position.y)
	_visiting = false
	return true

