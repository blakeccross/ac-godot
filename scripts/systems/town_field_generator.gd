class_name TownFieldGenerator
extends RefCounted

## Behavioral port of mRF_MakeRandomField_ovl (2-step landform + uniques).
## Produces a 7×10 acre-type grid and heights. Does not pick combo table meshes.

const BLOCK_X := 7
const BLOCK_Z := 10
const BLOCK_TOTAL := 70
const FG_X0 := 1
const FG_Z0 := 1
const FG_X_NUM := 5
const FG_Z_NUM := 6
const UT := 16

const DIRECT_NORTH := 0
const DIRECT_WEST := 1
const DIRECT_SOUTH := 2
const DIRECT_EAST := 3

const GROUP_CLIFF := 0
const GROUP_RIVER := 1
const GROUP_SLOPE := 3
const GROUP_RIVER_CLIFF_ANY := 5
const GROUP_CLIFF_ANY := 8

const RIVER_SIDE_LEFT := 0
const RIVER_SIDE_RIGHT := 1
const RIVER_SIDE_BOTH := 2
const CLIFF_ABOVE := 0
const CLIFF_BELOW := 1
const CLIFF_BOTH := 2

## mFM_BLOCK_TYPE_* (m_field_make.h order)
const T_BORDER_CLIFF_TOP := 0
const T_BORDER_CLIFF_RIVER := 1
const T_BORDER_CLIFF_LEFT := 2
const T_BORDER_CLIFF_RIGHT := 4
const T_BORDER_CLIFF_CORNER_TOP_LEFT := 5
const T_BORDER_CLIFF_CORNER_TOP_RIGHT := 8
const T_BORDER_CLIFF_LEFT_TUNNEL := 9
const T_BORDER_CLIFF_RIGHT_TUNNEL := 10
const T_TRACKS_STATION := 11
const T_TRACKS_DUMP := 12
const T_TRACKS_RIVER := 13
const T_PLAYER_HOUSE := 14
const T_CLIFF_H := 15
const T_CLIFF_BR := 16
const T_CLIFF_VR := 17
const T_CLIFF_TR := 18
const T_CLIFF_TL := 19
const T_CLIFF_VL := 20
const T_CLIFF_BL := 21
const T_WF_H := 22
const T_WF_BR := 23
const T_RIV_CLIFF_VR := 24
const T_RIV_CLIFF_TR := 25
const T_WF_TL := 26
const T_RIV_CLIFF_VL := 27
const T_RIV_CLIFF_BL := 28
const T_RIV_CLIFF_H := 29
const T_WF_E_BR := 30
const T_WF_E_VR := 31
const T_RIV_E_TR := 32
const T_RIV_E_TL := 33
const T_RIV_W_H := 34
const T_RIV_W_TR := 35
const T_RIV_W_TL := 36
const T_WF_W_VL := 37
const T_WF_W_BL := 38
const T_FLAT := 39
const T_RIVER_S := 40
const T_RIVER_E := 41
const T_RIVER_W := 42
const T_RIVER_SE := 43
const T_RIVER_ES := 44
const T_RIVER_SW := 45
const T_RIVER_WS := 46
const T_RIVER_S_BRIDGE := 47
const T_RIVER_E_BRIDGE := 48
const T_RIVER_W_BRIDGE := 49
const T_RIVER_SE_BRIDGE := 50
const T_RIVER_ES_BRIDGE := 51
const T_RIVER_SW_BRIDGE := 52
const T_RIVER_WS_BRIDGE := 53
const T_SLOPE_H := 54
const T_BORDER_CLIFF_LEFT_TRANSITION := 61
const T_BORDER_CLIFF_RIGHT_TRANSITION := 62
const T_BEACH := 63
const T_BEACH_RIVER := 64
const T_TRACKS_SHOP := 65
const T_SHRINE := 66
const T_TRACKS_POST := 67
const T_POLICE := 68
const T_BORDER_CLIFF_OCEAN_LEFT := 76
const T_BORDER_CLIFF_OCEAN_RIGHT := 77
const T_MUSEUM := 80
const T_NEEDLEWORK := 81
## `mFM_BLOCK_TYPE_BEACH_RIVER_BRIDGE` (decomp 82). Compacted ids keep museum/port as-is.
const T_BEACH_RIVER_BRIDGE := 82
const T_PORT := 86
const BIT_BRIDGE_UPPER := 1
const BIT_BRIDGE_LOWER := 2
## River → bridge acre (`RIVER_SOUTH_BRIDGE - RIVER_SOUTH`).
const RIVER_BRIDGE_DELTA := 7
const T_NONE := 255

const CLIFF_NEXT_DIRECT: Array[int] = [
	DIRECT_EAST, DIRECT_NORTH, DIRECT_NORTH, DIRECT_EAST, DIRECT_SOUTH, DIRECT_SOUTH, DIRECT_EAST
]
const RIVER_NEXT_DIRECT: Array[int] = [
	DIRECT_SOUTH, DIRECT_EAST, DIRECT_WEST, DIRECT_EAST, DIRECT_SOUTH, DIRECT_WEST, DIRECT_SOUTH
]

var _rng: RandomNumberGenerator
var _river_side: PackedInt32Array = PackedInt32Array()
var _cliff_height: PackedInt32Array = PackedInt32Array()


func generate(seed_value: int) -> Dictionary:
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value as int
	var blocks: PackedByteArray = PackedByteArray()
	blocks.resize(BLOCK_TOTAL)
	var heights: PackedByteArray = PackedByteArray()
	heights.resize(BLOCK_TOTAL)
	var stepmode_three: bool = _rand(100) < 15
	if stepmode_three:
		_copy(blocks, _pick_step3())
	else:
		_make_landform_step2(blocks)
	_make_flat_info(blocks)
	_set_beach(blocks)
	var bridge_flags: int = _set_bridge_block(blocks, not stepmode_three)
	_set_slope_block(blocks)
	_set_needlework_and_port(blocks)
	_set_unique_flat(blocks)
	_set_unique_rail(blocks)
	_set_pool(blocks)
	bridge_flags |= _set_sea_bridge_if_needed(blocks, bridge_flags)
	_make_heights(heights, blocks)
	return {
		"blocks": blocks,
		"heights": heights,
		"stepmode_three": stepmode_three,
		"seed": seed_value,
	}


func _rand(max_v: int) -> int:
	if max_v <= 0:
		return 0
	return int(_rng.randi() % max_v)


func _idx(bx: int, bz: int) -> int:
	return bz * BLOCK_X + bx


func _copy(dst: PackedByteArray, src: Array) -> void:
	for i: int in BLOCK_TOTAL:
		dst[i] = int(src[i])


func _pick_step3() -> Array:
	var layouts: Array = TownFieldLayouts.STEP3_LAYOUTS
	return layouts[_rand(layouts.size())]


func _make_landform_step2(blocks: PackedByteArray) -> void:
	var cliff := PackedByteArray()
	var river := PackedByteArray()
	cliff.resize(BLOCK_TOTAL)
	river.resize(BLOCK_TOTAL)
	var guard := 0
	while guard < 400:
		guard += 1
		_copy(cliff, TownFieldLayouts.BASE_BLOCKS)
		_copy(river, TownFieldLayouts.BASE_BLOCKS)
		if _set_random_block_data(river, cliff):
			_decide_river_album(cliff, river)
			for i: int in BLOCK_TOTAL:
				blocks[i] = cliff[i]
			return
	_copy(blocks, _pick_step3())


func _set_random_block_data(river: PackedByteArray, cliff: PackedByteArray) -> bool:
	if not _decide_base_cliff(cliff):
		return false
	return _decide_base_river(river, cliff)


func _decide_base_cliff(cliff: PackedByteArray) -> bool:
	var start_z: int = _rand(4)
	var bz: int = start_z + 2
	var starts: Array = [
		[T_CLIFF_H, T_CLIFF_TL],
		[T_CLIFF_H, T_CLIFF_TL],
		[T_CLIFF_H, T_CLIFF_BR, T_CLIFF_TL],
		[T_CLIFF_H, T_CLIFF_BR],
	]
	var options: Array = starts[start_z]
	var start_type: int = int(options[_rand(options.size())])
	cliff[_idx(1, bz)] = start_type
	cliff[_idx(0, bz)] = T_BORDER_CLIFF_LEFT_TRANSITION
	if not _trace_cliff(cliff, 1, bz):
		return false
	_set_end_cliff(cliff)
	return _last_check_cliff(cliff, 1, bz)


func _cliff_next_options(type_idx: int) -> Array:
	var table: Array = [
		[T_CLIFF_H, T_CLIFF_BR, T_CLIFF_TL],
		[T_CLIFF_VR, T_CLIFF_TR],
		[T_CLIFF_VR, T_CLIFF_TR],
		[T_CLIFF_H, T_CLIFF_BR, T_CLIFF_TL],
		[T_CLIFF_VL, T_CLIFF_BL],
		[T_CLIFF_VL, T_CLIFF_BL],
		[T_CLIFF_H, T_CLIFF_BR, T_CLIFF_TL],
	]
	return table[clampi(type_idx, 0, 6)]


func _trace_cliff(cliff: PackedByteArray, bx: int, bz: int) -> bool:
	var type_idx: int = int(cliff[_idx(bx, bz)]) - T_CLIFF_H
	var res := 0
	var n_bx0 := 0
	var n_bz0 := 0
	var guard := 0
	while res == 0 and guard < 40:
		guard += 1
		var options: Array = _cliff_next_options(type_idx)
		var next: int = int(options[_rand(options.size())])
		var next_idx: int = next - T_CLIFF_H
		var d0: Vector2i = _direct_offset(CLIFF_NEXT_DIRECT[type_idx])
		n_bx0 = bx + d0.x
		n_bz0 = bz + d0.y
		var d1: Vector2i = _direct_offset(CLIFF_NEXT_DIRECT[next_idx])
		var n_bx1: int = n_bx0 + d1.x
		var n_bz1: int = n_bz0 + d1.y
		if not _in_range(n_bx0, n_bz0, 1, 5, 2, 5):
			return false
		if not _in_range(n_bx1, n_bz1, 1, 6, 2, 5):
			return false
		if cliff[_idx(n_bx1, n_bz1)] == T_PLAYER_HOUSE:
			return false
		if cliff[_idx(n_bx0, n_bz0)] != T_FLAT:
			return false
		cliff[_idx(n_bx0, n_bz0)] = next
		if n_bx0 == 5:
			res = 2
		else:
			res = 1
	if res == 1:
		return _trace_cliff(cliff, n_bx0, n_bz0)
	return res == 2


