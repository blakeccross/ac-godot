class_name TestFootprintMarks
extends GdUnitTestSuite

## `ef_footprint` gate, fade curve, and slope fit.


func before_test() -> void:
	FieldCollision.clear_caches()


func after_test() -> void:
	FieldCollision.clear_caches()


func test_sand_and_wave_mark_in_every_season() -> void:
	for season: Clock.Season in [
		Clock.Season.SPRING, Clock.Season.SUMMER, Clock.Season.AUTUMN, Clock.Season.WINTER
	]:
		assert_bool(FootprintMarks.marks_attr(FieldCatalog.SAND_ATTR, season)).is_true()
		assert_bool(FootprintMarks.marks_attr(25, season)).is_true()


func test_grass_marks_only_in_winter() -> void:
	assert_bool(FootprintMarks.marks_attr(0, Clock.Season.WINTER)).is_true()
	assert_bool(FootprintMarks.marks_attr(3, Clock.Season.WINTER)).is_true()
	assert_bool(FootprintMarks.marks_attr(0, Clock.Season.SUMMER)).is_false()


func test_stone_and_water_never_mark() -> void:
	## Attr 7 is stone, 12 is water: `eFootPrint_ct` sets `timer = 0` for both.
	assert_bool(FootprintMarks.marks_attr(7, Clock.Season.WINTER)).is_false()
	assert_bool(FootprintMarks.marks_attr(12, Clock.Season.WINTER)).is_false()
	assert_bool(FootprintMarks.marks_attr(7, Clock.Season.SUMMER)).is_false()


func test_terrain_fallback_without_collision_table() -> void:
	assert_bool(
		FootprintMarks.marks_terrain(WorldGrid.Terrain.SAND, Clock.Season.SUMMER)
	).is_true()
	assert_bool(
		FootprintMarks.marks_terrain(WorldGrid.Terrain.GRASS, Clock.Season.SUMMER)
	).is_false()
	assert_bool(
		FootprintMarks.marks_terrain(WorldGrid.Terrain.GRASS, Clock.Season.WINTER)
	).is_true()
	assert_bool(
		FootprintMarks.marks_terrain(WorldGrid.Terrain.STONE, Clock.Season.WINTER)
	).is_false()


func test_tint_follows_prim_color() -> void:
	assert_bool(FootprintMarks.is_snow_mark(FieldCatalog.SAND_ATTR)).is_false()
	assert_bool(FootprintMarks.is_snow_mark(0)).is_true()
	assert_that(FootprintMarks.tint(false)).is_equal(FootprintMarks.SAND_TINT)
	assert_that(FootprintMarks.tint(true)).is_equal(FootprintMarks.SNOW_TINT)


func test_alpha_holds_then_fades_to_zero() -> void:
	var fps: float = FootprintMarks.GAME_FPS
	assert_float(FootprintMarks.alpha_at(0.0)).is_equal_approx(FootprintMarks.MAX_ALPHA, 0.0001)
	assert_float(FootprintMarks.alpha_at(100.0 / fps)).is_equal_approx(
		FootprintMarks.MAX_ALPHA, 0.0001
	)
	var mid: float = FootprintMarks.alpha_at(138.5 / fps)
	assert_float(mid).is_greater(0.0)
	assert_float(mid).is_less(FootprintMarks.MAX_ALPHA)
	assert_float(FootprintMarks.alpha_at(FootprintMarks.LIFETIME)).is_equal(0.0)
	assert_float(FootprintMarks.alpha_at(FootprintMarks.LIFETIME + 1.0)).is_equal(0.0)


func test_mark_geometry_matches_the_original_quad() -> void:
	## `ef_footprint01_00_v` is a flat quad at +/-1000 units, and `eFootPrint_dw` scales it
	## by (0.005, ., 0.0075) -> 10 x 15 GX. The 16x16 I4 mask inks 12/16 of the width and
	## 14/16 of the length, and that inked box is what `MARK_SIZE` describes.
	var quad_w: float = 2000.0 * 0.005 * FieldCatalog.GX_TO_METERS
	var quad_l: float = 2000.0 * 0.0075 * FieldCatalog.GX_TO_METERS
	assert_float(FootprintMarks.QUAD_SIZE.x).is_equal_approx(quad_w, 0.0001)
	assert_float(FootprintMarks.QUAD_SIZE.y).is_equal_approx(quad_l, 0.0001)
	## The print is longer than it is wide, by the original's 2:3 ratio.
	assert_float(quad_w / quad_l).is_equal_approx(2.0 / 3.0, 0.0001)
	## Rim peak sits 3.5 texels in across and 1.5 texels in along the length.
	assert_float(FootprintMarks.RIM_AXES.x).is_equal_approx(
		quad_w * (1.0 - 2.0 * 3.5 / 16.0), 0.0001
	)
	assert_float(FootprintMarks.RIM_AXES.y).is_equal_approx(
		quad_l * (1.0 - 2.0 * 1.5 / 16.0), 0.0001
	)


