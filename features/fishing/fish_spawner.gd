class_name FishSpawner
extends Node3D

## Runs the field's fish (`FishSchool`, `Gyoei_Profile`'s move) and the rod (`Fishing`) by
## `delta`, and keeps a `Fish` scene in the water for each shadow and each escape puff,
## adding and freeing them as they come and go.

const FISH_SCENE := preload("res://features/fishing/fish.tscn")
const GROUP := &"fish_spawner"
## `aGYO_KAGE`'s own ring at `delete_timer == 96`, four ticks in.
const KAGE_RIPPLE_SEC := 4.0 / DecompTime.TICK_HZ

var _school: FishSchool = null
## `FishShadow` / `FishSchool.Puff` → its `Fish` scene.
var _fish: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)
	_bind_school()


func school() -> FishSchool:
	return _school


## The field's spawner in `tree`, or null.
static func find(tree: SceneTree) -> FishSpawner:
	return tree.get_first_node_in_group(GROUP) as FishSpawner if tree != null else null


func _bind_school() -> void:
	var node: Node = get_parent()
	while node != null and not node is World:
		node = node.get_parent()
	if node == null:
		return
	_school = (node as World).fish


func _process(delta: float) -> void:
	if _school == null:
		_bind_school()
		if _school == null:
			return
	## The shadows move first and the bobber reads what they did, the way the actors take
	## turns.
	var sense: FishShadow.Sense = _make_sense()
	_school.tick(delta, sense)
	_school.line.tick(delta, _school)
	_sync()


func _make_sense() -> FishShadow.Sense:
	var sense := FishShadow.Sense.new()
	var player := Player.find(get_tree())
	if player != null:
		sense.player_position = player.global_position
		sense.player_dashing = player.is_dashing()
	if _school != null:
		_school.line.fill_sense(sense)
	return sense


func _sync() -> void:
	var live: Dictionary = {}
	for shadow: FishShadow in _school.shadows:
		live[shadow] = true
		_fish_for(shadow).place(
			shadow.position, _school.surface_at(shadow.position), shadow.yaw,
			shadow.shadow_extent(), FishSize.shadow_alpha(shadow.size), shadow.body_blend()
		)
	for puff: FishSchool.Puff in _school.puffs:
		live[puff] = true
		_puff_ripples(puff)
		_fish_for(puff).place(
			puff.position, _school.surface_at(puff.position), puff.yaw,
			FishSize.shadow_size(puff.size), puff.alpha(),
			FishSize.body_blend(FishSize.anim_frame(puff.age))
		)
	for key: Variant in _fish.keys():
		if not live.has(key):
			(_fish[key] as Fish).queue_free()
			_fish.erase(key)


func _fish_for(key: Object) -> Fish:
	var fish: Fish = _fish.get(key) as Fish
	if fish == null:
		fish = FISH_SCENE.instantiate() as Fish
		add_child(fish)
		_fish[key] = fish
	return fish


func _puff_ripples(puff: FishSchool.Puff) -> void:
	var on_water := Vector3(puff.position.x, _school.surface_at(puff.position), puff.position.z)
	if puff.ripples == 0:
		puff.ripples = 1
		if puff.birth_ripple >= 0:
			FootstepEffects.ripple(on_water, puff.birth_ripple)
	if puff.ripples == 1 and puff.age >= KAGE_RIPPLE_SEC:
		puff.ripples = 2
		var arg: int = puff.kage_ripple()
		if arg >= 0:
			FootstepEffects.ripple(on_water, arg)