func _set_end_cliff(cliff: PackedByteArray) -> void:
	var end_z := 0
	var cliff_type := 0
	for i: int in FG_Z_NUM:
		var bnum: int = _idx(5, i)
		var t: int = int(cliff[bnum])
		if t >= T_CLIFF_H and t <= T_CLIFF_BL:
			end_z = i
			cliff_type = t - T_CLIFF_H
	var direct: int = CLIFF_NEXT_DIRECT[cliff_type]
	if direct != DIRECT_EAST:
		var options: Array = _cliff_next_options(cliff_type)
		for opt: Variant in options:
			var t: int = int(opt) - T_CLIFF_H
			if CLIFF_NEXT_DIRECT[t] == DIRECT_EAST:
				var d: Vector2i = _direct_offset(direct)
				var bx: int = 5 + d.x
				var bz: int = end_z + d.y
				cliff[_idx(bx, bz)] = int(opt)
				cliff[_idx(bx + 1, bz)] = T_BORDER_CLIFF_RIGHT_TRANSITION
				return
	else:
		cliff[_idx(6, end_z)] = T_BORDER_CLIFF_RIGHT_TRANSITION


func _last_check_cliff(cliff: PackedByteArray, bx: int, bz: int) -> bool:
	var last_x := bx
	var last_z := bz
	var type: int = int(cliff[_idx(bx, bz)])
	var guard := 0
	while _in_group(type, GROUP_CLIFF) and guard < 20:
		guard += 1
		var idx: int = type - T_CLIFF_H
		var d: Vector2i = _direct_offset(CLIFF_NEXT_DIRECT[idx])
		last_x += d.x
		last_z += d.y
		type = int(cliff[_idx(last_x, last_z)])
	if last_x > 5:
		return bz != last_z
	return false


func _decide_base_river(river: PackedByteArray, cliff: PackedByteArray) -> bool:
	var keep := cliff.duplicate()
	for i: int in BLOCK_TOTAL:
		river[i] = keep[i]
		cliff[i] = keep[i]
	var start := _trace_river_part1(river, cliff)
	if start == Vector2i(-1, -1):
		return false
	if not _trace_river_part2(river, cliff, start.x, start.y):
		return false
	return _last_check_river(river, start.x, start.y)


func _river_next_options(river_idx: int) -> Array:
	var table: Array = [
		[T_RIVER_S, T_RIVER_SE, T_RIVER_SW],
		[T_RIVER_E, T_RIVER_ES],
		[T_RIVER_W, T_RIVER_WS],
		[T_RIVER_E, T_RIVER_ES],
		[T_RIVER_S, T_RIVER_SE, T_RIVER_SW],
		[T_RIVER_W, T_RIVER_WS],
		[T_RIVER_S, T_RIVER_SE, T_RIVER_SW],
	]
	return table[clampi(river_idx, 0, 6)]


func _trace_river_part1(river: PackedByteArray, cliff: PackedByteArray) -> Vector2i:
	var start_xs: Array[int] = [1, 2, 4, 5]
	var attempts := 0
	while attempts < 80:
		attempts += 1
		var bx: int = start_xs[_rand(4)]
		var options: Array = _river_next_options(0)
		var start_type: int = int(options[_rand(options.size())])
		var n_bx0: int = bx
		var n_bz0: int = 2
		var d: Vector2i = _direct_offset(_river_direct(start_type - T_RIVER_S))
		var n_bx1: int = n_bx0 + d.x
		var n_bz1: int = n_bz0 + d.y
		if not _in_range(n_bx0, n_bz0, 1, 5, 1, 6):
			continue
		if cliff[_idx(n_bx0, n_bz0)] == T_PLAYER_HOUSE:
			continue
		if _in_group(int(cliff[_idx(n_bx0, n_bz0)]), GROUP_CLIFF):
			if _river_album(int(cliff[_idx(n_bx0, n_bz0)]), T_RIVER_S) == T_NONE:
				return Vector2i(-1, -1)
			if cliff[_idx(n_bx0, n_bz0 + 1)] == T_PLAYER_HOUSE:
				continue
			river[_idx(n_bx0, n_bz0)] = T_RIVER_S
		elif cliff[_idx(n_bx1, n_bz1)] != T_PLAYER_HOUSE:
			river[_idx(n_bx0, n_bz0)] = start_type
		else:
			continue
		river[_idx(bx, 0)] = T_BORDER_CLIFF_RIVER
		river[_idx(bx, 1)] = T_TRACKS_RIVER
		return Vector2i(n_bx0, n_bz0)
	return Vector2i(-1, -1)


