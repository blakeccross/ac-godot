class_name PlayerHouse
extends RefCounted

## The player's house as the decomp lays it out: one persistent main floor whose walls, shell
## and stairs follow the house size (`l_proom_{s,m,l}_tmp`, `SCENE_MY_ROOM_{S,M,L,LL1}`),
## plus the upper floor (`SCENE_MY_ROOM_LL2`) and basement (`SCENE_MY_ROOM_BASEMENT_*`).
## Furniture lives on the room, not the scene, so it survives every upgrade
## (`mHm_RehouseWallDoor` only rewrites wall / door units).
##
## Coordinates are disc GX (`FieldCatalog.GX_TO_METERS`); a unit is 40 GX.

## Plot 0 (`HOUSE0`): the player's house until the intro picks another.
const DEFAULT_PLOT := &"player_house"
const MAIN := &"player_main"
const UPPER := &"player_upper"
const BASEMENT := &"player_basement"

const GX_UNIT := 40.0

## `aMI_size_dsp_table` shells per house tier (S, M, L, UPPER = LL1).
const MAIN_SHELLS: Array[Array] = [
	["rom_myhome1_floor", "rom_myhome1_wall"],
	["rom_myhome2B_floor", "rom_myhome2B_wall"],
	["rom_myhome3_floor", "rom_myhome3_wall"],
	["rom_myhome4_1_floor", "rom_myhome4_1_wall"],
]
const UPPER_SHELLS: Array[String] = ["rom_myhome4_2_floor", "rom_myhome4_2_wall"]
const BASEMENT_SHELLS: Array[String] = ["rom_myhome_ug"]

## Walkable rect per tier — the `.` run inside `l_proom_*_tmp` (NW origin is always (1,1)).
const MAIN_INNER: Array[Vector2i] = [
	Vector2i(4, 4), Vector2i(6, 6), Vector2i(8, 8), Vector2i(8, 8)
]
## `EXIT_DOOR` pair (west cell) per tier.
const MAIN_EXIT: Array[Vector2i] = [
	Vector2i(2, 7), Vector2i(3, 9), Vector2i(4, 11), Vector2i(4, 11)
]
## `aMHS_goto_next_pl_scene` startX/Z — where you stand after walking in from outside.
const MAIN_ENTER_GX: Array[Vector3] = [
	Vector3(120.0, 0.0, 220.0),
	Vector3(160.0, 0.0, 300.0),
	Vector3(200.0, 0.0, 380.0),
	Vector3(200.0, 0.0, 380.0),
]
## `DOOR0` unit on each main layout (stairs down to the basement). Small has one in the
## template but no slope, so it never fires (`Player_actor_check_bg_for_next_goto`).
const MAIN_BASEMENT_DOOR: Array[Vector2i] = [
	Vector2i(6, 5), Vector2i(7, 7), Vector2i(8, 9), Vector2i(8, 9)
]
## `aMI_size_dsp_table[kind].size` step anchor (`aMI_DrawMyStep`), per house tier.
const STEP_ANCHOR_GX: Array[Vector3] = [
	Vector3(120.0, 0.0, 220.0),
	Vector3(160.0, 0.0, 300.0),
	Vector3(200.0, 0.0, 380.0),
	Vector3(200.0, 0.0, 380.0),
]

## `l_proom_l_tmp` `DOOR1` — LL1 stairs up.
const UPPER_STAIR_DOOR := Vector2i(1, 9)
const UPPER_ARRIVE_GX := Vector3(60.0, 0.0, 300.0)
## `l_player_room_2_utinfo` `DOOR0` — LL2 stairs down; anchor is the medium size.
const UPPER_INNER := Vector2i(6, 6)
const UPPER_DOWN_DOOR := Vector2i(0, 7)
const UPPER_DOWN_ARRIVE_GX := Vector3(100.0, 0.0, 380.0)
const UPPER_ANCHOR_GX := Vector3(160.0, 0.0, 300.0)

