class_name TownSpace
extends RefCounted

## Decomp field coordinates (GX) for the generated town. The decomp field is 7 blocks wide
## with a one-block border ring; our `WorldData` covers the 5×6 FG blocks, centred on the
## origin. Block (bx, bz) spans GX `[bx·640, bx·640 + 640)`.

const BLOCK_GX := 640.0
const BORDER_GX := 640.0


static func gx_to_world(gx: Vector3) -> Vector3:
	return _origin() + Vector3(
		(gx.x - BORDER_GX) * FieldCatalog.GX_TO_METERS,
		gx.y * FieldCatalog.GX_TO_METERS,
		(gx.z - BORDER_GX) * FieldCatalog.GX_TO_METERS
	)


static func world_to_gx(world: Vector3) -> Vector3:
	var local: Vector3 = (world - _origin()) / FieldCatalog.GX_TO_METERS
	return Vector3(local.x + BORDER_GX, local.y, local.z + BORDER_GX)


## `mFI_Wpos2BlockNum`.
static func block_of(gx: Vector3) -> Vector2i:
	return Vector2i(floori(gx.x / BLOCK_GX), floori(gx.z / BLOCK_GX))


## `mFI_BkNum2WposXZ`: the block's north-west corner.
static func block_base(block: Vector2i) -> Vector2:
	return Vector2(block.x * BLOCK_GX, block.y * BLOCK_GX)


## The player is outdoors in a generated town (the only place with decomp field blocks).
static func is_outdoor_town() -> bool:
	return Game.world_mode == WorldData.Mode.GENERATED and Game.current_room_id == &""


static func _origin() -> Vector3:
	var size_x: float = float(WorldGenerator.FG_X * WorldGenerator.UT) * 2.0
	var size_z: float = float(WorldGenerator.FG_Z * WorldGenerator.UT) * 2.0
	return Vector3(-size_x * 0.5, 0.0, -size_z * 0.5)
