class_name ItemData
extends Resource

## Catalog entry for something that can sit in pockets or the world.
## Behavior comes from these fields + `Inventory` / UI tags — not per-item scripts.

enum Category { TOOL, FURNITURE, FRUIT, FISH, BUG, OTHER }

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var category: Category = Category.OTHER
@export var sell_price: int = 0
## Data-driven stacking. GC tools stay at 1; fruit/etc may be >1.
@export var max_stack: int = 1
@export var droppable: bool = true
@export var usable: bool = false
@export var equippable: bool = false
## Verb shown in the tag strip (`m_tag_ovl`), e.g. Eat / Use.
@export var use_verb: String = "Use"
@export var icon_color: Color = Color(0.75, 0.75, 0.75)


func can_stack_with(other: ItemData) -> bool:
	return other != null and other.id == id and max_stack > 1