## `l_player_room_bm_utinfo`.
const BASEMENT_INNER := Vector2i(8, 8)
const BASEMENT_UP_DOOR := Vector2i(8, 9)
const BASEMENT_ARRIVE_GX := Vector3(300.0, 0.0, 380.0)
const BASEMENT_ANCHOR_GX := Vector3(200.0, 0.0, 380.0)
## `P_ROOM_BM_*_door_data` exit position per tier (back up to the main floor).
const BASEMENT_EXIT_GX: Array[Vector3] = [
	Vector3(220.0, 0.0, 220.0),
	Vector3(260.0, 0.0, 300.0),
	Vector3(300.0, 0.0, 380.0),
	Vector3(300.0, 0.0, 380.0),
]

## `aMR_GetSceneFurnitureMax`: furniture actors a floor can hold — small 32, medium 48, large
## and upper 64; the upper floor 48; basements 64. Items sitting on tables count too.
const MAIN_FURNITURE_CAP: Array[int] = [32, 48, 64, 64]
const UPPER_FURNITURE_CAP := 48
const BASEMENT_FURNITURE_CAP := 64

const STEP_DOWN := &"obj_myhome_step_down"
const STEP_UP := &"obj_myhome_step_up"


## Tier index 0..3 for layout lookups (statue keeps the last house layout).
static func tier_of(house: House) -> int:
	if house == null:
		return 0
	return house.model_tier()


static func is_player_room(room_id: StringName) -> bool:
	return room_id == MAIN or room_id == UPPER or room_id == BASEMENT


## Rewrite the size-dependent fields of a runtime player room. Furniture, wall and floor
## are left alone.
static func configure_room(room: Room, house: House) -> void:
	if room == null:
		return
	var tier: int = tier_of(house)
	var basement: bool = house != null and house.has_basement
	match room.id:
		MAIN:
			_configure_main(room, tier, basement)
		UPPER:
			_configure_upper(room, tier)
		BASEMENT:
			_configure_basement(room, tier)


static func _configure_main(room: Room, tier: int, basement: bool) -> void:
	room.inner_origin = InteriorCatalog.PLAYER_INNER_ORIGIN
	room.inner_size = MAIN_INNER[tier]
	room.door_cell = MAIN_EXIT[tier]
	room.spawn_cell = MAIN_EXIT[tier] + Vector2i(0, -2)
	room.shell_ids = PackedStringArray(MAIN_SHELLS[tier])
	room.stairs.clear()
	if basement and tier >= int(House.SizeTier.MEDIUM):
		room.stairs.append(
			_stair(
				MAIN_BASEMENT_DOOR[tier],
				BASEMENT,
				BASEMENT_ARRIVE_GX,
				WorldGrid.Facing.WEST,
				RoomStair.Dir.DOWN,
				"Basement"
			)
		)
	if tier >= int(House.SizeTier.UPPER):
		room.stairs.append(
			_stair(
				UPPER_STAIR_DOOR,
				UPPER,
				UPPER_ARRIVE_GX,
				WorldGrid.Facing.EAST,
				RoomStair.Dir.UP,
				"Upstairs"
			)
		)


static func _configure_upper(room: Room, _tier: int) -> void:
	room.inner_origin = InteriorCatalog.PLAYER_INNER_ORIGIN
	room.inner_size = UPPER_INNER
	room.shell_ids = PackedStringArray(UPPER_SHELLS)
	## No outdoor exit up here — the only way out is the stairs.
	room.door_cell = Vector2i(-8, -8)
	room.spawn_cell = Vector2i(1, 7)
	room.stairs.clear()
	room.stairs.append(
		_stair(
			UPPER_DOWN_DOOR,
			MAIN,
			UPPER_DOWN_ARRIVE_GX,
			WorldGrid.Facing.EAST,
			RoomStair.Dir.DOWN,
			"Downstairs"
		)
	)


