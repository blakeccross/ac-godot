class_name PostDisplay
extends RefCounted

## Post office indoor layout (`SCENE_POST_OFFICE` / `FG_TYPE_GRD_POST_OFFICE` / `post_office_actable`).
## Behavioral reference: `post_office.c` scene, `bg_post_item`, `ac_npc_post_girl`.

## Walkable NW + size from `grd_post_office` collision (attr ≠ 31). Exit `EXIT_DOOR` at (3,8)/(4,8).
const INNER_ORIGIN := Vector2i(1, 1)
const INNER_SIZE := Vector2i(6, 8)
const DOOR_CELL := Vector2i(3, 8)
const SPAWN_CELL := Vector2i(3, 7)

## `POST_OFFICE_player_data` GX {100,0,200}, face south (yaw 0).
const SPAWN_GX := Vector3(100.0, 0.0, 200.0)
const SPAWN_FACING := WorldGrid.Facing.SOUTH

## `post_office_actable` ut (4,2); `aPG_actor_ct` then subtracts 20 GX on X.
const POST_GIRL_STAND_UT := Vector2i(4, 2)
const POST_GIRL_STAND_GX := Vector3(160.0, 0.0, 100.0)
const POST_GIRL_FACING := WorldGrid.Facing.SOUTH

## Day Pelly `pla` (7:00–19:00); night Phyllis `plb` (`bg_post_item` post_girl_npc_type).
const PELLY_SPECIES := &"pla"
const PHYLLIS_SPECIES := &"plb"
const PELLY_DAY_START_HOUR := 7
const PELLY_DAY_END_HOUR := 19

## `bPTI_actor_draw` letter piles: X {80,120,160,200,240}, Y 60, Z 60.
const MAIL_PILE_Y_GX := 60.0
const MAIL_PILE_Z_GX := 60.0
const MAIL_PILE_X_GX: Array[float] = [80.0, 120.0, 160.0, 200.0, 240.0]

const SHELL_ID := &"grd_post_office"


static func post_girl_species(hour: int = -1) -> StringName:
	var h: int = hour
	if h < 0 and Clock != null:
		h = Clock.hour
	if h < 0:
		h = 12
	if h >= PELLY_DAY_END_HOUR or h < PELLY_DAY_START_HOUR:
		return PHYLLIS_SPECIES
	return PELLY_SPECIES


static func post_girl_name(species: StringName = &"") -> String:
	var id: StringName = species if species != &"" else post_girl_species()
	return "Phyllis" if id == PHYLLIS_SPECIES else "Pelly"


static func gx_to_world(grid: WorldGrid, gx: Vector3) -> Vector3:
	return MuseumDisplay.gx_to_world(grid, gx)


static func mail_pile_gx(index: int) -> Vector3:
	var i: int = clampi(index, 0, MAIL_PILE_X_GX.size() - 1)
	return Vector3(MAIL_PILE_X_GX[i], MAIL_PILE_Y_GX, MAIL_PILE_Z_GX)
