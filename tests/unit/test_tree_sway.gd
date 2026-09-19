extends GdUnitTestSuite

## EffectBG shake keyframes (`cKF_ba_r_ef_*_shakeS/L`) and the sapling wobble.


func test_family_and_size_pick_the_decomp_curve() -> void:
	var med_s: Array[Vector3] = TreeSway.keys(PlantData.Family.HARDWOOD, TreeUse.Size.S1, false)
	var large_s: Array[Vector3] = TreeSway.keys(PlantData.Family.HARDWOOD, TreeUse.Size.S2, false)
	var full_s: Array[Vector3] = TreeSway.keys(PlantData.Family.HARDWOOD, TreeUse.Size.FULL, false)
	assert_int(med_s.size()).is_equal(6)
	assert_array(med_s).is_equal(large_s)
	assert_int(full_s.size()).is_equal(5)
	## Cedar's small shake is wider (4° vs 3°) at every size.
	var cedar_med: Array[Vector3] = TreeSway.keys(PlantData.Family.CEDAR, TreeUse.Size.S1, false)
	assert_float(cedar_med[1].y).is_equal(4.0)
	assert_float(full_s[1].y).is_equal(3.0)
	## Palm 3/4 follow the hardwood curve; palm 5 is the full one.
	assert_array(TreeSway.keys(PlantData.Family.PALM, TreeUse.Size.S2, true)).is_equal(
		TreeSway.keys(PlantData.Family.HARDWOOD, TreeUse.Size.S2, true)
	)
	assert_int(TreeSway.keys(PlantData.Family.HARDWOOD, TreeUse.Size.S1, true).size()).is_equal(21)
	assert_int(TreeSway.keys(PlantData.Family.CEDAR, TreeUse.Size.S1, true).size()).is_equal(11)
	assert_int(TreeSway.keys(PlantData.Family.PALM, TreeUse.Size.FULL, true).size()).is_equal(11)


func test_sample_hits_keys_and_holds_outside_them() -> void:
	var curve: Array[Vector3] = TreeSway.keys(PlantData.Family.HARDWOOD, TreeUse.Size.FULL, true)
	assert_float(TreeSway.sample(curve, 0.0)).is_equal(0.0)
	assert_float(TreeSway.sample(curve, 13.0)).is_equal_approx(6.0, 0.001)
	assert_float(TreeSway.sample(curve, 17.0)).is_equal_approx(-6.0, 0.001)
	assert_float(TreeSway.sample(curve, 99.0)).is_equal(0.0)
	## Flat tangents ease between keys, so the midpoint is the mean.
	assert_float(TreeSway.sample(curve, 15.0)).is_equal_approx(0.0, 0.001)


func test_hermite_uses_the_key_tangents() -> void:
	var curve: Array[Vector3] = TreeSway.keys(PlantData.Family.HARDWOOD, TreeUse.Size.S1, false)
	## Frame 1→3 leaves with a 61.6°/s tangent, so it runs ahead of the straight ramp.
	var mid: float = TreeSway.sample(curve, 2.0)
	assert_float(mid).is_greater(1.5)
	assert_float(TreeSway.sample(curve, 3.0)).is_equal_approx(3.0, 0.001)


func test_sapling_wobble_decays_over_its_life() -> void:
	assert_float(TreeSway.young_roll(0, 1.0)).is_equal(0.0)
	var early: float = absf(TreeSway.young_roll(40, PI / 2.0))
	var late: float = absf(TreeSway.young_roll(14, PI / 2.0))
	assert_float(early).is_equal_approx(12.0, 0.001)
	assert_float(late).is_equal_approx(12.0 * 14.0 / 40.0, 0.001)
