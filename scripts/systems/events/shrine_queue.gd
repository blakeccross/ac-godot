class_name ShrineQueue
extends RefCounted

## The New Year's queue at the wishing well (`ac_hatumode_control`, `ac_hatumode_npc0`).
## Villagers go round two loops, one each side of the well: from the waiting spot at the front
## of their column (`aHN0_posX/Z` points 1 and 2) to the offering spot, where they throw a coin
## (`SAISEN1`, the coin at frame 33) and pray (`OMAIRI1`); then out to the side, round the
## back, and a bow (`AISATU*`) to the one in the other column before stepping up again. The
## columns take turns at the well. A villager waiting at the front asks the player whether
## they'd like to go first (`base_msg`, `aHN0_talk_saisen_suru`); on Yes the player is walked
## to the spot behind the well's front (`aHTMD_clip_player_move`), waits their turn, steps up
## and makes their wish at the well (`aHTC_request`…`aHTC_inori_end`), and the villager who let
## them in goes round without praying (`aHN0_sanpai_wait` → think 10). Not an autoload.

## `aHN0_posX/Z` from the well's centre in GX (the decomp counts from its anchor unit,
## 20 GX across and 20 up): +X to the well's right as you face it, +Z out of its front.
const POINTS: Array[Vector2] = [
	Vector2(0.0, 55.0),     ## 0 the offering spot
	Vector2(-20.0, 140.0),  ## 1 front of the left column
	Vector2(20.0, 140.0),   ## 2 front of the right column
	Vector2(-20.0, 180.0),  ## 3 back of the left column
	Vector2(20.0, 180.0),   ## 4 back of the right column
	Vector2(-80.0, 55.0),   ## 5 out to the left
	Vector2(-80.0, 180.0),  ## 6 round the left back
	Vector2(80.0, 55.0),    ## 7 out to the right
	Vector2(80.0, 180.0),   ## 8 round the right back
]
## `aHN0_root`: each column's round, from the offering spot.
const LOOPS: Array = [[0, 5, 6, 3, 1], [0, 7, 8, 4, 2]]
const LEG_OFFER := 0
const LEG_BACK := 3
const LEG_FRONT := 4
## `aHTMD_clip_player_move`: where the player waits, then stands to pray (the well's own
## `visit_stand`).
const PLAYER_WAIT := Vector2(0.0, 100.0)
## `aHN0_omairi_af_init`: 120 frames standing after the prayer.
const AFTER_SEC := 2.0
## `ac_hatumode_npc0` `base_msg_table`, by looks: +0 the offer, +1 Yes, +2 No,
## +3/6/9/12 by place in the queue (`aHN0_make_msg`), +15 once the player has prayed.
const BASE_MSG: Array[int] = [7679, 7697, 7661, 7715, 7733, 7751]
## `aHN0_aisatu_local`: the bow by looks (girl / boy `AISATU2`, ko-girl / sport man
## `AISATU1`, grim man `AISATU3`, naniwa lady `AISATU4`).
const BOW_CLIPS: Array[String] = [
	"npc_1_aisatu2", "npc_1_aisatu1", "npc_1_aisatu2", "npc_1_aisatu1", "npc_1_aisatu3", "npc_1_aisatu4",
]
const CLIP_SAISEN := "npc_1_saisen1"
const CLIP_OMAIRI := "npc_1_omairi1"
## `aHN0_move_init`: `aNPC_ACT_RUN`.
const CLIP_RUN := "npc_1_run1"
const RUN_SPEED := 3.0
const PLAYER_WALK_SPEED := 2.0

enum PlayerState { NONE, QUEUED, UP, DONE }

