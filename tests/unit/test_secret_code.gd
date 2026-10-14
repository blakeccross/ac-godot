extends GdUnitTestSuite

## The GameCube's 28-character secret codes (`m_mail_password_check`).


func test_tables_are_whole() -> void:
	assert_int(SecretCode.PRIMES.size()).is_equal(256)
	assert_int(SecretCode.SUBST.size()).is_equal(256)
	assert_int(SecretCode.ALPHABET.length()).is_equal(64)
	var seen := {}
	for v: int in SecretCode.SUBST:
		seen[v] = true
	assert_int(seen.size()).is_equal(256)


func test_codes_round_trip() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in 40:
		var player := SecretCode.name_bytes("Ann%d" % i)
		var town := SecretCode.name_bytes("Pine")
		var item: int = rng.randi_range(0x1000, 0x3FFF)
		var code: String = SecretCode.make(SecretCode.Type.USER, 1, player, town, item)
		assert_int(code.length()).is_equal(SecretCode.STR_LEN)
		var f: Dictionary = SecretCode.decode(code)
		assert_int(int(f["type"])).is_equal(SecretCode.Type.USER)
		assert_int(int(f["item"])).is_equal(item)
		assert_bool(SecretCode.tampered(f)).is_false()
		assert_bool(SecretCode.for_player(f, "Ann%d" % i, "Pine")).is_true()
		assert_bool(SecretCode.for_player(f, "Bob", "Pine")).is_false()


func test_a_changed_letter_is_caught() -> void:
	var code: String = SecretCode.make(SecretCode.Type.USER, 1, SecretCode.name_bytes("Ann"), SecretCode.name_bytes("Pine"), 0x1234)
	var bad: String = code.substr(0, 5) + ("b" if code[5] != "b" else "K") + code.substr(6)
	var f: Dictionary = SecretCode.decode(bad)
	assert_bool(f.is_empty() or SecretCode.tampered(f) or not SecretCode.for_player(f, "Ann", "Pine") or int(f["item"]) != 0x1234).is_true()
	assert_bool(SecretCode.decode("too short").is_empty()).is_true()


func test_item_numbers_map_both_ways() -> void:
	ItemCatalog.reload()
	for id: StringName in [&"apple", &"net", &"red_pinwheel", &"leaf_fan", &"golden_axe"]:
		var n: int = CodeItems.number_of(id)
		assert_int(n).is_greater(0)
		assert_str(String(CodeItems.id_of(n))).is_equal(String(id))
	assert_int(CodeItems.number_of(&"apple")).is_equal(0x2800)
	assert_int(CodeItems.number_of(&"net")).is_equal(0x2200)
	assert_int(CodeItems.ftr_no(0x401)).is_equal(0x3004)
	if FtrCatalog.available() and FtrCatalog.count() > 10:
		var ftr: StringName = FtrCatalog.item_id(10)
		if ItemCatalog.get_item(ftr) != null:
			assert_str(String(CodeItems.id_of(CodeItems.number_of(ftr)))).is_equal(String(ftr))
	assert_str(String(CodeItems.id_of(0x2206 + 40))).is_equal("")


## `aNSC_pc_check_password`: a code Nook made for you is yours; someone else's isn't.
func test_nook_redeems_codes_for_their_owner() -> void:
	ItemCatalog.reload()
	var rng := RandomNumberGenerator.new()
	var code: String = NookShopTalk.make_code("Ann", "Pine", &"red_pinwheel")
	var mine: Dictionary = NookShopTalk.redeem(code, "Ann", "Pine", rng)
	assert_str(str(mine["result"])).is_equal("good")
	assert_str(String(mine["item"])).is_equal("red_pinwheel")
	assert_str(str(NookShopTalk.redeem(code, "Bob", "Pine", rng)["result"])).is_equal("bad")
	assert_str(str(NookShopTalk.redeem("bbbbbbbbbbbbbbbbbbbbbbbbbbbb", "Ann", "Pine", rng)["result"])).is_equal("wrong")


func test_say_code_needs_room_and_your_own_town() -> void:
	Game.reset_session()
	var ctx := DialogueContext.new()
	assert_str(String(NookShopTalk.apply_event({"op": "nook_shop", "action": "code_say"}, ctx)["open"])).is_equal("code_say")
	Game.nook_code_gifts = NookShopTalk.CODE_GIFTS_MAX
	NookShopTalk.apply_event({"op": "nook_shop", "action": "code_say"}, ctx)
	assert_str(str(ctx.get_var(NookShopTalk.VAR_CODE, ""))).is_equal("out")
	Game.nook_code_gifts = 0
	Game.foreigner = true
	NookShopTalk.apply_event({"op": "nook_shop", "action": "code_say"}, ctx)
	assert_str(str(ctx.get_var(NookShopTalk.VAR_CODE, ""))).is_equal("foreign")
	Game.foreigner = false
	Game.inventory.clear()
	NookShopTalk.apply_event({"op": "nook_shop", "action": "code_hear"}, ctx)
	assert_str(str(ctx.get_var(NookShopTalk.VAR_CODE, ""))).is_equal("none")
	Game.inventory.add(ItemCatalog.get_item(&"apple"), 1)
	NookShopTalk.apply_event({"op": "nook_shop", "action": "code_hear"}, ctx)
	assert_str(str(ctx.get_var(NookShopTalk.VAR_CODE, ""))).is_equal("ask")
	Game.reset_session()
