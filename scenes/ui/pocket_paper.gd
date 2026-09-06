extends Control

## Inventory paper fill. Uses pipeline `paper` (default cloth226 / ACHD) when present;
## otherwise draws a cream polka fallback matching `inv_mwin` silhouette.

@export var fill_color: Color = Color("fff8d0")
@export var dot_color: Color = Color(1, 1, 1, 0.92)
@export var rim_color: Color = Color(1, 1, 1, 1)
@export var shadow_color: Color = Color(0.15, 0.12, 0.1, 0.32)
@export var rim_width: float = 14.0
@export var bump_radius: float = 12.0
@export var bump_count: int = 48
@export var inset: float = 6.0
@export var corner_radius: float = 0.42
@export var dot_radius: float = 10.0
@export var dot_spacing: float = 32.0

var _paper_tex: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper_tex = InventoryChrome.load_tex("paper")
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if rect.size.x < 32.0 or rect.size.y < 32.0:
		return
	var outer := rect.grow(-inset)
	var r: float = mini(outer.size.x, outer.size.y) * clampf(corner_radius, 0.2, 0.5)
	var inner := outer.grow(-rim_width * 0.7)
	var inner_r: float = maxf(r - rim_width * 0.7, 8.0)
	_draw_shadow(outer, r)
	draw_colored_polygon(_round_rect_points(outer, r, 64), rim_color)
	_draw_bumps(outer, r)
	if _paper_tex != null:
		_draw_paper_fill(inner, inner_r)
	else:
		draw_colored_polygon(_round_rect_points(inner, inner_r, 64), fill_color)
		_draw_polka(inner, inner_r)


func _draw_shadow(rect: Rect2, radius: float) -> void:
	var shadow := rect
	shadow.position += Vector2(5, 7)
	draw_colored_polygon(_round_rect_points(shadow, radius, 48), shadow_color)


func _draw_bumps(rect: Rect2, radius: float) -> void:
	var pts: PackedVector2Array = _round_rect_points(rect, radius, bump_count)
	for p: Vector2 in pts:
		draw_circle(p, bump_radius, rim_color)


func _draw_paper_fill(rect: Rect2, radius: float) -> void:
	## Clip tiled shirt paper to the rounded body via a stencil-ish cover:
	## draw tiled paper in the AABB, then paint rim over the corners outside the round-rect.
	var tile: Vector2 = Vector2(_paper_tex.get_width(), _paper_tex.get_height())
	if tile.x < 1.0 or tile.y < 1.0:
		draw_colored_polygon(_round_rect_points(rect, radius, 64), fill_color)
		return
	var y: float = rect.position.y
	while y < rect.end.y:
		var x: float = rect.position.x
		while x < rect.end.x:
			var dest := Rect2(x, y, mini(tile.x, rect.end.x - x), mini(tile.y, rect.end.y - y))
			var src := Rect2(0, 0, dest.size.x, dest.size.y)
			draw_texture_rect_region(_paper_tex, dest, src)
			x += tile.x
		y += tile.y
	## Cover outside the round-rect with rim so tiles don't square-clip.
	_cover_outside_round_rect(rect, radius)


func _cover_outside_round_rect(rect: Rect2, radius: float) -> void:
	var full := Rect2(Vector2.ZERO, size)
	if rect.position.y > 0.0:
		draw_rect(Rect2(0, 0, full.size.x, rect.position.y), rim_color)
	if rect.end.y < full.size.y:
		draw_rect(Rect2(0, rect.end.y, full.size.x, full.size.y - rect.end.y), rim_color)
	if rect.position.x > 0.0:
		draw_rect(Rect2(0, rect.position.y, rect.position.x, rect.size.y), rim_color)
	if rect.end.x < full.size.x:
		draw_rect(Rect2(rect.end.x, rect.position.y, full.size.x - rect.end.x, rect.size.y), rim_color)
	## Corner lunes: sample a dense fan and paint anything outside the round-rect.
	var steps: int = 24
	var corners: Array[Vector2] = [
		Vector2(rect.end.x - radius, rect.position.y + radius),
		Vector2(rect.end.x - radius, rect.end.y - radius),
		Vector2(rect.position.x + radius, rect.end.y - radius),
		Vector2(rect.position.x + radius, rect.position.y + radius),
	]
	var start_angles: Array[float] = [-PI * 0.5, 0.0, PI * 0.5, PI]
	var corner_boxes: Array[Rect2] = [
		Rect2(rect.end.x - radius, rect.position.y, radius, radius),
		Rect2(rect.end.x - radius, rect.end.y - radius, radius, radius),
		Rect2(rect.position.x, rect.end.y - radius, radius, radius),
		Rect2(rect.position.x, rect.position.y, radius, radius),
	]
	for c: int in 4:
		var box: Rect2 = corner_boxes[c]
		var center: Vector2 = corners[c]
		var a0: float = start_angles[c]
		for i: int in steps:
			var t0: float = float(i) / float(steps)
			var t1: float = float(i + 1) / float(steps)
			var a_a: float = a0 + t0 * (PI * 0.5)
			var a_b: float = a0 + t1 * (PI * 0.5)
			var on_arc0 := center + Vector2(cos(a_a), sin(a_a)) * radius
			var on_arc1 := center + Vector2(cos(a_b), sin(a_b)) * radius
			## Far corner of the AABB relative to this quadrant.
			var far := Vector2(
				box.position.x if cos(a_a) < 0.0 else box.end.x,
				box.position.y if sin(a_a) < 0.0 else box.end.y
			)
			draw_colored_polygon(PackedVector2Array([on_arc0, on_arc1, far]), rim_color)


func _draw_polka(rect: Rect2, radius: float) -> void:
	var spacing: float = maxf(dot_spacing, dot_radius * 2.0 + 4.0)
	var y0: float = rect.position.y + spacing * 0.5
	var row: int = 0
	var y: float = y0
	while y <= rect.end.y:
		var x_off: float = spacing * 0.5 if (row % 2) == 1 else 0.0
		var x: float = rect.position.x + x_off
		while x <= rect.end.x:
			if _point_in_round_rect(Vector2(x, y), rect, radius - dot_radius):
				draw_circle(Vector2(x, y), dot_radius, dot_color)
			x += spacing
		y += spacing
		row += 1


func _point_in_round_rect(p: Vector2, rect: Rect2, radius: float) -> bool:
	if not rect.has_point(p):
		return false
	var r: float = maxf(radius, 0.0)
	var local := p - rect.position
	var q := Vector2(
		minf(local.x, rect.size.x - local.x),
		minf(local.y, rect.size.y - local.y)
	)
	if q.x >= r or q.y >= r:
		return true
	var d := Vector2(r - q.x, r - q.y)
	return d.length_squared() <= r * r


func _round_rect_points(rect: Rect2, radius: float, steps: int) -> PackedVector2Array:
	var r: float = minf(radius, mini(rect.size.x, rect.size.y) * 0.5)
	var pts: PackedVector2Array = []
	var per_corner: int = maxi(steps / 4, 4)
	var corners: Array[Vector2] = [
		Vector2(rect.end.x - r, rect.position.y + r),
		Vector2(rect.end.x - r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.position.y + r),
	]
	var start_angles: Array[float] = [-PI * 0.5, 0.0, PI * 0.5, PI]
	for c: int in 4:
		var center: Vector2 = corners[c]
		var a0: float = start_angles[c]
		for i: int in per_corner:
			var t: float = float(i) / float(per_corner)
			var a: float = a0 + t * (PI * 0.5)
			pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts
