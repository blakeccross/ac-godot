class_name WorldObjectRegistry
extends RefCounted

## Kind → scene map for outdoor objects and buildings.
## Register a new kind here (one line) + a thin scene with get_interactions / interact.

const GROUP_OBJECTS := &"Objects"
const GROUP_BUILDINGS := &"Buildings"
const GROUP_CHARACTERS := &"Characters"

## kind → { scene, place_kind, group }
static var _entries: Dictionary = {}
static var _ready := false


static func ensure() -> void:
	if _ready:
		return
	_ready = true
	_entries.clear()
	register(&"tree", "res://scenes/world/tree.tscn", WorldGrid.PlaceKind.PLANT, GROUP_OBJECTS)
	register(&"rock", "res://scenes/world/rock.tscn", WorldGrid.PlaceKind.PLANT, GROUP_OBJECTS)
	register(&"flower", "res://scenes/world/flower.tscn", WorldGrid.PlaceKind.PLANT, GROUP_OBJECTS)
	register(&"hole", "res://scenes/world/hole.tscn", WorldGrid.PlaceKind.PLANT, GROUP_OBJECTS)
	register(&"item", "res://scenes/world/item_pickup.tscn", WorldGrid.PlaceKind.ITEM, GROUP_OBJECTS)
	register(&"sign", "res://scenes/world/sign.tscn", WorldGrid.PlaceKind.FURNITURE, GROUP_OBJECTS)
	register(&"furniture", "res://scenes/world/furniture.tscn", WorldGrid.PlaceKind.FURNITURE, GROUP_OBJECTS)
	register(&"door", "res://scenes/world/door.tscn", WorldGrid.PlaceKind.FURNITURE, GROUP_OBJECTS)
	register(&"villager", "res://scenes/actors/villager.tscn", WorldGrid.PlaceKind.FURNITURE, GROUP_CHARACTERS)
	register(&"house", "res://scenes/world/house.tscn", WorldGrid.PlaceKind.BUILDING, GROUP_BUILDINGS)
	register(&"shop", "res://scenes/world/shop.tscn", WorldGrid.PlaceKind.BUILDING, GROUP_BUILDINGS)
	register(&"building", "res://scenes/world/building.tscn", WorldGrid.PlaceKind.BUILDING, GROUP_BUILDINGS)


static func register(
	kind: StringName, scene_path: String, place_kind: WorldGrid.PlaceKind, group: StringName
) -> void:
	_entries[kind] = {
		"scene": scene_path,
		"place_kind": place_kind,
		"group": group,
	}


static func has_kind(kind: StringName) -> bool:
	ensure()
	return _entries.has(kind)


static func scene_path(kind: StringName) -> String:
	ensure()
	var e: Variant = _entries.get(kind)
	if e == null:
		return ""
	return String((e as Dictionary).get("scene", ""))


static func place_kind(kind: StringName) -> WorldGrid.PlaceKind:
	ensure()
	var e: Variant = _entries.get(kind)
	if e == null:
		return WorldGrid.PlaceKind.PLANT
	return (e as Dictionary).get("place_kind", WorldGrid.PlaceKind.PLANT) as WorldGrid.PlaceKind


static func group(kind: StringName) -> StringName:
	ensure()
	var e: Variant = _entries.get(kind)
	if e == null:
		return GROUP_OBJECTS
	return (e as Dictionary).get("group", GROUP_OBJECTS) as StringName


static func kinds() -> Array[StringName]:
	ensure()
	var out: Array[StringName] = []
	for k: Variant in _entries.keys():
		out.append(k as StringName)
	out.sort()
	return out