func _trace_river_part2(river: PackedByteArray, cliff: PackedByteArray, bx: int, bz: int) -> bool:
	var river_idx: int = int(river[_idx(bx, bz)]) - T_RIVER_S
	var next_direct: int = _river_direct(river_idx)
	var res := 0
	var n_bx0 := 0
	var n_bz0 := 0
	var guard := 0
	while res == 0 and guard < 40:
		guard += 1
		var options: Array = _river_next_options(river_idx)
		var next_type: int = int(options[_rand(options.size())])
		var next_next_direct: int = _river_direct(next_type - T_RIVER_S)
		var d0: Vector2i = _direct_offset(next_direct)
		n_bx0 = bx + d0.x
		n_bz0 = bz + d0.y
		if n_bz0 == 6:
			next_type = T_RIVER_S
			next_next_direct = _river_direct(0)
		var d1: Vector2i = _direct_offset(next_next_direct)
		var n_bx1: int = n_bx0 + d1.x
		var n_bz1: int = n_bz0 + d1.y
		if not _in_range(n_bx0, n_bz0, 1, 5, 1, 6):
			return false
		if not _in_range(n_bx1, n_bz1, 1, 5, 1, 7):
			return false
		if cliff[_idx(n_bx1, n_bz1)] == T_PLAYER_HOUSE:
			continue
		var next_bnum: int = _idx(n_bx0, n_bz0)
		if _in_group(int(cliff[next_bnum]), GROUP_CLIFF):
			var album: int = _river_album(int(cliff[next_bnum]), int(options[0]))
			if album == T_NONE:
				return false
			river[next_bnum] = int(options[0])
		else:
			river[next_bnum] = next_type
		if n_bz1 == 7:
			res = 2
		else:
			res = 1
	if res == 1:
		return _trace_river_part2(river, cliff, n_bx0, n_bz0)
	if res == 2:
		if _center_cross_count(river) == 0:
			return false
		if n_bx0 == 1 or n_bx0 == 5:
			return false
		return true
	return false


func _last_check_river(river: PackedByteArray, bx: int, bz: int) -> bool:
	var x := bx
	var z := bz
	var type: int = int(river[_idx(bx, bz)])
	var guard := 0
	while _in_group(type, GROUP_RIVER) and guard < 30:
		guard += 1
		var d: Vector2i = _direct_offset(_river_direct(type - T_RIVER_S))
		x += d.x
		z += d.y
		type = int(river[_idx(x, z)])
	return z > 6


func _center_cross_count(blocks: PackedByteArray) -> int:
	var count := 0
	for bz: int in range(2, 6):
		if _in_group(int(blocks[_idx(3, bz)]), GROUP_RIVER):
			count += 1
	return count


func _river_album(cliff_type: int, river_type: int) -> int:
	if not _in_group(cliff_type, GROUP_CLIFF) or not _in_group(river_type, GROUP_RIVER):
		return T_NONE
	var river: int = river_type - T_RIVER_S
	var cliff: int = cliff_type - T_CLIFF_H
	if river < 0 or river >= 7 or cliff < 0 or cliff >= 7:
		return T_NONE
	var album: Array = [
		[T_WF_H, T_WF_BR, T_RIV_CLIFF_VR, T_RIV_CLIFF_TR, T_WF_TL, T_RIV_CLIFF_VL, T_RIV_CLIFF_BL],
		[T_RIV_CLIFF_H, T_WF_E_BR, T_WF_E_VR, T_RIV_E_TR, T_RIV_E_TL, T_NONE, T_NONE],
		[T_RIV_W_H, T_NONE, T_NONE, T_RIV_W_TR, T_RIV_W_TL, T_WF_W_VL, T_WF_W_BL],
		[T_NONE, T_NONE, T_NONE, T_NONE, T_NONE, T_NONE, T_NONE],
		[T_NONE, T_NONE, T_NONE, T_NONE, T_NONE, T_NONE, T_NONE],
		[T_NONE, T_NONE, T_NONE, T_NONE, T_NONE, T_NONE, T_NONE],
		[T_NONE, T_NONE, T_NONE, T_NONE, T_NONE, T_NONE, T_NONE],
	]
	return int(album[river][cliff])


func _decide_river_album(cliff: PackedByteArray, river: PackedByteArray) -> void:
	for bz: int in range(0, BLOCK_Z - 2):
		for bx: int in BLOCK_X:
			var bnum: int = _idx(bx, bz)
			var river_type: int = int(river[bnum])
			var album: int = _river_album(int(cliff[bnum]), river_type)
			if album != T_NONE:
				cliff[bnum] = album
			elif (
				_in_group(river_type, GROUP_RIVER)
				or river_type == T_BORDER_CLIFF_RIVER
				or river_type == T_TRACKS_RIVER
			):
				cliff[bnum] = river_type


