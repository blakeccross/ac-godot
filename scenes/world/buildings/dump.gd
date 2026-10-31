class_name Dump
extends StaticBody3D

## The dump (`ac_dump`): a walled yard at the end of the train-track acre with one gap in its
## south wall. Walking the walls is the heightfield (`StructureOffset._apply_dump`), not a hull.
## From the south, within 45° of straight on and not behind its origin line (`aDUM_wait`), its
## sign can be read: `MSG_4970`, in a terracotta window with no name.

const MSG_SIGN := 4970
const WINDOW_COLOR := Color8(185, 60, 40)
const FRONT_CONE := deg_to_rad(45.0)  ## `ABS(player_angle_y) < 0x2000`

@export var occupant_id: StringName = &"dump"
@export var footprint: Vector2i = Vector2i(6, 6)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.BUILDING
@export var visual_id: StringName = &"obj_s_dump"
@export var label: String = "Dump"
@export var door_verb: StringName = &""

var _reading: bool = false


func _ready() -> void:
	add_to_group("interactable")
	GeneratedVisual.attach(self, visual_id)
	HostCollision.apply_building(self, visual_id, footprint, HostCollision.CELL)


func apply_grid_yaw(facing: WorldGrid.Facing) -> void:
	rotation.y = WorldGrid.yaw_for_facing(facing)


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, visual_id)


## `aDUM_wait`: the player is south of the dump's origin and it is within 45° of its front.
func _faces(actor: Node3D) -> bool:
	if actor == null:
		return true
	var to: Vector3 = actor.global_position - global_position
	if to.z < 0.0:
		return false
	return absf(wrapf(atan2(to.x, to.z) - global_rotation.y, -PI, PI)) < FRONT_CONE


func get_interactions(ctx: InteractionContext) -> Array[Interaction]:
	if _reading or (ctx != null and not _faces(ctx.actor as Node3D)):
		return []
	return [Interaction.of(Interaction.READ, "Read sign", 6)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.READ or _reading:
		return false
	var ui := DialogueOverlay.find(get_tree())
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % MSG_SIGN))
	if ui == null or data == null:
		return false
	_reading = true
	var dctx: DialogueContext = DialogueContext.from_game()
	dctx.speaker_name = ""
	dctx.voice_mode = DialogueVoice.Mode.CLICK
	dctx.window_color = WINDOW_COLOR
	if ui.is_open():
		ui.close()
	ui.play(data, dctx)
	await ui.closed
	_reading = false
	return true
