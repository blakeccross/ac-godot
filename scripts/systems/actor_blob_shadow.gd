class_name ActorBlobShadow
extends RefCounted

## Soft ground blob under moving actors. Behavioral stand-in for the original's circular
## actor shadow (`GetShadowBgY` + XLU oval). Field objects keep authored `*_shadow_v`
## meshes from convert; characters use the procedural shader instead.

## Player footprint under `boy_1` / the placeholder capsule — slightly longer along facing.
const PLAYER_EXTENT := Vector2(0.95, 0.72)
const PLAYER_ALPHA := 0.42
## Same 2 GX lift as footprints so the blob clears the acre plane without z-fighting.
const GROUND_LIFT := FootprintMarks.GROUND_LIFT


static func ground_transform(
	data: WorldData, grid: WorldGrid, pos: Vector3, yaw: float = 0.0
) -> Transform3D:
	## Reuse the footprint slope fit so the blob lies on hills with the same probe triangle.
	return FootprintMarks.mark_transform(data, grid, pos, yaw)


static func flat_transform(pos: Vector3, yaw: float = 0.0) -> Transform3D:
	## Indoors / no heightfield: keep the parent's Y and sit a hair above the floor.
	var origin := Vector3(pos.x, pos.y + GROUND_LIFT, pos.z)
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return Transform3D(Basis(right, Vector3.UP, forward), origin)


static func precip_alpha(base: float) -> float:
	## `mEnv` dims shadow energy by 0.75 while raining / snowing.
	if Weather.is_precip(Weather.kind_from_name(Game.weather)):
		return base * Weather.PRECIP_LIGHT_SCALE
	return base
