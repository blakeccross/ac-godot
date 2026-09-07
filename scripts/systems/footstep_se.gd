class_name FootstepSe
extends RefCounted

## Outdoor / indoor player footstep labels (`sAdo_Get_WalkLabel` / `Na_PlyWalkSe` /
## `Na_PlyWalkSeRoom`). Play via `Audio.play_se` — no positional pan yet.

## `mCoBG_ATTRIBUTE_*` values used by `sAdo_Get_WalkLabel` (not grass3 / bridges).
const ATTR_GRASS0 := 0
const ATTR_GRASS2 := 2
const ATTR_SOIL0 := 4
const ATTR_SOIL2 := 6
const ATTR_STONE := 7
const ATTR_BUSH := 9
const ATTR_WAVE := 11
const ATTR_SAND := 22
const ATTR_WOOD := 23

## `Na_PlyWalkSe` optVolume by `sou_player_dash` (1 walk / 2 run / 3 dash).
const VOL_WALK := 0.6
const VOL_RUN := 0.8
const VOL_DASH := 1.0
## `Na_PlyWalkSeRoom` indoor volumes.
const VOL_ROOM_WALK := 0.54
const VOL_ROOM_RUN := 0.72
const VOL_ROOM_DASH := 0.9


static func id_for_attr(attr: int, season: Clock.Season) -> StringName:
	## `sAdo_Get_WalkLabel`. Unknown attrs (bridges, grass3, floor, …) → soil.
	if attr >= ATTR_GRASS0 and attr <= ATTR_GRASS2:
		if season == Clock.Season.WINTER:
			return &"footstep_snow"
		return &"footstep_grass"
	if attr >= ATTR_SOIL0 and attr <= ATTR_SOIL2:
		return &"footstep_soil"
	match attr:
		ATTR_STONE:
			return &"footstep_stone"
		ATTR_WOOD:
			return &"footstep_wood"
		ATTR_BUSH:
			return &"footstep_bush"
		ATTR_SAND:
			return &"footstep_sand"
		ATTR_WAVE:
			return &"footstep_wave"
		_:
			return &"footstep_soil"


static func id_for_terrain(terrain: WorldGrid.Terrain, season: Clock.Season) -> StringName:
	## Fallback when the acre has no `.col.json` unit attrs.
	match terrain:
		WorldGrid.Terrain.SAND:
			return &"footstep_sand"
		WorldGrid.Terrain.GRASS:
			if season == Clock.Season.WINTER:
				return &"footstep_snow"
			return &"footstep_grass"
		_:
			return &"footstep_soil"


static func id_indoors() -> StringName:
	## `Na_PlyWalkSeRoom(0xFF, …)` → wood.
	return &"footstep_wood"


static func volume_db(gait: PlayerLocomotion.Gait, indoors: bool = false) -> float:
	var linear: float
	match gait:
		PlayerLocomotion.Gait.WALK:
			linear = VOL_ROOM_WALK if indoors else VOL_WALK
		PlayerLocomotion.Gait.RUN:
			linear = VOL_ROOM_RUN if indoors else VOL_RUN
		PlayerLocomotion.Gait.DASH:
			linear = VOL_ROOM_DASH if indoors else VOL_DASH
		_:
			return -80.0
	return linear_to_db(linear)


static func play_at(
	at: Node,
	attr: int,
	terrain: WorldGrid.Terrain,
	season: Clock.Season,
	gait: PlayerLocomotion.Gait,
	indoors: bool
) -> void:
	if gait == PlayerLocomotion.Gait.WAIT:
		return
	var id: StringName
	if indoors:
		id = id_indoors()
	elif attr >= 0:
		id = id_for_attr(attr, season)
	else:
		id = id_for_terrain(terrain, season)
	Audio.play_se(id, at, 1.0, volume_db(gait, indoors))
