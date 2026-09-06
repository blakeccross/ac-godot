class_name PostDisplay
extends RefCounted

## Post office indoor layout (`SCENE_POST_OFFICE` / `FG_TYPE_GRD_POST_OFFICE` / `post_office_actable`).
## Behavioral reference: `post_office.c` scene, `bg_post_item`, `ac_npc_post_girl`.

## Walkable NW + size from `grd_post_office` collision (attr ≠ 31). Exit `EXIT_DOOR` at (3,8)/(4,8).
const INNER_ORIGIN := Vector2i(1, 1)
const INNER_SIZE := Vector2i(6, 8)
const DOOR_CELL := Vector2i(3, 8)
const SPAWN_CELL := Vector2i(3, 7)

## `POST_OFFICE_player_data` GX {100,0,200}, face south (yaw 0).
const SPAWN_GX := Vector3(100.0, 0.0, 200.0)
const SPAWN_FACING := WorldGrid.Facing.SOUTH

## `post_office_actable` ut (4,2); `aPG_actor_ct` then subtracts 20 GX on X.
const POST_GIRL_STAND_UT := Vector2i(4, 2)
const POST_GIRL_STAND_GX := Vector3(160.0, 0.0, 100.0)
const POST_GIRL_FACING := WorldGrid.Facing.SOUTH

## Day Pelly `pga` (7:00–19:00); night Phyllis `pgb` (`bg_post_item` post_girl_npc_type).
## Draw data: `SP_NPC_POST_GIRL` → `pga_1`, `SP_NPC_POST_GIRL2` → `pgb_1` (not `pla`/`plb`).
const PELLY_SPECIES := &"pga"
const PHYLLIS_SPECIES := &"pgb"
const PELLY_DAY_START_HOUR := 7
const PELLY_DAY_END_HOUR := 19

## `bPTI_actor_draw` letter piles: X {80,120,160,200,240}, Y 60, Z 60.
const MAIL_PILE_Y_GX := 60.0
const MAIL_PILE_Z_GX := 60.0
const MAIL_PILE_X_GX: Array[float] = [80.0, 120.0, 160.0, 200.0, 240.0]

## Desk slab between lobby and clerk (shell mesh has no physics). Center + half-extents GX.
const DESK_CENTER_GX := Vector3(160.0, 0.0, 140.0)
const DESK_HALF_GX := Vector3(100.0, 45.0, 22.0)

## `POST_OFFICE_actor_data` PTerminal GX {60,0,240}; talk probe near {60,40,220}.
const PTERMINAL_GX := Vector3(60.0, 0.0, 240.0)
const PTERMINAL_HALF_GX := Vector3(28.0, 50.0, 28.0)
const PTERMINAL_MSG := 15854
const PTERMINAL_GUEST_MSG := 15851
const PTERMINAL_NO_GBA_MSG := 15859

## `aPG_set_talk_info` base msg_no[status] (Pelly); Phyllis uses +1 (`draw_type`).
## status bits: desk_full | done_first_job | has_bank (`ac_npc_post_girl.h`).
const TALK_MSG_BY_STATUS: Array[int] = [
	0x31D3, 0x31D1, 0x08B1, 0x08AD, 0x08D1, 0x08CF, 0x08B1, 0x08AD
]
const FALLBACK_GREETING_ID := &"post_girl_greeting"
const DEPOSIT_AMOUNT_ID := &"post_girl_deposit"
const WITHDRAW_AMOUNT_ID := &"post_girl_withdraw"
const BANK_MENU_ID := &"post_girl_bank"
const REPAY_AMOUNT_ID := &"post_girl_repay"
const SEND_MAIL_ID := &"post_girl_send_mail"
const SAVE_MAIL_ID := &"post_girl_save_mail"
const WRITE_LETTER_ID := &"write_letter"
const STATUS_DESK_FULL := 1
const STATUS_DONE_FIRST_JOB := 2
const STATUS_HAS_BANK := 4

const SHELL_ID := &"grd_post_office"


static func post_girl_species(hour: int = -1) -> StringName:
	var h: int = hour
	if h < 0 and Clock != null:
		h = Clock.hour
	if h < 0:
		h = 12
	if h >= PELLY_DAY_END_HOUR or h < PELLY_DAY_START_HOUR:
		return PHYLLIS_SPECIES
	return PELLY_SPECIES


static func post_girl_name(species: StringName = &"") -> String:
	var id: StringName = species if species != &"" else post_girl_species()
	return "Phyllis" if id == PHYLLIS_SPECIES else "Pelly"


static func draw_type(species: StringName = &"") -> int:
	## Pelly 0 / Phyllis 1 (`aPG_actor_ct`).
	var id: StringName = species if species != &"" else post_girl_species()
	return 1 if id == PHYLLIS_SPECIES else 0


static func talk_status(desk_full: bool = false, has_bank: bool = true) -> int:
	## status = desk_full | done_first_job | has_bank (`aPG_set_post_status`).
	var owing: int = 0
	if Game != null and Game.inventory != null:
		owing = Game.inventory.loan
	var status: int = 0
	if owing > 0:
		status |= STATUS_DONE_FIRST_JOB
	elif has_bank:
		status |= STATUS_HAS_BANK
	if desk_full:
		status |= STATUS_DESK_FULL
	return status


static func talk_msg_no(
	species: StringName = &"", desk_full: bool = false, has_bank: bool = true
) -> int:
	var status: int = talk_status(desk_full, has_bank)
	var base: int = TALK_MSG_BY_STATUS[clampi(status, 0, TALK_MSG_BY_STATUS.size() - 1)]
	return base + draw_type(species)


static func talk_conversation(
	species: StringName = &"", desk_full: bool = false, has_bank: bool = true
) -> DialogueData:
	var imported: DialogueData = DialogueCatalog.conversation(
		StringName("msg_%d" % talk_msg_no(species, desk_full, has_bank))
	)
	if imported != null:
		return imported
	return DialogueCatalog.conversation(FALLBACK_GREETING_ID)


static func is_deposit_msg(msg_id: StringName) -> bool:
	var key := String(msg_id)
	return key == "msg_11744" or key == "msg_11745" or key == "deposit"


static func is_send_mail_msg(msg_id: StringName) -> bool:
	var key := String(msg_id)
	return key in ["msg_2229", "msg_2230", "mail_stub", "mail"]


static func is_save_mail_msg(msg_id: StringName) -> bool:
	var key := String(msg_id)
	return key in ["msg_7143", "msg_7144", "save_stub", "save"]


static func is_repay_msg(msg_id: StringName) -> bool:
	var key := String(msg_id)
	return key in ["msg_2259", "msg_2260", "repay"]


static func is_etm_connect_msg(msg_id: StringName) -> bool:
	var key := String(msg_id)
	return key == "msg_15855" or key == "msg_15858"


static func gx_to_world(grid: WorldGrid, gx: Vector3) -> Vector3:
	return MuseumDisplay.gx_to_world(grid, gx)


static func mail_pile_gx(index: int) -> Vector3:
	var i: int = clampi(index, 0, MAIL_PILE_X_GX.size() - 1)
	return Vector3(MAIL_PILE_X_GX[i], MAIL_PILE_Y_GX, MAIL_PILE_Z_GX)
