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


## `SE_FLOOR_DATA`: each floor's footstep, as an offset from `NA_SE_FLOOR_SE_START` (0x42E6).
const FLOOR_SE: PackedByteArray = [
	27, 27, 32, 31, 28, 32, 31, 27, 27, 28, 29, 29, 27, 31, 28, 30,
	33, 27, 30, 27, 32, 32, 31, 28, 32, 27, 35, 32, 32, 32, 27, 29,
	31, 32, 28, 28, 28, 27, 28, 28, 27, 31, 36, 32, 28, 27, 33, 27,
	35, 28, 32, 32, 28, 28, 32, 29, 28, 33, 27, 32, 33, 27, 32, 32,
	28, 32, 32, 34, 32, 32, 27, 32, 28, 27, 29, 27, 28, 28, 27, 31,
	28, 31, 28, 32, 28, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32,
]
const FLOOR_SE_START := 0x42E6


## `Player_actor_sound_FootStep2` → `Na_PlyWalkSeRoom`: the room's floor (`floor_idx`) sets
## the step; a room with no floor of its own, or a floor the sound table lacks, is wood
## (`0xFF`).
static func id_indoors(floor_index: int = -1) -> StringName:
	if floor_index < 0 or floor_index >= FLOOR_SE.size():
		return &"footstep_wood"
	return StringName("%x" % (FLOOR_SE_START + FLOOR_SE[floor_index]))


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
	indoors: bool,
	floor_index: int = -1
) -> void:
	if gait == PlayerLocomotion.Gait.WAIT:
		return
	var id: StringName
	if indoors:
		id = id_indoors(floor_index)
	elif attr >= 0:
		id = id_for_attr(attr, season)
	else:
		id = id_for_terrain(terrain, season)
	Audio.play_se(id, at, 1.0, volume_db(gait, indoors))