static func _configure_basement(room: Room, tier: int) -> void:
	room.inner_origin = InteriorCatalog.PLAYER_INNER_ORIGIN
	room.inner_size = BASEMENT_INNER
	room.shell_ids = PackedStringArray(BASEMENT_SHELLS)
	room.door_cell = Vector2i(-8, -8)
	room.spawn_cell = Vector2i(7, 9)
	room.stairs.clear()
	room.stairs.append(
		_stair(
			BASEMENT_UP_DOOR,
			MAIN,
			BASEMENT_EXIT_GX[tier],
			WorldGrid.Facing.WEST,
			RoomStair.Dir.UP,
			"Upstairs"
		)
	)


static func _stair(
	cell: Vector2i,
	target: StringName,
	spawn_gx: Vector3,
	facing: WorldGrid.Facing,
	dir: RoomStair.Dir,
	label: String
) -> RoomStair:
	var stair := RoomStair.new()
	stair.cell = cell
	stair.target_room_id = target
	stair.spawn_gx = spawn_gx
	stair.spawn_facing = facing
	stair.dir = dir
	stair.label = label
	return stair


## `aMHS_goto_next_pl_scene` stand for the current size.
static func enter_gx(house: House) -> Vector3:
	return MAIN_ENTER_GX[tier_of(house)]


## `obj_myhome_step_*` draws for a room: each is `{ "visual", "gx", "mirror" }`
## (`aMI_MakeStepData` + `aMI_DrawMyStep`).
static func step_draws(room: Room, house: House) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if room == null:
		return out
	var tier: int = tier_of(house)
	match room.id:
		MAIN:
			if house != null and house.has_basement and tier >= int(House.SizeTier.MEDIUM):
				out.append({"visual": STEP_DOWN, "gx": STEP_ANCHOR_GX[tier], "mirror": false})
			if tier >= int(House.SizeTier.UPPER):
				out.append({"visual": STEP_UP, "gx": STEP_ANCHOR_GX[tier], "mirror": false})
		UPPER:
			out.append({"visual": STEP_DOWN, "gx": UPPER_ANCHOR_GX, "mirror": true})
		BASEMENT:
			out.append({"visual": STEP_UP, "gx": BASEMENT_ANCHOR_GX, "mirror": true})
	return out


## Centre of a unit in GX.
static func cell_center_gx(cell: Vector2i) -> Vector3:
	return Vector3((float(cell.x) + 0.5) * GX_UNIT, 0.0, (float(cell.y) + 0.5) * GX_UNIT)


## Room a house tier's outdoor door leads to. Only the main floor is ever an outdoor entry.
static func entry_room(_house: House) -> StringName:
	return MAIN


## Outdoor model for the player's own house node (`aMHS_actor_ct` skeleton table): one of
## `obj_{s,w}_myhome1..4` by size; the season half is resolved by `FieldCatalog.mesh_paths`.
## Other plots (and every non-player house) keep the visual they were generated with.
static func exterior_visual(node_name: String, fallback: StringName) -> StringName:
	if not is_owned_node(node_name) or not String(fallback).begins_with("obj_s_myhome"):
		return fallback
	var house: House = Game.interiors.player_house() if Game != null and Game.interiors != null else null
	return StringName("obj_s_myhome%d" % (tier_of(house) + 1))


## Outdoor house node the player lives in (`mHS_get_arrange_idx`): the intro pick while
## the station intro is choosing, else the saved `House.outdoor_building_id` (the pick is
## written there by `Game.claim_intro_house`). "" while the intro has no pick yet — every
## plot is vacant then.
static func owned_building_id() -> StringName:
	if Game == null:
		return DEFAULT_PLOT
	if Game.intro_station_house_id != &"":
		return Game.intro_station_house_id
	if Game.intro_station_active:
		return &""
	var house: House = Game.interiors.player_house() if Game.interiors != null else null
	if house == null or not String(house.outdoor_building_id).begins_with(String(DEFAULT_PLOT)):
		return DEFAULT_PLOT
	return house.outdoor_building_id


## True for the plot the player actually lives in (see `owned_building_id`).
static func is_owned_node(node_name: String) -> bool:
	if not node_name.begins_with(String(DEFAULT_PLOT)):
		return false
	return node_name == String(owned_building_id())


