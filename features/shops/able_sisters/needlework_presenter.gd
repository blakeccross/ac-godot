class_name NeedleworkPresenter
extends RefCounted

## Furnishes the Able Sisters interior. Its fixtures — the animated sewing machine and
## fabric, the 4 clothing mannequins + 4 umbrella stands, Mabel & Sable with their drop
## shadows, and the back-wall clock — are authored in `needlework.tscn`; this adds the
## solid hulls for the shell's baked west counter / east fabric boxes and the two
## window sunbeams, both read from room data.
##
## Decomp: `ac_needlework_indoor.c` (`manekin_pos` / `umbrella_pos`),
## `ac_npc_needlework.c` (sisters), `ac_misin.c` (machine + dustcloth),
## `HOUSE_CLOCK` / `obj_clock_tailor`, `ef_room_sunshine.c` (window beams, placed by
## `WindowSunshine`). The static machine body / table / register / boxes are baked into
## the `rom_tailor` shell.

## The decomp tables the scene's fixtures sit on (`ac_needlework_indoor.c`
## `manekin_pos` z=100, `umbrella_pos` z=180, 40 GX apart). `rom_tailor` keeps the acre
## origin, so these map straight through `gx_to_world`. (`y=40` in decomp is a
## model-draw offset; the displays stand on the floor.)
const MANNEQUIN: Array = [
	Vector3(180, 0, 100) * FieldCatalog.GX_TO_METERS, Vector3(220, 0, 100) * FieldCatalog.GX_TO_METERS, Vector3(260, 0, 100) * FieldCatalog.GX_TO_METERS, Vector3(300, 0, 100) * FieldCatalog.GX_TO_METERS,
]
const UMBRELLA: Array = [
	Vector3(180, 0, 180) * FieldCatalog.GX_TO_METERS, Vector3(220, 0, 180) * FieldCatalog.GX_TO_METERS, Vector3(260, 0, 180) * FieldCatalog.GX_TO_METERS, Vector3(300, 0, 180) * FieldCatalog.GX_TO_METERS,
]
## Sable sits north of the shell's baked machine (`_schedule.c_inc` x=87, z≈home.z+13,
## facing south); `NEEDLEWORK_MABEL_GX` is Mabel's roam home near the door.
const SABLE := Vector3(87, 0, 108) * FieldCatalog.GX_TO_METERS
const MABEL := Vector3(210, 0, 250) * FieldCatalog.GX_TO_METERS
## Back-wall pendulum clock centre (`needlework_clock.gd` recentres the AABB on the
## host). `aHC_position_data[SCENE_NEEDLEWORK]` is `{0,0,0}` (unplaced) in decomp.
const CLOCK := Vector3(200.0, 46.0, 46.0) * FieldCatalog.GX_TO_METERS


func present(root: Node3D, interior: IndoorSession) -> void:
	if root == null or interior == null or interior.grid == null:
		return
	_furniture_collision(root, interior.grid)
	WindowSunshine.add(root, interior.grid, interior.room)


## `misin_clip->request_misin_stop_proc` / `_dustcloth_stop_proc` (Sable stops sewing
## to talk, `aNNW_talk_init`) and the matching `_move_proc`s when she goes back to it.
static func set_machine_running(root: Node, on: bool) -> void:
	if root == null:
		return
	for node_name: String in ["SewingMachine", "SewingCloth"]:
		var node: Node = root.get_node_or_null(node_name)
		if node != null and "running" in node:
			node.set("running", on)


## Solid hulls for the `rom_tailor` BG's raised units: the counter, the sewing-machine
## table and fabric boxes along the west wall, and the boxes at (8,6). The units between
## them stay walkable, as in the original (Sable works from (2,2)).
func _furniture_collision(root: Node3D, grid: WorldGrid) -> void:
	InteriorUnitCollision.add_hulls(root, grid, "NeedleworkFurnitureCol", blocked_units())


## `rom_tailor.col.json` inside the shop floor (1,1)+(8,6): unit → height in GX.
static func blocked_units() -> Dictionary:
	return InteriorUnitCollision.blocked_from_bg(
		&"rom_tailor", FieldCatalog.LAND_COUNTS, FieldCatalog.HEIGHT_MAX, Rect2i(1, 1, 8, 6)
	)
