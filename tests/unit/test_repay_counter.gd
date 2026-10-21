class_name TestRepayCounter
extends GdUnitTestSuite

## The post office's loan screen (`m_repay_ovl.c`).


func _inv(wallet: int, loan: int, bags: Array = []) -> Inventory:
	var inv := Inventory.new()
	inv.set_wallet(wallet)
	inv.set_loan(loan)
	for i: int in bags.size():
		var bag: Array = bags[i]
		inv.slot_at(i).set_stack(bag[0], 1, bag[1] if bag.size() > 1 else InventoryItem.Condition.NORMAL)
	return inv


func test_the_most_is_the_loan_or_the_money_whichever_is_less() -> void:
	var c := RepayCounter.new()
	c.open_from(_inv(5000, 148000, [[&"money_10000"], [&"money_1000", InventoryItem.Condition.PRESENT]]))
	## A wrapped bag isn't money.
	assert_int(c.max_money).is_equal(15000)
	assert_int(c.max_repay).is_equal(15000)
	c.open_from(_inv(90000, 17400))
	assert_int(c.max_repay).is_equal(17400)


func test_up_clamps_and_down_floors() -> void:
	var c := RepayCounter.new()
	c.open_from(_inv(15000, 148000))
	assert_int(c.cursor).is_equal(0)
	## 100,000 at once is more than there is: clamped to 15,000.
	assert_bool(c.up()).is_true()
	assert_int(c.amount).is_equal(15000)
	assert_bool(c.up()).is_false()
	assert_int(c.money).is_equal(0)
	assert_int(c.loan).is_equal(133000)
	c.cursor = 2
	assert_bool(c.down()).is_true()
	assert_int(c.amount).is_equal(14000)
	c.cursor = 0
	assert_bool(c.down()).is_true()
	assert_int(c.amount).is_equal(0)
	assert_bool(c.down()).is_false()


func test_cursor_stops_at_the_ends_and_steps_back_from_ok() -> void:
	var c := RepayCounter.new()
	c.open_from(_inv(100, 100))
	assert_bool(c.left()).is_false()
	for _i: int in 6:
		assert_bool(c.right()).is_true()
	assert_int(c.cursor).is_equal(RepayCounter.CURSOR_OK)
	assert_bool(c.right()).is_false()
	assert_bool(c.left()).is_true()
	assert_int(c.cursor).is_equal(RepayCounter.CURSOR_MAX)


func test_the_wallet_pays_alone_when_it_can() -> void:
	var inv := _inv(20000, 148000, [[&"money_100"]])
	var c := RepayCounter.new()
	c.open_from(inv)
	c.cursor = 1
	c.up()
	assert_bool(c.commit(inv)).is_true()
	assert_int(inv.wallet).is_equal(10000)
	assert_int(inv.loan).is_equal(138000)
	assert_int(inv.count_of(&"money_100")).is_equal(1)


func test_bags_go_smallest_first_and_the_change_comes_back() -> void:
	## Wallet 1,000 + 30,000 / 100 / 10,000 bags; paying 5,000 takes the 100 then the
	## 10,000 (smallest kinds first) and leaves the 30,000; change 6,100 to the wallet.
	var inv := _inv(1000, 148000, [[&"money_30000"], [&"money_100"], [&"money_10000"]])
	assert_int(RepayCounter.pay(inv, 5000)).is_equal(6100)
	assert_int(inv.count_of(&"money_100")).is_equal(0)
	assert_int(inv.count_of(&"money_10000")).is_equal(0)
	assert_int(inv.count_of(&"money_30000")).is_equal(1)


func test_paying_it_all_clears_the_loan() -> void:
	var inv := _inv(17400, 17400)
	var c := RepayCounter.new()
	c.open_from(inv)
	c.up()
	c.commit(inv)
	assert_int(inv.loan).is_equal(0)
	assert_int(inv.wallet).is_equal(0)
