class_name TownSpace
extends RefCounted

## The decomp's field frame for the generated town, in metres: a "field position" is measured
## from the north-west corner of the decomp field, which is 7 blocks wide with a one-block
## border ring. Our `WorldData` covers the 5×6 FG blocks, centred on the origin. Block (bx, bz)
## spans `[bx·BLOCK, bx·BLOCK + BLOCK)`. Decomp field coordinates (GX) convert with
## `FieldCatalog.GX_TO_METERS` where they are written, then come through `field_to_world`.

## 640 GX.
const BLOCK := 32.0
const BORDER := 32.0


static func field_to_world(field: Vector3) -> Vector3:
	return _origin() + field - Vector3(BORDER, 0.0, BORDER)


static func world_to_field(world: Vector3) -> Vector3:
	return world - _origin() + Vector3(BORDER, 0.0, BORDER)


## `mFI_Wpos2BlockNum`.
static func block_of(field: Vector3) -> Vector2i:
	return Vector2i(floori(field.x / BLOCK), floori(field.z / BLOCK))


## The decomp block a `WorldGrid` cell is in: our grid starts at FG block (1, 1).
static func block_of_cell(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(cell.x / 16.0), floori(cell.y / 16.0)) + Vector2i.ONE


## `mFI_BkNum2WposXZ`: the block's north-west corner.
static func block_base(block: Vector2i) -> Vector2:
	return Vector2(block.x * BLOCK, block.y * BLOCK)


## The player is outdoors in a generated town (the only place with decomp field blocks).
static func is_outdoor_town() -> bool:
	return Game.town.world_mode == WorldData.Mode.GENERATED and Game.current_room_id == &""


static func _origin() -> Vector3:
	var size_x: float = float(WorldGenerator.FG_X * WorldGenerator.UT) * 2.0
	var size_z: float = float(WorldGenerator.FG_Z * WorldGenerator.UT) * 2.0
	return Vector3(-size_x * 0.5, 0.0, -size_z * 0.5)
