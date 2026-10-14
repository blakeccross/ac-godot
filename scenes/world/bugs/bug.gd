class_name Bug
extends Node3D

## One live insect in the field: the scene for a `BugActor` (`aINS_INSECT_ACTOR`). The actor
## record runs the species behavior; this node sits where it is, draws it (`Model`) and
## offers it to the net (`CatchArea`, on the creatures layer). `BugSpawner` makes and frees
## these as the field's insects come and go.

@onready var model: BugModel = $Model
@onready var catch_area: Area3D = $CatchArea
@onready var _catch_shape: CollisionShape3D = $CatchArea/Shape

const GROUP := &"field_bugs"

var actor: BugActor = null
## The range the insect registers with the net this frame (`aINS_get_catch_range`), GX;
## 0 while it cannot be caught.
var catch_range_gx: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)


## Binds the insect this scene shows. Call once it is in the tree.
func setup(p_actor: BugActor) -> void:
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
	catch_range_gx = row.range_gx if row != null else 0.0
	_catch_shape.disabled = row == null
	if row != null:
		(_catch_shape.shape as SphereShape3D).radius = catch_range_gx * FieldCatalog.GX_TO_METERS


## The `Bug` that owns `area` (a `CatchArea`), or null.
static func of_area(area: Object) -> Bug:
	var node := area as Node
	return node.get_parent() as Bug if node != null else null
