class_name ResettiVisit
extends RefCounted

## Who comes up out of the ground after a reset (`aRSD_first_set_init`, `ac_npc_majin*`).
## `majin_name[reset_count - 1]`; past eight the last three take turns
## (`reset = 6 + (reset - 9) % 3`). Each opens with his own message (`aMJN_set_force_talk_info`,
## `aMJN2/3/4_set_force_talk_info`); the fourth hangs about until he is spoken to
## (`aMJN2_THINK_WAIT` → `0x2360`). The fifth is his brother, Don.

const RESETTI := &"mol"
const DON := &"mob"

## [species, opening message, waits to be talked to, follow-up message].
const VISITS: Array = [
	[RESETTI, 0x3A38, false, -1],  ## SP_NPC_MAJIN_D07C
	[RESETTI, 0x3A42, false, -1],  ## SP_NPC_MAJIN_D07D
	[RESETTI, 0x1B3B, false, -1],  ## SP_NPC_MAJIN
	[RESETTI, 0x235D, true, 0x2360],  ## SP_NPC_MAJIN2
	[DON, 0x3A4C, false, -1],  ## SP_NPC_MAJIN_BROTHER
	[RESETTI, 0x23E6, false, -1],  ## SP_NPC_MAJIN3
	[RESETTI, 0x250F, false, -1],  ## SP_NPC_MAJIN4
	[RESETTI, 0x3B05, false, -1],  ## SP_NPC_MAJIN_D080
]


## `aRSD_first_set_init`: the count wraps 9, 10, 11 → 6, 7, 8 (and is stored that way).
static func normalized(reset_count: int) -> int:
	if reset_count >= 9:
		return 6 + (reset_count - 9) % 3
	return reset_count


static func visit(reset_count: int) -> Array:
	var n: int = clampi(normalized(reset_count), 1, VISITS.size())
	return VISITS[n - 1]
