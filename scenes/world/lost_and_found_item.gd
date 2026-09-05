extends StaticBody3D

## One lost-and-found RSV slot (`RSV_POLICE_ITEM_*` / `bg_police_item`).

@export var slot: int = 0
@export var item_id: StringName = &""

@onready var _mesh: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("police_set")
	_apply_visual()


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if item_id == &"":
		return []
	var data: ItemData = ItemCatalog.get_item(item_id)
	var label: String = data.display_name if data != null else String(item_id)
	return [Interaction.of(Interaction.TAKE, "Claim %s" % label, 15)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TAKE or Game == null:
		return false
	## Face RSV + talk to Booker (`aPOL2_message_ctrl`).
	var booker: Node = null
	if get_tree() != null:
		for node: Node in get_tree().get_nodes_in_group("police_set"):
			if node.has_method("begin_claim"):
				booker = node
				break
	if booker != null:
		return bool(booker.call("begin_claim", slot, ctx))
	var msg: String = Game.police.claim(slot, Game.inventory)
	Game.post_notice(msg)
	Game.call_deferred("refresh_police_set")
	return true


func _apply_visual() -> void:
	var data: ItemData = ItemCatalog.get_item(item_id)
	var visual: StringName = ShopDisplay.display_visual_for_item(item_id)
	var cloth: int = -1
	if data != null and data.cloth_index >= 0:
		cloth = data.cloth_index
		if visual == &"":
			visual = &"obj_shop_manekin"
	var attached: Node3D = GeneratedVisual.attach(self, visual) if visual != &"" else null
	if attached != null:
		if cloth >= 0:
			GeneratedVisual.apply_cloth(self, cloth)
		if _mesh != null:
			_mesh.visible = false
		return
	if _mesh != null and data != null:
		_mesh.visible = true
		var mat := StandardMaterial3D.new()
		mat.albedo_color = data.icon_color
		_mesh.material_override = mat
