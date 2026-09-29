class_name VillagerOutdoor
extends RefCounted

## Rules for what an outdoor villager does between wander steps (`aNPC_think_chk_interrupt_proc`,
## `ac_npc_think.c_inc`, and the acts it requests). Distances are GX turned into metres.
##
## - Rain: one villager at a time takes out their umbrella (`aNPC_ctrl_umbrella`, the NPC
##   control actor's `umbrella_open_actor` / `umbrella_open_timer`); it goes away when the
##   rain stops unless they're heading to bed. Someone who appears outdoors in the rain
##   already has it open (`aNPC_check_force_use_umbrella`).
## - Clap: a villager in a normal mood, within 3 units and facing the player (±67.5°), claps
##   while the player shows off a bug or fish (`aNPC_check_clap`).
## - Chase: while walking in a normal mood, a fish shadow within 140 GX (else, only if no
##   shadow exists at all, a bug within 100 GX) draws them over for up to a minute
##   (`aNPC_check_insect_and_gyoei`, `aNPC_act_chase_insect`).

const GX := FieldCatalog.GX_TO_METERS
## `3 * mFI_UNIT_BASE_SIZE_F`.
const CLAP_RANGE := 120.0 * GX
const CLAP_CONE := deg_to_rad(67.5)
const CHASE_FISH_RANGE := 140.0 * GX
const CHASE_INSECT_RANGE := 100.0 * GX
const CHASE_SECONDS := 60.0
## `aNPC_act_chase_insect_chg_step` thresholds.
const INSECT_NEAR := 80.0 * GX
const INSECT_WALK := 120.0 * GX
const FISH_NEAR := 100.0 * GX
const CHASE_TURN_CONE := deg_to_rad(22.5)
## `aNPC_part_tbl1x`: joints the sub-animation (`UMBRELLA1`) drives — RARM1, RARM2, HAND,
## HEAD_ROOT.
const SUB_ANIM_JOINTS: Array = [18, 19, 20, 21]
const UMBRELLA_NUM := 32

enum ChaseStep { WAIT, WALK, RUN, TURN }

## `umbrella_open_actor` / the window `umbrella_open_timer` opens (0.5–1 s, then one frame at 0).
static var _umbrella_holder: Object = null
static var _umbrella_ready_at: float = 0.0


static func reset() -> void:
	_umbrella_holder = null
	_umbrella_ready_at = 0.0


## `aNPC_ctrl_umbrella` rain branch: may `who` take their umbrella out now?
static func claim_umbrella(who: Object, now: float, rng: RandomNumberGenerator) -> bool:
	if now < _umbrella_ready_at:
		return false
	_umbrella_holder = who
	_umbrella_ready_at = now + _window(rng)
	return true


## `aNPC_reset_umb_open_flg` once the umbrella is open.
static func release_umbrella(who: Object, now: float, rng: RandomNumberGenerator) -> void:
	if _umbrella_holder == who:
		_umbrella_holder = null
		_umbrella_ready_at = now + _window(rng)


static func _window(rng: RandomNumberGenerator) -> float:
	## `FRAMES_PER_SECOND * 0.5 + RANDOM_F(FRAMES_PER_SECOND * 0.5)`.
	return 0.5 + rng.randf() * 0.5


## The umbrella a villager carries: an Able design (`ITM_MY_ORG_UMBRELLA`) isn't drawn yet, so
## that falls back to their own.
static func umbrella_visual(villager: VillagerData, _state: VillagerState) -> StringName:
	var idx: int = villager.default_umbrella if villager != null else -1
	if idx < 0 or idx >= UMBRELLA_NUM:
		return &""
	return StringName("tol_umb_%02d" % (idx + 1))


## `aNPC_check_clap`.
static func wants_clap(npc_pos: Vector3, npc_yaw: float, player_pos: Vector3, player_catching: bool, mood_normal: bool) -> bool:
	if not player_catching or not mood_normal:
		return false
	var to: Vector3 = player_pos - npc_pos
	to.y = 0.0
	if to.length() >= CLAP_RANGE:
		return false
	return absf(angle_difference(npc_yaw, atan2(to.x, to.z))) < CLAP_CONE


## `aNPC_check_insect_and_gyoei`: {"target": Object, "fish": bool} or {}.
## `fish_positions` / `bug_positions` are [Object, Vector3] pairs.
static func chase_target(npc_pos: Vector3, fish: Array, bugs: Array) -> Dictionary:
	var near: Array = _nearest(npc_pos, fish)
	if not near.is_empty():
		if near[1] < CHASE_FISH_RANGE:
			return {"target": near[0], "fish": true}
		return {}
	near = _nearest(npc_pos, bugs)
	if not near.is_empty() and near[1] < CHASE_INSECT_RANGE:
		return {"target": near[0], "fish": false}
	return {}


static func _nearest(from: Vector3, pairs: Array) -> Array:
	var best: Array = []
	for pair: Variant in pairs:
		var p: Array = pair
		var d: Vector3 = (p[1] as Vector3) - from
		d.y = 0.0
		var dist: float = d.length()
		if best.is_empty() or dist < float(best[1]):
			best = [p[0], dist]
	return best


## `aNPC_act_chase_insect_chg_step`.
static func chase_step(npc_pos: Vector3, npc_yaw: float, target_pos: Vector3, fish: bool) -> ChaseStep:
	var to: Vector3 = target_pos - npc_pos
	to.y = 0.0
	var dist: float = to.length()
	var off: float = absf(angle_difference(npc_yaw, atan2(to.x, to.z)))
	if fish:
		if dist < FISH_NEAR:
			return ChaseStep.TURN if off > CHASE_TURN_CONE else ChaseStep.WAIT
		return ChaseStep.WALK
	if dist < INSECT_NEAR:
		return ChaseStep.TURN if off > CHASE_TURN_CONE else ChaseStep.WAIT
	if dist < INSECT_WALK:
		return ChaseStep.WALK
	return ChaseStep.RUN
