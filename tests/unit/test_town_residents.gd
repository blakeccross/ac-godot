class_name TestTownResidents
extends GdUnitTestSuite

## `TownResidents` against `m_npc.c` (`mNpc_Grow`, `mNpc_ForceRemove`, `mNpc_SetNpcHome`).

const DAY := 400
const MINUTE := DAY * 1440 + 12 * 60


func before_test() -> void:
	VillagerCatalog.reload()


## One starter per looks, like `mNpc_DecideLivingNpcMax`.
func _starters() -> Array[StringName]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var out: Array[StringName] = []
	for v: VillagerData in VillagerCatalog.pick_starters(rng, 6):
		out.append(v.id)
	return out


func _town(ids: Array[StringName]) -> TownResidents:
	var t := TownResidents.new()
	var houses: Array[Dictionary] = []
	var i: int = 0
	for id: StringName in ids:
		houses.append({"id": id, "home": Vector2i(20 + i * 8, 40)})
		i += 1
	t.adopt_from_houses(houses)
	return t


func _ctx(met_all: bool = true, rank: int = 6, seed_value: int = 1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return {
		"rng": rng,
		"day": DAY,
		"minute": MINUTE,
		"met": func(_id: StringName) -> bool: return met_all,
		"field_rank": rank,
		"reserves": [Vector2i(100, 40), Vector2i(110, 40), Vector2i(120, 40)] as Array[Vector2i],
	}


func _looks(id: StringName) -> int:
	return int(VillagerCatalog.get_villager(id).personality.looks)


func test_adopt_marks_starters_as_appeared() -> void:
	var t: TownResidents = _town(_starters())
	assert_int(t.animal_num()).is_equal(6)
	assert_int(t.now_npc_max).is_equal(6)
	for id: StringName in t.resident_ids():
		assert_bool(t.appeared.has(VillagerCatalog.get_villager(id).npc_index)).is_true()


func test_first_grow_only_stamps_the_clock() -> void:
	var t: TownResidents = _town(_starters())
	assert_that(t.grow(_ctx())).is_equal(&"")
	assert_int(t.last_grow_minute).is_equal(MINUTE)


func test_grow_needs_a_day_and_everyone_met() -> void:
	var t: TownResidents = _town(_starters())
	t.last_grow_minute = MINUTE - 1439
	assert_that(t.grow(_ctx())).is_equal(&"")
	t.last_grow_minute = MINUTE - 1440
	assert_that(t.grow(_ctx(false))).is_equal(&"")
	t.last_grow_minute = MINUTE - 1440
	var arrived: StringName = t.grow(_ctx())
	assert_that(arrived).is_not_equal(&"")
	assert_int(t.now_npc_max).is_equal(7)
	assert_int(t.force_remove_day).is_equal(DAY)
	assert_bool(t.moved_in(arrived)).is_true()
	assert_int(t.slot_of(arrived)).is_equal(6)


func test_grow_tie_leans_to_the_wrong_sex_like_the_decomp() -> void:
	## Six looks one each: all tie. `mNpc_GetMinSex` sees 3 male / 3 female → FEMALE,
	## so the newcomer is normal, peppy or snooty.
	for seed_value: int in 12:
		var t: TownResidents = _town(_starters())
		t.last_grow_minute = MINUTE - 1440
		var arrived: StringName = t.grow(_ctx(true, 6, seed_value))
		var v: VillagerData = VillagerCatalog.get_villager(arrived)
		assert_int(TownResidents.looks_sex(_looks(arrived))).is_equal(TownResidents.SEX_FEMALE)
		assert_bool(v.islander).is_false()


func test_grow_picks_the_rarest_looks() -> void:
	var ids: Array[StringName] = _starters()
	var t: TownResidents = _town(ids)
	## Add a second of every looks except jock, so jock is the unique minimum.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var extra: int = 6
	for v: VillagerData in VillagerCatalog.all_villagers():
		if extra >= 11:
			break
		var l: int = int(v.personality.looks)
		if v.islander or t.has_resident(v.id) or l == VillagerPersonality.Looks.JOCK:
			continue
		if t.same_looks_num(l) >= 2:
			continue
		t.slots[extra] = {"id": v.id, "home": Vector2i(extra * 4, 60), "moved_in": false}
		extra += 1
	t.now_npc_max = t.animal_num()
	t.last_grow_minute = MINUTE - 1440
	var arrived: StringName = t.grow(_ctx())
	assert_int(_looks(arrived)).is_equal(VillagerPersonality.Looks.JOCK)


func test_grow_stops_at_fifteen() -> void:
	var t: TownResidents = _town(_starters())
	t.now_npc_max = TownResidents.ANIMAL_NUM_MAX
	t.last_grow_minute = MINUTE - 5000
	assert_that(t.grow(_ctx())).is_equal(&"")


func _full_town() -> TownResidents:
	var t: TownResidents = _town(_starters())
	var i: int = 6
	for v: VillagerData in VillagerCatalog.all_villagers():
		if i >= TownResidents.ANIMAL_NUM_MAX:
			break
		if v.islander or t.has_resident(v.id):
			continue
		t.slots[i] = {"id": v.id, "home": Vector2i(i * 4, 80), "moved_in": false}
		i += 1
	t.now_npc_max = TownResidents.ANIMAL_NUM_MAX
	return t


func test_force_remove_waits_ten_days_then_takes_the_one_never_met() -> void:
	var t: TownResidents = _full_town()
	var stranger: StringName = t.slots[9]["id"]
	var ctx: Dictionary = _ctx()
	ctx["met"] = func(id: StringName) -> bool: return id != stranger
	var left: Array[StringName] = []
	ctx["on_goodbye"] = func(id: StringName, _looks: int) -> void: left.append(id)
	t.force_remove_day = DAY - 9
	assert_that(t.force_remove(ctx)).is_equal(&"")
	t.force_remove_day = DAY - 10
	assert_that(t.force_remove(ctx)).is_equal(stranger)
	assert_bool(t.is_free(9)).is_true()
	assert_int(t.now_npc_max).is_equal(14)
	assert_int(t.force_remove_day).is_equal(DAY)
	assert_int(left.size()).is_equal(1)


func test_force_remove_needs_a_full_town_and_skips_the_moving_candidate() -> void:
	var t: TownResidents = _town(_starters())
	t.force_remove_day = DAY - 30
	assert_that(t.force_remove(_ctx())).is_equal(&"")
	var full: TownResidents = _full_town()
	full.force_remove_day = DAY - 30
	var only_stranger: StringName = full.slots[3]["id"]
	var ctx: Dictionary = _ctx()
	ctx["met"] = func(id: StringName) -> bool: return id != only_stranger
	full.remove_idx = 3
	assert_that(full.force_remove(ctx)).is_not_equal(only_stranger)


func test_new_arrival_takes_a_free_plot() -> void:
	var t: TownResidents = _town(_starters())
	t.slots[6] = {"id": &"stu", "home": TownResidents.NO_HOME, "moved_in": true}
	var ctx: Dictionary = _ctx()
	ctx["reserves"] = [Vector2i(20, 40), Vector2i(21, 41), Vector2i(100, 40)] as Array[Vector2i]
	var built: Array[int] = t.assign_homes(ctx)
	assert_array(built).contains_exactly([6])
	## (20, 40) is slot 0's plot and (21, 41) sits inside its 3×3.
	assert_that(t.home_of(6)).is_equal(Vector2i(100, 40))
	assert_bool(t.used_plots.has(Vector2i(100, 40))).is_true()


func test_moving_candidate_prefers_someone_met() -> void:
	var t: TownResidents = _town(_starters())
	var friend: StringName = t.slots[4]["id"]
	var ctx: Dictionary = _ctx()
	ctx["met"] = func(id: StringName) -> bool: return id == friend
	t.pick_moving_candidate(ctx, -1)
	assert_int(t.remove_idx).is_equal(4)
	t.cancel_moving(ctx)
	assert_int(t.remove_idx).is_not_equal(4)


func test_make_rand_table_is_a_permutation() -> void:
	var table: PackedInt32Array = TownResidents.make_rand_table(_ctx(), 9, 30)
	var seen: Dictionary = {}
	for n: int in table:
		seen[n] = true
	assert_int(seen.size()).is_equal(9)


func test_save_round_trip() -> void:
	var t: TownResidents = _full_town()
	t.set_relation(2, 5, 200)
	t.remove_idx = 4
	t.last_grow_minute = 1234
	t.force_remove_day = 77
	var back := TownResidents.new()
	back.apply_snapshot(JSON.parse_string(JSON.stringify(t.to_save())))
	assert_array(back.resident_ids()).is_equal(t.resident_ids())
	assert_that(back.home_of(7)).is_equal(t.home_of(7))
	assert_int(back.relation(2, 5)).is_equal(200)
	assert_int(back.remove_idx).is_equal(4)
	assert_int(back.last_grow_minute).is_equal(1234)
	assert_int(back.force_remove_day).is_equal(77)
	assert_int(back.appeared.size()).is_equal(t.appeared.size())


func test_mail_bank_goodbye_letter() -> void:
	if not MailBank.has_bank():
		return
	var text: Dictionary = MailBank.letter(0x20E + 1, "Ann", {1: "Stu"})
	assert_str(str(text["header"])).is_equal("Dear Ann,")
	assert_str(str(text["footer"])).is_equal("Farewell! Stu!")
	assert_str(str(text["body"])).contains("leave the village")


func test_world_rebuilds_houses_from_the_roster() -> void:
	Game.reset_session()
	Game.world_mode = WorldData.Mode.GENERATED
	Game.world_seed = 12345
	var first: WorldData = Game.resolve_world_data()
	var roster: TownResidents = Game.residents
	assert_int(roster.animal_num()).is_equal(6)
	## A newcomer on a free plot, and slot 2 gone.
	var free_plot := TownResidents.NO_HOME
	for r: Vector2i in first.reserve_cells:
		if not TownResidents._under_house(r, roster.used_plots):
			free_plot = r
			break
	assert_that(free_plot).is_not_equal(TownResidents.NO_HOME)
	var gone: StringName = roster.slots[2]["id"]
	var gone_plot: Vector2i = roster.home_of(2)
	roster.slots[2] = {}
	roster.slots[6] = {"id": &"stu", "home": free_plot, "moved_in": true}
	roster.used_plots[free_plot] = true
	var data: WorldData = Game.resolve_world_data()
	var stu_house: BuildingPlacement = null
	var gone_house: bool = false
	for b: BuildingPlacement in data.buildings:
		if b.resident_id == &"stu":
			stu_house = b
		if b.resident_id == gone:
			gone_house = true
	assert_object(stu_house).is_not_null()
	assert_that(stu_house.id).is_equal(&"npc_house_6")
	assert_that(stu_house.cell).is_equal(free_plot - Vector2i(1, 1))
	assert_bool(gone_house).is_false()
	var stu_out: bool = false
	for o: ObjectPlacement in data.objects:
		if o.kind == &"villager" and o.id == &"stu":
			stu_out = true
		## The emptied plot stays clear of template objects.
		assert_bool(o.occupy_grid and absi(o.cell.x - gone_plot.x) <= 1 and absi(o.cell.y - gone_plot.y) <= 1).is_false()
	assert_bool(stu_out).is_true()
	Game.reset_session()
