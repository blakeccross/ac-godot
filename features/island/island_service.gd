class_name IslandService
extends Node

## Kapp'n's boat trips (`BOAT_DEMO`, `ac_boat_demo`) without the Game Boy Advance. A dinghy and
## Kapp'n wait at the town's wharf (F-5) and at the island's landing; talking to him and answering
## yes boards the player, and the boat sails the route (`IslandRoute`) while he sings. The sea is the
## town's, so the island trip sails there and swaps to the island world on arrival
## (`mISL_ChangeBG`), and the way home swaps back and sails the other way.
##
## `Game.island_visit` says which world is up; `Game.island_ride` carries a trip across the swap.

enum State { IDLE, BOARDING, SAILING, ARRIVING, LANDING }

const BOAT_SCENE := preload("res://features/island/boat.tscn")
const KAPPN_SCENE := preload("res://features/island/kappn.tscn")
const HOP_SEC := 0.6
const HOP_HEIGHT := 0.7
## `aBTD_ACTION_SONG_BGM_START_WAIT`: the boat gets under way before the shanty starts.
const SONG_DELAY := 2.0
const SONG_GAP := 1.5

var world: World
var boat: Boat
var kappn: Kappn
var state: State = State.IDLE
var _player: Player = null
var _on_island: bool = false
var _rng := RandomNumberGenerator.new()
## Debug (`ride fast`): Kapp'n says nothing, so a trip runs unattended.
var mute: bool = false


## Put a boat and Kapp'n where this world has a wharf or a landing; resume a trip under way.
static func setup(for_world: World) -> IslandService:
	var island: bool = Game.island_visit
	if not island and not IslandRoute.town_has_wharf(for_world.layout) and Game.island_ride == &"":
		return null
	var svc := IslandService.new()
	svc.name = "IslandService"
	svc.world = for_world
	svc._on_island = island
	for_world.add_child(svc)
	svc._build()
	return svc


func _build() -> void:
	_rng.randomize()
	var parent: Node = world.get_node_or_null("Characters")
	if parent == null:
		parent = world
	boat = BOAT_SCENE.instantiate() as Boat
	parent.add_child(boat)
	var surface: Callable = func(p: Vector3) -> float: return world.fish.surface_at(p)
	var returning: bool = Game.island_ride == &"return" and not _on_island
	if _on_island:
		boat.moor(_world_point(IslandRoute.point(IslandRoute.LAST, true)), IslandRoute.LANDING_YAW, surface)
	elif returning:
		boat.moor(_world_point(IslandRoute.point(IslandRoute.LAST, false)), IslandRoute.LANDING_YAW, surface)
	else:
		boat.moor(_world_point(IslandRoute.point(0, false)), IslandRoute.WHARF_YAW, surface)
	kappn = KAPPN_SCENE.instantiate() as Kappn
	kappn.service = self
	kappn.at_island = _on_island
	parent.add_child(kappn)
	kappn.talked.connect(_on_talked)
	_seat()
	_player = Player.find(get_tree())
	var ride: StringName = Game.island_ride
	Game.island_ride = &""
	if ride == &"arrive" and _on_island:
		_board_instantly()
		_arrive(true)
	elif ride == &"return" and not _on_island:
		_board_instantly()
		_voyage(false)
	elif _on_island and _player != null:
		## Straight onto the island (the `island` command): stand by the landing.
		_player.apply_spawn(_landing_stand(true), PI * 0.5)


func is_idle() -> bool:
	return state == State.IDLE


func _physics_process(_delta: float) -> void:
	_seat()
	if state in [State.SAILING, State.ARRIVING] and _player != null and is_instance_valid(_player):
		_player.global_position = boat.seat(Boat.PASSENGER_SEAT)
		_player.apply_facing(boat.rotation.y)


func _world_point(local: Vector3) -> Vector3:
	return WorldGrid.room_point(world.grid, local)


func _seat() -> void:
	if boat == null or kappn == null or not is_instance_valid(kappn):
		return
	kappn.global_position = boat.seat(Boat.KAPPN_SEAT)
	kappn.home_yaw = boat.rotation.y + PI
	if not kappn.talking:
		kappn.rotation.y = kappn.home_yaw


# --- the talk ---------------------------------------------------------------------------

