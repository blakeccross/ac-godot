class_name Weather
extends RefCounted

## Daily weather roll and outdoor look helpers (`m_kankyo_weather` / rain lighting).
## Not an autoload — `Game` owns the session type + intensity; FX reads those.

enum Kind { CLEAR, RAIN, SNOW, SAKURA }
enum Intensity { NONE, LIGHT, NORMAL, HEAVY }

## Inclusive end month/day for each of the 20 weather terms (`weather_term_table`).
const TERM_ENDS: Array[Vector2i] = [
	Vector2i(1, 7),
	Vector2i(2, 24),
	Vector2i(3, 31),
	Vector2i(4, 4),
	Vector2i(4, 7),
	Vector2i(4, 8),
	Vector2i(4, 19),
	Vector2i(4, 20),
	Vector2i(6, 25),
	Vector2i(7, 15),
	Vector2i(8, 31),
	Vector2i(9, 30),
	Vector2i(10, 30),
	Vector2i(10, 31),
	Vector2i(11, 15),
	Vector2i(12, 9),
	Vector2i(12, 10),
	Vector2i(12, 23),
	Vector2i(12, 30),
	Vector2i(12, 31),
]

## Per-term weights: clear, rain, thunder, snow, blizzard, sakura, heavy_sakura (sum 10).
const TERM_WEIGHTS: Array = [
	[10, 0, 0, 0, 0, 0, 0],
	[7, 0, 0, 2, 1, 0, 0],
	[8, 2, 0, 0, 0, 0, 0],
	[10, 0, 0, 0, 0, 0, 0],
	[0, 0, 0, 0, 0, 10, 0],
	[0, 0, 0, 0, 0, 0, 10],
	[8, 2, 0, 0, 0, 0, 0],
	[10, 0, 0, 0, 0, 0, 0],
	[7, 2, 1, 0, 0, 0, 0],
	[5, 3, 2, 0, 0, 0, 0],
	[9, 0, 1, 0, 0, 0, 0],
	[6, 0, 4, 0, 0, 0, 0],
	[8, 2, 0, 0, 0, 0, 0],
	[10, 0, 0, 0, 0, 0, 0],
	[8, 1, 0, 1, 0, 0, 0],
	[7, 0, 0, 3, 0, 0, 0],
	[0, 0, 0, 0, 10, 0, 0],
	[4, 0, 0, 4, 2, 0, 0],
	[0, 0, 0, 6, 4, 0, 0],
	[10, 0, 0, 0, 0, 0, 0],
]

## Rain/snow palette (`l_mEnv_kcolor_rain_data`). Same eight windows as fine lighting.
const _RAIN_LIGHT: Array[Dictionary] = [
	{
		"ambient": Color8(18, 9, 108),
		"sun": Color8(0, 0, 0),
		"moon": Color8(108, 162, 72),
		"fog": Color8(20, 20, 80),
		"bg": Color8(28, 32, 92),
		"fog_begin": 55.0,
		"fog_end": 140.0,
	},
	{
		"ambient": Color8(0, 9, 108),
		"sun": Color8(0, 18, 36),
		"moon": Color8(135, 180, 90),
		"fog": Color8(80, 100, 120),
		"bg": Color8(44, 52, 112),
		"fog_begin": 50.0,
		"fog_end": 145.0,
	},
	{
		"ambient": Color8(54, 54, 108),
		"sun": Color8(229, 229, 180),
		"moon": Color8(9, 36, 54),
		"fog": Color8(120, 150, 150),
		"bg": Color8(60, 76, 120),
		"fog_begin": 45.0,
		"fog_end": 160.0,
	},
	{
		"ambient": Color8(72, 72, 135),
		"sun": Color8(162, 198, 198),
		"moon": Color8(0, 9, 18),
		"fog": Color8(80, 120, 150),
		"bg": Color8(56, 72, 140),
		"fog_begin": 50.0,
		"fog_end": 170.0,
	},
	{
		"ambient": Color8(72, 72, 135),
		"sun": Color8(180, 216, 216),
		"moon": Color8(0, 0, 0),
		"fog": Color8(80, 120, 150),
		"bg": Color8(52, 78, 144),
		"fog_begin": 50.0,
		"fog_end": 170.0,
	},
	{
		"ambient": Color8(72, 72, 135),
		"sun": Color8(180, 216, 216),
		"moon": Color8(9, 0, 27),
		"fog": Color8(80, 120, 150),
		"bg": Color8(48, 72, 140),
		"fog_begin": 50.0,
		"fog_end": 165.0,
	},
	{
		"ambient": Color8(54, 54, 135),
		"sun": Color8(180, 108, 0),
		"moon": Color8(18, 0, 72),
		"fog": Color8(20, 20, 80),
		"bg": Color8(32, 32, 92),
		"fog_begin": 50.0,
		"fog_end": 145.0,
	},
	{
		"ambient": Color8(27, 27, 108),
		"sun": Color8(54, 54, 0),
		"moon": Color8(108, 162, 72),
		"fog": Color8(20, 20, 80),
		"bg": Color8(28, 28, 92),
		"fog_begin": 55.0,
		"fog_end": 140.0,
	},
]

