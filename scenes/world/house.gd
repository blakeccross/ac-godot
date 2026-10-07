extends StaticBody3D

## Outdoor house shell. Villager homes use `obj_s_house{1-5}_{a-e}` (`ac_house`);
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
@export var visual_id: StringName = &"obj_s_house1_a"


func _ready() -> void:
	add_to_group("interactable")
	visual_id = PlayerHouse.exterior_visual(String(name), visual_id)
	GeneratedVisual.attach(self, visual_id)
	PlayerHouse.apply_exterior_decorations(self)
	HostCollision.apply_house(self, visual_id, footprint, HostCollision.CELL)
	## A redrawn design repaints the door it is posted on.
	if Game != null and not Game.design_changed.is_connected(_on_design_changed):
		Game.design_changed.connect(_on_design_changed)


func _exit_tree() -> void:
	if Game != null and Game.design_changed.is_connected(_on_design_changed):
		Game.design_changed.disconnect(_on_design_changed)


func _on_design_changed() -> void:
	PlayerHouse.apply_exterior_decorations(self)


func apply_grid_yaw(facing: WorldGrid.Facing) -> void:
	rotation.y = WorldGrid.yaw_for_facing(facing)


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, visual_id)
	PlayerHouse.apply_exterior_decorations(self)


## `ac_nameplate`: the signboard on the south-west unit of a villager's 3×3 plot
## (`mNpc_BuildHouseBeforeFieldct`, `ACTOR_PROP_VILLAGER_SIGNBOARD`), read from the south.
const NAMEPLATE_MSG := 4969
const NAMEPLATE_COLOR := Color8(205, 120, 0)


func get_interactions(ctx: InteractionContext) -> Array[Interaction]:
	if _facing_nameplate(ctx):
		return [Interaction.of(Interaction.READ, "Read sign", 13)]
	return [Interaction.of(Interaction.ENTER, "Enter house", 12)]


func nameplate_cell(grid: WorldGrid) -> Vector2i:
	if grid == null or not String(name).begins_with("npc_house_"):
		return Vector2i(-1, -1)
	var cells: Array[Vector2i] = grid.cells_of(StringName(name))
	if cells.is_empty():
		cells = grid.cells_of(occupant_id)
	if cells.is_empty():
		return Vector2i(-1, -1)
	var corner := Vector2i(cells[0].x, cells[0].y)
	for c: Vector2i in cells:
		corner.x = mini(corner.x, c.x)
		corner.y = maxi(corner.y, c.y)
	return corner


## `aNP_actor_move`: the player south of the sign, within 45° of straight in front.
func _facing_nameplate(ctx: InteractionContext) -> bool:
	if ctx == null or ctx.actor == null or ctx.world == null or not "grid" in ctx.world:
		return false
	var grid: WorldGrid = ctx.world.get("grid") as WorldGrid
	var plate: Vector2i = nameplate_cell(grid)
	if plate.x < 0 or ToolUse.facing_cell(ctx) != plate:
		return false
	var to_player: Vector3 = (ctx.actor as Node3D).global_position - grid.cell_to_world(plate)
	return to_player.z >= 0.0 and absf(atan2(to_player.x, to_player.z)) < PI / 4.0


func _read_nameplate() -> bool:
	var entry: StringName = occupant_id if occupant_id != &"" else StringName(name)
	var villager: VillagerData = VillagerCatalog.get_villager(VillagerHome.villager_of(entry))
	var who: String = villager.display_name if villager != null else ""
	if who == "":
		return false
	var ui := DialogueOverlay.find(get_tree())
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % NAMEPLATE_MSG))
	if ui == null or data == null:
		Game.post_notice("%s's house" % who)
		return true
	var ctx: DialogueContext = DialogueContext.from_game()
	ctx.speaker_name = ""
	ctx.voice_mode = DialogueVoice.Mode.CLICK
	ctx.window_color = NAMEPLATE_COLOR
	ctx.frees = PackedStringArray([who])
	ui.play(data, ctx)
	return true


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action != null and action.id == Interaction.READ:
		return _read_nameplate()
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
	## Player plots: your own house, another resident's (their rooms stand in while you are
	## inside), or a vacant one, which stays shut.
	if String(name).begins_with(String(PlayerHouse.DEFAULT_PLOT)):
		var slot: int = Game.roster.slot_on_plot(StringName(name))
		if slot < 0:
			Game.post_notice("The door is locked.")
			return true
		if slot != Game.roster.current:
			Game.enter_resident_house(slot)
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
	if Game.try_enter_interior(entry_id):
		return true
	StructureDoor.end_enter(self)
	Game.leave_resident_house()
	return false
