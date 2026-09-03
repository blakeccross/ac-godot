class_name MuseumDisplay
extends RefCounted

## Museum wing layout tables from `m_museum_display` / `ac_museum_*`.
## Positions are FG-acre GX; convert with `gx_to_world`. Not an autoload.

enum Category { FOSSIL, ART, INSECT, FISH }

## `aGYO_TYPE_*` order — museum fish index == this array index.
const FISH_IDS: Array[StringName] = [
	&"crucian_carp",
	&"brook_trout",
	&"carp",
	&"koi",
	&"catfish",
	&"small_bass",
	&"bass",
	&"large_bass",
	&"bluegill",
	&"giant_catfish",
	&"giant_snakehead",
	&"barbel_steed",
	&"dace",
	&"pale_chub",
	&"bitterling",
	&"loach",
	&"pond_smelt",
	&"sweetfish",
	&"cherry_salmon",
	&"large_char",
	&"rainbow_trout",
	&"stringfish",
	&"salmon",
	&"goldfish",
	&"piranha",
	&"arowana",
	&"eel",
	&"freshwater_goby",
	&"angelfish",
	&"guppy",
	&"popeyed_goldfish",
	&"coelacanth",
	&"crawfish",
	&"frog",
	&"killifish",
	&"jellyfish",
	&"sea_bass",
	&"red_snapper",
	&"barred_knifejaw",
	&"arapaima",
]

## `mfish_group_tbl` — tank 0..4 per fish index.
const FISH_TANKS: Array[int] = [
	0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 3, 0, 2, 2, 0, 1, 2, 2, 2, 2, 2, 2, 4, 0, 3, 3, 0, 1, 3, 3, 0, 4,
	2, 1, 0, 4, 4, 4, 4, 3,
]

## `suisou_pos` tank centers (GX). Y is the water-line used by swim init (`_0C`).
const TANK_POS_GX: Array[Vector3] = [
	Vector3(220.0, 40.0, 220.0),
	Vector3(420.0, 40.0, 220.0),
	Vector3(220.0, 40.0, 460.0),
	Vector3(420.0, 40.0, 460.0),
	Vector3(320.0, 40.0, 20.0),
]

## `cKF_bs_r_act_mus_*` stems in `aGYO_TYPE_*` order. Empty = no museum mesh (jellyfish).
const FISH_MUS_STEMS: PackedStringArray = [
	"funa",
	"hera",
	"koi",
	"nisiki",
	"namazu",
	"bass",
	"bassm",
	"bassl",
	"gill",
	"onamazu",
	"raigyo",
	"nigoi",
	"ugui",
	"oikawa",
	"tanago",
	"dojyo",
	"wakasa",
	"ayu",
	"yamame",
	"iwana",
	"niji",
	"ito",
	"sake",
	"kingyo",
	"pirania",
	"aroana",
	"unagi",
	"donko",
	"angel",
	"gupi",
	"demekin",
	"kaseki",
	"zari",
	"kaeru",
	"medaka",
	"",
	"suzuki",
	"tai",
	"isidai",
	"pira",
]

## Approximate tank half-extents used for wander clamps (GX).
## Player-blocking glass half-extent (visual `obj_suisou1` ~60 GX). Swim AI uses
## per-fish `54 + _28` via `MuseumFishActor` — not this constant.
const TANK_HALF_GX := Vector3(60.0, 0.0, 60.0)
const SEA_TANK_HALF_GX := Vector3(189.0, 0.0, 40.0)

## Entrance → wing doors (`MUSEUM_ENTRANCE_door_data`).
## `spawn`/`facing` = appear in the wing. `sensor` = wall threshold in the entrance
## (one cell behind the return spawn so walk-in does not re-fire).
const ENTRANCE_WING_DOORS: Array[Dictionary] = [
	{
		"room": &"museum_painting",
		"sensor": Vector3(160.0, 0.0, 80.0),
		"spawn": Vector3(280.0, 0.0, 480.0),
		"facing": WorldGrid.Facing.NORTH,
	},
	{
		"room": &"museum_fossil",
		"sensor": Vector3(320.0, 0.0, 80.0),
		"spawn": Vector3(280.0, 0.0, 480.0),
		"facing": WorldGrid.Facing.NORTH,
	},
	{
		"room": &"museum_insect",
		"sensor": Vector3(80.0, 0.0, 280.0),
		"spawn": Vector3(520.0, 0.0, 560.0),
		"facing": WorldGrid.Facing.WEST,
	},
	{
		"room": &"museum_fish",
		"sensor": Vector3(400.0, 0.0, 280.0),
		"spawn": Vector3(120.0, 0.0, 560.0),
		"facing": WorldGrid.Facing.EAST,
	},
]

