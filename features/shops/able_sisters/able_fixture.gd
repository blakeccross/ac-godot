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


func _ready() -> void:
	_ensure_visual()
	if not Game.designs.changed.is_connected(_refresh_design):
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
	var d: DesignPattern = _design()
	Game.post_notice("A design by the Able Sisters: \"%s\"." % (d.name if d != null else "?"))
	return true


func _design() -> DesignPattern:
	return Game.designs.shop[slot & 7]


func _refresh_design() -> void:
	var d: DesignPattern = _design()
	if d == null:
		return
	var tex: Texture2D = DesignTexture.build(d)
	VisualCloth.apply_design(self, tex)
	if kind == Kind.UMBRELLA:
		## `obj_shop_umbmy` binds the design to `ANIME_2` (`seg_09`) for the canopy only;
		## the handle is the plain `tol_umb_w_tuka` texture and keeps it.
		VisualCloth.paint_surface_albedo(self, tex, PackedStringArray(["seg_09", "anime_2"]))


## The display's model under `Model`.
func _ensure_visual() -> void:
	_model = $Model
	var visual: StringName = &"obj_shop_manekin" if kind == Kind.CLOTH else &"obj_shop_umbmy"
	var vis: Node3D = GeneratedVisual.attach(_model, visual)
	if vis != null:
		_refresh_design()
