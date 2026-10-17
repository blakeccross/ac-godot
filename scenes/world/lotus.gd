extends Node3D

## FG `LOTUS` (`ac_lotus`): a lily-pad cluster floating on a pond. Leaves sway on the baked
## `obj_s_lotus` clip; the flower joint only draws from May 26 through Aug 25.
## Not solid (it floats on water) and has no verb.

@export var visual_id: StringName = &"obj_s_lotus"
@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = false

## `cKF_SkeletonInfo_R_init(…, 1.0, 129.0, 1.0, 0.5, …, TRUE)`: loops at half speed.
const CLIP_SPEED := 0.5
const FLOWER_MESH := "obj_s_lotus"

var _anim: AnimationPlayer


func _ready() -> void:
	_attach()
	if Clock != null and not Clock.day_changed.is_connected(_sync_flower):
		Clock.day_changed.connect(_sync_flower)


func _exit_tree() -> void:
	if Clock != null and Clock.day_changed.is_connected(_sync_flower):
		Clock.day_changed.disconnect(_sync_flower)


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, visual_id)
	_attach_done()


func _attach() -> void:
	if GeneratedVisual.attach(self, visual_id) == null:
		return
	_attach_done()


func _attach_done() -> void:
	_anim = VisualAnimation.find_animation_player(self)
	if _anim != null:
		var clip: StringName = _first_clip(_anim)
		if clip != &"":
			_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			_anim.speed_scale = CLIP_SPEED
			_anim.play(clip)
	_sync_flower()


func _sync_flower() -> void:
	var shown: bool = flower_in_bloom(Clock.month if Clock != null else 6, Clock.day if Clock != null else 1)
	var flower: Node = _find_named(self, FLOWER_MESH)
	if flower is MeshInstance3D:
		(flower as MeshInstance3D).visible = shown


## `aLOT_actor_draw_before` joint 0x12: `on_off_tbl` is May–Jul, with the May and Aug day-26 edges.
static func flower_in_bloom(month: int, day: int) -> bool:
	if month == 5:
		return day >= 26
	if month == 8:
		return day < 26
	return month == 6 or month == 7


func _first_clip(anim: AnimationPlayer) -> StringName:
	for clip: StringName in anim.get_animation_list():
		if clip != &"RESET":
			return clip
	return &""


func _find_named(node: Node, want: String) -> Node:
	if node is MeshInstance3D and node.name == want:
		return node
	for child in node.get_children():
		var found: Node = _find_named(child, want)
		if found != null:
			return found
	return null
