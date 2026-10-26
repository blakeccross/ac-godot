class_name InteriorLightModel
extends RefCounted

## Indoor light values for one room at one time (`m_kankyo` indoors). Pure data, so the
## interior scene and tests read the same numbers.
##
## What the original does indoors (`mEnv_SetBaseLight`, `mEnv_RoomTypeLightSet`):
## - Homes, Nook's Cranny, post office, police, museum lobby, tailor and tent keep the
##   *outdoor* time-of-day palette (fine or rain): same ambient, same sun/moon colours and
##   the same time-driven sun/moon directions as outside.
## - Other public rooms use one fixed palette (`l_mEnv_kcolor_shop`, `_broker`, museum
##   wings, …) with fixed sun/moon directions (`mEnv_ChangeDiffuseVctlSet`).
## - Every room adds one point light (`mEnv_GetNowRoomPointLightInfo`). Actors and
##   furniture turn it into a directional light from the lamp toward themselves
##   (`LightsN__point_proc`), fading as 1 − (d / radius)².
## - Rooms with a light switch (player floors, villager homes, cottage, lighthouse, tent)
##   scale the lamp by `point_light_percent` (1.0 on, 0.14 off). Homes (not basement /
##   lighthouse / tent) also scale sun and moon by 0.7, and by up to a further 0.4 as the
##   lamp comes on, so a lit home is lit by its lamp rather than the window.
## - Shell surfaces that multiply by PRIM take `mEnv_GetRoomPrimColor`: the palette's room
##   colour mixed with the lamp.
##
## Colours are the decomp 0–255 values as sRGB `Color`s; positions are room units (one
## grid cell = 40) measured from the room grid's NW corner.

## `point_light_min` in `Global_kankyo_ct`.
const POINT_LIGHT_MIN := 0.14
## `mEnv_DiffuseLightEffectRate` for rooms with a light switch.
const SWITCH_DIFFUSE_RATE := 0.7
## `diffuse_adjust`: sun/moon multiplier when the lamp is fully on.
const DIFFUSE_ADJUST := 0.4
## Room units per grid cell (`mFI_UT_WORLDSIZE_X_F`).
const UNITS_PER_CELL := 40.0
## `mEnv_NPC_LIGHTS_OFF_TIME` / `_ON_TIME` and `mRmTp_SetDefaultLightSwitchData(0)`.
const LAMP_OFF_HOUR := 5
const LAMP_ON_HOUR := 18

## Default lamp for any indoor scene not listed (`mEnv_GetNowRoomPointLightInfo`).
const _DEFAULT_LAMP := {"pos": Vector3(250, 1000, 378), "color": Color8(160, 160, 160), "power": 8000.0}
## `l_mEnv_kcolor_*` fixed palettes (ambient / sun / moon / room colour).
const _FIXED := {
	&"shop": [Color8(20, 10, 100), Color8(150, 160, 130), Color8(50, 40, 20), Color8(255, 255, 255)],
	&"buggy": [Color8(30, 30, 30), Color8(0, 0, 0), Color8(0, 60, 90), Color8(175, 175, 155)],
	&"broker": [Color8(20, 30, 40), Color8(100, 80, 80), Color8(20, 10, 0), Color8(140, 120, 120)],
	&"kamakura": [Color8(50, 25, 20), Color8(50, 40, 5), Color8(50, 80, 85), Color8(250, 240, 160)],
	&"museum_fossil": [Color8(50, 50, 60), Color8(60, 60, 80), Color8(20, 10, 0), Color8(255, 255, 255)],
	&"museum_fish": [Color8(40, 50, 60), Color8(20, 30, 40), Color8(0, 10, 20), Color8(120, 90, 100)],
	&"museum_picture": [Color8(30, 30, 60), Color8(120, 100, 80), Color8(0, 10, 20), Color8(255, 255, 255)],
	&"basement": [Color8(35, 30, 25), Color8(0, 0, 0), Color8(0, 0, 0), Color8(53, 53, 33)],
	&"lighthouse": [Color8(35, 30, 25), Color8(0, 0, 0), Color8(0, 0, 0), Color8(135, 125, 105)],
}
## `mEnv_ChangeDiffuseVctlSet` fixed directions (toward the light).
const _FIXED_SUN_DIR := Vector3(0, 69, 97)
const _FIXED_MOON_DIR := Vector3(0, -33, 115)


