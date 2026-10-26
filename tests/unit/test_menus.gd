extends GdUnitTestSuite

## `Menus`: whether a menu is up, by group, across overlay classes.


class _Fake extends Node:
	var open: bool = false

	func is_open() -> bool:
		return open


func test_a_group_is_open_when_any_member_says_so() -> void:
	var group := &"test_menus_ui"
	var a: _Fake = auto_free(_Fake.new())
	var b: _Fake = auto_free(_Fake.new())
	add_child(a)
	add_child(b)
	a.add_to_group(group)
	b.add_to_group(group)
	assert_bool(Menus.is_open(get_tree(), group)).is_false()
	b.open = true
	assert_bool(Menus.is_open(get_tree(), group)).is_true()
	assert_bool(Menus.any_open(get_tree(), [&"test_menus_other", group] as Array[StringName])).is_true()
	assert_bool(Menus.any_open(get_tree(), [&"test_menus_other"] as Array[StringName])).is_false()
	## A node without `is_open` never counts.
	var plain: Node = auto_free(Node.new())
	add_child(plain)
	plain.add_to_group(&"test_menus_other")
	assert_bool(Menus.is_open(get_tree(), &"test_menus_other")).is_false()