func _set_beach(blocks: PackedByteArray) -> void:
	for bx: int in range(1, BLOCK_X - 1):
		var bnum: int = _idx(bx, 6)
		if blocks[bnum] == T_FLAT:
			blocks[bnum] = T_BEACH
		elif blocks[bnum] == T_RIVER_S:
			blocks[bnum] = T_BEACH_RIVER
	blocks[_idx(0, 6)] = T_BORDER_CLIFF_OCEAN_LEFT
	blocks[_idx(6, 6)] = T_BORDER_CLIFF_OCEAN_RIGHT


func _set_unique_rail(blocks: PackedByteArray) -> void:
	var t0: int
	var t1: int
	if _rand(1000) & 1:
		t0 = T_TRACKS_SHOP
		t1 = T_TRACKS_POST
	else:
		t0 = T_TRACKS_POST
		t1 = T_TRACKS_SHOP
	while true:
		var bx: int = 1 + _rand(2)
		var bnum: int = _idx(bx, 1)
		if blocks[bnum] == T_TRACKS_DUMP:
			blocks[bnum] = t0
			break
	while true:
		var bx: int = 4 + _rand(2)
		var bnum: int = _idx(bx, 1)
		if blocks[bnum] == T_TRACKS_DUMP:
			blocks[bnum] = t1
			break


func _make_flat_info(blocks: PackedByteArray) -> void:
	_river_side.resize(BLOCK_TOTAL)
	_cliff_height.resize(BLOCK_TOTAL)
	for i: int in BLOCK_TOTAL:
		_river_side[i] = RIVER_SIDE_BOTH
		_cliff_height[i] = CLIFF_BOTH
	for bx: int in range(1, BLOCK_X - 1):
		var side: int = CLIFF_ABOVE
		for bz: int in range(1, BLOCK_Z - 1):
			var bnum: int = _idx(bx, bz)
			var type: int = int(blocks[bnum])
			if side == CLIFF_ABOVE and _in_group(type, GROUP_CLIFF_ANY):
				side = CLIFF_BELOW
			_cliff_height[bnum] = side
	for bz: int in range(1, BLOCK_Z - 1):
		var side: int = RIVER_SIDE_LEFT
		for bx: int in range(1, BLOCK_X - 1):
			var bnum: int = _idx(bx, bz)
			var type: int = int(blocks[bnum])
			if side == RIVER_SIDE_LEFT and (
				_in_group(type, GROUP_RIVER) or _in_group(type, GROUP_RIVER_CLIFF_ANY)
			):
				side = RIVER_SIDE_RIGHT
			_river_side[bnum] = side


func _count_flat(blocks: PackedByteArray, river_side: int, cliff_h: int) -> int:
	var count := 0
	for bz: int in range(2, 6):
		for bx: int in range(1, 6):
			var bnum: int = _idx(bx, bz)
			if blocks[bnum] != T_FLAT:
				continue
			if cliff_h != CLIFF_BOTH and _cliff_height[bnum] != cliff_h:
				continue
			if river_side != RIVER_SIDE_BOTH and _river_side[bnum] != river_side:
				continue
			count += 1
	return count


func _rewrite_flat(blocks: PackedByteArray, selected: int, unique: int, river_side: int, cliff_h: int) -> bool:
	var count := 0
	for bz: int in range(2, 6):
		for bx: int in range(1, 6):
			var bnum: int = _idx(bx, bz)
			if blocks[bnum] != T_FLAT:
				continue
			if cliff_h != CLIFF_BOTH and _cliff_height[bnum] != cliff_h:
				continue
			if river_side != RIVER_SIDE_BOTH and _river_side[bnum] != river_side:
				continue
			if count == selected:
				blocks[bnum] = unique
				return true
			count += 1
	return false


func _flat_to_unique(blocks: PackedByteArray, unique: int, river_side: int, cliff_h: int) -> bool:
	var num: int = _count_flat(blocks, river_side, cliff_h)
	if num == 0:
		return false
	return _rewrite_flat(blocks, _rand(num), unique, river_side, cliff_h)


func _set_unique_flat(blocks: PackedByteArray) -> void:
	var side0: int = _rand(100) & 1
	var side1: int = side0 ^ 1
	if not _flat_to_unique(blocks, T_SHRINE, side0, CLIFF_BELOW):
		_flat_to_unique(blocks, T_SHRINE, side1, CLIFF_BELOW)
	if not _flat_to_unique(blocks, T_POLICE, side1, CLIFF_BELOW):
		_flat_to_unique(blocks, T_POLICE, side0, CLIFF_BELOW)
	_flat_to_unique(blocks, T_MUSEUM, RIVER_SIDE_BOTH, CLIFF_BELOW)


func _set_needlework_and_port(blocks: PackedByteArray) -> void:
	if blocks[_idx(5, 6)] == T_BEACH:
		blocks[_idx(5, 6)] = T_PORT
	var beaches: Array[int] = []
	for bx: int in range(1, BLOCK_X - 1):
		if blocks[_idx(bx, 6)] == T_BEACH:
			beaches.append(bx)
	if beaches.is_empty():
		return
	var pick: int = beaches[_rand(mini(3, beaches.size()))]
	blocks[_idx(pick, 6)] = T_NEEDLEWORK


