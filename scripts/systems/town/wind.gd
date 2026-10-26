class_name Wind
extends RefCounted

## The town's wind (`m_kankyo_weather.c_inc`: `mEnv_wind_info`). Each day picks a power range
## by season (`mEnv_DecideTodayWindPowerRange`: calm 0–0.4 / normal 0.4–0.6 / strong 0.6–1.0);
## the direction starts random and every 10 minutes drifts up to ±15°, the power toward a new
## value inside the range (`mEnv_ChangeWind`, stepped over the next 10 minutes). Koinobori day
## blows steadily from 135° at full power. Gusts are not modelled.

## `mEnv_WIND_CHANGE_RATE`: 10 minutes of 60 Hz ticks.
const CHANGE_TICKS := 10.0 * 60.0 * 60.0
## `wind_term` month/day ends and `pow_table` calm / normal / strong percents.
const TERMS: Array = [[1, 7], [4, 5], [8, 19], [9, 30]]
const POWER_TABLE: Array = [[10, 80, 10], [0, 70, 30], [10, 80, 10], [0, 70, 30], [10, 80, 10]]
const KOINOBORI_ANGLE := 0x6000

static var _day: String = ""
static var _range: Vector2 = Vector2(0.4, 0.6)
## Binangles as floats (`wind_angle` is stored that way).
static var _angle: float = 0.0
static var _angle_target: float = 0.0
static var _angle_step: float = 0.0
static var _power: float = 0.5
static var _power_target: float = 0.5
static var _power_step: float = 0.0
static var _change_left: float = 0.0
static var _inited: bool = false
static var _rng := RandomNumberGenerator.new()


## `mEnv_GetWindAngleS` as a yaw (radians, 0 = +Z).
static func yaw() -> float:
	return fmod(_angle, 65536.0) / 65536.0 * TAU


static func angle_s() -> int:
	return int(_angle) & 0xFFFF


## `mEnv_GetWindPowerF` (0–1).
static func power() -> float:
	return clampf(_power, 0.0, 1.0)


static func _koinobori() -> bool:
	return Game != null and Game.events != null and Game.events.is_today(&"koinobori")


## `mEnv_GetWindPowerTableTerm`.
static func term(month: int, day: int) -> int:
	for i: int in TERMS.size():
		var t: Array = TERMS[i]
		if month < int(t[0]) or (month == int(t[0]) and day <= int(t[1])):
			return i
	return TERMS.size()


## Advance by `delta` seconds (60 Hz steps, like `mEnv_WindMove`).
static func tick(delta: float) -> void:
	var today: String = "%d-%d-%d" % [Clock.year, Clock.month, Clock.day]
	if today != _day:
		_day = today
		_decide_range()
		if not _inited:
			_init_wind()
	var ticks: float = delta * DecompTime.TICK_HZ
	_change_left -= ticks
	if _change_left <= 0.0:
		_change_left = CHANGE_TICKS
		_change()
	_angle = _approach(_angle, _angle_target, absf(_angle_step) * ticks)
	_power = _approach(_power, _power_target, absf(_power_step) * ticks)


static func _approach(v: float, target: float, step: float) -> float:
	if absf(target - v) <= step:
		return target
	return v + signf(target - v) * step


static func _decide_range() -> void:
	_rng.randomize()
	var pct: Array = POWER_TABLE[term(Clock.month, Clock.day)]
	var roll: int = _rng.randi_range(0, 99)
	if roll < int(pct[0]):
		_range = Vector2(0.0, 0.4)
	elif roll < int(pct[0]) + int(pct[1]):
		_range = Vector2(0.4, 0.6)
	else:
		_range = Vector2(0.6, 1.0)


## `mEnv_InitWind`.
static func _init_wind() -> void:
	_inited = true
	if _koinobori():
		_angle_target = KOINOBORI_ANGLE
		_power_target = 1.0
	else:
		_angle_target = _rng.randf() * 65536.0
		_power_target = _range.x + _rng.randf() * (_range.y - _range.x)
	_angle = _angle_target
	_power = _power_target
	_angle_step = 0.0
	_power_step = 0.0
	_change_left = CHANGE_TICKS


## `mEnv_ChangeWind`.
static func _change() -> void:
	if _koinobori():
		_angle = KOINOBORI_ANGLE
		_angle_target = KOINOBORI_ANGLE
		_power = 1.0
		_power_target = 1.0
		_angle_step = 0.0
		_power_step = 0.0
		return
	var adjust: float = _rng.randf() * 5461.0 - 5461.0 / 2.0
	_angle_target = _angle + adjust
	_angle_step = adjust / CHANGE_TICKS
	_power_target = _range.x + _rng.randf() * (_range.y - _range.x)
	_power_step = (_power_target - _power) / CHANGE_TICKS
