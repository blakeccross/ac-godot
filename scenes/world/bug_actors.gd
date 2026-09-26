extends Node3D

## Presents live insects and drives their clock. Analog of `Insect_Profile` draw/move.

var _field: BugField = null
var _nodes: Array[BugActorVisual] = []


func _ready() -> void:
	add_to_group("bug_actors")
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
	_field.tick(delta, sense)
	_sync(delta)


func _make_sense() -> BugActor.Sense:
	var sense := BugActor.Sense.new()
	var player := Player.find(get_tree())
	if player != null:
		sense.player_position = player.global_position
		sense.player_move_gx = player.insect_stress_move_gx()
		sense.player_dashing = player.is_dashing()
		sense.player_yaw = player.facing_yaw()
	var grid: Variant = _grid_for()
	if grid is WorldGrid:
		sense.bg = BugBg.make_probe(grid, _layout_for())
		sense.grid = grid
	if player != null:
		for cell: Vector2i in player.shaken_tree_cells():
			sense.shaken_cells[cell] = true
	if _field != null:
		var act: Dictionary = _field.take_field_action()
		sense.player_action = int(act.get("kind", 0))
		sense.player_action_cell = act.get("cell", Vector2i(-1, -1))
	return sense


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


func _sync(delta: float) -> void:
	_fit(_field.actors.size())
	for i: int in _field.actors.size():
		var actor: BugActor = _field.actors[i]
		var visual: BugActorVisual = _nodes[i]
		if visual.bug_id != actor.bug.id:
			remove_child(visual)
			visual.free()
			visual = BugActorVisual.create(actor.bug)
			add_child(visual)
			_nodes[i] = visual
		visual.sync(actor, delta)


func _fit(want: int) -> void:
	while _nodes.size() < want:
		var visual := BugActorVisual.create(null)
		add_child(visual)
		_nodes.append(visual)
	for i: int in range(want, _nodes.size()):
		_nodes[i].visible = false
