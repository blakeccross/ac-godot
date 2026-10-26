class_name InteriorArrival
extends RefCounted

## Where and how the player lands in the room that is about to load. `Game` builds one in
## `try_enter_interior`; `interior.tscn` reads it when it spawns the player and clears the
## parts it has used.

## Stand at `stand` (metres from the room's corner; the decomp's door data) facing
## `stand_yaw`.
var has_stand: bool = false
var stand: Vector3 = Vector3.ZERO
var stand_yaw: float = 0.0
## No door data for this room: stand on the room's own spawn cell.
var at_room_door: bool = false
## After spawning, walk in past the door (`INTO_S1`).
var walks_in: bool = false


func clear() -> void:
	has_stand = false
	at_room_door = false
	walks_in = false


## The landing for `room_id`: an explicit stand if the caller has one (a door that links two
## rooms), else the building's own door data.
static func for_room(
	room_id: StringName, room: Room, explicit: Variant = null, explicit_yaw: Variant = null
) -> InteriorArrival:
	if explicit is Vector3:
		var linked := _standing_at(explicit, float(explicit_yaw) if explicit_yaw != null else 0.0)
		## Museum wings and the player's own rooms spawn from door data, with no walk-in.
		var museum: bool = room != null and room.kind == Room.Kind.MUSEUM
		linked.walks_in = not museum and not PlayerHouse.is_player_room(room_id)
		return linked
	if room_id == &"museum_entrance":
		## `aMsm_museum_enter_data`, not the scene's player data or a generic south door cell.
		## The wipe lands facing north, so there is no walk-in.
		return _standing_at(
			MuseumDisplay.ENTRANCE_SPAWN, WorldGrid.yaw_for_furniture(MuseumDisplay.ENTRANCE_SPAWN_FACING)
		)
	if ShopDisplay.nook_is_shop_room(room_id):
		## The building's `Door_data_c` (`aSHOP_` ... `aDPT_depart_door_data`), `mSc_DIRECT_NORTH`.
		return _standing_at(
			ShopDisplay.nook_spawn(room_id), WorldGrid.yaw_for_facing(ShopDisplay.CRANNY_SPAWN_FACING)
		)
	if room_id == &"post_office":
		## `aPOFF_post_office_door_data` GX {160,0,300}, orient 4 = north.
		return _standing_at(PostDisplay.SPAWN, WorldGrid.yaw_for_facing(PostDisplay.SPAWN_FACING))
	if room_id == &"police_box":
		## `aPBOX_police_box_enter_data` GX {200,0,380}, `mSc_DIRECT_NORTH`.
		return _standing_at(PoliceDisplay.SPAWN, WorldGrid.yaw_for_facing(PoliceDisplay.SPAWN_FACING))
	if room_id == &"needlework":
		## `aNW_needlework_shop_door_data` GX {160,0,300}, orient 4 = north. `rom_tailor` keeps
		## the acre origin, so this maps like the Nook shops.
		return _standing_at(
			InteriorCatalog.ABLE_SPAWN, WorldGrid.yaw_for_facing(InteriorCatalog.ABLE_SPAWN_FACING)
		)
	if room_id == &"lighthouse":
		## `aTOU_door_data` GX {120,0,100}, `mSc_DIRECT_SOUTH` (just inside the north door).
		return _standing_at(LighthouseRoom.SPAWN, WorldGrid.yaw_for_facing(LighthouseRoom.SPAWN_FACING))
	if room.kind == Room.Kind.NPC:
		## `aHUS_npc_house_door_data`, not the walkable-south `door_cell - 1`.
		return _standing_at(
			InteriorCatalog.NPC_HOUSE_SPAWN, WorldGrid.yaw_for_facing(WorldGrid.Facing.NORTH)
		)
	if room_id == &"player_main":
		## `aMHS_goto_next_pl_scene` startX/Z for the current house size.
		return _standing_at(
			PlayerHouse.enter_point(Game.interiors.player_house()),
			WorldGrid.yaw_for_facing(WorldGrid.Facing.NORTH)
		)
	var at_door := InteriorArrival.new()
	at_door.at_room_door = true
	return at_door


static func _standing_at(at: Vector3, yaw: float) -> InteriorArrival:
	var arrival := InteriorArrival.new()
	arrival.has_stand = true
	arrival.stand = at
	arrival.stand_yaw = yaw
	return arrival