## Wing → entrance. Sensors sit on the wall behind the wing enter spawn.
const WING_EXIT_DOORS: Dictionary = {
	&"museum_painting":
	{
		"sensor": Vector3(280.0, 0.0, 520.0),
		"spawn": Vector3(160.0, 0.0, 120.0),
		"facing": WorldGrid.Facing.SOUTH,
	},
	&"museum_fossil":
	{
		"sensor": Vector3(280.0, 0.0, 520.0),
		"spawn": Vector3(320.0, 0.0, 120.0),
		"facing": WorldGrid.Facing.SOUTH,
	},
	&"museum_insect":
	{
		"sensor": Vector3(560.0, 0.0, 560.0),
		"spawn": Vector3(120.0, 0.0, 280.0),
		"facing": WorldGrid.Facing.EAST,
	},
	&"museum_fish":
	{
		"sensor": Vector3(80.0, 0.0, 560.0),
		"spawn": Vector3(360.0, 0.0, 280.0),
		"facing": WorldGrid.Facing.WEST,
	},
}

## Outdoor → entrance (`aMsm_museum_enter_data`). Not scene `MUSEUM_ENTRANCE_player_data` (240,0,200).
const ENTRANCE_SPAWN_GX := Vector3(240.0, 0.0, 440.0)
const ENTRANCE_SPAWN_FACING := WorldGrid.Facing.NORTH
## Entrance → outdoors. South threshold on the same X as the outdoor enter stand.
const ENTRANCE_EXIT_SENSOR_GX := Vector3(240.0, 0.0, 500.0)
## Blathers stand (`museum_entrance_actable` ut 6,5 → cell center 260,220;
## `ac_npc_curator` then adds +20 GX on X). Faces south (spawn rot 0).
const BLATHERS_STAND_GX := Vector3(280.0, 0.0, 220.0)
const BLATHERS_FACING := WorldGrid.Facing.SOUTH
## `HOUSE_CLOCK` / `obj_clock_museum1`. Decomp actor pos is `(0,0,0)`
## (`aHC_position_data`); skeleton root is `(240,70,150)` GX — mid-body, so the
## mesh floats. We keep joint XZ and snap the AABB to the floor.
const CLOCK_GX := Vector3(240.0, 0.0, 150.0)
const CLOCK_VISUAL := &"obj_clock_museum1"
## `aMP_DrawOneArt` hang height (GX).
const ART_HANG_Y_GX := 40.0

## Painting-wing E–W partition rows (unit Z). Paintings hang on these mid walls;
## gaps are cells in that row with no `ART_CELLS` entry.
const ART_PARTITION_ROWS: Array[int] = [5, 9]

## Museum wall meshes (`obj_art*` / `obj_art_dummy*`), not house `int_sum_art*` FTR.
const ART_MUSEUM_VISUALS: Array[StringName] = [
	&"obj_art01",
	&"obj_art02",
	&"obj_art03",
	&"obj_art04",
	&"obj_art05",
	&"obj_art06",
	&"obj_art07",
	&"obj_art08",
	&"obj_art09",
	&"obj_art10",
	&"obj_art11",
	&"obj_art12",
	&"obj_art13",
	&"obj_art14",
	&"obj_art15",
]

## Empty-frame dummies from `aMP_art_data_table`.
const ART_MUSEUM_DUMMIES: Array[StringName] = [
	&"obj_art_dummy01",
	&"obj_art_dummy03",
	&"obj_art_dummy01",
	&"obj_art_dummy04",
	&"obj_art_dummy02",
	&"obj_art_dummy05",
	&"obj_art_dummy07",
	&"obj_art_dummy06",
	&"obj_art_dummy04",
	&"obj_art_dummy06",
	&"obj_art_dummy07",
	&"obj_art_dummy04",
	&"obj_art_dummy08",
	&"obj_art_dummy08",
	&"obj_art_dummy08",
]

