class_name FootprintMarks
extends RefCounted

## Footprints pressed into sand (and snow-covered grass in winter). Behavioral analog of
## `ef_footprint`: the walk animation spawns the effect unconditionally and the effect
## kills itself unless the unit attribute can hold a mark. Not an autoload — the pooled
## presentation lives on the world's `Footprints` node; everything decidable lives here.

## `effect->timer = 160`, counted down one per effect frame.
const LIFE_FRAMES := 160.0
## `calc_adjust_proc(160 - timer, 118, 159, 150.0, 0.0)`: hold, then fade over 41 frames.
const FADE_START_FRAME := 118.0
const FADE_END_FRAME := 159.0
const MAX_ALPHA := 150.0 / 255.0
const GAME_FPS := 60.0
const LIFETIME := LIFE_FRAMES / GAME_FPS

## `gDPSetPrimColor` per surface: sand/wave is a dark depression, snow a cool dent.
const SAND_TINT := Color(70.0 / 255.0, 50.0 / 255.0, 50.0 / 255.0)
const SNOW_TINT := Color(0.0, 50.0 / 255.0, 100.0 / 255.0)

## `effect->position.y = 2.0f + GetShadowBgY(...)` — 2 GX clear of the acre plane.
const GROUND_LIFT := 2.0 * FieldCatalog.GX_TO_METERS
## The `eFootPrint_area_offset_data` probe triangle, in meters.
const SLOPE_PROBES: Array[Vector2] = [
	Vector2(2.0 * FieldCatalog.GX_TO_METERS, -2.0 * FieldCatalog.GX_TO_METERS),
	Vector2(-2.0 * FieldCatalog.GX_TO_METERS, -2.0 * FieldCatalog.GX_TO_METERS),
	Vector2(0.0, 2.0 * FieldCatalog.GX_TO_METERS),
]

## Measured off the original, not estimated. `ef_footprint01_00_v` is a flat quad at
## ±1000 units in X and Z, and `eFootPrint_dw` applies `Matrix_scale(0.005, ·, 0.0075)`,
## giving 10 x 15 GX. Length runs along the facing.
const QUAD_SIZE := Vector2(0.5, 0.75)
## The rim ellipse of the 16x16 I4 mask (`ef_footprint01_0`), as full axes in meters. Its
## peak sits 3.5 texels in from the quad edge across but only 1.5 texels in along the
## length, so the rim is *not* inset uniformly — it hugs the ends and stands well clear
## of the sides.
const RIM_AXES := Vector2(0.28125, 0.609375)
## How far the rim fades either side of that ellipse, in meters. The mark is soft in game
## for two reasons: a 16x16 tile stretched over this quad is 3-5 cm per texel and gets
## filtered, and the mask's own profile ramps (0, 3, 7, 5, 2) instead of stepping. The
## falloff is bounded rather than gaussian because bilinear magnification of a discrete
## profile is piecewise *linear* — a gaussian's tails wash the rim out instead of leaving
## the defined-but-soft band the game shows. Measured reach is ~2 texels, which is 6 cm
## across and 9 cm along; this sits between them.
const RIM_REACH := 0.075
## The drawn quad, padded past the original's so the blur's tail fades out inside the
## mesh instead of being cut off at its edge. The mark itself keeps the size above.
const MARK_SIZE := QUAD_SIZE * 1.2
## The mask is I4 and tops out at 7/15, so it never drives prim alpha to full. The
## combiner takes alpha from `TEXEL0 * PRIMITIVE`, so this multiplies `MAX_ALPHA`.
const TILE_PEAK := 7.0 / 15.0
## Interior texels average 1.5 against the rim's 7 — a faint dish, not a hollow.
const INTERIOR_ALPHA := 0.214


## Half the stance width. Only a fallback: the original reads each print's position and
## yaw off the `LFOOT3` / `RFOOT3` joint, which `player.gd` does whenever the visual has a
## rig. This stands in for an unrigged placeholder, which has no feet to sample.
const FOOT_OFFSET := 0.21
## `left_data_walk1 = {1}` / `right_data_walk1 = {9}` — 8 animation frames between feet.
const STEP_FRAMES := 8.0
const ANIM_FPS := 30.0


