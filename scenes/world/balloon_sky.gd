class_name BalloonSky
extends Node3D

## `m_fuusen.c`: whether a present balloon is in the sky. At minute :x3 of every five
## (`Balloon_move`) with none out, roll against a chance that starts at 5% and grows each miss
## by 2.5% + up to 2.5% for luck (`mPr_GetGoodsPower`, Katrina's goods luck / bad luck) + up
## to 2.5% for the town's rank (not modelled: 0) + a random 0–2.5%; a hit launches one and
## resets the chance to a tenth of what it missed by. A balloon that got away near the player
## (`Balloon_look_up`) adds 25% to the next roll. Also drives the town's wind.

const BALLOON_SCRIPT := preload("res://scenes/world/balloon.gd")
const START_CHANCE := 0.05
const LOOK_UP_BONUS := 0.25
## `mPr_GOODS_POWER_MAX`.
const GOODS_POWER_MAX := 50.0

enum State { DEAD, CHECKED, SPAWNED, LOOK_UP }

var state: State = State.DEAD
var chance: float = START_CHANCE
var _last_min: int = -1
var _rng := RandomNumberGenerator.new()
var balloon: Balloon


func _ready() -> void:
	add_to_group("balloon_sky")
	_rng.randomize()


func _process(delta: float) -> void:
	Wind.tick(delta)
	if state == State.SPAWNED:
		return
	if Game != null and Game.first_job != null and Game.first_job.is_active() and not Game.first_job.open_quest:
		return
	var minute: int = Clock.minute
	if minute % 5 != 3 or minute == _last_min:
		return
	_last_min = minute
	if state == State.LOOK_UP:
		chance += LOOK_UP_BONUS
	state = State.CHECKED
	roll()


## `Balloon_chk_make_fuusen`.
func roll() -> void:
	if _rng.randf() < chance:
		launch()
		return
	var goods: float = goods_power() / GOODS_POWER_MAX
	chance += 0.025 + goods * 0.025 + 0.0 * 0.025 + _rng.randf() * 0.025


## `mPr_GetGoodsPower`: feng shui and the day's fortune.
static func goods_power() -> float:
	if Game == null:
		return 0.0
	return float(Game.goods_power_now())
	match Game.destiny():
		Game.Destiny.GOODS_LUCK:
			return 30.0
		Game.Destiny.BAD_LUCK:
			return -30.0
	return 0.0


## `Balloon_make_fuusen`.
func launch() -> Balloon:
	balloon = BALLOON_SCRIPT.new() as Balloon
	balloon.name = "Balloon"
	balloon.gone.connect(_on_gone)
	add_child(balloon)
	state = State.SPAWNED
	chance = (1.0 - chance) * 0.1
	return balloon


func _on_gone(look_up: bool) -> void:
	balloon = null
	state = State.LOOK_UP if look_up else State.DEAD