## Fossil part visual when donated (`FTR_DIN_TRIKERA_HEAD` + index).
const FOSSIL_VISUALS: Array[StringName] = [
	&"int_din_trikera_head",
	&"int_din_trikera_tail",
	&"int_din_trikera_body",
	&"int_din_trex_head",
	&"int_din_trex_tail",
	&"int_din_trex_body",
	&"int_din_bront_head",
	&"int_din_bront_tail",
	&"int_din_bront_body",
	&"int_din_stego_head",
	&"int_din_stego_tail",
	&"int_din_stego_body",
	&"int_din_ptera_head",
	&"int_din_ptera_Rwing",
	&"int_din_ptera_Lwing",
	&"int_din_hutaba_head",
	&"int_din_hutaba_neck",
	&"int_din_hutaba_body",
	&"int_din_mammoth_head",
	&"int_din_mammoth_body",
	&"int_din_amber",
	&"int_din_stump",
	&"int_din_ammonite",
	&"int_din_egg",
	&"int_din_trilobite",
]

## Undonated dummy pedestals from `mMmd_museum_fossil_data`.
const FOSSIL_DUMMIES: Array[StringName] = [
	&"int_din_trikera_dummy",
	&"int_din_trikera_dummy",
	&"int_din_trikera_dummy",
	&"int_din_trex_dummy",
	&"int_din_trex_dummy",
	&"int_din_trex_dummy",
	&"int_din_bront_dummy",
	&"int_din_bront_dummy",
	&"int_din_bront_dummy",
	&"int_din_stego_dummyA",
	&"int_din_stego_dummyB",
	&"int_din_stego_dummyB",
	&"int_din_ptera_dummy",
	&"int_din_ptera_dummy",
	&"int_din_ptera_dummy",
	&"int_din_hutaba_dummy",
	&"int_din_hutaba_dummy",
	&"int_din_hutaba_dummy",
	&"int_din_mammoth_dummy",
	&"int_din_mammoth_dummy",
	&"int_din_dummy",
	&"int_din_dummy",
	&"int_din_dummy",
	&"int_din_dummy",
	&"int_din_dummy",
]

## Unit cells (x, z) from `mMmd_UT`.
const FOSSIL_CELLS: Array[Vector2i] = [
	Vector2i(5, 2),
	Vector2i(1, 2),
	Vector2i(3, 2),
	Vector2i(9, 2),
	Vector2i(13, 2),
	Vector2i(11, 2),
	Vector2i(5, 10),
	Vector2i(1, 10),
	Vector2i(3, 10),
	Vector2i(10, 6),
	Vector2i(13, 5),
	Vector2i(11, 5),
	Vector2i(6, 6),
	Vector2i(6, 5),
	Vector2i(6, 7),
	Vector2i(9, 10),
	Vector2i(11, 10),
	Vector2i(13, 10),
	Vector2i(2, 7),
	Vector2i(2, 5),
	Vector2i(6, 8),
	Vector2i(7, 8),
	Vector2i(8, 8),
	Vector2i(9, 8),
	Vector2i(10, 8),
]

## `aFTR_SHAPE_*` → footprint for `furniture_world`. TYPEC (2×2) adds +½ cell
## (`aMR_UnitNumber2Position`); TYPEB stays on the stored unit; TYPEA is 1×1.
static func fossil_footprint(index: int) -> Vector2i:
	match index:
		9, 12, 13, 14:
			## stego head + ptera parts / dummyA (`TYPEB_0`)
			return Vector2i(2, 1)
		20, 21, 22, 23, 24:
			## amber / stump / ammonite / egg / trilobite (`TYPEA`)
			return Vector2i(1, 1)
		_:
			return Vector2i(2, 2)

