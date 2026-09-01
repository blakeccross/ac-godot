extends Node3D

## Door / entrance sensor. Compose under a building or place as its own world object.
## Outdoor: enter the mapped interior. Indoor: leave or walk to a linked room.

@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i.ONE
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = false
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.FURNITURE
@export var label: String = "Door"
@export var verb: StringName = &"enter"
@export var closed_notice: String = "The door is locked."
@export var linked_room_id: StringName = &""
@export var exits_interior: bool = false


func _ready() -> void:
	add_to_group("interactable")


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	## Outdoor exit is a walk-on warp (`EXIT_DOOR`); no A prompt.
	if Game.is_indoors() and exits_interior:
		return []
	if Game.is_indoors() and linked_room_id != &"":
		return [Interaction.of(Interaction.ENTER, "Enter %s" % label, 12)]
	var prompt: String = "Enter %s" % label if verb == Interaction.ENTER else String(verb).capitalize()
	if verb == Interaction.SHOP:
		prompt = "Shop"
	return [Interaction.of(verb, prompt, 12)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null:
		return false
	if Game.is_indoors() and exits_interior:
		## Walk-exit is the normal path; keep A as a fallback.
		if action.id != Interaction.ENTER:
			return false
		return Game.exit_interior()
	if Game.is_indoors() and linked_room_id != &"":
		if action.id != Interaction.ENTER:
			return false
		return Game.try_enter_interior(linked_room_id)
	if action.id != verb:
		return false
	if verb == Interaction.SHOP:
		if not Clock.in_hour_window(9, 22):
			Game.post_notice("The shop is closed.")
			return false
		var shop_target: StringName = _enter_target()
		if shop_target != &"":
			await StructureDoor.play_enter(self)
			if Game.try_enter_interior(shop_target):
				return true
			if InteriorCatalog.resolve_entry(shop_target) != &"":
				return false
		Game.post_notice("The shop is open.")
		return true
	var target: StringName = _enter_target()
	if target != &"":
		if InteriorCatalog.resolve_entry(target) == &"":
			Game.post_notice(closed_notice)
			return true
		await StructureDoor.play_enter(self)
		if Game.try_enter_interior(target):
			return true
		if InteriorCatalog.resolve_entry(target) != &"":
			return false
	Game.post_notice(closed_notice)
	return true


func _enter_target() -> StringName:
	if occupant_id != &"":
		return occupant_id
	var parent: Node = get_parent()
	if parent != null and "occupant_id" in parent:
		var from_parent: StringName = parent.get("occupant_id") as StringName
		if from_parent != &"":
			return from_parent
	return &""