## Shadow / sun energy scale while raining or snowing (`mEnv_MakeShadowInfo`).
const PRECIP_LIGHT_SCALE := 0.75

const CYCLE_ORDER: Array[StringName] = [&"clear", &"rain", &"snow", &"sakura"]

static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


static func kind_name(kind: Kind) -> StringName:
	match kind:
		Kind.RAIN:
			return &"rain"
		Kind.SNOW:
			return &"snow"
		Kind.SAKURA:
			return &"sakura"
		_:
			return &"clear"


static func kind_from_name(name: StringName) -> Kind:
	match name:
		&"rain":
			return Kind.RAIN
		&"snow":
			return Kind.SNOW
		&"sakura":
			return Kind.SAKURA
		&"leaves":
			## Demo-only in the original; treat as clear outdoors.
			return Kind.CLEAR
		_:
			return Kind.CLEAR


static func is_precip(kind: Kind) -> bool:
	return kind == Kind.RAIN or kind == Kind.SNOW


static func is_raining(name: StringName = &"") -> bool:
	var key: StringName = name if name != &"" else Game.weather
	return key == &"rain"


static func weather_term(month: int, day: int) -> int:
	## `mEnv_GetWeatherChangeStep`.
	for i: int in TERM_ENDS.size():
		var end: Vector2i = TERM_ENDS[i]
		if month < end.x:
			return i
		if month == end.x and day <= end.y:
			return i
	return 1


static func seed_rng(value: int) -> void:
	_rng.seed = value


static func roll(month: int = -1, day: int = -1) -> Dictionary:
	## `mEnv_RandomWeather`. Returns `{kind: Kind, intensity: Intensity}`.
	var m: int = month if month > 0 else Clock.month
	var d: int = day if day > 0 else Clock.day
	var term: int = weather_term(m, d)
	var weights: Array = TERM_WEIGHTS[term] as Array
	var selected: int = _rng.randi_range(0, 9)
	var acc: int = 0
	for bucket: int in weights.size():
		acc += int(weights[bucket])
		if selected < acc:
			return _bucket_to_result(bucket)
	return {"kind": Kind.CLEAR, "intensity": Intensity.LIGHT}


static func _bucket_to_result(bucket: int) -> Dictionary:
	match bucket:
		0:
			return {"kind": Kind.CLEAR, "intensity": Intensity.LIGHT}
		1:
			return {"kind": Kind.RAIN, "intensity": Intensity.LIGHT}
		2:
			return {"kind": Kind.RAIN, "intensity": Intensity.HEAVY}
		3:
			return {"kind": Kind.SNOW, "intensity": Intensity.LIGHT}
		4:
			return {"kind": Kind.SNOW, "intensity": Intensity.HEAVY}
		5:
			return {"kind": Kind.SAKURA, "intensity": Intensity.LIGHT}
		_:
			return {"kind": Kind.SAKURA, "intensity": Intensity.HEAVY}