func _set_pool(blocks: PackedByteArray) -> void:
	## POOL_SOUTH = 69 = RIVER_SOUTH + 29 in m_field_make.h.
	const POOL_DELTA := 29
	var pure: Array[int] = []
	for i: int in (BLOCK_Z - 2) * BLOCK_X:
		var t: int = int(blocks[i])
		if t >= T_RIVER_S and t <= T_RIVER_WS:
			pure.append(i)
	if pure.is_empty():
		return
	var i: int = pure[_rand(pure.size())]
	blocks[i] = int(blocks[i]) + POOL_DELTA


func _river_cross_cliff_bz(blocks: PackedByteArray) -> int:
	## First waterfall acre in the scanned prefix (`mRF_GetRiverCrossCliffInfo`).
	var crosses: Array[int] = [
		T_WF_H, T_WF_BR, T_WF_TL, T_WF_E_BR, T_WF_E_VR, T_WF_W_VL, T_WF_W_BL
	]
	for i: int in (BLOCK_Z - 2) * BLOCK_X:
		var t: int = int(blocks[i])
		if crosses.has(t):
			return i / BLOCK_X
	return 4


func _set_bridge_block(blocks: PackedByteArray, two_step: bool) -> int:
	## `mRF_SetBridgeBlock`: one river acre north of the waterfall always becomes a
	## bridge type (+7). 2-step towns also get a 50% south span. Meshes are `grd_s_r*_b_*`.
	var cross_bz: int = _river_cross_cliff_bz(blocks)
	var flags := 0
	var before: Array[int] = []
	var after: Array[int] = []
	for bz: int in range(BLOCK_Z - 2):
		for bx: int in BLOCK_X:
			var bnum: int = _idx(bx, bz)
			if not _in_group(int(blocks[bnum]), GROUP_RIVER):
				continue
			if bz < cross_bz:
				before.append(bnum)
			elif bz > cross_bz:
				after.append(bnum)
	if not before.is_empty():
		var pick: int = before[_rand(before.size())]
		blocks[pick] = int(blocks[pick]) + RIVER_BRIDGE_DELTA
		flags |= BIT_BRIDGE_UPPER
	if not after.is_empty() and two_step and (_rand(10) & 1) != 0:
		var pick: int = after[_rand(after.size())]
		blocks[pick] = int(blocks[pick]) + RIVER_BRIDGE_DELTA
		flags |= BIT_BRIDGE_LOWER
	return flags


func _set_sea_bridge_if_needed(blocks: PackedByteArray, flags: int) -> int:
	## `mRF_SetSeaBlockWithBridgeRiver`: if there is no lower span, the beach mouth
	## (`BEACH_RIVER`) becomes `BEACH_RIVER_BRIDGE` (`grd_s_m_r1_b_*`).
	if (flags & BIT_BRIDGE_LOWER) != 0:
		return 0
	for i: int in (BLOCK_Z - 2) * BLOCK_X:
		if int(blocks[i]) == T_BEACH_RIVER:
			blocks[i] = T_BEACH_RIVER_BRIDGE
			return BIT_BRIDGE_LOWER
	return 0


func _set_slope_block(blocks: PackedByteArray) -> void:
	## `mRF_SetSlopeBlock`: each west `LEFT_TRANSITION` is a cliff band. Walk the
	## cliff (`l_cliff_next_direct`) and turn one pure cliff on each river side into
	## a slope. 2-step towns have two bands; one pair of slopes left the beach
	## unreachable.
	for bz: int in range(BLOCK_Z - 2):
		if int(blocks[_idx(0, bz)]) != T_BORDER_CLIFF_LEFT_TRANSITION:
			continue
		_place_slope_on_half(blocks, bz, RIVER_SIDE_LEFT)
		_place_slope_on_half(blocks, bz, RIVER_SIDE_RIGHT)


func _place_slope_on_half(blocks: PackedByteArray, start_bz: int, half: int) -> void:
	var sites: Array[int] = _slope_sites_on_half(blocks, start_bz, half)
	if sites.is_empty():
		return
	var bnum: int = sites[_rand(sites.size())]
	var t: int = int(blocks[bnum])
	var idx: int = cliff_shape(t)
	if idx < 0:
		return
	blocks[bnum] = T_SLOPE_H + idx


