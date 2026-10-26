class_name Wind
extends RefCounted

## The town's wind (`m_kankyo_weather.c_inc`: `mEnv_wind_info`). Each day picks a power range
## by season (`mEnv_DecideTodayWindPowerRange`: calm 0–0.4 / normal 0.4–0.6 / strong 0.6–1.0);
## the direction starts random and every 10 minutes drifts up to ±15°, the power toward a new
## value inside the range (`mEnv_ChangeWind`, stepped over the next 10 minutes). Koinobori day
## blows steadily from 135° at full power. Gusts are not modelled.
##
## One per play session, on `Game.wind` (the decomp keeps it in `Common`, so it carries
## through buildings and back); the town `World` steps it outdoors.

## `mEnv_WIND_CHANGE_RATE`: 36000 ticks, ten minutes.
const CHANGE_SECONDS := 36000.0 * DecompTime.TICK_SEC
## `wind_term` month/day ends and `pow_table` calm / normal / strong percents.
const TERMS: Array = [[1, 7], [4, 5], [8, 19], [9, 30]]
const POWER_TABLE: Array = [[10, 80, 10], [0, 70, 30], [10, 80, 10], [0, 70, 30], [10, 80, 10]]
const KOINOBORI_ANGLE := 0x6000

var _day: String = ""
var _range: Vector2 = Vector2(0.4, 0.6)
## Binangles as floats (`wind_angle` is stored that way).
var _angle: float = 0.0
var _angle_target: float = 0.0
## Binangle a second toward the target, spread evenly over the change.
var _angle_rate: float = 0.0
var _power: float = 0.5
var _power_target: float = 0.5
## Power a second toward the target.
var _power_rate: float = 0.0
## Seconds to the next change.
var _change_left: float = 0.0
var _inited: bool = false
var _rng := RandomNumberGenerator.new()


## `mEnv_GetWindAngleS` as a yaw (radians, 0 = +Z).
func yaw() -> float:
	return fmod(_angle, 65536.0) / 65536.0 * TAU


func angle_s() -> int:
	return int(_angle) & 0xFFFF


## `mEnv_GetWindPowerF` (0–1).
func power() -> float:
	return clampf(_power, 0.0, 1.0)


func _koinobori() -> bool:
	return Game != null and Game.events != null and Game.events.is_today(&"koinobori")


## `mEnv_GetWindPowerTableTerm`.
static func term(month: int, day: int) -> int:
	for i: int in TERMS.size():
		var t: Array = TERMS[i]
		if month < int(t[0]) or (month == int(t[0]) and day <= int(t[1])):
			return i
	return TERMS.size()


## `mEnv_WindMove`, `delta` seconds of it.
func advance(delta: float) -> void:
	var today: String = "%d-%d-%d" % [Clock.year, Clock.month, Clock.day]
	if today != _day:
		_day = today
		_decide_range()
		if not _inited:
			_init_wind()
	_change_left -= delta
	if _change_left <= 0.0:
		_change_left = CHANGE_SECONDS
		_change()
	_angle = move_toward(_angle, _angle_target, absf(_angle_rate) * delta)
	_power = move_toward(_power, _power_target, absf(_power_rate) * delta)


func _decide_range() -> void:
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
func _init_wind() -> void:
	_inited = true
	if _koinobori():
		_angle_target = KOINOBORI_ANGLE
		_power_target = 1.0
	else:
		_angle_target = _rng.randf() * 65536.0
		_power_target = _range.x + _rng.randf() * (_range.y - _range.x)
	_angle = _angle_target
	_power = _power_target
	_angle_rate = 0.0
	_power_rate = 0.0
	_change_left = CHANGE_SECONDS


## `mEnv_ChangeWind`.
func _change() -> void:
	if _koinobori():
		_angle = KOINOBORI_ANGLE
		_angle_target = KOINOBORI_ANGLE
		_power = 1.0
		_power_target = 1.0
		_angle_rate = 0.0
		_power_rate = 0.0
		return
	var adjust: float = _rng.randf() * 5461.0 - 5461.0 / 2.0
	_angle_target = _angle + adjust
	_angle_rate = adjust / CHANGE_SECONDS
	_power_target = _range.x + _rng.randf() * (_range.y - _range.x)
	_power_rate = (_power_target - _power) / CHANGE_SECONDS
