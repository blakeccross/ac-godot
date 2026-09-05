extends Node3D

## Ground item. Offers pick_up; pockets refuse if full (`mPr`).
## Tree shake can spawn this mid-air and tween it onto the tile (`fruit_set`).

@export var item: ItemData
@export var persist_id: StringName = &"ground_apple"
@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.ITEM

var _fall: Tween
var _pocket_pulling: bool = false
signal landed


func _ready() -> void:
	add_to_group("interactable")
	if Game.is_interactable_removed(persist_id):
		queue_free()
		return
	_apply_visual()


func _apply_visual() -> void:
	if item == null:
		return
	## Prefer the disc item card (`obj_item_apple` etc.) over the sphere placeholder.
	var visual: StringName = FieldCatalog.item_visual(item.id)
	if visual != &"" and GeneratedVisual.attach(self, visual) != null:
		return
	GeneratedVisual.apply_item_albedo(self, item.id)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if item == null or _fall != null or _pocket_pulling:
		return []
	## `mPlayer_ANIM_PICKUP1`: pocket write + shrink start at frame 20
	## (`Player_actor_Set_Item_Pickup`).
	return [
		Interaction.of(Interaction.PICK_UP, "Pick up %s" % item.display_name, 15, &"ply_1_pickup1", 20.0)
	]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.PICK_UP or item == null or ctx == null:
		return false
	if _fall != null or _pocket_pulling:
		return false
	if ctx.inventory == null or not ctx.inventory.has_space_for(item, 1):
		Game.post_notice("Pockets full")
		return false
	if ctx.inventory.add(item, 1) != 0:
		Game.post_notice("Pockets full")
		return false
	Game.mark_interactable_removed(persist_id)
	var id: StringName = persist_id if persist_id != &"" else occupant_id
	ctx.release_occupant(id)
	Game.post_notice("Picked up %s" % item.display_name)
	_pocket_pulling = true
	## Shrink into the left hand while the rest of PICKUP1 plays (`Set_Item_Pickup`).
	await PocketPull.run(self, PocketPull.hand_from_context(ctx, global_position))
	_pocket_pulling = false
	queue_free()
	return true


## Ballistic-ish fall from crown to tile (`fruit_set` drop_speed / accel).
func begin_fall(from: Vector3, to: Vector3, duration: float, floaty: bool = false) -> void:
	global_position = from
	if duration <= 0.0:
		global_position = to
		landed.emit()
		return
	if _fall != null and is_instance_valid(_fall):
		_fall.kill()
	_fall = create_tween()
	var mid := from.lerp(to, 0.45)
	if floaty:
		## Furniture leaf: slight upward loft (`acceleration_y = +0.15`).
		mid.y = maxf(from.y, to.y) + 0.35
		_fall.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		## Normal fruit/money: peak then drop (`acceleration_y = -1.2`).
		mid.y = maxf(from.y, to.y) + 0.15
		_fall.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fall.tween_property(self, "global_position", mid, duration * 0.4)
	_fall.tween_property(self, "global_position", to, duration * 0.6)
	_fall.finished.connect(_on_landed, CONNECT_ONE_SHOT)


func _on_landed() -> void:
	_fall = null
	landed.emit()
