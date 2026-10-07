extends StaticBody3D

## A signboard the player put up (`ac_sign`): the white sign model with one of their designs
## on the paper, or blank paper (`hakushi_tex`). A: "Shall I post a design?"; picking it up
## puts it back in the pockets. See `SignboardUse`.

const VISUAL := &"SIGNBOARD"
## `write_model`: the paper face the design is drawn on.
const PAPER_SURFACE := "bulletin_paper"
const BLANK_TEX := "res://assets/generated/textures/rel/hakushi_tex.png"
## `aSIGN_set_talk_info`.
const WINDOW_COLOR := Color8(185, 60, 40)

@export var occupant_id: StringName = &""


func _ready() -> void:
	add_to_group("interactable")
	GeneratedVisual.attach(self, VISUAL)
	refresh_design()


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, VISUAL)
	refresh_design()


func refresh_design() -> void:
	var design: DesignPattern = SignboardUse.design_of(occupant_id)
	var tex: Texture2D = DesignTexture.build(design) if design != null else null
	if tex == null and ResourceLoader.exists(BLANK_TEX):
		tex = load(BLANK_TEX) as Texture2D
	_paint(self, tex)


func _paint(node: Node, tex: Texture2D) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i: int in (mi.mesh.get_surface_count() if mi.mesh != null else 0):
			var mat: Material = mi.get_active_material(i)
			if not (mat is StandardMaterial3D) or not VisualSurface.surface_label(mi, i, mat).contains(PAPER_SURFACE):
				continue
			var own := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			own.albedo_texture = tex
			mi.set_surface_override_material(i, own)
	for child: Node in node.get_children():
		_paint(child, tex)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	return [
		Interaction.of(Interaction.READ, "Post a design", 8),
		Interaction.of(Interaction.PICK_UP, "Pick up signboard", 7, &"ply_1_pickup1", 20.0),
	]


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null:
		return false
	if action.id == Interaction.PICK_UP:
		return _pick_up(ctx)
	if action.id == Interaction.READ:
		await _talk()
		return true
	return false


func _pick_up(ctx: InteractionContext) -> bool:
	var item: ItemData = ItemCatalog.get_item(SignboardUse.ITEM_ID)
	if item == null or ctx == null or ctx.inventory == null or ctx.inventory.add(item, 1) != 0:
		Game.post_notice("Pockets full")
		return false
	SignboardUse.take(World.find(get_tree()), occupant_id)
	ctx.release_occupant(occupant_id)
	Audio.play_se(&"item_horidashi")
	queue_free()
	return true


## `aSIGN_talk`: CHOICE0 posts.
class PostTalk extends BankTalk:
	var post: bool = false

	func start_msg() -> int:
		return SignboardUse.MSG_HANDS_OFF if Game.foreigner else SignboardUse.MSG_POST

	func picked(msg_no: int, index: int) -> int:
		post = msg_no == SignboardUse.MSG_POST and index == 0
		return -1


## `aSIGN_set_talk_info` / `aSIGN_talk`: "Post" opens the design list (`mNW_OPEN_DESIGN`);
## a visitor is told hands off.
func _talk() -> void:
	var talk := PostTalk.new()
	var ui := DialogueOverlay.find(get_tree())
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % talk.start_msg()))
	if ui == null or data == null:
		if not Game.foreigner:
			_open_designs()
		return
	var ctx: DialogueContext = DialogueContext.from_game()
	ctx.speaker_name = ""
	ctx.voice_mode = DialogueVoice.Mode.CLICK
	ctx.window_color = WINDOW_COLOR
	talk.context = ctx
	ui.play(data, ctx, null, Callable(), talk)
	await ui.closed
	if talk.post:
		_open_designs()


func _open_designs() -> void:
	var list: Node = get_tree().get_first_node_in_group("design_list_ui")
	if list != null and list.has_method("open"):
		list.call("open", "pick_trade", Callable(self, "_on_design_picked"))


func _on_design_picked(slot: int) -> void:
	if slot < 0 or Game.designs == null or slot >= Game.designs.player.size():
		return
	SignboardUse.post(occupant_id, Game.designs.player[slot])
	refresh_design()
	## `aSIGN_change_my_original`: `NA_SE_461`.
	Audio.play_se(&"461")
