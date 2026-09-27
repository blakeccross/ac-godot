extends Node3D

## One lost-and-found RSV slot (`RSV_POLICE_ITEM_*` / `bg_police_item`). The kept item is
## drawn as its field card (`obj_item_*` via `mNT_get_itemTableNo`) on the unit centre at
## the BG height under it, like a dropped item — the RSV unit itself has no collision.
## Pressing A while facing it hands the talk to Booker (`aPOL2_message_ctrl`).

@export var slot: int = 0
@export var item_id: StringName = &""

@onready var _mesh: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("police_set")
	_apply_visual()
	_snap_to_bg.call_deferred()


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if item_id == &"":
		return []
	var data: ItemData = ItemCatalog.get_item(item_id)
	var label: String = data.display_name if data != null else String(item_id)
	return [Interaction.of(Interaction.TAKE, "Claim %s" % label, 15)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TAKE or Game == null:
		return false
	var booker: Node = _booker()
	if booker == null:
		return false
	return bool(booker.call("begin_claim", slot, ctx))


func _booker() -> Node:
	if get_tree() == null:
		return null
	for node: Node in get_tree().get_nodes_in_group("police_set"):
		if node.has_method("begin_claim"):
			return node
	return null


func _apply_visual() -> void:
	var visual: StringName = FieldCatalog.item_visual(item_id)
	var attached: Node3D = GeneratedVisual.attach(self, visual) if visual != &"" else null
	if attached != null:
		if _mesh != null:
			_mesh.visible = false
		return
	var data: ItemData = ItemCatalog.get_item(item_id)
	if _mesh != null and data != null:
		_mesh.visible = true
		var mat := StandardMaterial3D.new()
		mat.albedo_color = data.icon_color
		_mesh.material_override = mat


## `mCoBG_GetBgY_OnlyCenter_FromWpos2(pos, 1.0f)`: sit on whatever BG is under the unit
## centre (floor or shelf top).
func _snap_to_bg() -> void:
	if not is_inside_tree():
		return
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3.UP * 4.0
	var query := PhysicsRayQueryParameters3D.create(from, global_position + Vector3.DOWN * 1.0, 1)
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		global_position.y = (hit["position"] as Vector3).y
