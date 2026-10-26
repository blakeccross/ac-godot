class_name BugSpawner
extends Node3D

## Runs the field's insects (`BugField`, the `Insect_Profile` move) and keeps one `Bug`
## scene in the world for each live one, adding and freeing them as insects come and go.

const BUG_SCENE := preload("res://features/bugs/bug.tscn")
const GROUP := &"bug_spawner"

var _field: BugField = null
## `BugActor` → its `Bug` scene.
var _bugs: Dictionary = {}
## Villager positions last physics tick (instance id → metres), for their frame move.
var _npc_last: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP)
	_bind_field()


func field() -> BugField:
	return _field


func _bind_field() -> void:
	var node: Node = get_parent()
	while node != null:
		if node.get("bugs") is BugField:
			_field = node.get("bugs") as BugField
			return
		node = node.get_parent()


func _physics_process(delta: float) -> void:
	if _field == null:
		_bind_field()
		if _field == null:
			return
	var sense: BugActor.Sense = _make_sense()
	_sense_npcs(sense, delta)
	_field.advance(delta, sense)
	if _field.take_bite():
		var player := Player.find(get_tree())
		if player != null:
			player.run_stung_mosquito()
	_sync(delta, Player.find(get_tree()))


func _make_sense() -> BugActor.Sense:
	var sense := BugActor.Sense.new()
	var player := Player.find(get_tree())
	if player != null:
		sense.player_position = player.global_position
		sense.player_speed = player.planar_speed()
		sense.player_dashing = player.is_dashing()
		sense.player_yaw = player.facing_yaw()
		sense.wade_end = player.wade_end_position()
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		sense.on_screen = cam.is_position_in_frustum
	var grid: Variant = _grid_for()
	if grid is WorldGrid:
		var layout := _layout_for()
		sense.bg = BugTerrain.make_probe(grid, layout)
		sense.ground = BugTerrain.make_ground(grid, layout)
		sense.layout = layout
		sense.grid = grid
	if player != null:
		for cell: Vector2i in player.shaken_tree_cells():
			sense.shaken_cells[cell] = true
	if _field != null:
		var act: Dictionary = _field.take_field_action()
		sense.player_action = int(act.get("kind", 0))
		sense.player_action_cell = act.get("cell", Vector2i(-1, -1))
	return sense


## `aINS_get_stress` walks the NPC actor list too: a villager walking past spooks an
## insect exactly like the player does.
func _sense_npcs(sense: BugActor.Sense, delta: float) -> void:
	var seen: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("villagers"):
		var npc := node as Node3D
		if npc == null or not npc.visible or not npc.is_inside_tree():
			continue
		var id: int = npc.get_instance_id()
		var at: Vector3 = npc.global_position
		var speed: float = 0.0
		if _npc_last.has(id) and delta > 0.0:
			var last: Vector3 = _npc_last[id]
			speed = Vector2(at.x - last.x, at.z - last.z).length() / delta
		seen[id] = at
		sense.npc_positions.append(at)
		sense.npc_speeds.append(speed)
	_npc_last = seen


func _grid_for() -> Variant:
	var node: Node = get_parent()
	while node != null:
		if node.get("grid") is WorldGrid:
			return node.get("grid")
		node = node.get_parent()
	return null


func _layout_for() -> WorldData:
	var node: Node = get_parent()
	while node != null:
		var d: Variant = node.get("layout")
		if d is WorldData:
			return d
		d = node.get("world_data")
		if d is WorldData:
			return d
		node = node.get_parent()
	return null


func _sync(delta: float, player: Node3D) -> void:
	var player_position: Vector3 = player.global_position if player != null else Vector3.INF
	var live: Dictionary = {}
	for actor: BugActor in _field.actors:
		live[actor] = true
		var bug: Bug = _bugs.get(actor) as Bug
		if bug == null:
			bug = BUG_SCENE.instantiate() as Bug
			add_child(bug)
			bug.setup(actor)
			_bugs[actor] = bug
		bug.sync(delta, player_position)
	for actor: BugActor in _bugs.keys():
		if not live.has(actor):
			(_bugs[actor] as Bug).queue_free()
			_bugs.erase(actor)


## The `Bug` scene showing `actor`, or null.
## Test-only: no in-game callers; kept for tests.
func bug_for(actor: BugActor) -> Bug:
	return _bugs.get(actor) as Bug


## The field's spawner in `tree`, or null.
static func find(tree: SceneTree) -> BugSpawner:
	return tree.get_first_node_in_group(GROUP) as BugSpawner if tree != null else null