static func rim_radii_uv() -> Vector2:
	## Rim semi-axes in the shader's space, where the quad's length is 1.0.
	return Vector2(RIM_AXES.x * 0.5, RIM_AXES.y * 0.5) / MARK_SIZE.y


static func rim_reach_uv() -> float:
	return RIM_REACH / MARK_SIZE.y


static func marks_attr(attr: int, season: Clock.Season) -> bool:
	## `eFootPrint_ct`: sand and wave always take a print; grass only under snow.
	if FieldCatalog.is_sand_attr(attr) or FieldCatalog.is_wave_attr(attr):
		return true
	return season == Clock.Season.WINTER and FieldCatalog.is_grass_attr(attr)


static func marks_terrain(terrain: WorldGrid.Terrain, season: Clock.Season) -> bool:
	## Fallback for acres with no `.col.json`: the coarse terrain enum stands in for the attr.
	if terrain == WorldGrid.Terrain.SAND:
		return true
	return season == Clock.Season.WINTER and terrain == WorldGrid.Terrain.GRASS


static func is_snow_mark(attr: int) -> bool:
	## `effect_specific[3]`: sand/wave takes the warm prim, everything else the snow prim.
	return not (FieldCatalog.is_sand_attr(attr) or FieldCatalog.is_wave_attr(attr))


static func tint(snow: bool) -> Color:
	return SNOW_TINT if snow else SAND_TINT


static func alpha_at(age: float) -> float:
	var frame: float = age * GAME_FPS
	if frame >= LIFE_FRAMES:
		return 0.0
	if frame <= FADE_START_FRAME:
		return MAX_ALPHA
	var t: float = (frame - FADE_START_FRAME) / (FADE_END_FRAME - FADE_START_FRAME)
	return MAX_ALPHA * (1.0 - clampf(t, 0.0, 1.0))


static func step_period(anim_speed: float) -> float:
	## Original triggers on animation frames, so a faster gait clip steps sooner and the
	## tracks spread out with speed. Distance-based emission would space them evenly.
	return STEP_FRAMES / (ANIM_FPS * maxf(anim_speed, 0.05))


static func foot_position(center: Vector3, yaw: float, right_foot: bool) -> Vector3:
	## `left_foot_pos` / `right_foot_pos`. Facing 0 looks down +Z, so lateral is +X at yaw 0.
	var side: float = FOOT_OFFSET if right_foot else -FOOT_OFFSET
	return center + Vector3(cos(yaw) * side, 0.0, -sin(yaw) * side)


static func mark_transform(
	data: WorldData, grid: WorldGrid, pos: Vector3, yaw: float
) -> Transform3D:
	## `mCoBG_GetBgY_AngleS_FromWpos` over the probe triangle, so the print lies on the
	## slope. We only have heights, so fit a plane through the three samples instead of
	## averaging s16 angles.
	var y: float = FieldCollision.ground_y_at(data, grid, pos)
	if not FieldCollision.has_floor(y):
		## Zero basis, not identity: callers reject a mark by its determinant, and an
		## identity basis is a valid one that would place a print at the world origin.
		return Transform3D(Basis.from_scale(Vector3.ZERO), pos)
	var samples: Array[Vector3] = []
	for probe: Vector2 in SLOPE_PROBES:
		var at := Vector3(pos.x + probe.x, pos.y, pos.z + probe.y)
		var py: float = FieldCollision.ground_y_at(data, grid, at)
		samples.append(Vector3(at.x, py if FieldCollision.has_floor(py) else y, at.z))
	var normal: Vector3 = (samples[1] - samples[0]).cross(samples[2] - samples[0])
	if normal.y < 0.0:
		normal = -normal
	if normal.length_squared() < 0.000001:
		normal = Vector3.UP
	normal = normal.normalized()
	var origin := Vector3(pos.x, y + GROUND_LIFT, pos.z)
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var right: Vector3 = normal.cross(forward)
	if right.length_squared() < 0.000001:
		## Facing straight up the normal. Lay the print flat rather than dropping it.
		return Transform3D(Basis.IDENTITY, origin)
	right = right.normalized()
	forward = right.cross(normal).normalized()
	## PlaneMesh lies in XZ with +Y up, so basis Y is the ground normal.
	return Transform3D(Basis(right, normal, forward), origin)