## House plot index (0..3, `HOUSE0`–`3`) of a per-plot placement id: `player_house`,
## `player_mailbox`, `player_haniwa` → 0; `…_1`–`…_3` → 1–3.
static func plot_of(node_name: String) -> int:
	var tail: String = node_name.get_slice("_", 2)
	return clampi(tail.to_int(), 0, 3) if tail.is_valid_int() else 0


## The outdoor house node for plot `idx`.
static func plot_building(idx: int) -> String:
	return String(DEFAULT_PLOT) if idx <= 0 else "%s_%d" % [DEFAULT_PLOT, idx]


## `aMHS_actor_draw_before`: the fish weathervane (`kazamiA` / `kazamiB`, joints 3 / 5) and the
## insect plaque (`fuda`, joint 1) only draw once a villager has congratulated the player on
## the finished collection. Only the joint's own mesh is dropped — the plaque joint parents
## the rest of the house. The weathervane does not turn with the wind yet.
static func apply_exterior_decorations(host: Node3D) -> void:
	if host == null or not is_owned_node(String(host.name)):
		return
	var visual: Node = host.get_node_or_null("GeneratedVisual")
	if visual == null:
		return
	_apply_decoration(visual, "_kazamiA_model", CompleteTalk.talked(CompleteTalk.FISH))
	_apply_decoration(visual, "_kazamiB_model", CompleteTalk.talked(CompleteTalk.FISH))
	_apply_decoration(visual, "_fuda_model", CompleteTalk.talked(CompleteTalk.INSECT))
	apply_door_pattern(visual)


## `aMHS_actor_draw`: the door's mark (`obj_myhome_mark_tex_txt` on segments 9 / A) is swapped
## for one of the owner's designs while `door_original` names one (`my_org[door_original & 7]`,
## posted through the house gyroid); 0xFF shows the mark. Only the albedo changes — the
## surface keeps its house material and shading.
const DOOR_MARK_TEX := "obj_myhome_mark"
const NO_DOOR_PATTERN := 0xFF


static func door_design(house: House) -> DesignPattern:
	if house == null or house.door_original == NO_DOOR_PATTERN or Game == null or Game.designs == null:
		return null
	var idx: int = house.door_original & 7
	return Game.designs.player[idx] if idx < Game.designs.player.size() else null


static func apply_door_pattern(visual: Node) -> void:
	var design: DesignPattern = door_design(Game.interiors.player_house() if Game != null and Game.interiors != null else null)
	var tex: Texture2D = DesignTexture.build(design) if design != null else null
	_paint_door_mark(visual, tex)


static func _paint_door_mark(node: Node, tex: Texture2D) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
		for i: int in count:
			var mat: Material = mi.get_active_material(i)
			if not (mat is StandardMaterial3D):
				continue
			if not VisualSurface.surface_label(mi, i, mat).contains(DOOR_MARK_TEX):
				continue
			var std: StandardMaterial3D = mat as StandardMaterial3D
			if not std.has_meta(&"door_mark_albedo"):
				std = std.duplicate() as StandardMaterial3D
				std.set_meta(&"door_mark_albedo", std.albedo_texture)
				mi.set_surface_override_material(i, std)
			std.albedo_texture = tex if tex != null else std.get_meta(&"door_mark_albedo") as Texture2D
	for child: Node in node.get_children():
		_paint_door_mark(child, tex)


static func _apply_decoration(root: Node, name_suffix: String, shown: bool) -> void:
	if shown:
		return
	for node: Node in root.find_children("*" + name_suffix, "MeshInstance3D", true, false):
		(node as MeshInstance3D).mesh = null


## Furniture limit for a player floor, or 0 when the room has none (`aMR_WeightPossible`).
static func furniture_cap(room_id: StringName, house: House) -> int:
	match room_id:
		MAIN:
			return MAIN_FURNITURE_CAP[tier_of(house)]
		UPPER:
			return UPPER_FURNITURE_CAP
		BASEMENT:
			return BASEMENT_FURNITURE_CAP
	return 0
