class_name VillagerFortune
extends RefCounted

## How villagers treat the player on the day of a Katrina fortune (`aNPC_set_over_friendship`
## → `aNPC_chk_friendship_lv`). The fortune shifts every villager's friendship by ±256
## (`over_friendship`), past anything friendship reaches on its own: on an unpopular day
## everyone in the player's acre keeps away (`aNPC_hate_player`: run within 3 units, walk
## within 4); on a popular day those of the other sex come looking (`aNPC_love_player`: run
## from beyond 3 units, walk from beyond 1.5) and, close enough, start talking
## (`aNPC_force_talk_request`: 0x075F + looks × 3, then 300 frames before the next call).

enum Step { NONE, AVOID_WALK, AVOID_RUN, SEEK_RUN, SEEK_WALK, SEEK_WAIT }

const UNIT_GX := 40.0
const AVOID_RUN_GX := 3.0 * UNIT_GX
const AVOID_WALK_GX := 4.0 * UNIT_GX
const SEEK_RUN_GX := 3.0 * UNIT_GX
const SEEK_WALK_GX := 1.5 * UNIT_GX
## `aNPC_force_talk_request`: within 80 GX across and 60 up.
const CALL_GX := 80.0
const CALL_HEIGHT_GX := 60.0
const CALL_MSG := 0x075F
## `aNPC_setup_talk_end`: 300 frames before calling out again.
const CALL_COOLDOWN_SEC := 300.0 / 60.0
## How far an avoiding villager heads off at a time.
const AVOID_STEP_GX := 2.0 * UNIT_GX


## `mNpc_GetLooks2Sex`: girl, ko-girl and naniwa lady are female; boy, sport man and grim man
## male.
static func is_female(looks: int) -> bool:
	return looks == VillagerPersonality.Looks.NORMAL or looks == VillagerPersonality.Looks.PEPPY \
		or looks == VillagerPersonality.Looks.SNOOTY


static func player_is_female(gender: StringName) -> bool:
	return gender == &"female" or gender == &"girl"


## What a villager does about the player this tick. `same_block`: the player is in the
## villager's acre; `distance_gx` across the ground.
static func step(destiny: int, looks: int, player_gender: StringName, same_block: bool, distance_gx: float) -> int:
	if not same_block:
		return Step.NONE
	match destiny:
		Game.Destiny.UNPOPULAR:
			if distance_gx < AVOID_RUN_GX:
				return Step.AVOID_RUN
			if distance_gx < AVOID_WALK_GX:
				return Step.AVOID_WALK
		Game.Destiny.POPULAR:
			if is_female(looks) == player_is_female(player_gender):
				return Step.NONE
			if distance_gx > SEEK_RUN_GX:
				return Step.SEEK_RUN
			if distance_gx > SEEK_WALK_GX:
				return Step.SEEK_WALK
			return Step.SEEK_WAIT
	return Step.NONE


## Close enough to call the player over.
static func can_call(distance_gx: float, height_gx: float) -> bool:
	return distance_gx < CALL_GX and absf(height_gx) < CALL_HEIGHT_GX


static func call_msg(looks: int, rng: RandomNumberGenerator) -> int:
	return CALL_MSG + looks * 3 + rng.randi_range(0, 2)


## Where an avoiding villager heads: straight away from the player.
static func away_from(npc: Vector3, player: Vector3) -> Vector3:
	var away := Vector3(npc.x - player.x, 0.0, npc.z - player.z)
	if away.length_squared() < 0.0001:
		away = Vector3(0.0, 0.0, 1.0)
	return npc + away.normalized() * AVOID_STEP_GX * FieldCatalog.GX_TO_METERS
