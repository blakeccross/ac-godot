class_name EncyclopediaCatalog
extends RefCounted

## Fish / insect encyclopedia order + icon lookup for the pockets submenu.
##
## Order is `mIV_fish_collect_list` / `mIV_insect_collect_list` (`m_inventory_ovl.c`).
## Icons are `inv_mwin_{NN}{romaji}_tex` in `assets/generated/textures/rel/`, where NN
## is the 1-based slot and romaji is the decomp asset name for that species. Both
## grids are `mIV_COLLECT_NUM` = 40 entries, drawn in a scrollable column grid.

const COLLECT_NUM := 40

## slot index (0-based) -> {id, icon}. `id` matches `data/creatures/*.tres`.
const FISH: Array = [
	{"id": &"crucian_carp", "icon": "inv_mwin_01funa_tex"},
	{"id": &"brook_trout", "icon": "inv_mwin_02masu_tex"},
	{"id": &"carp", "icon": "inv_mwin_03koi_tex"},
	{"id": &"koi", "icon": "inv_mwin_04nishiki_tex"},
	{"id": &"barbel_steed", "icon": "inv_mwin_05nigoi_tex"},
	{"id": &"dace", "icon": "inv_mwin_06ugui_tex"},
	{"id": &"catfish", "icon": "inv_mwin_07namazu_tex"},
	{"id": &"giant_catfish", "icon": "inv_mwin_08oonamazu_tex"},
	{"id": &"pale_chub", "icon": "inv_mwin_09oikawa_tex"},
	{"id": &"bitterling", "icon": "inv_mwin_10tanago_tex"},
	{"id": &"loach", "icon": "inv_mwin_11dojyou_tex"},
	{"id": &"bluegill", "icon": "inv_mwin_12gill_tex"},
	{"id": &"small_bass", "icon": "inv_mwin_13bass_tex"},
	{"id": &"bass", "icon": "inv_mwin_14bassm_tex"},
	{"id": &"large_bass", "icon": "inv_mwin_15bassl_tex"},
	{"id": &"giant_snakehead", "icon": "inv_mwin_16raigyo_tex"},
	{"id": &"eel", "icon": "inv_mwin_17unagi_tex"},
	{"id": &"freshwater_goby", "icon": "inv_mwin_18donko_tex"},
	{"id": &"pond_smelt", "icon": "inv_mwin_19wakasagi_tex"},
	{"id": &"sweetfish", "icon": "inv_mwin_20ayu_tex"},
	{"id": &"cherry_salmon", "icon": "inv_mwin_21yamame_tex"},
	{"id": &"rainbow_trout", "icon": "inv_mwin_22niji_tex"},
	{"id": &"large_char", "icon": "inv_mwin_23iwana_tex"},
	{"id": &"stringfish", "icon": "inv_mwin_24itou_tex"},
	{"id": &"salmon", "icon": "inv_mwin_25sake_tex"},
	{"id": &"goldfish", "icon": "inv_mwin_26kingyo_tex"},
	{"id": &"popeyed_goldfish", "icon": "inv_mwin_27demekin_tex"},
	{"id": &"guppy", "icon": "inv_mwin_28gupi_tex"},
	{"id": &"angelfish", "icon": "inv_mwin_29angel_tex"},
	{"id": &"piranha", "icon": "inv_mwin_30pirania_tex"},
	{"id": &"arowana", "icon": "inv_mwin_31aroana_tex"},
	{"id": &"coelacanth", "icon": "inv_mwin_32kaseki_tex"},
	{"id": &"crawfish", "icon": "inv_mwin_33zarigani_tex"},
	{"id": &"frog", "icon": "inv_mwin_34kaeru_tex"},
	{"id": &"killifish", "icon": "inv_mwin_35medaka_tex"},
	{"id": &"jellyfish", "icon": "inv_mwin_36kurage_tex"},
	{"id": &"sea_bass", "icon": "inv_mwin_37suzuki_tex"},
	{"id": &"red_snapper", "icon": "inv_mwin_38tai_tex"},
	{"id": &"barred_knifejaw", "icon": "inv_mwin_39ishidai_tex"},
	{"id": &"arapaima", "icon": "inv_mwin_40piraruku_tex"},
]

