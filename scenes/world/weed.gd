extends Node3D

## A weed (`GRASS_A`–`GRASS_C`, `obj_zassou_a/b/c`). A pulls it (`m_player_main_remove_grass`):
## `ZASSOU1`, and on frame 17 the weed flies off over the player's shoulder
## (`bg_item_clip->fly_entry_proc`, 110° off the facing) with the `zassou_nuku` rustle.

const FLY_YAW := deg_to_rad(110.0)
const FLY_SEC := 0.5

@export var occupant_id: StringName = &""
@export var persist_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.PLANT
@export var visual_id: StringName = &"obj_zassou_a"


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("weed")
	GeneratedVisual.attach(self, visual_id)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	return [Interaction.of(Interaction.PICK_UP, "Pull weed", 10, WeedUse.PULL_ANIM, WeedUse.PULL_FRAME)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.PICK_UP:
		return false
	if not WeedUse.pull(self, ctx):
		return false
	Audio.play_se(&"zassou_nuku", self)
	var yaw: float = 0.0
	if ctx != null and ctx.actor != null and ctx.actor.has_method("facing_yaw"):
		yaw = float(ctx.actor.call("facing_yaw"))
	var away := Vector3(sin(yaw + FLY_YAW), 0.0, cos(yaw + FLY_YAW))
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(self, "global_position", global_position + away * 1.2 + Vector3.UP * 0.8, FLY_SEC)
	tw.tween_property(self, "scale", Vector3.ZERO, FLY_SEC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)
	return true