func _on_talked(script: KappnTalk) -> void:
	if state != State.IDLE or script == null or not script.ride:
		return
	_player = Player.find(get_tree())
	if _player == null:
		return
	state = State.BOARDING
	_lock(true)
	if not _on_island:
		Game.island_town_stand = _player.global_position
	await _hop(_player, boat.seat(Boat.PASSENGER_SEAT))
	if _on_island:
		## Already told he is heading home (`MSG_HEAD_BACK`); the town world takes the sailing.
		await _travel(false, &"return")
		return
	await _say(KappnTalk.new(KappnTalk.Kind.SHOVE_OFF))
	_voyage(true)


func _say(talk: KappnTalk) -> void:
	talk.female = Game.resident.player_gender == IntroSequence.GENDER_FEMALE
	if mute:
		return
	if is_instance_valid(kappn) and kappn.begin_talk(_player, talk, false):
		await kappn.talked


# --- the voyage -------------------------------------------------------------------------

## Sail the town's sea out (`out`) or home, singing on the way.
func _voyage(out: bool) -> void:
	state = State.SAILING
	boat.sail(_route(out))
	await get_tree().create_timer(SONG_DELAY).timeout
	for msg: int in _song(out):
		if not is_instance_valid(kappn):
			return
		await _say(KappnTalk.new(KappnTalk.Kind.SONG, msg))
		await get_tree().create_timer(SONG_GAP).timeout
	if boat.is_sailing():
		await boat.arrived
	if out:
		await _travel(true, &"arrive")
	else:
		_arrive(false)


func _route(out: bool) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for p: Vector3 in IslandRoute.path(out):
		pts.append(_world_point(p))
	return pts


## The three lyrics of a trip (`aBTD_sing_sendo_start_wait_init`).
func _song(out: bool) -> Array[int]:
	var female: bool = Game.resident.player_gender == IntroSequence.GENDER_FEMALE
	var pattern: int = KappnTalk.pattern_for(not out, female)
	return KappnTalk.song_messages(pattern, _rng.randi_range(0, 4), _rng.randi_range(0, 9), _rng.randi_range(0, 9))


# --- arriving ---------------------------------------------------------------------------

## The boat has touched the landing (island) or the wharf (town): Kapp'n calls it, the player steps off.
func _arrive(island: bool) -> void:
	state = State.ARRIVING
	if island:
		boat.moor(_world_point(IslandRoute.point(IslandRoute.LAST, true)), IslandRoute.LANDING_YAW, boat.surface())
	else:
		boat.moor(_world_point(IslandRoute.point(0, false)), IslandRoute.WHARF_YAW, boat.surface())
	await get_tree().create_timer(1.0).timeout
	await _say(KappnTalk.new(KappnTalk.Kind.ARRIVE_ISLAND if island else KappnTalk.Kind.ARRIVE_TOWN))
	state = State.LANDING
	await _hop(_player, _landing_stand(island))
	_lock(false)
	state = State.IDLE
	_on_island = island
	kappn.at_island = island


func _landing_stand(island: bool) -> Vector3:
	var at: Vector3
	if island:
		at = world.grid.cell_to_world(WorldGenerator.ISLAND_BOAT_UNIT + Vector2i(-2, 1))
	else:
		at = Game.island_town_stand
	var y: float = FieldCollision.ground_y_at(world.layout, world.grid, at, 0.0, false)
	if FieldCollision.has_floor(y):
		at.y = y
	return at


func _board_instantly() -> void:
	_player = Player.find(get_tree())
	if _player == null:
		return
	_lock(true)
	_player.global_position = boat.seat(Boat.PASSENGER_SEAT)


# --- helpers ----------------------------------------------------------------------------

func _lock(on: bool) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_player.set_busy(on)
	_player.set_cutscene_driven(on)
	if not on:
		_player.play_wait_idle()


func _hop(actor: Node3D, to: Vector3) -> void:
	var from: Vector3 = actor.global_position
	var tween: Tween = actor.create_tween()
	tween.tween_method(func(t: float) -> void:
		var p: Vector3 = from.lerp(to, t)
		p.y += sin(t * PI) * HOP_HEIGHT
		actor.global_position = p, 0.0, 1.0, HOP_SEC)
	await tween.finished


func _travel(to_island: bool, ride: StringName) -> void:
	await SceneTransition.play_wipe_out()
	Game.island_visit = to_island
	Game.island_ride = ride
	Game.travel_to_world()