## `mRmTp_DIRECT_*` → `WorldGrid.Facing`.
const FOSSIL_FACINGS: Array[int] = [
	int(WorldGrid.Facing.NORTH),
	int(WorldGrid.Facing.NORTH),
	int(WorldGrid.Facing.NORTH),
	int(WorldGrid.Facing.SOUTH),
	int(WorldGrid.Facing.SOUTH),
	int(WorldGrid.Facing.SOUTH),
	int(WorldGrid.Facing.NORTH),
	int(WorldGrid.Facing.NORTH),
	int(WorldGrid.Facing.NORTH),
	int(WorldGrid.Facing.EAST),
	int(WorldGrid.Facing.SOUTH),
	int(WorldGrid.Facing.SOUTH),
	int(WorldGrid.Facing.SOUTH),
	int(WorldGrid.Facing.SOUTH),
	int(WorldGrid.Facing.SOUTH),
	int(WorldGrid.Facing.SOUTH),
	int(WorldGrid.Facing.SOUTH),
	int(WorldGrid.Facing.SOUTH),
	int(WorldGrid.Facing.EAST),
	int(WorldGrid.Facing.EAST),
	int(WorldGrid.Facing.SOUTH),
	int(WorldGrid.Facing.SOUTH),
	int(WorldGrid.Facing.SOUTH),
	int(WorldGrid.Facing.SOUTH),
	int(WorldGrid.Facing.SOUTH),
]

## Multi-part skeleton groups for Blathers' "parts complete" check.
const FOSSIL_SETS: Array = [
	[0, 1, 2],
	[3, 4, 5],
	[6, 7, 8],
	[9, 10, 11],
	[12, 13, 14],
	[15, 16, 17],
	[18, 19],
]

## Solo fossils that skip the multi-part thanks branch.
const FOSSIL_SOLO: Array[int] = [20, 21, 22, 23, 24]

## `aMP_art_data_table` grid cells.
const ART_CELLS: Array[Vector2i] = [
	Vector2i(7, 1),
	Vector2i(1, 9),
	Vector2i(11, 5),
	Vector2i(9, 1),
	Vector2i(5, 9),
	Vector2i(3, 1),
	Vector2i(3, 9),
	Vector2i(1, 5),
	Vector2i(3, 5),
	Vector2i(11, 9),
	Vector2i(11, 1),
	Vector2i(13, 5),
	Vector2i(13, 9),
	Vector2i(9, 5),
	Vector2i(5, 1),
]

const ART_VISUALS: Array[StringName] = [
	&"int_sum_art01",
	&"int_sum_art02",
	&"int_sum_art03",
	&"int_sum_art04",
	&"int_sum_art05",
	&"int_sum_art06",
	&"int_sum_art07",
	&"int_sum_art08",
	&"int_sum_art09",
	&"int_sum_art10",
	&"int_sum_art11",
	&"int_sum_art12",
	&"int_sum_art13",
	&"int_sum_art14",
	&"int_sum_art15",
]

## Dummy frame model ids from `aMP_art_data_table` (1-based → zero index in name).
const ART_DUMMY_IDS: Array[int] = [1, 3, 1, 4, 2, 5, 7, 6, 4, 6, 7, 4, 8, 8, 8]

## Insect museum anchors (`flower_pos`, `tree_pos`, …) in GX.
const INSECT_FLOWER_POS: Array[Vector3] = [
	Vector3(147.0, 66.0, 169.0),
	Vector3(238.0, 66.0, 201.0),
	Vector3(264.0, 66.0, 164.0),
	Vector3(165.0, 66.0, 219.0),
	Vector3(181.0, 66.0, 235.0),
	Vector3(199.0, 66.0, 188.0),
	Vector3(327.5, 66.0, 154.0),
	Vector3(410.0, 66.0, 190.0),
]

const INSECT_TREE_POS: Array[Vector3] = [
	Vector3(92.0, 0.0, -15.0),
	Vector3(168.0, 0.0, 5.0),
	Vector3(244.0, 0.0, -15.0),
	Vector3(316.0, 0.0, 5.0),
	Vector3(392.0, 0.0, -15.0),
	Vector3(468.0, 0.0, 5.0),
	Vector3(360.0, 0.0, 245.0),
	Vector3(165.0, 0.0, 485.0),
]

