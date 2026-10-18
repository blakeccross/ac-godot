class_name InteractVolume
extends Area3D

## A host's interactable component: the sensor the player's probe sees, and what it offers.
## `InteractionQuery` talks only to this node.
##
## Verbs that depend only on the tool held are authored on it in the scene (`verbs`). A
## host whose verbs depend on more (the hour, its own state) supplies them from
## `get_interactions(ctx)`. Either way the host carries them out in `interact(action, ctx)`,
## which may await; a host with no `interact` hears `activated` instead. Both methods are
## found once, on the nearest ancestor that has `interact`; this is the one place that duck
## typing lives.

## A verb was picked on a host with no `interact` of its own.
signal activated(action: Interaction, ctx: InteractionContext)

@export var verbs: Array[InteractionVerb] = []

## The actor this belongs to: the nearest ancestor with `interact`, else the parent.
var host: Node:
	get:
		if _host == null:
			_bind()
		return _host

var _host: Node
var _offers: Callable
var _handle: Callable


func _enter_tree() -> void:
	collision_layer = 8
	collision_mask = 0
	monitoring = false
	monitorable = true


## The volume a host offers its verbs through (its own child, or itself), or null.
static func of(node: Node) -> InteractVolume:
	if node == null:
		return null
	if node is InteractVolume:
		return node as InteractVolume
	for child: Node in node.get_children():
		if child is InteractVolume:
			return child as InteractVolume
	return null


## What the player can do here now: the fixed verbs that apply, then the host's own.
func offers(ctx: InteractionContext) -> Array[Interaction]:
	var out: Array[Interaction] = []
	for verb: InteractionVerb in verbs:
		if verb != null and verb.applies(ctx):
			out.append(verb.to_interaction())
	if host != null and _offers.is_valid():
		var raw: Variant = _offers.call(ctx)
		if raw is Array:
			for action: Variant in raw:
				if action is Interaction:
					out.append(action as Interaction)
	return out


## Carry out `action`: the host's `interact` (awaitable; false when it did not take), or
## `activated` for a host without one.
func activate(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null:
		return false
	if host != null and _handle.is_valid():
		return bool(await _handle.call(action, ctx))
	activated.emit(action, ctx)
	return true


func _bind() -> void:
	var cursor: Node = get_parent()
	while cursor != null:
		if cursor.has_method(&"interact"):
			_host = cursor
			_handle = Callable(cursor, &"interact")
			if cursor.has_method(&"get_interactions"):
				_offers = Callable(cursor, &"get_interactions")
			return
		cursor = cursor.get_parent()
	_host = get_parent()
