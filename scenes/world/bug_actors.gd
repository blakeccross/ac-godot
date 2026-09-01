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


func _process(delta: float) -> void:
	if _field == null:
		_bind_field()
		if _field == null:
			return
	var sense: BugActor.Sense = _make_sense()
	_field.tick(delta, sense)
	_sync(delta)


func _make_sense() -> BugActor.Sense:
	var sense := BugActor.Sense.new()
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D if get_tree() else null
	if player != null:
		sense.player_position = player.global_position
		if player.has_method("is_dashing"):
			sense.player_dashing = bool(player.call("is_dashing"))
	return sense


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
