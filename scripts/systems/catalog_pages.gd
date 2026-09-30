class_name CatalogPages
extends RefCounted

## The nine pages of the player's catalog (`mCL_catalog_ovl_init`): each lists the
## collected entries of its disc list (`m_catalog_ovl_data.c_inc`, via `FtrCatalog`) in
## page order, and is "completed" (the star) when every entry of the list is there.
## Owned catalog items that the disc lists don't name (authored furniture, the single
## stationery pad) go at the end of their page, so nothing the player owns goes missing.

enum Page { FTR, WALL, CARPET, CLOTH, UMBRELLA, PAPER, HANIWA, FOSSIL, MUSIC }

const PAGE_KEYS: Array[String] = ["ftr", "wall", "carpet", "cloth", "umbrella", "paper", "haniwa", "fossil", "music"]
## `mTG_catalog_str`.
const PAGE_NAMES: Array[String] = [
	"Furniture", "Wallpaper", "Carpet", "Clothing", "Items", "Stationery", "Gyroids", "Fossils", "Music",
]
## `FTR_CLOTH_START` / `FTR_UMBRELLA_START` as furniture indices: the clothing and
## umbrella entries are the furniture forms of `shirt_NNN` / the umbrella tools.
const CLOTH_FTR_BASE := 0x1EB
const UMBRELLA_FTR_BASE := 0x342
const UMBRELLA_COUNT := 32

## Page -> item ids shown, in order.
var entries: Array = []
## Page -> size of the page's disc list (the "/ N" total is the shown count; this is
## only for the star).
var list_sizes: Array[int] = []


static func build(book: CatalogBook) -> CatalogPages:
	var out := CatalogPages.new()
	var umbrellas: Dictionary = {}
	for item: ItemData in ItemCatalog.all_items():
		if item is ToolData and (item as ToolData).kind == ToolData.Kind.UMBRELLA:
			umbrellas[(item as ToolData).umbrella_index] = item.id
	var placed: Dictionary = {}
	for page: int in PAGE_KEYS.size():
		var ids: Array[StringName] = []
		var disc: Array[int] = FtrCatalog.catalog_page(PAGE_KEYS[page])
		for index: int in disc:
			var id: StringName = entry_id(page, index, umbrellas)
			if id != &"" and book != null and book.has(id):
				ids.append(id)
				placed[id] = true
		out.entries.append(ids)
		out.list_sizes.append(disc.size())
	if book != null:
		for id: StringName in book.owned_ids():
			if placed.has(id):
				continue
			var page: int = page_for(ItemCatalog.get_item(id))
			if page >= 0:
				(out.entries[page] as Array).append(id)
	return out


## The item id for disc entry `index` of `page` (&"" when this port has no such item).
static func entry_id(page: int, index: int, umbrellas: Dictionary = {}) -> StringName:
	match page:
		Page.FTR, Page.HANIWA, Page.FOSSIL:
			return FtrCatalog.item_id(index)
		Page.WALL:
			return InteriorStyleCatalog.wall_style_id(index)
		Page.CARPET:
			return InteriorStyleCatalog.floor_style_id(index)
		Page.CLOTH:
			return StringName("shirt_%03d" % (index - CLOTH_FTR_BASE)) if index >= CLOTH_FTR_BASE else &""
		Page.UMBRELLA:
			var u: int = index - UMBRELLA_FTR_BASE
			return umbrellas.get(u, &"") as StringName if u >= 0 and u < UMBRELLA_COUNT else &""
		Page.PAPER:
			return ShopGoods.PAPER if index == 0 else &""
		Page.MUSIC:
			return MinidiskCatalog.item_id(index)
	return &""


## Which page an owned item the disc lists don't name belongs on; -1 = none.
static func page_for(data: ItemData) -> int:
	if data == null:
		return -1
	if data is FurnitureData:
		return Page.HANIWA if (data as FurnitureData).kind == FurnitureData.Kind.GYROID else Page.FTR
	if data is ToolData:
		return Page.UMBRELLA if (data as ToolData).kind == ToolData.Kind.UMBRELLA else -1
	if MinidiskCatalog.is_disc(data.id):
		return Page.MUSIC
	match data.category:
		ItemData.Category.WALL:
			return Page.WALL
		ItemData.Category.FLOOR:
			return Page.CARPET
		ItemData.Category.CLOTH:
			return Page.CLOTH
	return Page.PAPER if data.id == ShopGoods.PAPER else -1


func page(p: int) -> Array:
	return entries[p] if p >= 0 and p < entries.size() else []


## `menu->completed_flag`: every entry of the page's list collected.
func completed(p: int) -> bool:
	return p >= 0 and p < list_sizes.size() and list_sizes[p] > 0 and page(p).size() >= list_sizes[p]


## `mCL_*_init` price: what Nook asks, 0 = "Not for Sale".
static func price_of(item_id: StringName) -> int:
	var data: ItemData = ItemCatalog.get_item(item_id)
	return ShopBook.buy_price(data) if CatalogBook.is_orderable(data) else 0
