extends EventNpc

## A resident out in Jack's costume on Halloween night (`ac_halloween_npc`,
## `SP_NPC_EV_HALLOWEEN_0..4`). Runs at a player in the same acre (`aHWN_approach`) and,
## within 70 GX, starts the trick-or-treat talk itself; afterwards just a Halloween line.

const RUN_SPEED := 3.0
const CALL_RANGE := 70.0 * FieldCatalog.GX_TO_METERS
const CHASE_REPATH := 0.5

var villager: VillagerData
var _met: bool = false
var _repath: float = 0.0


func assign(p_villager: VillagerData) -> void:
	villager = p_villager
	species = &"pkn"
	display_name = villager.display_name if villager != null else "Jack"
	sound_spec = DialogueVoice.sound_spec_for_looks(_looks() as VillagerPersonality.Looks)


func _looks() -> int:
	return int(villager.personality.looks) if villager != null and villager.personality != null else 0


func make_context() -> DialogueContext:
	var state: VillagerState = null
	if Game != null and villager != null and Game.villagers.has_id(villager.id):
		state = Game.villagers.get_or_create(villager.id)
	var ctx: DialogueContext = DialogueContext.from_game(villager, state)
	ctx.speaker_name = display_name
	if ctx.rng == null:
		ctx.rng = RandomNumberGenerator.new()
		ctx.rng.randomize()
	return ctx


func make_talk() -> BankTalk:
	var t := TrickOrTreatTalk.new(false, _looks(), Game.inventory if Game != null else null, rng())
	t.met = _met
	_met = true
	return t


func _same_acre() -> bool:
	var p: Node3D = player_node()
	var world: World = World.find(get_tree())
	if p == null or world == null:
		return false
	return EventManager.cell_to_block(world.grid.world_to_cell(p.global_position)) == \
		EventManager.cell_to_block(world.grid.world_to_cell(global_position))


func think(delta: float) -> void:
	if _met or not can_call_out():
		return
	if not _same_acre():
		return
	if player_distance() <= CALL_RANGE:
		stop_moving()
		begin_talk(player_node())
		return
	_repath -= delta
	if _repath <= 0.0:
		_repath = CHASE_REPATH
		move_to(player_node().global_position, RUN_SPEED, "npc_1_run1")