## Who is at (or heading to) the offering spot: a slot, `PLAYER`, or -1.
const PLAYER := 99
static var offering_by: int = -1
## The column whose turn it is at the well.
static var turn: int = 0
## Per column, the slot at (or heading to) its front spot, or -1.
static var front_by: Array[int] = [-1, -1]
static var player_state: int = PlayerState.NONE
## The villager who let the player in.
static var sponsor: int = -1
## Villagers out in the queue (the well only takes wishes through it while any are).
static var members: int = 0


static func reset() -> void:
	offering_by = -1
	turn = 0
	front_by = [-1, -1]
	player_state = PlayerState.NONE
	sponsor = -1
	members = 0


## `aHN0_ready2` roots: slot 0 starts at the well on the right, 1 at the front on the left,
## 2 at the front on the right, 3 at the back on the left.
static func column_of(slot: int) -> int:
	return 1 if slot % 2 == 0 else 0


static func start_leg(slot: int) -> int:
	return [LEG_OFFER, LEG_FRONT, LEG_FRONT, LEG_BACK][slot % 4]


static func point_of(column: int, leg: int) -> Vector2:
	return POINTS[int(LOOPS[column][posmod(leg, 5)])]


## The next leg round the column.
static func next_leg(leg: int) -> int:
	return posmod(leg + 1, 5)


## The front spot is free for `slot` (nobody else of its column there).
static func can_take_front(slot: int) -> bool:
	var col: int = column_of(slot)
	return front_by[col] == -1 or front_by[col] == slot


static func take_front(slot: int) -> void:
	front_by[column_of(slot)] = slot


## `aHN0_flag2_wait`: the well is free and it's this column's turn; a player let in by this
## villager goes in its place.
static func may_step_up(slot: int) -> bool:
	if offering_by != -1 or turn != column_of(slot):
		return false
	return not (player_state == PlayerState.QUEUED and sponsor == slot)


static func step_up(slot: int) -> void:
	offering_by = slot
	if front_by[column_of(slot)] == slot:
		front_by[column_of(slot)] = -1


## Done at the well: the other column goes next.
static func step_down(who: int) -> void:
	if offering_by == who:
		offering_by = -1
	var col: int = column_of(sponsor) if who == PLAYER and sponsor >= 0 else column_of(who)
	turn = 1 - col


## The player's turn has come (their sponsor's column, the well free).
static func player_may_step_up() -> bool:
	return player_state == PlayerState.QUEUED and offering_by == -1 and sponsor >= 0 \
		and turn == column_of(sponsor)


static func queue_player(slot: int) -> void:
	player_state = PlayerState.QUEUED
	sponsor = slot


## The villager at the front may offer the player a place.
static func can_offer(slot: int) -> bool:
	return player_state == PlayerState.NONE and front_by[column_of(slot)] == slot


## `aHN0_make_msg`: how far `slot` is from the one at the well, 1…4.
static func place_in_line(slot: int, at_well: int) -> int:
	var k: int = posmod(slot - maxi(at_well, 0), 4)
	return 4 if k == 0 else k


static func talk_msg(looks: int, slot: int, rng: RandomNumberGenerator) -> int:
	var base: int = BASE_MSG[clampi(looks, 0, 5)]
	return base + 3 * place_in_line(slot, offering_by) + rng.randi_range(0, 2)


static func offer_msg(looks: int) -> int:
	return BASE_MSG[clampi(looks, 0, 5)]


static func thanks_msg(looks: int, rng: RandomNumberGenerator) -> int:
	return BASE_MSG[clampi(looks, 0, 5)] + 15 + rng.randi_range(0, 2)


## A queue point in the world, from the well's centre and facing.
static func to_world(well: Node3D, at_gx: Vector2) -> Vector3:
	var b: Basis = Basis(Vector3.UP, well.global_rotation.y)
	return well.global_position + b * Vector3(at_gx.x, 0.0, at_gx.y) * FieldCatalog.GX_TO_METERS


## Facing the well's front from out in the queue.
static func facing_well(well: Node3D) -> float:
	return wrapf(well.global_rotation.y + PI, -PI, PI)
