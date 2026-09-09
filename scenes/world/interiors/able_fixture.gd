extends StaticBody3D

## One Able Sisters display: a clothing mannequin (`obj_shop_manekin_model`) or an
## umbrella stand (`obj_shop_umbmy_model`), each showing one shared shop design
## (`Save_Get(needlework).original_design[slot]`, `ac_needlework_indoor.c`).
##
## Pressing A in front of it starts the Mabel trade flow for this slot — decomp
## `player_buy` sets `buy_ut_idx` from the unit the player faces, then talks to Mabel.

enum Kind { CLOTH, UMBRELLA }

@export var slot: int = 0  ## 0-7 into DesignBook.shop (0-3 cloth, 4-7 umbrella)
@export var kind: Kind = Kind.CLOTH

var _model: Node3D
var _umbrella_fallback: bool = false


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("needlework_set")
	collision_layer = 1
	collision_mask = 0
	_ensure_collision()
	_ensure_visual()
	_ensure_interact()
	if Game != null and Game.designs != null and not Game.designs.changed.is_connected(_refresh_design):
		Game.designs.changed.connect(_refresh_design)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	var d: DesignPattern = _design()
	var label: String = d.name if d != null else "design"
	return [Interaction.of(Interaction.TALK, "Check \"%s\"" % label, 15)]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.TALK:
		return false
	var mabel: Node = get_tree().get_first_node_in_group("needlework_mabel") if get_tree() != null else null
	if mabel != null and mabel.has_method("begin_trade"):
		return bool(mabel.call("begin_trade", slot, ctx))
	if Game != null:
		var d: DesignPattern = _design()
		Game.post_notice("A design by the Able Sisters: \"%s\"." % (d.name if d != null else "?"))
	return true


func _design() -> DesignPattern:
	if Game == null or Game.designs == null:
		return null
	return Game.designs.shop[slot & 7]


func _refresh_design() -> void:
	var d: DesignPattern = _design()
	if d == null:
		return
	var tex: Texture2D = DesignTexture.build(d)
	GeneratedVisual.apply_design(self, tex)
	if kind == Kind.UMBRELLA:
		## `obj_shop_umbmy` binds the design to `ANIME_2` on the `umb_w` canopy.
		GeneratedVisual.paint_surface_albedo(
			self, tex, PackedStringArray(["kasa", "umbmy", "umb_w", "anime_2"])
		)


func _ensure_visual() -> void:
	if get_node_or_null("Model") != null:
		return
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var visual: StringName = &"obj_shop_manekin" if kind == Kind.CLOTH else &"obj_shop_umbmy"
	var vis: Node3D = GeneratedVisual.attach(_model, visual)
	if vis == null:
		var mesh := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.1
		cyl.bottom_radius = 0.2
		cyl.height = 1.6
		mesh.mesh = cyl
		mesh.position.y = 0.8
		_model.add_child(mesh)
		return
	_refresh_design()


func _ensure_collision() -> void:
	if get_node_or_null("CollisionShape3D") != null:
		return
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	## `l_manekin_mBgData` half-extent 14.5 GX ≈ 0.72 m in XZ; an umbrella stand is
	## much shorter than a dress form, so keep its box low.
	var h: float = 1.7 if kind == Kind.CLOTH else 0.95
	box.size = Vector3(1.45, h, 1.45)
	shape.shape = box
	shape.position = Vector3(0.0, h * 0.5, 0.0)
	add_child(shape)


func _ensure_interact() -> void:
	if get_node_or_null("InteractVolume") != null:
		return
	var volume := Area3D.new()
	volume.name = "InteractVolume"
	volume.collision_layer = 8
	volume.collision_mask = 0
	volume.monitoring = false
	volume.monitorable = true
	volume.set_script(load("res://scenes/world/interact_volume.gd"))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 2.0, 1.8)
	shape.shape = box
	shape.position = Vector3(0.0, 1.0, 0.0)
	volume.add_child(shape)
	add_child(volume)