const INSECT_ROCK_POS: Array[Vector3] = [
	Vector3(225.0, 0.0, 388.5),
	Vector3(385.0, 0.0, 485.0),
]

const INSECT_OHMURASAKI_TREE := Vector3(360.0, 85.0, 265.0)
const INSECT_AMENBO_CENTER := Vector3(289.0, 25.0, 218.0)
const INSECT_OKERA_BASE := Vector3(235.0, 45.0, 445.0)
const INSECT_GENJI_BASE := Vector3(258.0, 62.0, 258.5)

## `minsect_scale_tbl`.
const INSECT_SCALES: Array[float] = [
	0.01, 0.01, 0.01, 0.01, 0.008, 0.008, 0.008, 0.008, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01,
	0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.01, 0.009, 0.009, 0.009, 0.009, 0.01, 0.01, 0.01, 0.01,
	0.01, 0.01, 0.01, 0.01, 0.007, 0.01, 0.01, 0.01, 0.01, 0.01,
]

## `active_time_tbl` / `relax_time_tbl` as hour-of-day (seconds from midnight / 3600).
const INSECT_ACTIVE_HOUR: Array[float] = [
	8, 8, 8, 8, 8, 4, 4, 4, 0, 8, 8, 8, 8, 8, 8, 16, 8, 16, 16, 0, 19, 19, 8, 8, 8, 8, 8, 19, 0, 19,
	19, 19, 0, 0, 8, 0, 0, 0, 0, 0,
]

const INSECT_RELAX_HOUR: Array[float] = [
	17, 17, 17, 17, 17, 17, 8, 17, 0, 17, 17, 17, 17, 17, 17, 8, 16, 8, 8, 0, 8, 8, 16, 17, 17, 17,
	17, 4, 0, 8, 8, 8, 0, 0, 19, 0, 0, 0, 0, 0,
]

## Fish plaque groups A–E (`Museum_Fish_Set_MsgFishInfo`).
const FISH_PLAQUE_GROUPS: Array = [
	[0, 1, 2, 3, 11, 14, 26, 23, 30, 34],
	[4, 9, 15, 8, 5, 6, 7, 27, 33],
	[12, 13, 16, 17, 18, 20, 19, 21, 32],
	[10, 29, 28, 24, 25, 39],
	[22, 31, 35, 36, 37, 38],
]

## Insect plaque groups from `Museum_Insect_Set_MsgInsectInfo`.
const INSECT_PLAQUE_GROUPS: Array = [
	[22, 4, 21, 29, 38, 20, 7],
	[31, 30, 19, 5, 23, 6],
	[0, 25, 26, 1, 27, 2],
	[32, 34, 37, 3, 24, 39],
	[35, 8, 33, 9, 10, 11, 12],
	[15, 16, 18, 17, 13, 14, 36],
]

const FISH_PLAQUE_POS: Array[Vector3] = [
	Vector3(260.0, 40.0, 300.0),
	Vector3(460.0, 40.0, 300.0),
	Vector3(260.0, 40.0, 540.0),
	Vector3(460.0, 40.0, 540.0),
	Vector3(500.0, 40.0, 60.0),
]

const INSECT_PLAQUE_POS: Array[Vector3] = [
	Vector3(140.0, 40.0, 60.0),
	Vector3(420.0, 40.0, 60.0),
	Vector3(220.0, 40.0, 300.0),
	Vector3(380.0, 40.0, 300.0),
	Vector3(180.0, 40.0, 540.0),
	Vector3(340.0, 40.0, 540.0),
]

## Already-collected catch report (`mSM_CHECK_LAST_FISH_GET` → 0x1349).
const FISH_ALREADY_MSG := 0x1349
## Bug already-collected uses the same shorter branch when modelled; 0xA54 is a stand-in
## until the insect bank line is wired the same way.
const BUG_ALREADY_MSG := 0xA54


static func fish_index(fish_id: StringName) -> int:
	return FISH_IDS.find(fish_id)


static func fish_id_at(index: int) -> StringName:
	if index < 0 or index >= FISH_IDS.size():
		return &""
	return FISH_IDS[index]


static func fish_tank(index: int) -> int:
	if index < 0 or index >= FISH_TANKS.size():
		return 0
	return FISH_TANKS[index]