## Which decomp scene a room plays as, and that scene's lamp. Keys:
## `palette` (&"normal", &"insect" or a `_FIXED` key), `fixed_dirs`, `switch`,
## `home_rate` (0.7 sun/moon scale applies), `lamp_pos`, `lamp_color`, `lamp_power`, `flame`.
static func scene_profile(room: Room, house_tier: int = 0) -> Dictionary:
	var p := {
		"palette": &"normal",
		"fixed_dirs": false,
		"switch": false,
		"home_rate": false,
		"lamp_pos": _DEFAULT_LAMP["pos"],
		"lamp_color": _DEFAULT_LAMP["color"],
		"lamp_power": _DEFAULT_LAMP["power"],
		"flame": false,
	}
	if room == null:
		return p
	var warm := Color8(220, 220, 200)
	match room.kind:
		Room.Kind.PLAYER:
			p["switch"] = true
			if room.id == &"player_basement":
				_fixed(p, &"basement")
				_lamp(p, Vector3(200, 220, 300), Color8(220, 190, 190), 1000.0)
			else:
				p["home_rate"] = true
				_lamp(p, _player_lamp_pos(room.id, house_tier), warm, 1000.0)
		Room.Kind.NPC:
			p["switch"] = true
			p["home_rate"] = true
			_lamp(p, Vector3(160, 180, 240), warm, 1000.0)
		Room.Kind.COTTAGE:
			p["switch"] = true
			p["home_rate"] = true
			_lamp(p, Vector3(200, 220, 300), warm, 1000.0)
		Room.Kind.SHOP:
			if room.id == &"shop0":
				_lamp(p, Vector3(160, 180, 240), warm, 1000.0)
			else:
				## Nook 'n' Go / Nookway / Nookington's (`SCENE_CONVENI` / `SUPER` / `DEPART*`).
				_fixed(p, &"shop")
		Room.Kind.POST_OFFICE:
			_lamp(p, Vector3(160, 180, 240), warm, 1000.0)
		Room.Kind.POLICE:
			_lamp(p, Vector3(200, 220, 300), warm, 1000.0)
		Room.Kind.NEEDLEWORK:
			_lamp(p, Vector3(200, 160, 280), warm, 1000.0)
		Room.Kind.BROKER:
			_fixed(p, &"broker")
			_lamp(p, Vector3(250, 1000, 378), Color8(170, 170, 160), 8000.0)
		Room.Kind.DUMP:
			_fixed(p, &"buggy")
			_lamp(p, Vector3(160, 80, 200), Color8(205, 165, 110), 155.0)
			p["flame"] = true
		Room.Kind.KAMAKURA:
			_fixed(p, &"kamakura")
			_lamp(p, Vector3(160, 80, 38), Color8(250, 240, 120), 300.0)
			p["flame"] = true
		Room.Kind.LIGHTHOUSE:
			_fixed(p, &"lighthouse")
			p["switch"] = true
			_lamp(p, Vector3(120, 80, 160), Color8(235, 190, 185), 6000.0)
		Room.Kind.TENT:
			p["switch"] = true
			_lamp(p, Vector3(120, 80, 120), Color8(235, 190, 185), 6000.0)
		Room.Kind.MUSEUM:
			match room.id:
				&"museum_painting":
					_fixed(p, &"museum_picture")
					_lamp(p, Vector3(320, 220, 280), Color8(180, 180, 150), 800.0)
				&"museum_fossil":
					_fixed(p, &"museum_fossil")
					_lamp(p, Vector3(320, 220, 280), Color8(200, 200, 180), 800.0)
				&"museum_fish":
					_fixed(p, &"museum_fish")
					_lamp(p, Vector3(320, 220, 320), Color8(100, 120, 130), 1000.0)
				&"museum_insect":
					## Time-of-day palette dimmed at night (`l_mEnv_kcolor_insect_*`), unfixed dirs.
					p["palette"] = &"insect"
					_lamp(p, Vector3(280, 220, 320), Color8(50, 50, 50), 1000.0)
				_:
					_lamp(p, Vector3(240, 220, 280), warm, 1000.0)
	return p


## Lamp state for switch rooms at `hour`. Villager homes: lit while the owner is home and
## awake at night (`mEnv_CheckNpcRoomPointLightNiceStatus`). Player floors follow the
## default switch data (on 18:00–05:00; there is no Z-button toggle yet). Lighthouse and
## tent lamps stay on.
static func lamp_on(room: Room, hour: int, owner_home: bool) -> bool:
	if room == null:
		return true
	var night: bool = hour >= LAMP_ON_HOUR or hour < LAMP_OFF_HOUR
	match room.kind:
		Room.Kind.NPC:
			return owner_home and night
		Room.Kind.PLAYER, Room.Kind.COTTAGE:
			return night
		_:
			return true


