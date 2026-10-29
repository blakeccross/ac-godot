class_name MuseumFishSchool
extends Node

## The fish wing's tanks as one system (`Museum_Fish_Actor_move`): which tank the player stands
## at, each tank's slowly turning current, the fish shoving one another and steering round the
## big tank-3 fish, then every fish's own move. Runs before the fish visuals, which only draw.

## Fish that never shove (`Museum_Fish_Object_Check`): they move on their own rules.
const NO_SHOVE: Array[StringName] = [&"frog", &"crawfish", &"eel", &"arapaima", &"giant_snakehead"]
const NOT_SHOVED: Array[StringName] = [&"frog", &"eel", &"arapaima", &"giant_snakehead"]
## `Museum_Fish_BigFishObjCheck`: the two big tank-3 fish everyone else steers round, and the
## z each keeps to.
const BIG_FISH: Array[StringName] = [&"arapaima", &"giant_snakehead"]
const BIG_FISH_Z: Array[float] = [430.0, 530.0]
## `mfish_get_player_area` rechecks every 30 frames.
const AREA_TICKS := 30.0

var fish: Array[MuseumFishActor] = []
var player_area: int = -1
var _area_timer: float = 0.0
## `_14daa`: each tank's current angle.
var _flow: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _rng := RandomNumberGenerator.new()


func add(actor: MuseumFishActor) -> void:
	actor.school = self
	fish.append(actor)


func flow_angle(tank: int) -> float:
	return _flow[tank]


## The player in the room's GX (floor at y 40).
func player_gx() -> Vector3:
	var p := Player.find(get_tree()) if is_inside_tree() else null
	if p == null:
		return Vector3(-9999.0, 0.0, -9999.0)
	var g: Vector3 = p.global_position / FieldCatalog.GX_TO_METERS
	return Vector3(g.x, g.y + MuseumFishActor.FLOOR_GX, g.z)


## `mfish_peck_check`: piranhas always come to a player at their tank; carp and koi when the
## player carries candy; goldfish when they carry fruit.
func peck_check(a: MuseumFishActor) -> bool:
	if player_area != a.tank:
		return false
	if a.fish.id == &"piranha":
		return true
	var inv: Inventory = Game.inventory if Game != null else null
	if inv == null:
		return false
	if inv.count_of(&"candy") > 0:
		return a.fish.id == &"carp" or a.fish.id == &"koi"
	if _carries_fruit(inv):
		return a.fish.id == &"goldfish" or a.fish.id == &"popeyed_goldfish"
	return false


func _carries_fruit(inv: Inventory) -> bool:
	for id: StringName in [&"apple", &"orange", &"pear", &"peach", &"cherry", &"coconut"]:
		if inv.count_of(id) > 0:
			return true
	return false


func _physics_process(delta: float) -> void:
	tick(delta * DecompTime.TICK_HZ)


func tick(t: float) -> void:
	var old_area: int = player_area
	_area_timer -= t
	if _area_timer < 0.0:
		_area_timer = AREA_TICKS
		player_area = _area_of(player_gx())
	if player_area != old_area:
		_on_area_changed()
	for i: int in _flow.size():
		if i == 2:
			_flow[i] += deg_to_rad(0.5 + _rng.randf()) * t
		else:
			_flow[i] += 8.0 * MathUtil.S16 * t
	_object_check()
	for a: MuseumFishActor in fish:
		a.move(t)


## `mfish_get_player_area`.
static func _area_of(p: Vector3) -> int:
	if p.z < 80.0:
		return MuseumFishActor.SEA_TANK
	if p.z > 120.0 and p.z < 320.0:
		return 0 if p.x < 320.0 else 1
	if p.z > 360.0 and p.z < 560.0:
		return 2 if p.x < 320.0 and p.x > 120.0 else 3
	return -1


## Walking up to a tank wakes its fish at once (`Museum_Fish_Actor_move`).
func _on_area_changed() -> void:
	var p: Vector3 = player_gx()
	for a: MuseumFishActor in fish:
		if player_area == 3 and a.fish.id in [&"goldfish", &"popeyed_goldfish", &"piranha"]:
			a.activity = 0.0
		elif player_area == 0 and a.fish.id in [&"carp", &"koi"]:
			a.activity = 20.0
		if a.tank == player_area and Vector2(p.x - a.pos.x, p.z - a.pos.z).length() < 60.0:
			a.activity = _rng.randf() * 60.0