func test_blur_tail_fits_inside_the_drawn_quad() -> void:
	## The rim fades outward, so the mesh has to be wider than the mark or the falloff gets
	## sliced off at the quad edge and the print regains a hard outline.
	var radii: Vector2 = FootprintMarks.rim_radii_uv()
	var reach: float = FootprintMarks.rim_reach_uv()
	assert_float(radii.y + reach).is_less(0.5)
	var half_width: float = 0.5 * FootprintMarks.MARK_SIZE.x / FootprintMarks.MARK_SIZE.y
	assert_float(radii.x + reach).is_less(half_width)
	## And the mark still covers the original's rim, not the padded mesh.
	assert_float(radii.y * 2.0 * FootprintMarks.MARK_SIZE.y).is_equal_approx(
		FootprintMarks.RIM_AXES.y, 0.0001
	)


func test_peak_alpha_keeps_the_tile_ceiling() -> void:
	## Combiner alpha is `TEXEL0 * PRIMITIVE`: the I4 mask peaks at 7/15 and prim alpha at
	## 150/255, so a fresh print can never be more opaque than their product.
	assert_float(FootprintMarks.TILE_PEAK).is_equal_approx(7.0 / 15.0, 0.0001)
	assert_float(FootprintMarks.MAX_ALPHA).is_equal_approx(150.0 / 255.0, 0.0001)
	var peak: float = FootprintMarks.TILE_PEAK * FootprintMarks.alpha_at(0.0)
	assert_float(peak).is_equal_approx(0.2745, 0.001)
	assert_float(peak).is_less(0.5)


func test_step_period_shortens_with_clip_speed() -> void:
	var slow: float = FootprintMarks.step_period(0.8)
	var fast: float = FootprintMarks.step_period(1.25)
	assert_float(fast).is_less(slow)
	assert_float(FootprintMarks.step_period(1.0)).is_equal_approx(8.0 / 30.0, 0.0001)


func test_feet_straddle_the_facing_direction() -> void:
	var center := Vector3(4.0, 0.0, 4.0)
	var right: Vector3 = FootprintMarks.foot_position(center, 0.0, true)
	var left: Vector3 = FootprintMarks.foot_position(center, 0.0, false)
	assert_float(right.x - center.x).is_equal_approx(FootprintMarks.FOOT_OFFSET, 0.0001)
	assert_float(left.x - center.x).is_equal_approx(-FootprintMarks.FOOT_OFFSET, 0.0001)
	assert_float(right.z).is_equal_approx(center.z, 0.0001)
	## Both feet stay off the path center whichever way the player looks.
	var turned: Vector3 = FootprintMarks.foot_position(center, PI * 0.5, true)
	assert_float(turned.distance_to(center)).is_equal_approx(FootprintMarks.FOOT_OFFSET, 0.0001)


func test_mark_transform_lies_on_flat_ground_facing_the_player() -> void:
	var data := WorldData.new()
	var grid := WorldGrid.new()
	var pos: Vector3 = grid.cell_to_world(Vector2i(4, 4))
	var xform: Transform3D = FootprintMarks.mark_transform(data, grid, pos, 0.0)
	assert_float(xform.basis.determinant()).is_not_equal(0.0)
	assert_vector(xform.basis.y.normalized()).is_equal_approx(Vector3.UP, Vector3.ONE * 0.001)
	assert_vector(xform.basis.z.normalized()).is_equal_approx(
		Vector3(0.0, 0.0, 1.0), Vector3.ONE * 0.001
	)
	var ground: float = FieldCollision.ground_y_at(data, grid, pos)
	assert_float(xform.origin.y - ground).is_equal_approx(FootprintMarks.GROUND_LIFT, 0.0001)


func test_mark_transform_rotates_with_facing() -> void:
	var data := WorldData.new()
	var grid := WorldGrid.new()
	var pos: Vector3 = grid.cell_to_world(Vector2i(4, 4))
	var xform: Transform3D = FootprintMarks.mark_transform(data, grid, pos, PI * 0.5)
	assert_vector(xform.basis.z.normalized()).is_equal_approx(
		Vector3(1.0, 0.0, 0.0), Vector3.ONE * 0.001
	)
	assert_vector(xform.basis.y.normalized()).is_equal_approx(Vector3.UP, Vector3.ONE * 0.001)