const INSECT: Array = [
	{"id": &"common_butterfly", "icon": "inv_mwin_01monshiro_tex"},
	{"id": &"yellow_butterfly", "icon": "inv_mwin_02monki_tex"},
	{"id": &"tiger_butterfly", "icon": "inv_mwin_03kiageha_tex"},
	{"id": &"purple_butterfly", "icon": "inv_mwin_04ohmurasaki_tex"},
	{"id": &"brown_cicada", "icon": "inv_mwin_05abura_tex"},
	{"id": &"robust_cicada", "icon": "inv_mwin_06minmin_tex"},
	{"id": &"walker_cicada", "icon": "inv_mwin_07tukutuku_tex"},
	{"id": &"evening_cicada", "icon": "inv_mwin_08higurashi_tex"},
	{"id": &"red_dragonfly", "icon": "inv_mwin_09akiakane_tex"},
	{"id": &"common_dragonfly", "icon": "inv_mwin_10shiokara_tex"},
	{"id": &"darner_dragonfly", "icon": "inv_mwin_11ginyanma_tex"},
	{"id": &"banded_dragonfly", "icon": "inv_mwin_12oniyanma_tex"},
	{"id": &"cricket", "icon": "inv_mwin_13koorogi_tex"},
	{"id": &"grasshopper", "icon": "inv_mwin_14kirigirisu_tex"},
	{"id": &"pine_cricket", "icon": "inv_mwin_15matumushi_tex"},
	{"id": &"bell_cricket", "icon": "inv_mwin_16suzumushi_tex"},
	{"id": &"ladybug", "icon": "inv_mwin_17tentou_tex"},
	{"id": &"spotted_ladybug", "icon": "inv_mwin_18nanahoshi_tex"},
	{"id": &"mantis", "icon": "inv_mwin_19kamakiri_tex"},
	{"id": &"long_locust", "icon": "inv_mwin_20syouryou_tex"},
	{"id": &"migratory_locust", "icon": "inv_mwin_21tonosama_tex"},
	{"id": &"cockroach", "icon": "inv_mwin_22danna_tex"},
	{"id": &"bee", "icon": "inv_mwin_23hati_tex"},
	{"id": &"firefly", "icon": "inv_mwin_24genji_tex"},
	{"id": &"drone_beetle", "icon": "inv_mwin_25kanabun_tex"},
	{"id": &"longhorn_beetle", "icon": "inv_mwin_26gomadara_tex"},
	{"id": &"jewel_beetle", "icon": "inv_mwin_27tamamushi_tex"},
	{"id": &"dynastid_beetle", "icon": "inv_mwin_28kabuto_tex"},
	{"id": &"flat_stag_beetle", "icon": "inv_mwin_29hirata_tex"},
	{"id": &"saw_stag_beetle", "icon": "inv_mwin_30nokogiri_tex"},
	{"id": &"mountain_beetle", "icon": "inv_mwin_31miyama_tex"},
	{"id": &"giant_beetle", "icon": "inv_mwin_32okuwa_tex"},
	{"id": &"pond_skater", "icon": "inv_mwin_35amenbo_tex"},
	{"id": &"ant", "icon": "inv_mwin_39ari_tex"},
	{"id": &"pill_bug", "icon": "inv_mwin_37dango_tex"},
	{"id": &"mosquito", "icon": "inv_mwin_40ka_tex"},
	{"id": &"mole_cricket", "icon": "inv_mwin_34kera_tex"},
	{"id": &"spider", "icon": "inv_mwin_38kumo_tex"},
	{"id": &"snail", "icon": "inv_mwin_33maimai_tex"},
	{"id": &"bagworm", "icon": "inv_mwin_36mino_tex"},
]


static func page(kind: StringName) -> Array:
	return INSECT if kind == &"insect" or kind == &"bug" else FISH


static func icon_for(kind: StringName, slot: int) -> String:
	var rows: Array = page(kind)
	if slot < 0 or slot >= rows.size():
		return ""
	return String(rows[slot].get("icon", ""))


static func id_for(kind: StringName, slot: int) -> StringName:
	var rows: Array = page(kind)
	if slot < 0 or slot >= rows.size():
		return &""
	return rows[slot].get("id", &"")


## kind for a creature id, or &"" if it is neither.
static func kind_of(id: StringName) -> StringName:
	for row: Dictionary in FISH:
		if row["id"] == id:
			return &"fish"
	for row: Dictionary in INSECT:
		if row["id"] == id:
			return &"insect"
	return &""