## `Museum_Fish_Object_Check`: overlapping fish push apart, lighter ones more, and remember who
## crowded them (`_594`) and who is nearest (`_598`).
func _object_check() -> void:
	for f: MuseumFishActor in fish:
		f.flags &= ~0x20
	for f: MuseumFishActor in fish:
		if f.fish.id in NO_SHOVE:
			_big_fish_check(f)
			continue
		var push_xz := Vector2.ZERO
		var n_xz: float = 0.0
		var push_y: float = 0.0
		var n_y: float = 0.0
		var best: float = INF
		for o: MuseumFishActor in fish:
			if o == f or o.tank != f.tank or o.fish.id in NOT_SHOVED:
				continue
			var d: Vector3 = f.objchk - o.objchk
			var xz: float = Vector2(d.x, d.z).length()
			var full: float = d.length()
			if full < best:
				best = full
				f.nearest = o
			var heights: float = f.ofs_y + o.ofs_y
			if absf(d.y) >= heights:
				continue
			var reach: float = f.body_len + o.body_len
			if xz >= reach:
				continue
			var gap: float = (reach - xz) * 0.2
			var dy: float = (heights - d.y if d.y > 0.0 else -d.y - heights) * 0.2
			f.escape_angle = atan2(d.x, d.z)
			f.flags |= 0x20
			o.escape_angle = wrapf(f.escape_angle + PI, -PI, PI)
			f.crowd = o
			var share: float
			if (o.flags & 0x1e) == 0 or absf(MuseumFishActor._diff(o.wall_angle, f.escape_angle)) >= PI / 2.0:
				share = o.mass / (f.mass + o.mass)
			else:
				share = 2.0 * o.mass / (f.mass + 2.0 * o.mass)
			share *= 1.0 - f.mass
			gap *= share
			dy *= share
			if gap < absf(dy) or f.fish.id == &"coelacanth":
				push_xz += Vector2(sin(f.escape_angle), cos(f.escape_angle)) * gap
				n_xz += 1.0
			else:
				push_y += dy
				n_y += 1.0
			if o.mass > f.mass and f.pushed <= f.body_len * 10.0:
				f.pushed += gap
		if n_xz > 0.0:
			f.pos.x += push_xz.x / n_xz
			f.pos.z += push_xz.y / n_xz
		if n_y > 0.0:
			f.pos.y += clampf(push_y / n_y, -0.5, 0.5)
			f.height_ofs += push_y / n_y
		if n_xz > 0.0 and n_y > 0.0 and f.crowd != null:
			var r: Vector3 = f.crowd.pos - f.pos
			f.escape_angle = atan2(r.x, r.z)
		_big_fish_check(f)


## `Museum_Fish_BigFishObjCheck`: in tank 3 everyone else gives way to the arapaima and the
## giant snakehead, which barely move for them.
func _big_fish_check(f: MuseumFishActor) -> void:
	if f.tank != 3 or f.fish.id in BIG_FISH:
		return
	for i: int in BIG_FISH.size():
		var big: MuseumFishActor = null
		for o: MuseumFishActor in fish:
			if o.fish.id == BIG_FISH[i]:
				big = o
		if big == null:
			continue
		var op: Vector3 = f.objchk - big.objchk
		var fx: float = f.body_len * (sin(f.yaw) * 0.3 + 0.7) + big.body_len
		var fz: float = 10.0 + f.body_len * (0.7 + 0.3 * cos(f.yaw))
		var fy: float = f.ofs_y + big.ofs_y
		if not (absf(op.z) < fz and absf(op.y) < fy and absf(op.x) < fx):
			continue
		fx -= absf(op.x)
		fz -= absf(op.z)
		fy -= absf(op.y)
		if fy < minf(fx, fz):
			var s: float = -1.0 if op.y < 0.0 else 1.0
			f.pos.y += s * minf(fy, 0.25)
			big.pos.y -= s * minf(fy, 0.05)
		elif fz < fx:
			var v: float = absf(cos(f.yaw) * f.speed)
			if op.z < 0.0:
				f.pos.z -= minf(fz, maxf(0.5, v))
				if big.objchk.z < BIG_FISH_Z[i] + 10.0:
					big.pos.z += minf(fz, 0.05)
			else:
				f.pos.z += minf(fz, maxf(0.5, v))
				if big.objchk.z > BIG_FISH_Z[i] - 10.0:
					big.pos.z -= minf(fz, 0.05)
		else:
			var v: float = absf(sin(f.yaw) * f.speed)
			var s: float = -1.0 if op.x < 0.0 else 1.0
			f.pos.x += s * minf(fx, maxf(0.5, v))
			big.pos.x -= s * minf(fx, 0.05)