## Museum tank mesh path (`act_mus_*`), not the outdoor `act_f*` catch models.
static func museum_fish_model_path(index: int) -> String:
	if index < 0 or index >= FISH_MUS_STEMS.size():
		return ""
	var stem: String = FISH_MUS_STEMS[index]
	if stem.is_empty():
		return ""
	if stem == "zari":
		return "res://assets/generated/environment/act_mus_zari.glb"
	return "res://assets/generated/environment/act_mus_%s_a1.glb" % stem


static func tank_half(tank: int) -> Vector3:
	return SEA_TANK_HALF_GX if tank == 4 else TANK_HALF_GX


## Swim-AI half extent for a species (`Museum_Fish_BGCheck` with f26=f25=1).
static func fish_swim_half_gx(index: int) -> Vector3:
	var init: Dictionary = fish_init(index)
	var pad: float = float(init.get("body_pad", -6.0))
	var tank: int = fish_tank(index)
	if tank >= 4:
		return Vector3(pad + 189.0, 0.0, pad + 25.0)
	return Vector3(54.0 + pad, 0.0, 54.0 + pad)


## Per-species museum swim params from `mfish_init_data` (scale, ofs_y, depth, speeds…).
static func fish_init(index: int) -> Dictionary:
	## renderScale, ofs_y, _08, depth(_0C), _10,_14,_18,_1C,_20, ofs_z, _28, activeMin, activeRange, turnDeg
	const ROWS: Array = [
		[0.0100, 3.8, 7.5, 74.0, 0.400, 0.450, 0.98995, 0.2, 0.40, -3.5, -6.0, 120, 120, 70.0],
		[0.0100, 4.6, 7.0, 78.0, 0.400, 0.600, 0.98995, 0.2, 0.40, -3.5, -6.0, 100, 160, 70.0],
		[0.0100, 6.0, 10.6, 80.0, 0.350, 0.300, 0.98995, 0.2, 0.60, -5.0, -9.0, 100, 150, 90.0],
		[0.0100, 6.0, 10.7, 85.0, 0.350, 0.300, 0.98995, 0.2, 0.60, -5.0, -9.0, 100, 120, 90.0],
		[0.0110, 6.0, 13.6, 63.0, 0.050, 0.075, 0.995, 0.4, 0.85, -2.5, -10.0, 600, 900, 60.0],
		[0.0110, 3.0, 8.0, 85.0, 0.700, 0.500, 0.97468, 0.2, 0.30, -4.0, -6.0, 100, 100, 70.0],
		[0.0110, 4.7, 9.8, 92.0, 0.700, 0.500, 0.97468, 0.2, 0.60, -5.0, -8.0, 150, 110, 70.0],
		[0.0110, 5.5, 12.0, 90.0, 0.600, 0.500, 0.97468, 0.2, 0.80, -5.5, -10.0, 160, 120, 70.0],
		[0.0100, 4.3, 6.1, 95.0, 0.700, 0.500, 0.97468, 0.2, 0.30, -3.5, -5.0, 80, 80, 70.0],
		[0.0120, 7.6, 19.4, 65.0, 0.075, 0.150, 0.995, 0.4, 0.95, -6.0, -18.0, 720, 1000, 60.0],
		[0.0120, 9.6, 20.8, 65.0, 0.050, 0.100, 0.98489, 0.4, 0.95, -13.0, -19.0, 240, 480, 90.0],
		[0.0100, 4.8, 10.5, 102.0, 0.350, 0.300, 0.98995, 0.2, 0.70, -3.5, -9.0, 150, 120, 70.0],
		[0.0100, 3.0, 10.6, 75.0, 0.750, 1.500, 0.94868, 0.2, 0.60, -4.5, -8.0, 480, 150, 45.0],
		[0.0100, 2.5, 7.0, 90.0, 0.050, 0.475, 0.94868, 0.4, 0.30, -3.5, -6.0, 240, 200, 50.0],
		[0.0100, 3.5, 6.0, 76.0, 0.350, 0.400, 0.98995, 0.4, 0.40, -3.0, -6.0, 100, 120, 45.0],
		[0.0100, 4.0, 6.4, 65.0, 0.100, 0.150, 0.89443, 0.4, 0.20, -2.0, -6.0, 240, 240, 50.0],
		[0.0100, 2.0, 6.0, 96.0, 0.100, 0.450, 0.92195, 0.2, 0.10, -3.5, -6.0, 300, 120, 50.0],
		[0.0100, 3.0, 9.8, 75.0, 1.000, 1.500, 0.94868, 0.2, 0.50, -3.5, -7.5, 480, 120, 45.0],
		[0.0100, 3.5, 9.3, 85.0, 0.750, 1.000, 0.94868, 0.2, 0.50, -3.0, -8.0, 540, 120, 45.0],
		[0.0100, 2.5, 10.6, 80.0, 0.750, 1.000, 0.94868, 0.2, 0.70, -3.0, -9.0, 600, 140, 70.0],
		[0.0100, 2.5, 8.8, 80.0, 0.500, 1.000, 0.94868, 0.2, 0.50, -4.0, -7.0, 660, 160, 45.0],
		[0.0120, 6.1, 19.8, 75.0, 0.050, 0.100, 0.98489, 0.4, 0.95, -14.0, -19.0, 360, 720, 90.0],
		[0.0140, 6.2, 15.0, 80.0, 0.300, 1.000, 0.995, 0.1, 0.70, -6.0, -10.0, 120, 220, 40.0],
		[0.0080, 2.2, 4.9, 90.0, 0.000, 0.250, 0.89443, 0.2, 0.10, -1.5, -3.0, 120, 240, 50.0],
		[0.0120, 4.2, 7.0, 75.0, 0.750, 1.000, 0.94868, 0.2, 0.40, -3.5, -6.0, 240, 240, 90.0],
		[0.0130, 5.0, 13.4, 70.0, 0.500, 0.750, 0.98995, 0.2, 0.60, -4.5, -12.0, 240, 300, 60.0],
		[0.0095, 3.4, 15.0, 55.0, 0.200, 0.250, 0.98995, 0.6, 0.70, -13.5, -4.0, 60, 1120, 70.0],
		[0.0120, 3.3, 8.0, 75.0, 0.300, 0.600, 0.97468, 0.2, 0.20, -2.0, -7.0, 240, 240, 70.0],
		[0.0100, 5.1, 6.0, 85.0, 0.200, 0.200, 0.94868, 0.5, 0.20, -3.0, -4.0, 120, 360, 50.0],
		[0.0080, 2.7, 4.9, 96.0, 0.200, 0.400, 0.89443, 0.5, 0.10, -3.0, -3.0, 120, 360, 30.0],
		[0.0080, 2.5, 4.9, 102.0, 0.000, 0.250, 0.89443, 0.2, 0.10, -2.0, -3.0, 120, 240, 50.0],
		[0.0160, 7.1, 22.8, 65.0, 0.100, 0.300, 0.98995, 0.4, 0.85, -2.5, -20.5, 300, 420, 20.0],
		[0.0165, 5.8, 10.4, 70.0, -0.050, 0.150, 0.94868, 0.2, 0.40, 5.0, -14.0, 120, 180, 70.0],
		[0.0100, 1.0, 1.0, 70.0, 0.500, 0.500, 0.94868, 0.2, 0.40, -1.0, -9.0, 120, 180, 70.0],
		[0.0080, 1.5, 3.9, 102.0, 0.150, 0.400, 0.89443, 0.1, 0.40, -1.0, -3.0, 120, 360, 30.0],
		[0.0100, 4.0, 5.5, 70.0, 0.200, 0.150, 0.94868, 0.1, 0.40, -1.0, -3.0, 60, 120, 70.0],
		[0.0100, 4.0, 9.5, 80.0, 0.300, 0.800, 0.995, 0.1, 0.75, -3.5, -5.0, 160, 200, 25.0],
		[0.0100, 6.0, 11.4, 90.0, 0.250, 0.350, 0.995, 0.2, 0.45, -6.0, -6.5, 120, 240, 30.0],
		[0.0100, 5.0, 10.9, 95.0, 0.250, 0.450, 0.995, 0.2, 0.40, -5.0, -6.0, 120, 240, 30.0],
		[0.0120, 9.3, 31.5, 75.0, 0.050, 0.100, 0.97468, 0.2, 0.90, -14.0, -31.0, 240, 480, 90.0],
	]
	if index < 0 or index >= ROWS.size():
		return {}
	var row: Array = ROWS[index]
	return {
		"render_scale": float(row[0]),
		"ofs_y": float(row[1]),
		"body_len": float(row[2]),
		"depth": float(row[3]),
		"speed": float(row[4]),
		"speed_range": float(row[5]),
		"drag": float(row[6]),
		"turn_chance": float(row[7]),
		"ofs_z": float(row[9]),
		"body_pad": float(row[10]),
		"active_min": int(row[11]),
		"active_range": int(row[12]),
		"turn_deg": float(row[13]),
	}


