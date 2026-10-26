extends Control

## Draws the ground-item name (`GroundItemLabel`) in the 320×240 font window.
## The pieces are `fki_win`: the body centered on the origin, the two tail ovals
## toward the player, and the glyphs inset from the body's top-left. Prim is (255, 255, 215).

const CREAM := Color(1.0, 1.0, 215.0 / 255.0)
const BODY_TEX := preload("res://assets/ui/fki_name_body.png")
const FADE_TEX := preload("res://assets/ui/fki_name_fade.png")

@onready var _bubble: TextureRect = %Bubble
@onready var _joint: TextureRect = %TailMid
@onready var _tip: TextureRect = %TailTip
@onready var _name: Label = %Name

var _popup := GroundItemLabel.Reveal.new()
var _frozen_px := Vector2.ZERO
var _frozen_side := Vector2.ONE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.visible = false
	_joint.visible = false
	_tip.visible = false
	_joint.modulate = CREAM
	_tip.modulate = CREAM


func _process(delta: float) -> void:
	var player := Player.find(get_tree())
	var label := ""
	var player_px := Vector2.ZERO
	var side := Vector2.ONE
	var viewport := get_viewport().get_visible_rect().size
	if player != null and _can_show(player):
		var grid := _grid_of(player)
		if grid != null:
			label = GroundItemLabel.label_for(
				player.global_position,
				player.facing_yaw(),
				grid,
				_spots(),
				Game == null or not Game.is_indoors(),
			)
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var head := player.global_position + Vector3.UP * GroundItemLabel.HEAD
			if not cam.is_position_behind(head):
				player_px = cam.unproject_position(head)
				side = GroundItemLabel.flip_for(player_px, viewport, player.facing_yaw())
	var held := false
	var follow := get_viewport().get_camera_3d() as FollowCamera
	if follow != null:
		held = follow.name_window_held()
	_popup.advance(delta, label, held)
	_show_frame(player_px, side, viewport)


func _can_show(player: Player) -> bool:
	if Game != null and Game.title_demo_active:
		return false
	if not player.is_waiting():
		return false
	if Game == null or not Game.is_indoors():
		return true
	## Loose items in your rooms; nothing in shops, the museum, or a villager's house.
	return PlayerHouse.is_player_room(Game.current_room_id)


func _grid_of(player: Node) -> WorldGrid:
	var cursor: Node = player
	while cursor != null:
		var grid: Variant = cursor.get("grid")
		if grid is WorldGrid:
			return grid
		cursor = cursor.get_parent()
	return null


func _spots() -> Array:
	var tree := get_tree()
	if tree == null:
		return []
	var spots: Array = []
	for node: Node in tree.get_nodes_in_group(ItemPickup.GROUP):
		var pickup := node as ItemPickup
		if pickup == null or pickup.item == null:
			continue
		var id := pickup.occupant_id if pickup.occupant_id != &"" else pickup.persist_id
		var furniture := pickup.item.category == ItemData.Category.FURNITURE
		var text := "Present" if pickup.wrapped else pickup.item.display_name
		spots.append(GroundItemLabel.make(id, pickup.global_position, text, false, false, furniture))
	var sign_item: ItemData = ItemCatalog.get_item(SignboardUse.ITEM_ID)
	var sign_name := sign_item.display_name if sign_item != null else "Signboard"
	for node: Node in tree.get_nodes_in_group(SignboardUse.GROUP):
		if not node is Node3D:
			continue
		var id: StringName = node.get("occupant_id")
		spots.append(GroundItemLabel.make(id, (node as Node3D).global_position, sign_name, true))
	for node: Node in tree.get_nodes_in_group("weed"):
		if not node is Node3D:
			continue
		var weed_id: StringName = node.get("occupant_id")
		if weed_id == &"":
			weed_id = node.get("persist_id")
		spots.append(GroundItemLabel.make(weed_id, (node as Node3D).global_position, "", false, true))
	return spots


func _show_frame(player_px: Vector2, side: Vector2, viewport: Vector2) -> void:
	if _popup.phase == GroundItemLabel.Reveal.Phase.HIDDEN:
		_bubble.visible = false
		_joint.visible = false
		_tip.visible = false
		_name.visible = false
		return
	if _popup.phase == GroundItemLabel.Reveal.Phase.CLOSING:
		player_px = _frozen_px
		side = _frozen_side
	else:
		_frozen_px = player_px
		_frozen_side = side
	var frame := GroundItemLabel.frame_at(player_px, side, viewport, _cell_width(_popup.label))
	_place(_bubble, frame.body_position, frame.body_size)
	_place(_joint, frame.joint_position, frame.joint_size)
	_place(_tip, frame.tip_position, frame.tip_size)
	_name.text = _popup.label
	_name.add_theme_font_size_override("font_size", frame.font_px)
	_name.position = frame.text_position
	_name.size = _name.get_minimum_size()
	var opening := _popup.phase == GroundItemLabel.Reveal.Phase.OPENING
	var closing := _popup.phase == GroundItemLabel.Reveal.Phase.CLOSING
	## Mode 3 grows the body about its centre with opacity. Mode 4 holds the size and fades (`w4`).
	_bubble.visible = not opening
	_bubble.texture = FADE_TEX if closing else BODY_TEX
	_bubble.scale = Vector2.ONE if closing else Vector2.ONE * _popup.opacity
	var tint := CREAM
	tint.a = _popup.opacity if closing else 1.0
	_bubble.modulate = tint
	var tail := not closing
	_joint.visible = tail
	_tip.visible = tail
	_name.visible = not opening
	_name.modulate = Color(1, 1, 1, _popup.text_alpha())


func _place(rect: TextureRect, position: Vector2, panel_size: Vector2) -> void:
	rect.position = position
	rect.size = panel_size
	rect.pivot_offset = panel_size * 0.5


## Cut advance at the 16px cell (`mFont_GetStringWidth`), before the 0.875 draw scale.
func _cell_width(text: String) -> float:
	var font := _name.get_theme_font("font")
	if font == null or text.is_empty():
		return 0.0
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(GroundItemLabel.CELL_H)).x
