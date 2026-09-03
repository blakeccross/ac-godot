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
## Walk into the sensor to enter (museum). No A prompt while open.
@export var auto_enter: bool = false
## Optional decomp spawn when following `linked_room_id`.
@export var has_linked_spawn: bool = false
@export var linked_spawn_gx: Vector3 = Vector3.ZERO
@export var linked_spawn_yaw: float = 0.0


func _ready() -> void:
	add_to_group("interactable")


func should_auto_enter() -> bool:
	## Outdoor museum / indoor museum wing links: walk in, no A prompt.
	if not auto_enter:
		return false
	## Just spawned on/near a door — wait until the player walks clear.
	if Game.block_auto_enter_doors:
		return false
	if Game.is_indoors():
		return linked_room_id != &""
	var target: StringName = _enter_target()
	if target == &"":
		return false
	var room_id: StringName = InteriorCatalog.resolve_entry(target)
	if room_id == &"":
		return false
	var room: Room = Game.interiors.room(room_id)
	return room != null and InteriorCatalog.is_open_now(room)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	## Outdoor exit is a walk-on warp (`EXIT_DOOR`); no A prompt.
	if Game.is_indoors() and exits_interior:
		return []
	## Open auto-enter (outdoor museum or indoor wing link): silent verb so the probe
	## still finds us; player walks in without an E prompt.
	if should_auto_enter():
		return [Interaction.of(Interaction.ENTER, "", 20)]
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
		await _play_indoor_link_enter()
		var entered: bool = false
		if has_linked_spawn:
			entered = Game.try_enter_interior(linked_room_id, linked_spawn_gx, linked_spawn_yaw)
		else:
			entered = Game.try_enter_interior(linked_room_id)
		if entered:
			await _play_indoor_arrive()
		return entered
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


func _play_indoor_link_enter() -> void:
	## Wing doors have no structure cKF — walk INTO_S1 into the sensor like outdoor museum.
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		return
	if not player.has_method("begin_door_enter"):
		return
	var target := Vector3(global_position.x, player.global_position.y, global_position.z)
	var to: Vector3 = target - player.global_position
	to.y = 0.0
	var yaw: float = atan2(to.x, to.z) if to.length_squared() > 0.0001 else 0.0
	player.call("begin_door_enter", target, yaw, true)
	if player.has_method("await_door_enter"):
		await player.call("await_door_enter")
	if player.has_method("end_door_enter"):
		player.call("end_door_enter")


## After the wing load, keep walking INTO_S1 past the door so exit sensors stay clear.
func _play_indoor_arrive() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		return
	if not player.has_method("begin_door_enter"):
		return
	Game.block_auto_enter_doors = true
	var yaw: float = (
		float(player.call("facing_yaw"))
		if player.has_method("facing_yaw")
		else (player as Node3D).rotation.y
	)
	var along := Vector3(sin(yaw), 0.0, cos(yaw))
	var from: Vector3 = (player as Node3D).global_position
	var target: Vector3 = from + along * (StructureDoor.INTO_GX * FieldCatalog.GX_TO_METERS)
	target.y = from.y
	player.call("begin_door_enter", target, yaw, true)
	if player.has_method("await_door_enter"):
		await player.call("await_door_enter")
	if player.has_method("end_door_enter"):
		player.call("end_door_enter")


func _enter_target() -> StringName:
	if occupant_id != &"":
		return occupant_id
	var parent: Node = get_parent()
	if parent != null and "occupant_id" in parent:
		var from_parent: StringName = parent.get("occupant_id") as StringName
		if from_parent != &"":
			return from_parent
	return &""