static func gx_to_world(grid: WorldGrid, gx: Vector3) -> Vector3:
	if grid == null:
		return gx * FieldCatalog.GX_TO_METERS
	return grid.origin + gx * FieldCatalog.GX_TO_METERS


static func map_item(item: ItemData) -> Dictionary:
	if item == null:
		return {}
	if item is FishData:
		var fi: int = fish_index(item.id)
		if fi < 0:
			return {}
		return {"category": Category.FISH, "index": fi}
	if item is BugData:
		var bi: int = (item as BugData).type_index
		if bi < 0 or bi >= 40:
			return {}
		return {"category": Category.INSECT, "index": bi}
	if item is FurnitureData:
		var visual := String((item as FurnitureData).visual_id)
		if visual.is_empty():
			visual = String(item.id)
		var fossil_i: int = FOSSIL_VISUALS.find(StringName(visual))
		if fossil_i < 0:
			fossil_i = FOSSIL_VISUALS.find(item.id)
		if fossil_i >= 0:
			return {"category": Category.FOSSIL, "index": fossil_i}
		var art_i: int = ART_VISUALS.find(StringName(visual))
		if art_i < 0:
			art_i = ART_VISUALS.find(item.id)
		if art_i >= 0:
			return {"category": Category.ART, "index": art_i}
	## Pocket fossils / art by id naming.
	var raw := String(item.id)
	if raw.begins_with("int_din_") or raw.begins_with("din_"):
		var fid: int = FOSSIL_VISUALS.find(item.id)
		if fid < 0 and raw.begins_with("din_"):
			fid = FOSSIL_VISUALS.find(StringName("int_%s" % raw))
		if fid >= 0:
			return {"category": Category.FOSSIL, "index": fid}
	if raw.begins_with("int_sum_art") or raw.begins_with("art"):
		var aid: int = ART_VISUALS.find(item.id)
		if aid < 0 and raw.begins_with("art"):
			aid = ART_VISUALS.find(StringName("int_sum_%s" % raw))
		if aid >= 0:
			return {"category": Category.ART, "index": aid}
	return {}


