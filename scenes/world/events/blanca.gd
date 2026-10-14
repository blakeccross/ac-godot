extends EventNpc

## Blanca (`ac_npc_mask_cat` in town, `ac_npc_mask_cat2` on the train; skeleton `mka_1`). Her face
## is the drawn design on the face quad (`ANIME_1_TXT_SEG` ← `mask_cat.design`, its palette),
## so she has no blink or mouth. She wears one of Nook's A/B/C shirts (`mask_cat.cloth_no`).
##
## `on_train`: she has just come in on the traveller's train and asks for a face at once; the
## editor opens on her blank face, and a face back is the town's (`MaskCat.store`). `done` fires
## when she has one.

signal done

var on_train: bool = false
var _first_today: bool = true
var _asked: bool = false


func _init() -> void:
	species = &"mka"
	display_name = "Blanca"


func setup() -> void:
	var cloth: int = int(MaskCat.state().get("cloth", -1))
	if cloth >= 0:
		VisualCloth.apply_cloth(self, cloth)
	show_face(MaskCat.face() if not on_train else MaskCat.blank_face())
	if on_train:
		call_deferred("_ask_for_face")


## No blink or mouth flap: the face is a picture.
func _process(_delta: float) -> void:
	pass


func show_face(d: DesignPattern) -> void:
	var m: Node3D = model()
	if m == null:
		return
	var tex: Texture2D = DesignTexture.build(d)
	for node: Node in m.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for i: int in mesh.mesh.get_surface_count():
			var mat := mesh.get_active_material(i) as StandardMaterial3D
			if mat == null or not _is_eye_segment(mesh, i):
				continue
			var own := mat.duplicate() as StandardMaterial3D
			own.albedo_texture = tex
			mesh.set_surface_override_material(i, own)


static func _is_eye_segment(mesh: MeshInstance3D, surface: int) -> bool:
	var mat: Material = mesh.mesh.surface_get_material(surface)
	if mat == null:
		return false
	var label := String(mat.resource_name)
	return label == "mka_1_face" or label.begins_with("seg_08")


func make_talk() -> BankTalk:
	var t := BlancaTalk.new(BlancaTalk.Kind.TOWN, rng(), _first_today)
	_first_today = false
	return t


func _ask_for_face() -> void:
	if _asked:
		return
	_asked = true
	var kind: int = BlancaTalk.Kind.ASK_AGAIN if Game.met_blanca else BlancaTalk.Kind.ASK
	Game.met_blanca = true
	if not begin_talk(player_node(), BlancaTalk.new(kind, rng())):
		done.emit()


func talk_ended(script: BankTalk) -> void:
	var t := script as BlancaTalk
	if not on_train or t == null:
		super.talk_ended(script)
		return
	match t.kind:
		BlancaTalk.Kind.ASK, BlancaTalk.Kind.ASK_AGAIN, BlancaTalk.Kind.REDO:
			_open_editor()
		BlancaTalk.Kind.THANKS:
			## Off she goes to see the town with her new face.
			on_train = false
			done.emit()
			queue_free()


## `aNM2_draw_menu_open_wait` → the design editor on her face; `aNM2_msg_win_open_wait` decides.
func _open_editor() -> void:
	var editor: Node = get_tree().get_first_node_in_group("design_ui")
	var face: DesignPattern = MaskCat.blank_face()
	if editor == null or not editor.has_method("open_pattern"):
		done.emit()
		return
	editor.call("open_pattern", face, func(_saved: bool) -> void:
		if MaskCat.is_drawn(face):
			MaskCat.store(face, Game.player_name, EventDates.ordinal(Clock.year, Clock.month, Clock.day))
			show_face(face)
			begin_talk(player_node(), BlancaTalk.new(BlancaTalk.Kind.THANKS, rng()))
		else:
			begin_talk(player_node(), BlancaTalk.new(BlancaTalk.Kind.REDO, rng()))
	)
