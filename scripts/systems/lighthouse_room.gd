class_name LighthouseRoom
extends RefCounted

## The switch room at the foot of the lighthouse (`SCENE_LIGHTHOUSE`, `lighthouse.c` scene
## data, `rom_toudai`, `FG_TYPE_ROM_TOUDAI`). Layout constants in GX on the room's 16×16
## acre (40 GX per unit).

const SHELL_ID := &"rom_toudai"
## Walkable units from `rom_toudai.col.json`: a two-unit hall inside the door (2–3, 1–2),
## a ring round the machinery pit (1–4, 3–4) and a two-unit bay south of it (2–3, 5).
const INNER_ORIGIN := Vector2i(1, 1)
const INNER_SIZE := Vector2i(4, 5)
## `EXIT_DOOR` pair (`FG_TYPE_ROM_TOUDAI` units (2,0) and (3,0)) on the north rim.
const DOOR_CELL := Vector2i(2, 0)
const SPAWN_CELL := Vector2i(3, 2)
## `aTOU_door_data`: GX {120,0,100}, `mSc_DIRECT_SOUTH`.
const SPAWN_GX := Vector3(120.0, 0.0, 100.0)
const SPAWN_FACING := WorldGrid.Facing.SOUTH
## Floor and wall heights in `mCoBG` counts. The pit rail (units 2–3, 3–4) stands 20 GX.
const FLOOR_COUNTS := 4
const WALL_COUNTS := 31

## `aLS_CheckPlayerSwitchPositionAngle`: the switch panel on the east wall.
const SWITCH_GX := Vector3(180.0, 0.0, 100.0)
## Reach from `SWITCH_GX` (`GETREG(CRV, 86) + 33.5684`, the register is 0 on retail).
const SWITCH_REACH_GX := 33.5684
## `aLS_CheckPlayerAction`: the player is moved here, facing 135° (toward the panel).
const SWITCH_STAND_GX := Vector3(167.27208, 40.0, 112.72792)

## `mEnv` point light for `SCENE_LIGHTHOUSE`: over the pit, warm white.
const LIGHT_GX := Vector3(120.0, 80.0, 160.0)
const LIGHT_COLOR := Color(235.0 / 255.0, 190.0 / 255.0, 185.0 / 255.0)


## Units in the walkable rect the BG raises (pit rail) or walls off: unit → height in GX.
static func blocked_units() -> Dictionary:
	return InteriorUnitCollision.blocked_from_bg(
		SHELL_ID, FLOOR_COUNTS, WALL_COUNTS, Rect2i(INNER_ORIGIN, INNER_SIZE)
	)


static func gx_to_world(grid: WorldGrid, gx: Vector3) -> Vector3:
	return MuseumDisplay.gx_to_world(grid, gx)
