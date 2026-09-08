extends StaticBody3D

## The player's house mailbox (`ac_mailbox` / `ACTOR_PROP_MAILBOX0`). Delivered letters
## land in `Inventory._mail` with a `RECV*` font; this is where the player reads them.

## `obj_s_post` / `obj_w_post` (`ac_mailbox`): box + post + raiseable flag, seasonal pair.
@export var occupant_id: StringName = &"player"
@export var footprint: Vector2i = Vector2i(1, 1)
## Compass direction the mail slot / flag face (where the player stands to read it).
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.NORTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.FURNITURE
@export var visual_id: StringName = &"obj_s_post"

## `obj_s_post` rest pose points the slot at −X; offset so `grid_facing` reads as "slot dir".
const SLOT_REST_OFFSET := -PI * 0.5

var _has_mesh: bool = false


func _ready() -> void:
	add_to_group("interactable")
	apply_grid_yaw(grid_facing)
	if visual_id != &"" and not FieldCatalog.mesh_paths(visual_id).is_empty():
		GeneratedVisual.attach(self, visual_id)
		_has_mesh = true
		var placeholder: Node = get_node_or_null("Post")
		if placeholder != null:
			placeholder.queue_free()
		var box_mesh: Node = get_node_or_null("Box")
		if box_mesh != null:
			box_mesh.queue_free()
	HostCollision.apply_box(self, footprint, HostCollision.CELL, 1.0)


func apply_grid_yaw(facing: WorldGrid.Facing) -> void:
	grid_facing = facing
	rotation.y = WorldGrid.yaw_for_facing(facing) + SLOT_REST_OFFSET


func refresh_seasonal_visual() -> void:
	if _has_mesh:
		GeneratedVisual.refresh(self, visual_id)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	var label := "Check mailbox"
	if Game != null and Game.inventory != null and Game.inventory.unread_mail_count() > 0:
		label = "Read mail (%d)" % Game.inventory.unread_mail_count()
	return [Interaction.of(Interaction.READ, label, 10)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.READ or Game == null:
		return false
	var inv: Inventory = Game.inventory
	if inv == null or inv.received_mail_count() <= 0:
		Game.post_notice("The mailbox is empty.")
		return true
	var ui: Node = get_tree().get_first_node_in_group("inventory_ui") if get_tree() != null else null
	if ui != null and ui.has_method("open_letters"):
		ui.call("open_letters")
	else:
		Game.post_notice("You have %d letter(s). Check your Letters page." % inv.received_mail_count())
	return true
