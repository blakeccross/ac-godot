extends StaticBody3D

## One shelf good (`ac_shop_goods` / mannequin). Buy spends Bells and removes the listing.

@export var shop_id: StringName = &""
@export var item_id: StringName = &""
@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = false
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.FURNITURE

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("shop_set")
	_apply_visual()


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null:
		return []
	var price: int = ShopBook.buy_price(data)
	return [Interaction.of(Interaction.BUY, "Buy %s (%d)" % [data.display_name, price], 10)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.BUY:
		return false
	var msg: String = Game.shops.buy(shop_id, item_id, Game.inventory)
	Game.post_notice(msg)
	## Defer so this host is not freed while `interact` is still running.
	Game.call_deferred("refresh_shop_set")
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
		_paint_sample(data)
		if _mesh != null:
			_mesh.visible = false
		return
	if _mesh != null and data != null:
		_mesh.visible = true
		_mesh.material_override = _tint(data.icon_color)
	_fit_placeholder()


func _paint_sample(data: ItemData) -> void:
	## Wallpaper / carpet sample stands show the listed bank page when present.
	if data == null:
		return
	match data.category:
		ItemData.Category.WALL:
			var path: String = InteriorCatalog.wall_texture_path(data.id)
			if path.is_empty():
				return
			var tex: Texture2D = load(path) as Texture2D
			if tex != null:
				GeneratedVisual._paint_albedo(self, tex)
		ItemData.Category.FLOOR:
			var path: String = InteriorCatalog.floor_texture_path(data.id)
			if path.is_empty():
				return
			var tex: Texture2D = load(path) as Texture2D
			if tex != null:
				GeneratedVisual._paint_albedo(self, tex)


func _fit_placeholder() -> void:
	var w: float = 0.7
	var d: float = 0.7
	if _collision != null and _collision.shape is BoxShape3D:
		(_collision.shape as BoxShape3D).size = Vector3(w, 0.8, d)
		_collision.position.y = 0.4
	if _mesh != null and _mesh.mesh is BoxMesh:
		(_mesh.mesh as BoxMesh).size = Vector3(w * 0.7, 0.7, d * 0.7)
		_mesh.position.y = 0.35


func _tint(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat
