class_name ItemData
extends Resource

## Catalog entry for something that can sit in pockets or the world.

enum Category { TOOL, FURNITURE, FRUIT, FISH, BUG, OTHER }

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var category: Category = Category.OTHER
@export var sell_price: int = 0
## GC pockets do not stack (`m_private` pockets are one item id per slot). Keep 1.
@export var max_stack: int = 1
