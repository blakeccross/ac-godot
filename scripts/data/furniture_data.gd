class_name FurnitureData
extends ItemData

## Placeable furniture. Fields are the catalog; `FurnitureUse` / `Interior` read them.
## Shape/contact/placement follow `aFTR_PROFILE` behavior, not the C bitfields.

enum Shape { TYPE_A, TYPE_B, TYPE_C }
enum Placement { FLOOR, TABLE, SMALL, WALL }
enum Kind {
	GENERIC,
	CHAIR,
	SOFA,
	BED,
	TABLE,
	STORAGE,
	MUSIC,
	TOGGLE,
	DISPLAY,
	MANNEQUIN,
	UMBRELLA,
	GYROID,
	RUG,
}
enum Contact { NONE, CHAIR_FRONT, CHAIR_ANY, SOFA, BED_SINGLE, BED_DOUBLE }

## `aFTR_KEEP_ITEM_COUNT` (`mCoBG_LAYER_NUM - 1`).
const KEEP_SLOTS := 3

@export var visual_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var shape: Shape = Shape.TYPE_A
@export var can_rotate: bool = true
## Extra occupancy care while turning (`aFTR_PROFILE.check_rotation`).
@export var check_rotation: bool = false
@export var indoor: bool = true
@export var placement: Placement = Placement.FLOOR
@export var kind: Kind = Kind.GENERIC
@export var contact: Contact = Contact.NONE
@export var can_sit: bool = false
@export var can_store: bool = false
@export var blocks_walk: bool = true
@export var storage_slots: int = 0
## TVs start off (`aFTR_INTERACTION_START_DISABLED`).
@export var starts_off: bool = false


func _init() -> void:
	category = Category.FURNITURE


func resolved_footprint() -> Vector2i:
	if footprint != Vector2i.ZERO:
		return footprint
	match shape:
		Shape.TYPE_B:
			return Vector2i(2, 1)
		Shape.TYPE_C:
			return Vector2i(2, 2)
		_:
			return Vector2i.ONE


func is_sittable() -> bool:
	if can_sit:
		return true
	return (
		contact == Contact.CHAIR_FRONT
		or contact == Contact.CHAIR_ANY
		or contact == Contact.SOFA
	)


func is_bed() -> bool:
	return contact == Contact.BED_SINGLE or contact == Contact.BED_DOUBLE


func has_storage() -> bool:
	return can_store or storage_slots > 0 or kind == Kind.STORAGE or kind == Kind.MUSIC


func keep_count() -> int:
	if storage_slots > 0:
		return storage_slots
	if has_storage():
		return KEEP_SLOTS
	return 0


func allows_on_top() -> bool:
	return placement == Placement.TABLE or kind == Kind.TABLE


func needs_surface() -> bool:
	return placement == Placement.SMALL


func needs_wall() -> bool:
	return placement == Placement.WALL


func is_toggleable() -> bool:
	return kind == Kind.TOGGLE or kind == Kind.MUSIC or kind == Kind.GYROID


func accepts_display(item: ItemData) -> bool:
	if item == null:
		return false
	match kind:
		Kind.DISPLAY:
			return item.category == Category.FISH or item.category == Category.BUG
		Kind.MANNEQUIN:
			return item.category == Category.CLOTH or item.cloth_index >= 0
		Kind.UMBRELLA:
			return String(item.id).contains("umbrella") or String(item.display_name).to_lower().contains("umbrella")
		_:
			return false


func infer_from_visual() -> void:
	## Runtime stub for disc FTR that has a GLB but no authored `.tres`.
	if visual_id == &"":
		visual_id = id
	if footprint == Vector2i.ZERO:
		footprint = Vector2i.ONE
	indoor = true
	blocks_walk = true
	var raw := String(visual_id).to_lower()
	if raw.contains("sofa") or raw.contains("bench") or raw.contains("benti"):
		kind = Kind.SOFA
		contact = Contact.SOFA
		can_sit = true
	elif raw.contains("bed"):
		kind = Kind.BED
		contact = Contact.BED_DOUBLE if raw.contains("dbed") or raw.contains("double") else Contact.BED_SINGLE
	elif raw.contains("chair") or raw.contains("isu"):
		kind = Kind.CHAIR
		contact = Contact.CHAIR_FRONT
		can_sit = true
	elif raw.contains("table") or raw.contains("desk") or raw.contains("counter"):
		kind = Kind.TABLE
		placement = Placement.TABLE
	elif (
		raw.contains("chest")
		or raw.contains("drawer")
		or raw.contains("closet")
		or raw.contains("wardrobe")
		or raw.contains("tansu")
		or raw.contains("reizou")
	):
		kind = Kind.STORAGE
		can_store = true
		storage_slots = KEEP_SLOTS
	elif raw.contains("stereo") or raw.contains("radio") or raw.contains("jukebox") or raw.contains("disk"):
		kind = Kind.MUSIC
		can_store = true
		storage_slots = KEEP_SLOTS
	elif raw.contains("tv") or raw.contains("toudai") or raw.contains("lamp") or raw.contains("light"):
		kind = Kind.TOGGLE
		starts_off = raw.contains("tv")
	elif raw.contains("fmanekin") or raw.contains("manekin"):
		kind = Kind.MANNEQUIN
	elif raw.contains("umbrella") or raw.contains("fumbrella"):
		kind = Kind.UMBRELLA
	elif raw.contains("hnw"):
		kind = Kind.GYROID
	elif raw.contains("fish") or raw.contains("insect") or raw.contains("fossil") or raw.contains("din_"):
		kind = Kind.DISPLAY
	elif raw.contains("mat") or raw.contains("rug") or raw.contains("carpet"):
		kind = Kind.RUG
		blocks_walk = false
	if raw.contains("art") or raw.contains("paint") or raw.contains("poster") or raw.contains("easel"):
		placement = Placement.WALL
	if footprint.x == 2 and footprint.y == 2:
		shape = Shape.TYPE_C
	elif footprint.x == 2 or footprint.y == 2:
		shape = Shape.TYPE_B
	else:
		shape = Shape.TYPE_A