## True when donating `index` completes its multi-part skeleton (`aCR_chk_fossil_parts_complete`).
static func fossil_set_just_completed(book: Variant, index: int) -> bool:
	if book == null or index in FOSSIL_SOLO:
		return false
	if not book.has_method("fossil_info"):
		return false
	for group: Variant in FOSSIL_SETS:
		var parts: Array = group as Array
		if not parts.has(index):
			continue
		for part: Variant in parts:
			var donator: int = int(book.call("fossil_info", int(part)))
			if donator < 1 or donator > 5:
				return false
		return true
	return false


static func insect_is_active(type_index: int, hour: int, minute: int = 0) -> bool:
	if type_index < 0 or type_index >= INSECT_ACTIVE_HOUR.size():
		return true
	var active_h: float = INSECT_ACTIVE_HOUR[type_index]
	var relax_h: float = INSECT_RELAX_HOUR[type_index]
	## 0/0 means always active (no schedule).
	if active_h <= 0.0 and relax_h <= 0.0:
		return true
	var now: float = float(posmod(hour, 24)) + float(clampi(minute, 0, 59)) / 60.0
	if active_h <= relax_h:
		return now >= active_h and now < relax_h
	## Wraps midnight (e.g. firefly 19→4).
	return now >= active_h or now < relax_h
