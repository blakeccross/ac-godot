class_name BugAnt
extends BugProgram

## `ac_ant`: ants swarming over a candy or a spoiled turnip left on the ground. The swarm
## stays on its unit, a patch of ants crawling in place (`act_antT_model`, two scrolling
## copies of the ant texture), and can be netted like any insect (`aANT_wait`: a 24 GX row in
## the net's table); netted, it becomes the ant you catch (`aANT_caught` →
## `make_insect_proc`). Once the food is gone it fades out (`aANT_disappear`: alpha −15 a
## tick). A released ant is an ordinary crawler (`BugDango`).

const TYPE := 38

enum { WAIT, DISAPPEAR }

## `ITM_FOOD_CANDY` / `ITM_KABU_SPOILED`.
const BAIT: Array[StringName] = [&"candy", &"spoiled_turnips"]
## `aANT_actor_ct`: the patch is tipped 45°.
const TILT := PI * 0.25
const FADE_STEP := 15


func actor_init(a: BugActor, _released: bool) -> void:
	a.item = TYPE
	a.drawn = true
	a.rot.x = TILT
	a.move_proc = BugProgram.freeze_move
	## The swarm keeps to its food: no life timer, no fade timer.
	a.life_time = 0
	a.alpha_time = 0
	setup_action(a, WAIT)


func setup_action(a: BugActor, action: int) -> void:
	a.action = action
	if action == DISAPPEAR:
		a.rot.x = 0.0
		a.f_no_catch = true


func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	match a.action:
		WAIT:
			if not on_bait(a, sense):
				setup_action(a, DISAPPEAR)
		DISAPPEAR:
			a.alpha0 -= FADE_STEP
			if a.alpha0 <= 0:
				a.alpha0 = 0
				a.finished = true


## The food is still on the swarm's unit.
static func on_bait(a: BugActor, sense: BugActor.Sense) -> bool:
	if sense == null or sense.grid == null:
		return true
	return FieldItems.item_at(sense.grid.world_to_cell(a.position)) in BAIT


func pose_index(_a: BugActor) -> int:
	return 0
