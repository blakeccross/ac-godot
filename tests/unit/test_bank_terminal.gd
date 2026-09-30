extends GdUnitTestSuite

## `m_bank_ovl.c` / `mMl_send_postoffice_mail`.


func _inv(wallet: int, savings: int) -> Inventory:
	var inv := Inventory.new()
	inv.set_wallet(wallet)
	inv.set_savings(savings)
	return inv


func test_digits_are_powers_of_ten_from_the_left() -> void:
	assert_int(BankTerminal.digit_value(0)).is_equal(100000)
	assert_int(BankTerminal.digit_value(5)).is_equal(1)


func test_deposit_moves_cash_to_the_balance_and_back_no_further() -> void:
	var inv := _inv(5000, 0)
	var t := BankTerminal.new()
	t.open_from(inv)
	t.cursor = 2  ## 1,000s
	assert_bool(t.deposit()).is_true()
	assert_int(t.bank_bell).is_equal(1000)
	assert_int(t.now_bell).is_equal(4000)
	assert_int(t.bell).is_equal(1000)
	## 100,000s: only what cash holds.
	t.cursor = 0
	assert_bool(t.deposit()).is_true()
	assert_int(t.now_bell).is_equal(0)
	assert_bool(t.deposit()).is_false()
	## Withdrawing stops at the starting cash on the way back.
	assert_bool(t.withdraw()).is_true()
	assert_int(t.now_bell).is_equal(5000)
	assert_int(t.bell).is_equal(0)


func test_withdrawal_over_the_wallet_cap_pays_in_bags() -> void:
	var inv := _inv(90000, 200000)
	var t := BankTerminal.new()
	t.open_from(inv)
	t.cursor = 1  ## 10,000s
	for _i: int in 4:
		t.withdraw()
	assert_int(t.now_bell).is_equal(130000)
	t.commit(inv)
	assert_int(inv.savings).is_equal(160000)
	## 100,000 is still over the wallet's 99,999, so a second bag goes out.
	assert_int(inv.count_of(&"money_30000")).is_equal(2)
	assert_int(inv.wallet).is_equal(70000)


func test_deposit_spends_bags_before_the_wallet() -> void:
	var inv := _inv(500, 0)
	inv.slot_at(0).set_stack(&"money_1000", 1)
	var t := BankTerminal.new()
	t.open_from(inv)
	assert_int(t.now_bell).is_equal(1500)
	t.cursor = 3  ## 100s
	for _i: int in 10:
		t.deposit()
	t.commit(inv)
	assert_int(inv.count_of(&"money_1000")).is_equal(0)
	assert_int(inv.wallet).is_equal(500)
	assert_int(inv.savings).is_equal(1000)


func test_gifts_go_out_one_milestone_at_a_time() -> void:
	assert_bool(BankTerminal.due_gift(999999, 0).is_empty()).is_true()
	var g: Dictionary = BankTerminal.due_gift(20000000, 0)
	assert_int(int(g["mail_no"])).is_equal(0x246)
	g = BankTerminal.due_gift(20000000, 1)
	assert_str(String(g["present"])).is_equal("ftr_1003")
	assert_bool(BankTerminal.due_gift(20000000, 3).is_empty()).is_true()