func _slope_sites_on_half(blocks: PackedByteArray, start_bz: int, half: int) -> Array[int]:
	## `mRF_CountDirectedInfoCliff` / `SetSlopeDirectedInfoCliff`.
	var sites: Array[int] = []
	var bx: int = 1
	var bz: int = start_bz
	var side: int = RIVER_SIDE_LEFT
	for _i: int in BLOCK_TOTAL:
		if not _in_range(bx, bz, 0, BLOCK_X - 1, 0, BLOCK_Z - 1):
			break
		var bnum: int = _idx(bx, bz)
		var t: int = int(blocks[bnum])
		if t == T_BORDER_CLIFF_RIGHT_TRANSITION:
			break
		var idx: int = cliff_shape(t)
		if _in_group(t, GROUP_RIVER_CLIFF_ANY):
			side = RIVER_SIDE_RIGHT
		elif side == half and idx >= 0 and _in_group(t, GROUP_CLIFF):
			sites.append(bnum)
		if idx < 0:
			break
		var step: Vector2i = _direct_offset(CLIFF_NEXT_DIRECT[idx])
		bx += step.x
		bz += step.y
	return sites


func _make_heights(heights: PackedByteArray, blocks: PackedByteArray) -> void:
	for i: int in BLOCK_TOTAL:
		heights[i] = 0
	for bx: int in BLOCK_X:
		var height := 0
		for bz: int in range(BLOCK_Z - 1, -1, -1):
			var bnum: int = _idx(bx, bz)
			heights[bnum] = height
			var t: int = int(blocks[bnum])
			if raises_height(t):
				height = mini(height + 1, 3)


static func raises_height(type: int) -> bool:
	## `mRF_GetBlockBase`: step only on HORIZONTAL / TOP_RIGHT / TOP_LEFT cliff bits
	## (and the two border transitions). Vertical and bottom-corner acres stay on the
	## same terrace — treating every waterfall as a step made the next acre 6 m too high.
	if type == T_BORDER_CLIFF_LEFT_TRANSITION or type == T_BORDER_CLIFF_RIGHT_TRANSITION:
		return true
	var shape: int = cliff_shape(type)
	return shape == 0 or shape == 3 or shape == 4


func _in_group(type: int, group: int) -> bool:
	match group:
		GROUP_CLIFF:
			return type >= T_CLIFF_H and type <= T_CLIFF_BL
		GROUP_RIVER:
			return type >= T_RIVER_S and type <= T_RIVER_WS
		GROUP_SLOPE:
			return type >= T_SLOPE_H and type <= T_SLOPE_H + 6
		GROUP_RIVER_CLIFF_ANY:
			return type >= T_WF_H and type <= T_WF_W_BL
		GROUP_CLIFF_ANY:
			return (
				(type >= T_CLIFF_H and type <= T_CLIFF_BL)
				or (type >= T_SLOPE_H and type <= T_SLOPE_H + 6)
				or (type >= T_WF_H and type <= T_WF_W_BL)
			)
	return false


func _river_direct(river_idx: int) -> int:
	if river_idx < 0 or river_idx >= RIVER_NEXT_DIRECT.size():
		return DIRECT_SOUTH
	return RIVER_NEXT_DIRECT[river_idx]


func _direct_offset(direct: int) -> Vector2i:
	match direct & 3:
		DIRECT_NORTH:
			return Vector2i(0, -1)
		DIRECT_WEST:
			return Vector2i(-1, 0)
		DIRECT_SOUTH:
			return Vector2i(0, 1)
		DIRECT_EAST:
			return Vector2i(1, 0)
	return Vector2i.ZERO


func _in_range(bx: int, bz: int, bx_min: int, bx_max: int, bz_min: int, bz_max: int) -> bool:
	return bx >= bx_min and bx <= bx_max and bz >= bz_min and bz <= bz_max


static func is_riverish(type: int) -> bool:
	return (
		(type >= T_RIVER_S and type <= T_RIVER_WS)
		or is_river_bridge(type)
		or type == T_TRACKS_RIVER
		or type == T_BEACH_RIVER
		or type == T_BORDER_CLIFF_RIVER
		or (type >= T_WF_H and type <= T_WF_W_BL)
	)


static func is_river_bridge(type: int) -> bool:
	return (
		(type >= T_RIVER_S_BRIDGE and type <= T_RIVER_WS_BRIDGE) or type == T_BEACH_RIVER_BRIDGE
	)


static func is_beach(type: int) -> bool:
	return (
		type == T_BEACH
		or type == T_BEACH_RIVER
		or type == T_BEACH_RIVER_BRIDGE
		or type == T_NEEDLEWORK
		or type == T_PORT
	)


static func is_cliffish(type: int) -> bool:
	return (
		(type >= T_CLIFF_H and type <= T_CLIFF_BL)
		or (type >= T_SLOPE_H and type <= T_SLOPE_H + 6)
		or (type >= T_WF_H and type <= T_WF_W_BL)
	)


static func is_slope(type: int) -> bool:
	return type >= T_SLOPE_H and type <= T_SLOPE_H + 6


