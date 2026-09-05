extends StaticBody3D

## Outdoor house shell. Villager homes use `obj_s_house1` (`ac_house`);
## the player house placement sets `obj_s_myhome1` (`ac_my_house`).
##
## Door rest yaw is baked into the GLB (joint-0). `apply_grid_yaw` only applies
## world `mesh_facing` (east 0 / west +90° from AC `angle_table`) — do not add
## extra orientation fixes here.

@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(2, 2)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.BUILDING
@export var visual_id: StringName = &"obj_s_house1"


func _ready() -> void:
	add_to_group("interactable")
	GeneratedVisual.attach(self, visual_id)
	HostCollision.apply_house(self, visual_id, footprint, HostCollision.CELL)


func apply_grid_yaw(facing: WorldGrid.Facing) -> void:
	rotation.y = WorldGrid.yaw_for_facing(facing)


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, visual_id)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	return [Interaction.of(Interaction.ENTER, "Enter house", 12)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.ENTER:
		return false
	var entry_id: StringName = occupant_id
	if entry_id == &"":
		entry_id = StringName(name)
	## Vacant myhome shells during station intro house pick — Nook speaks first.
	if (
		Game.intro_station_active
		and Game.intro_station_can_pick_house
		and String(name).begins_with("player_house")
	):
		Game.request_intro_house_look(StringName(name))
		return true
	elif Game.intro_station_active and not Game.intro_station_can_pick_house:
		if Game.intro_pending_house_id != &"":
			return true
		Game.post_notice("Talk to Tom Nook first.")
		return true
	if entry_id == &"":
		Game.post_notice("The door is locked.")
		return true
	## Villager homes: `aHUS_odekake_check` — sleep / not home / enter.
	var gate: String = VillagerHome.door_notice(entry_id)
	if gate != "":
		Game.post_notice(gate)
		return true
	var room_id: StringName = InteriorCatalog.resolve_entry(entry_id)
	if room_id == &"":
		Game.post_notice("The door is locked.")
		return true
	var room: Room = Game.interiors.room(room_id)
	## Closed hours: notice only, no door swing.
	if room != null and not InteriorCatalog.is_open_now(room):
		return Game.try_enter_interior(entry_id)
	await StructureDoor.play_enter(self)
	return Game.try_enter_interior(entry_id)
