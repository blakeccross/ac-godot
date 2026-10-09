class_name EventBgm
extends RefCounted

## Event music on the field (`mBGMFieldSchedEv`, `mbgm_event_data`). Each row is an event,
## its BGM and where it is heard: the whole town, or one acre (the shrine or the pond) at full
## volume with the four acres beside it at half (`mbgm_pattern_data`). Numbers 250 and up
## are not sequences — the tent's room code (254) is one — so those acres go quiet.
## The New Year countdown rows (silences and timed tracks) are not here.

enum Area { ALL, BLOCK }
enum Level { NONE, NEARBY, FULL }

const QUIET := &"_quiet"
## `ps_volume` 0.5.
const NEARBY_DB := -6.0206

## [event id, bgm_num, area, block kind] in `mbgm_event_data` order (first wins).
const ROWS: Array = [
	[&"fireworks_show", 55, Area.BLOCK, "pool"],
	[&"halloween", 53, Area.ALL, ""],
	[&"toy_day_jingle", 54, Area.ALL, ""],
	[&"cherry_blossom_festival", 56, Area.BLOCK, "shrine"],
	[&"morning_aerobics", 27, Area.BLOCK, "shrine"],
	[&"harvest_moon_festival", 30, Area.BLOCK, "pool"],
	[&"harvest_festival", 253, Area.BLOCK, "shrine"],
	[&"sports_fair_aerobics", 27, Area.BLOCK, "shrine"],
	[&"sports_fair_foot_race", 28, Area.BLOCK, "shrine"],
	[&"sports_fair_ball_toss", 29, Area.BLOCK, "shrine"],
	[&"sports_fair_tug_of_war", 60, Area.BLOCK, "shrine"],
	[&"new_years_day", 59, Area.BLOCK, "shrine"],
	[&"groundhog_day", 251, Area.BLOCK, "shrine"],
	[&"meteor_shower", 250, Area.BLOCK, "pool"],
]


## `mBGMFieldSchedEv_bl_attr_get`.
static func level(area: Area, player_block: Vector2i, event_block: Vector2i) -> Level:
	if area == Area.ALL:
		return Level.FULL
	if event_block.x < 0:
		return Level.NONE
	var d: Vector2i = (event_block - player_block).abs()
	if d == Vector2i.ZERO:
		return Level.FULL
	if d.x + d.y == 1:
		return Level.NEARBY
	return Level.NONE


## The event music for a player in `player_block`: {"id", "db"}, or {} for the field's own.
## `is_active(id) -> bool`, `block_of(kind) -> Vector2i` (x < 0 when the town has none).
static func pick(is_active: Callable, player_block: Vector2i, block_of: Callable) -> Dictionary:
	for row: Array in ROWS:
		if not bool(is_active.call(row[0])):
			continue
		var at: Vector2i = block_of.call(row[3]) if row[2] == Area.BLOCK else Vector2i.ZERO
		var lv: Level = level(row[2], player_block, at)
		if lv == Level.NONE:
			continue
		var bgm_num: int = int(row[1])
		var id: StringName = QUIET if bgm_num >= 250 else BgmCatalog.id_for_num(bgm_num)
		return {"id": id, "db": NEARBY_DB if lv == Level.NEARBY else 0.0}
	return {}