static func cliff_shape(type: int) -> int:
	## 0–6 = H, BR, VR, TR, TL, VL, BL (`CLIFF_NEXT_DIRECT` order). -1 = not a cliff/slope.
	if type >= T_CLIFF_H and type <= T_CLIFF_BL:
		return type - T_CLIFF_H
	if type >= T_SLOPE_H and type <= T_SLOPE_H + 6:
		return type - T_SLOPE_H
	match type:
		T_WF_H, T_RIV_CLIFF_H, T_RIV_W_H:
			return 0
		T_WF_BR, T_WF_E_BR:
			return 1
		T_RIV_CLIFF_VR, T_WF_E_VR:
			return 2
		T_RIV_CLIFF_TR, T_RIV_E_TR, T_RIV_W_TR:
			return 3
		T_WF_TL, T_RIV_E_TL, T_RIV_W_TL:
			return 4
		T_RIV_CLIFF_VL, T_WF_W_VL:
			return 5
		T_RIV_CLIFF_BL, T_WF_W_BL:
			return 6
		_:
			return -1


static func acre_abbrev(type: int) -> String:
	## Fixed 4-char console label for the 7×10 acre map.
	match type:
		T_BORDER_CLIFF_TOP:
			return "clN "
		T_BORDER_CLIFF_RIVER:
			return "clNR"
		T_BORDER_CLIFF_LEFT:
			return "clL "
		T_BORDER_CLIFF_RIGHT:
			return "clR "
		T_BORDER_CLIFF_CORNER_TOP_LEFT:
			return "clTL"
		T_BORDER_CLIFF_CORNER_TOP_RIGHT:
			return "clTR"
		T_BORDER_CLIFF_LEFT_TUNNEL:
			return "tnL "
		T_BORDER_CLIFF_RIGHT_TUNNEL:
			return "tnR "
		T_TRACKS_STATION:
			return "STAT"
		T_TRACKS_DUMP:
			return "RAIL"
		T_TRACKS_RIVER:
			return "tRiv"
		T_PLAYER_HOUSE:
			return "HOME"
		T_CLIFF_H:
			return "ClfH"
		T_CLIFF_BR:
			return "ClBR"
		T_CLIFF_VR:
			return "ClVR"
		T_CLIFF_TR:
			return "ClTR"
		T_CLIFF_TL:
			return "ClTL"
		T_CLIFF_VL:
			return "ClVL"
		T_CLIFF_BL:
			return "ClBL"
		T_WF_H:
			return "WfH "
		T_WF_BR:
			return "WfBR"
		T_RIV_CLIFF_VR:
			return "RcVR"
		T_RIV_CLIFF_TR:
			return "RcTR"
		T_WF_TL:
			return "WfTL"
		T_RIV_CLIFF_VL:
			return "RcVL"
		T_RIV_CLIFF_BL:
			return "RcBL"
		T_RIV_CLIFF_H:
			return "RcH "
		T_WF_E_BR:
			return "WfEB"
		T_WF_E_VR:
			return "WfEV"
		T_RIV_E_TR:
			return "ReTR"
		T_RIV_E_TL:
			return "ReTL"
		T_RIV_W_H:
			return "RwH "
		T_RIV_W_TR:
			return "RwTR"
		T_RIV_W_TL:
			return "RwTL"
		T_WF_W_VL:
			return "WfWV"
		T_WF_W_BL:
			return "WfWB"
		T_FLAT:
			return "...."
		T_RIVER_S:
			return "RivS"
		T_RIVER_E:
			return "RivE"
		T_RIVER_W:
			return "RivW"
		T_RIVER_SE:
			return "RvSE"
		T_RIVER_ES:
			return "RvES"
		T_RIVER_SW:
			return "RvSW"
		T_RIVER_WS:
			return "RvWS"
		T_RIVER_S_BRIDGE:
			return "BrgS"
		T_RIVER_E_BRIDGE:
			return "BrgE"
		T_RIVER_W_BRIDGE:
			return "BrgW"
		T_RIVER_SE_BRIDGE:
			return "BgSE"
		T_RIVER_ES_BRIDGE:
			return "BgES"
		T_RIVER_SW_BRIDGE:
			return "BgSW"
		T_RIVER_WS_BRIDGE:
			return "BgWS"
		T_BEACH:
			return "sand"
		T_BEACH_RIVER:
			return "sRiv"
		T_TRACKS_SHOP:
			return "SHOP"
		T_SHRINE:
			return "WELL"
		T_TRACKS_POST:
			return "POST"
		T_POLICE:
			return "COPS"
		T_BORDER_CLIFF_LEFT_TRANSITION:
			return "clLT"
		T_BORDER_CLIFF_RIGHT_TRANSITION:
			return "clRT"
		T_BORDER_CLIFF_OCEAN_LEFT:
			return "ocL "
		T_BORDER_CLIFF_OCEAN_RIGHT:
			return "ocR "
		T_MUSEUM:
			return "MUSE"
		T_NEEDLEWORK:
			return "ABLE"
		T_BEACH_RIVER_BRIDGE:
			return "sBrg"
		T_PORT:
			return "DOCK"
		T_NONE:
			return "    "
		_:
			if type >= T_SLOPE_H and type <= T_SLOPE_H + 6:
				var slope: PackedStringArray = ["SlpH", "SlBR", "SlVR", "SlTR", "SlTL", "SlVL", "SlBL"]
				return slope[type - T_SLOPE_H]
			if type >= 69 and type <= 75:
				return "POOL"
			return "T%03d" % type