## Light values for `room` at `sec` seconds past midnight. Returns `ambient`, `sun`,
## `moon`, `sun_dir`, `moon_dir`, `lamp_color` (already scaled by the switch),
## `lamp_pos` / `lamp_power` (room units), `lamp_percent`, `room_prim`, `flame`.
static func evaluate(
	room: Room, sec: int, rain: bool, lit: bool, house_tier: int = 0
) -> Dictionary:
	var prof: Dictionary = scene_profile(room, house_tier)
	var base: Dictionary = _palette(prof["palette"] as StringName, sec, rain)
	var percent: float = 1.0
	if bool(prof["switch"]):
		percent = 1.0 if lit else POINT_LIGHT_MIN
	var rate: float = SWITCH_DIFFUSE_RATE if bool(prof["home_rate"]) else 1.0
	var celestial: float = rate
	if bool(prof["switch"]):
		celestial *= (DIFFUSE_ADJUST - 1.0) * percent + 1.0
	var dirs: Dictionary = ClockService.celestial_dirs_at(sec)
	var sun_dir: Vector3 = dirs["sun"]
	var moon_dir: Vector3 = dirs["moon"]
	if bool(prof["fixed_dirs"]):
		sun_dir = _FIXED_SUN_DIR
		moon_dir = _FIXED_MOON_DIR
	var lamp: Color = prof["lamp_color"]
	return {
		"ambient": base["ambient"],
		"sun": _scale(base["sun"] as Color, celestial),
		"moon": _scale(base["moon"] as Color, celestial),
		"sun_dir": sun_dir,
		"moon_dir": moon_dir,
		"lamp_color": _scale(lamp, percent),
		"lamp_pos": prof["lamp_pos"],
		"lamp_power": prof["lamp_power"],
		"lamp_percent": percent,
		"flame": prof["flame"],
		"room_prim": room_prim(base["room"] as Color, lamp, percent, rate, bool(prof["flame"])),
	}


## `mEnv_GetRoomPrimColor`.
static func room_prim(room_color: Color, lamp: Color, percent: float, rate: float, flame: bool) -> Color:
	if flame:
		return Color8(
			(lamp.r8 >> 1) + (room_color.r8 >> 1),
			(lamp.g8 >> 1) + (room_color.g8 >> 1),
			(lamp.b8 >> 1) + (room_color.b8 >> 1)
		)
	var f0: float = 1.0 - 0.3 * percent
	var f1: float = 0.6 * percent
	return Color8(
		clampi(int(room_color.r8 * f0 * rate + lamp.r8 * f1), 0, 255),
		clampi(int(room_color.g8 * f0 * rate + lamp.g8 * f1), 0, 255),
		clampi(int(room_color.b8 * f0 * rate + lamp.b8 * f1), 0, 255)
	)


static func _palette(key: StringName, sec: int, rain: bool) -> Dictionary:
	if _FIXED.has(key):
		var row: Array = _FIXED[key]
		return {"ambient": row[0], "sun": row[1], "moon": row[2], "room": row[3]}
	## `l_mEnv_kcolor_rain_data` is the fine table ×0.9; the insect wing's is ×0.6 at night.
	var term: int = ClockService.light_term_at(sec)
	var t: float = ClockService.light_blend_at(sec)
	var weather_scale: float = 0.9 if rain else 1.0
	var s0: float = weather_scale * _insect_scale(key, term)
	var s1: float = weather_scale * _insect_scale(key, term + 1)
	var a: Dictionary = ClockService.fine_light_row(term)
	var b: Dictionary = ClockService.fine_light_row(term + 1)
	var out := {}
	for k: String in ["ambient", "sun", "moon", "room"]:
		out[k] = _scale(a[k] as Color, s0).lerp(_scale(b[k] as Color, s1), t)
	return out


static func _insect_scale(key: StringName, term: int) -> float:
	if key != &"insect":
		return 1.0
	var term_idx: int = posmod(term, 8)
	return 1.0 if term_idx >= 3 and term_idx <= 5 else 0.6


static func _player_lamp_pos(room_id: StringName, house_tier: int) -> Vector3:
	## `SCENE_MY_ROOM_S` / `_M` / `_L` / `_LL1` main floor, `_LL2` upper floor.
	if room_id == &"player_upper":
		return Vector3(160, 180, 240)
	match house_tier:
		House.SizeTier.SMALL:
			return Vector3(120, 180, 180)
		House.SizeTier.MEDIUM:
			return Vector3(160, 180, 240)
		_:
			return Vector3(200, 220, 300)


static func _fixed(p: Dictionary, key: StringName) -> void:
	p["palette"] = key
	p["fixed_dirs"] = true


static func _lamp(p: Dictionary, pos: Vector3, color: Color, power: float) -> void:
	p["lamp_pos"] = pos
	p["lamp_color"] = color
	p["lamp_power"] = power


static func _scale(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)
