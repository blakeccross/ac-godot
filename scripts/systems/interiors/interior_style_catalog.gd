class_name InteriorStyleCatalog
extends RefCounted

## Wall/floor style resolution: bank-index ↔ style-id conversion, colors
## (used when a texture bank page is missing), and generated texture paths.
## Independent of which rooms/houses exist — see `InteriorCatalog` for that.

const WALL_BANK_COUNT := 71
const FLOOR_BANK_COUNT := 71
const ROOM_TEX_ROOT := "res://assets/generated/textures/rooms/"

const WALL_DEFAULT := &"wall_default"
const WALL_BLUE := &"wall_blue"
const WALL_GREEN := &"wall_green"
const WALL_ROSE := &"wall_rose"
const WALL_CREAM := &"wall_cream"
const FLOOR_DEFAULT := &"floor_default"
const FLOOR_WOOD := &"floor_wood"
const FLOOR_TILE := &"floor_tile"
const FLOOR_STONE := &"floor_stone"


static func has_wall(wall_id: StringName) -> bool:
	return wall_color(wall_id) != Color(0, 0, 0, 0)


static func has_floor(floor_id: StringName) -> bool:
	return floor_color(floor_id) != Color(0, 0, 0, 0)


static func wall_style_id(index: int) -> StringName:
	return StringName("wall_%02d" % clampi(index, 0, WALL_BANK_COUNT - 1))


static func floor_style_id(index: int) -> StringName:
	return StringName("floor_%02d" % clampi(index, 0, FLOOR_BANK_COUNT - 1))


static func style_index(style_id: StringName, prefix: String) -> int:
	var raw := String(style_id)
	if not raw.begins_with(prefix):
		return -1
	var rest := raw.substr(prefix.length())
	if not rest.is_valid_int():
		return -1
	return rest.to_int()


static func wall_texture_path(wall_id: StringName, page: int = 0) -> String:
	var idx: int = style_index(wall_id, "wall_")
	if idx < 0 or idx >= WALL_BANK_COUNT:
		return ""
	var path := "%swall/wall_%02d_%d.png" % [ROOM_TEX_ROOT, idx, clampi(page, 0, 1)]
	if ResourceLoader.exists(path):
		return path
	path = "%swall/wall_%02d_0.png" % [ROOM_TEX_ROOT, idx]
	return path if ResourceLoader.exists(path) else ""


static func floor_texture_path(floor_id: StringName, page: int = 0) -> String:
	var idx: int = style_index(floor_id, "floor_")
	if idx < 0 or idx >= FLOOR_BANK_COUNT:
		return ""
	var path := "%sfloor/floor_%02d_%d.png" % [ROOM_TEX_ROOT, idx, clampi(page, 0, 3)]
	if ResourceLoader.exists(path):
		return path
	path = "%sfloor/floor_%02d_0.png" % [ROOM_TEX_ROOT, idx]
	return path if ResourceLoader.exists(path) else ""


static func wall_color(wall_id: StringName) -> Color:
	match wall_id:
		WALL_BLUE:
			return Color(0.52, 0.68, 0.84)
		WALL_GREEN:
			return Color(0.55, 0.72, 0.58)
		WALL_ROSE:
			return Color(0.82, 0.58, 0.62)
		WALL_CREAM:
			return Color(0.9, 0.84, 0.72)
		WALL_DEFAULT:
			return Color(0.86, 0.8, 0.7)
		_:
			var idx: int = style_index(wall_id, "wall_")
			if idx < 0:
				return Color(0, 0, 0, 0)
			return Color.from_hsv(fmod(float(idx) * 0.13, 1.0), 0.22, 0.86)


static func floor_color(floor_id: StringName) -> Color:
	match floor_id:
		FLOOR_WOOD:
			return Color(0.62, 0.44, 0.28)
		FLOOR_TILE:
			return Color(0.78, 0.76, 0.72)
		FLOOR_STONE:
			return Color(0.58, 0.58, 0.6)
		FLOOR_DEFAULT:
			return Color(0.72, 0.62, 0.48)
		_:
			var idx: int = style_index(floor_id, "floor_")
			if idx < 0:
				return Color(0, 0, 0, 0)
			return Color.from_hsv(fmod(float(idx) * 0.17 + 0.08, 1.0), 0.35, 0.62)