static func pack(kind: Kind, intensity: Intensity) -> int:
	## Save nibble pair (`type << 4 | intensity`).
	return (int(kind) << 4) | (int(intensity) & 0xF)


static func unpack(packed: int) -> Dictionary:
	return {
		"kind": clampi((packed >> 4) & 0xF, 0, Kind.SAKURA) as Kind,
		"intensity": clampi(packed & 0xF, 0, Intensity.HEAVY) as Intensity,
	}


static func next_in_cycle(current: StringName) -> StringName:
	var idx: int = CYCLE_ORDER.find(current)
	if idx < 0:
		return CYCLE_ORDER[0]
	return CYCLE_ORDER[(idx + 1) % CYCLE_ORDER.size()]


static func default_intensity_for(kind: Kind) -> Intensity:
	match kind:
		Kind.CLEAR:
			return Intensity.NONE
		Kind.RAIN, Kind.SNOW, Kind.SAKURA:
			return Intensity.LIGHT
		_:
			return Intensity.NONE


static func rain_outdoor_light() -> Dictionary:
	## Same blend windows as `Clock.outdoor_light`, but rain palette.
	var term: int = Clock.light_term()
	var a: Dictionary = _RAIN_LIGHT[term]
	var b: Dictionary = _RAIN_LIGHT[(term + 1) % _RAIN_LIGHT.size()]
	var t: float = _light_blend_public()
	var sun: Color = (a["sun"] as Color).lerp(b["sun"] as Color, t)
	var moon: Color = (a["moon"] as Color).lerp(b["moon"] as Color, t)
	var dirs: Dictionary = Clock.outdoor_light()
	return {
		"ambient": (a["ambient"] as Color).lerp(b["ambient"] as Color, t),
		"sun": sun,
		"moon": moon,
		"bg": (a["bg"] as Color).lerp(b["bg"] as Color, t),
		"fog": (a["fog"] as Color).lerp(b["fog"] as Color, t),
		"fog_begin": lerpf(float(a["fog_begin"]), float(b["fog_begin"]), t),
		"fog_end": lerpf(float(a["fog_end"]), float(b["fog_end"]), t),
		"sun_dir": dirs["sun_dir"],
		"moon_dir": dirs["moon_dir"],
		"sun_energy": maxf(sun.get_luminance() * 1.35, 0.02) * PRECIP_LIGHT_SCALE,
		"moon_energy": maxf(moon.get_luminance() * 0.9, 0.0) * PRECIP_LIGHT_SCALE,
	}


static func outdoor_light_for(weather_name: StringName) -> Dictionary:
	## Fine palette for clear/sakura; rain palette (and dim) for rain/snow.
	var kind: Kind = kind_from_name(weather_name)
	if is_precip(kind):
		return rain_outdoor_light()
	var pal: Dictionary = Clock.outdoor_light()
	return pal


static func _light_blend_public() -> float:
	var term: int = Clock.light_term()
	var t0: int = int(ClockService.LIGHT_TERM_HOURS[term]) * 3600
	var t1: int = int(ClockService.LIGHT_TERM_HOURS[term + 1]) * 3600
	if t1 <= t0:
		return 0.0
	return clampf(float(Clock.now_sec() - t0) / float(t1 - t0), 0.0, 1.0)


static func spawn_count_per_frame(kind: Kind, intensity: Intensity) -> int:
	## Rain: 1/2/3 per frame. Snow/sakura: 1 on a frame mask (caller checks).
	if intensity == Intensity.NONE or kind == Kind.CLEAR:
		return 0
	match kind:
		Kind.RAIN:
			match intensity:
				Intensity.LIGHT:
					return 1
				Intensity.NORMAL:
					return 2
				_:
					return 3
		Kind.SNOW, Kind.SAKURA:
			return 1
		_:
			return 0


static func snow_spawn_mask(intensity: Intensity) -> int:
	## Frame counter mask: light every 8, normal every 4, heavy every 2.
	match intensity:
		Intensity.LIGHT:
			return 7
		Intensity.NORMAL:
			return 3
		_:
			return 1
