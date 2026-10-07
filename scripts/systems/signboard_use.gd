class_name SignboardUse
extends RefCounted

## The signboard from Nook's (`ITM_SIGNBOARD`, `ac_sign`). Put down outside it stands up as a
## blank white sign (`aSIGN_set_white_sign`, `RSV_SIGNBOARD`); talked to it offers to post one
## of the player's designs (msg 12388 → the design list, `aSIGN_change_my_original`); picked up
## it goes back in the pockets (`aSIGN_erase_white_sign`). Visitors may not change it (12389).
## Not an autoload.
##
## `Game.signboards`: `signboard_<x>_<z>` → `{design}` (the posted design's save, or `{}`).
## The original draws the owner's live `my_org` slot; the port keeps a copy of what was posted.

const ITEM_ID := &"signboard"
const SCENE := "res://scenes/world/signboard.tscn"
const GROUP := &"signboard"
const MSG_POST := 12388
const MSG_HANDS_OFF := 12389
const PREFIX := "signboard_"


static func persist_id(cell: Vector2i) -> StringName:
	return StringName("%s%d_%d" % [PREFIX, cell.x, cell.y])


static func cell_from_persist(id: StringName) -> Vector2i:
	var s := String(id)
	if not s.begins_with(PREFIX):
		return Vector2i(-1, -1)
	var parts: PackedStringArray = s.substr(PREFIX.length()).split("_")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


## Outdoors on open ground (`mTG_search_put_pos` with the signboard's own checks).
static func can_place(grid: WorldGrid, cell: Vector2i) -> bool:
	if grid == null or not grid.is_in_bounds(cell) or grid.is_occupied(cell):
		return false
	var t: WorldGrid.Terrain = grid.terrain_at(cell)
	return t == WorldGrid.Terrain.GRASS or t == WorldGrid.Terrain.SOIL or t == WorldGrid.Terrain.SAND


static func place(world: Node, cell: Vector2i) -> bool:
	var grid: WorldGrid = world.get("grid") as WorldGrid if world != null else null
	if not can_place(grid, cell):
		return false
	var pid: StringName = persist_id(cell)
	if not grid.place(pid, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.FURNITURE):
		return false
	Game.signboards[String(pid)] = {}
	_instance(world, grid, cell, pid)
	return true


static func design_of(pid: StringName) -> DesignPattern:
	var rec: Variant = Game.signboards.get(String(pid), {})
	if typeof(rec) != TYPE_DICTIONARY:
		return null
	var raw: Variant = (rec as Dictionary).get("design", {})
	if typeof(raw) != TYPE_DICTIONARY or (raw as Dictionary).is_empty():
		return null
	return DesignPattern.from_save(raw)


static func post(pid: StringName, design: DesignPattern) -> void:
	if not Game.signboards.has(String(pid)):
		return
	Game.signboards[String(pid)] = {"design": design.to_save() if design != null else {}}


## Back into the pockets: the record and the grid cell are freed.
static func take(world: Node, pid: StringName) -> void:
	Game.signboards.erase(String(pid))
	var grid: WorldGrid = world.get("grid") as WorldGrid if world != null else null
	if grid != null:
		grid.remove(pid)


static func restore(world: Node, grid: WorldGrid) -> void:
	if grid == null:
		return
	for key: Variant in Game.signboards.keys():
		var pid := StringName(str(key))
		var cell: Vector2i = cell_from_persist(pid)
		if not grid.is_in_bounds(cell) or (grid.is_occupied(cell) and grid.occupant_at(cell) != pid):
			Game.signboards.erase(key)
			continue
		if not grid.is_occupied(cell):
			grid.place(pid, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.FURNITURE)
		_instance(world, grid, cell, pid)


static func _instance(world: Node, grid: WorldGrid, cell: Vector2i, pid: StringName) -> void:
	if world == null:
		return
	var objects: Node = world.get_node_or_null("Objects")
	if objects == null or not ResourceLoader.exists(SCENE):
		return
	var host: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	host.set("occupant_id", pid)
	host.add_to_group(GROUP)
	objects.add_child(host)
	var pos: Vector3 = grid.cell_to_world(cell)
	if "layout" in world and world.layout != null:
		pos.y = FieldCollision.ground_y(world.layout as WorldData, cell, FieldCollision.FG_GROUND_DIST)
	host.global_position = pos
