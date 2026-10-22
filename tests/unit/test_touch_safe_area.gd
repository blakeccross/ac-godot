extends GdUnitTestSuite


func test_resize_after_the_root_is_freed_is_harmless() -> void:
	var root := Control.new()
	add_child(root)
	TouchSafeArea.fit(root)
	var vp: Viewport = root.get_viewport()
	root.free()
	vp.size_changed.emit()
	assert_bool(true).is_true()
