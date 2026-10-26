class_name Bug
extends Node3D

## One live insect in the field: the scene for a `BugActor` (`aINS_INSECT_ACTOR`). The actor
## record runs the species behavior; this node sits where it is, draws it (`Model`) and
## offers it to the net (`CatchArea`, on the creatures layer). `BugSpawner` makes and frees
## these as the field's insects come and go. In a museum case the same scene shows a
## donated insect instead (`setup_display`), driven by a `MuseumInsectActor` and never netted.

@onready var model: BugModel = $Model
@onready var _catch_shape: CollisionShape3D = $CatchArea/Shape

const GROUP := &"field_bugs"

var actor: BugActor = null
## Set instead of `actor` for a museum case insect.
var display_actor: MuseumInsectActor = null
## The range the insect registers with the net this frame (`aINS_get_catch_range`), GX;
## 0 while it cannot be caught.
var catch_range: float = 0.0


## Binds the field insect this scene shows. Call once it is in the tree.
func setup(p_actor: BugActor) -> void:
	add_to_group(GROUP)
	actor = p_actor
	model.build(actor.bug, actor.is_swarm())
	sync(0.0, Vector3.INF)


## Follows the actor after its step. `player_position` (metres; `INF` with no player) gates
## the trunk insects' catch range on which side the player stands (`aINS_get_catch_range`).
func sync(delta: float, player_position: Vector3) -> void:
	if actor == null:
		return
	global_position = actor.position
	model.sync(actor, delta)
	var row: NetSwing.Candidate = actor.net_candidate(
		player_position if player_position != Vector3.INF else actor.position
	)
	## The catch sphere is the insect's registered range; the net's own reach is the
	## sphere the net queries with, so overlap is the decomp's `reach + range` test.
	catch_range = row.catch_range if row != null else 0.0
	_catch_shape.disabled = row == null
	if row != null:
		(_catch_shape.shape as SphereShape3D).radius = catch_range


## Binds a museum case insect. Call once it is in the tree.
func setup_display(p_actor: MuseumInsectActor) -> void:
	display_actor = p_actor
	model.build(display_actor.bug)
	_catch_shape.disabled = true
	_follow_display(0.0)


func _process(delta: float) -> void:
	if display_actor != null:
		_follow_display(delta)


func _follow_display(delta: float) -> void:
	display_actor.advance(delta)
	global_position = display_actor.position
	model.sync_display(display_actor)


## The `Bug` that owns `area` (a `CatchArea`), or null.
static func of_area(area: Object) -> Bug:
	var node := area as Node
	return node.get_parent() as Bug if node != null else null
