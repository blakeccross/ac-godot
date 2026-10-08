class_name SecretCode
extends RefCounted

## The 28-character secret codes (`m_mail_password_check`, `mMpswd_*`): a gift of one item for
## a named player in a named town, packed into 21 bytes and scrambled by a substitution, two
## keyed transpositions, two bit shuffles, a small RSA step and a keyed bit mix, then written
## in 64 safe characters. The same algorithm as the GameCube, so its codes work here and these
## work there. Names are the 8-byte font strings (space padded).
##
## Fields: `type` (`Type`), `hit_rate`, `npc_type`, `npc_code`, `str0` (player) and `str1`
## (town) as `PackedByteArray`, `item` (the decomp item number), `checksum`.

enum Type { FAMICOM, POPULAR, CARD_E, MAGAZINE, USER, CARD_E_MINI }

const DATA_LEN := 21
const STR_LEN := 28
const NAME_LEN := 8
const KEY_IDX := 1
const BITMIX_IDX := 1
const RSA_R_IDX := 5
const RSA_INFO_IDX := 15
const RSA_KEYSAVE_IDX := 20
## `usable_to_fontnum`: the 64 characters a code is written in.
const ALPHABET := "bKz5cqYZOdt6nlByo84Lk%AQmDPI7&RswU#r3ExMC@e9gvVGuNiXWfTJFSHp2ajh"
const TRANS0: Array[String] = [
	"NiiMasaru", "KomatsuKunihiro", "TakakiGentarou", "MiyakeHiromichi", "HayakawaKenzo",
	"KasamatsuShigehiro", "SumiyoshiNobuhiro", "NomaTakafumi", "EguchiKatsuya", "NogamiHisashi",
	"IidaToki", "IkegawaNoriko", "KawaseTomohiro", "BandoTaro", "TotakaKazuo", "WatanabeKunio",
]
const TRANS1: Array[String] = [
	"RichAmtower", "KyleHudson", "MichaelKelbaugh", "RaycholeLAneff", "LeslieSwan",
	"YoshinobuMantani", "KirkBuchanan", "TimOLeary", "BillTrinen", "nAkAyOsInoNyuuSankin",
	"zendamaKINAKUDAMAkin", "OishikutetUYOKUNARU", "AsetoAminofen", "fcSFCn64GCgbCGBagbVB",
	"YossyIsland", "KedamonoNoMori",
]
const PRIMES: PackedInt32Array = [
	17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79,
	83, 89, 97, 101, 103, 107, 109, 113, 127, 131, 137, 139, 149, 151, 157, 163,
	167, 173, 179, 181, 191, 193, 197, 199, 211, 223, 227, 229, 233, 239, 241, 251,
	257, 263, 269, 271, 277, 281, 283, 293, 307, 311, 313, 317, 331, 337, 347, 349,
	353, 359, 367, 373, 379, 383, 389, 397, 401, 409, 419, 421, 431, 433, 439, 443,
	449, 457, 461, 463, 467, 479, 487, 491, 499, 503, 509, 521, 523, 541, 547, 557,
	563, 569, 571, 577, 587, 593, 599, 601, 607, 613, 617, 619, 631, 641, 643, 647,
	653, 659, 661, 673, 677, 683, 691, 701, 709, 719, 727, 733, 739, 743, 751, 757,
	761, 769, 773, 787, 797, 809, 811, 821, 823, 827, 829, 839, 853, 857, 859, 863,
	877, 881, 883, 887, 907, 911, 919, 929, 937, 941, 947, 953, 967, 971, 977, 983,
	991, 997, 1009, 1013, 1019, 1021, 1031, 1033, 1039, 1049, 1051, 1061, 1063, 1069, 1087, 1091,
	1093, 1097, 1103, 1109, 1117, 1123, 1129, 1151, 1153, 1163, 1171, 1181, 1187, 1193, 1201, 1213,
	1217, 1223, 1229, 1231, 1237, 1249, 1259, 1277, 1279, 1283, 1289, 1291, 1297, 1301, 1303, 1307,
	1319, 1321, 1327, 1361, 1367, 1373, 1381, 1399, 1409, 1423, 1427, 1429, 1433, 1439, 1447, 1451,
	1453, 1459, 1471, 1481, 1483, 1487, 1489, 1493, 1499, 1511, 1523, 1531, 1543, 1549, 1553, 1559,
	1567, 1571, 1579, 1583, 1597, 1601, 1607, 1609, 1613, 1619, 1621, 1627, 1637, 1657, 1663, 1667,
]
const SUBST: PackedInt32Array = [
	0xf0, 0x83, 0xfd, 0x62, 0x93, 0x49, 0x0d, 0x3e, 0xe1, 0xa4, 0x2b, 0xaf, 0x3a, 0x25, 0xd0, 0x82,
	0x7f, 0x97, 0xd2, 0x03, 0xb2, 0x32, 0xb4, 0xe6, 0x09, 0x42, 0x57, 0x27, 0x60, 0xea, 0x76, 0xab,
	0x2d, 0x65, 0xa8, 0x4d, 0x8b, 0x95, 0x01, 0x37, 0x59, 0x79, 0x33, 0xac, 0x2f, 0xae, 0x9f, 0xfe,
	0x56, 0xd9, 0x04, 0xc6, 0xb9, 0x28, 0x06, 0x5c, 0x54, 0x8d, 0xe5, 0x00, 0xb3, 0x7b, 0x5e, 0xa7,
	0x3c, 0x78, 0xcb, 0x2e, 0x6d, 0xe4, 0xe8, 0xdc, 0x40, 0xa0, 0xde, 0x2c, 0xf5, 0x1f, 0xcc, 0x85,
	0x71, 0x3d, 0x26, 0x74, 0x9c, 0x13, 0x7d, 0x7e, 0x66, 0xf2, 0x9e, 0x02, 0xa1, 0x53, 0x15, 0x4f,
	0x51, 0x20, 0xd5, 0x39, 0x1a, 0x67, 0x99, 0x41, 0xc7, 0xc3, 0xa6, 0xc4, 0xbc, 0x38, 0x8c, 0xaa,
	0x81, 0x12, 0xdd, 0x17, 0xb7, 0xef, 0x2a, 0x80, 0x9d, 0x50, 0xdf, 0xcf, 0x89, 0xc8, 0x91, 0x1b,
	0xbb, 0x73, 0xf8, 0x14, 0x61, 0xc2, 0x45, 0xc5, 0x55, 0xfc, 0x8e, 0xe9, 0x8a, 0x46, 0xdb, 0x4e,
	0x05, 0xc1, 0x64, 0xd1, 0xe0, 0x70, 0x16, 0xf9, 0xb6, 0x36, 0x44, 0x8f, 0x0c, 0x29, 0xd3, 0x0e,
	0x6f, 0x7c, 0xd7, 0x4a, 0xff, 0x75, 0x6c, 0x11, 0x10, 0x77, 0x3b, 0x98, 0xba, 0x69, 0x5b, 0xa3,
	0x6a, 0x72, 0x94, 0xd6, 0xd4, 0x22, 0x08, 0x86, 0x31, 0x47, 0xbe, 0x87, 0x63, 0x34, 0x52, 0x3f,
	0x68, 0xf6, 0x0f, 0xbf, 0xeb, 0xc0, 0xce, 0x24, 0xa5, 0x9a, 0x90, 0xed, 0x19, 0xb8, 0xb5, 0x96,
	0xfa, 0x88, 0x6e, 0xfb, 0x84, 0x23, 0x5d, 0xcd, 0xee, 0x92, 0x58, 0x4c, 0x0b, 0xf7, 0x0a, 0xb1,
	0xda, 0x35, 0x5f, 0x9b, 0xc9, 0xa9, 0xe7, 0x07, 0x1d, 0x18, 0xf3, 0xe3, 0xf1, 0xf4, 0xca, 0xb0,
	0x6b, 0x30, 0xec, 0x4b, 0x48, 0x1c, 0xad, 0xe2, 0x21, 0x1e, 0xa2, 0xbd, 0x5a, 0xd8, 0x43, 0x7a,
]
const SELECT: Array = [
	[17, 11, 0, 10, 12, 6, 8, 4],
	[3, 8, 11, 16, 4, 6, 9, 19],
	[9, 14, 17, 18, 11, 10, 12, 2],
	[0, 2, 1, 4, 18, 10, 12, 8],
	[17, 19, 16, 7, 12, 8, 2, 9],
	[16, 3, 1, 8, 18, 4, 7, 6],
	[19, 6, 10, 17, 3, 16, 8, 9],
	[17, 7, 18, 16, 12, 2, 11, 0],
	[6, 2, 12, 1, 8, 14, 0, 16],
	[19, 16, 11, 8, 17, 3, 6, 14],
	[18, 12, 2, 7, 10, 11, 1, 14],
	[8, 0, 14, 2, 7, 11, 12, 17],
	[9, 3, 2, 0, 11, 8, 14, 10],
	[10, 11, 12, 16, 19, 7, 17, 8],
	[19, 8, 6, 1, 17, 9, 14, 10],
	[9, 7, 17, 12, 19, 10, 1, 11],
]


## A name as the 8-byte font string the codes carry: ASCII, space padded.
static func name_bytes(name: String) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(NAME_LEN)
	out.fill(0x20)
	var raw: PackedByteArray = name.to_ascii_buffer()
	for i: int in mini(raw.size(), NAME_LEN):
		out[i] = raw[i]
	return out


## `mMpswd_make_password`: the 28-character code.
static func make(type: int, hit_rate: int, str0: PackedByteArray, str1: PackedByteArray, item: int,
		npc_type: int = 0, npc_code: int = 0) -> String:
	var buf: PackedByteArray = _passcode(type, hit_rate, str0, str1, item, npc_type, npc_code)
	_substitution(buf)
	_transposition(buf, 1, 0)
	_bit_shuffle(buf, 0)
	_rsa(buf)
	_bit_mix(buf)
	_bit_shuffle(buf, 1)
	_transposition(buf, 0, 1)
	var out := ""
	for six: int in _to_6bits(buf):
		out += ALPHABET[six]
	return out


## `mMpswd_decode_code` + `mMpswd_password`: the fields, or `{}` when a character is not in
## the alphabet. `0` and `1` read as `O` and `l` (`mMpswd_adjust_letter`).
static func decode(code: String) -> Dictionary:
	var text: String = code.replace("\n", "")
	if text.length() != STR_LEN:
		return {}
	var six := PackedByteArray()
	for ch: String in text:
		if ch == "0":
			ch = "O"
		elif ch == "1":
			ch = "l"
		var v: int = ALPHABET.find(ch)
		if v < 0:
			return {}
		six.append(v)
	var buf: PackedByteArray = _to_8bits(six)
	_transposition(buf, 1, 1)
	_unshuffle(buf, 1)
	_unmix(buf)
	_unrsa(buf)
	_unshuffle(buf, 0)
	_transposition(buf, 0, 0)
	_unsubstitution(buf)
	return fields(buf)


static func fields(buf: PackedByteArray) -> Dictionary:
	var b0: int = buf[0]
	var out := {
		"checksum": (b0 >> 3) & 3,
		"str0": buf.slice(2, 10),
		"str1": buf.slice(10, 18),
		"item": (buf[18] << 8) + buf[19],
		"type": (b0 >> 5) & 7,
		"hit_rate": (b0 >> 1) & 3,
		"npc_type": -1,
		"npc_code": -1,
	}
	match int(out["type"]):
		Type.POPULAR, Type.CARD_E:
			out["npc_type"] = b0 & 1
			out["npc_code"] = buf[1]
		Type.MAGAZINE:
			out["hit_rate"] = ((b0 >> 1) & 3) | ((b0 & 1) << 2)
	return out


## `mMpswd_password_zuru_check`: false when the checksum holds (not tampered with).
static func tampered(f: Dictionary) -> bool:
	if f.is_empty() or int(f["type"]) > Type.CARD_E_MINI:
		return true
	var sum: int = 0
	for b: int in f["str0"]:
		sum += b
	for b: int in f["str1"]:
		sum += b
	sum += int(f["item"]) + int(f["npc_code"])
	return (sum & 3) != int(f["checksum"])


## `mMpswd_check_name`: addressed to this player in this town.
static func for_player(f: Dictionary, player: String, town: String) -> bool:
	return f.get("str0") == name_bytes(player) and f.get("str1") == name_bytes(town)


static func _passcode(type: int, hit_rate: int, str0: PackedByteArray, str1: PackedByteArray, item: int,
		npc_type: int, npc_code: int) -> PackedByteArray:
	match type:
		Type.FAMICOM, Type.USER, Type.CARD_E_MINI:
			hit_rate = 1
			npc_code = 0xFF
		Type.POPULAR:
			hit_rate = 4
		Type.CARD_E:
			pass
		Type.MAGAZINE:
			npc_type = (hit_rate >> 2) & 1
			hit_rate &= 3
			npc_code = 0xFF
		_:
			type = Type.USER
	var p := PackedByteArray()
	p.resize(STR_LEN)
	p[0] = ((type << 5) | (hit_rate << 1) | (npc_type & 1)) & 0xFF
	p[1] = npc_code & 0xFF
	var sum: int = 0
	for i: int in NAME_LEN:
		p[2 + i] = str0[i]
		p[10 + i] = str1[i]
		sum += str0[i] + str1[i]
	p[18] = (item >> 8) & 0xFF
	p[19] = item & 0xFF
	sum += item + npc_code
	p[0] = (p[0] | ((sum & 3) << 3)) & 0xFF
	return p


static func _substitution(p: PackedByteArray) -> void:
	for i: int in DATA_LEN:
		p[i] = SUBST[p[i]]


static func _unsubstitution(p: PackedByteArray) -> void:
	for i: int in DATA_LEN:
		p[i] = SUBST.find(p[i])


## `mMpswd_transposition_cipher`: add (dir 0) or take away (dir 1) a keyed name, skipping
## the key byte.
static func _transposition(p: PackedByteArray, dir: int, table: int) -> void:
	var key_idx: int = 18 if table == 0 else 9
	var names: Array[String] = TRANS0 if table == 0 else TRANS1
	var s: PackedByteArray = names[p[key_idx] & 0xF].to_ascii_buffer()
	var m: int = -1 if dir == 1 else 1
	var j: int = 0
	for i: int in DATA_LEN:
		if i == key_idx:
			continue
		p[i] = (p[i] + s[j] * m) & 0xFF
		j = (j + 1) % s.size()


## The 20 bytes without the key byte, and back.
static func _strip(p: PackedByteArray, key: int) -> PackedByteArray:
	var out: PackedByteArray = p.slice(0, key)
	out.append_array(p.slice(key + 1, DATA_LEN))
	return out


static func _unstrip(p: PackedByteArray, key: int, buf: PackedByteArray) -> void:
	for i: int in key:
		p[i] = buf[i]
	for i: int in range(key, DATA_LEN - 1):
		p[i + 1] = buf[i]


static func _bit_shuffle(p: PackedByteArray, stage: int) -> void:
	var key: int = 13 if stage == 0 else 2
	var count: int = DATA_LEN - 2 if stage == 0 else DATA_LEN - 1
	var buf: PackedByteArray = _strip(p, key)
	var work := PackedByteArray()
	work.resize(DATA_LEN - 1)
	work.fill(0)
	var sel: Array = SELECT[p[key] & 3]
	for i: int in count:
		for bit: int in 8:
			var dst: int = i + int(sel[bit])
			if dst >= count:
				dst -= count
			work[dst] |= ((buf[i] >> bit) & 1) << bit
	if count < DATA_LEN - 1:
		work[DATA_LEN - 2] = buf[DATA_LEN - 2]
	_unstrip(p, key, work)


static func _unshuffle(p: PackedByteArray, stage: int) -> void:
	var key: int = 13 if stage == 0 else 2
	var count: int = DATA_LEN - 2 if stage == 0 else DATA_LEN - 1
	var work: PackedByteArray = _strip(p, key)
	var buf := PackedByteArray()
	buf.resize(DATA_LEN - 1)
	buf.fill(0)
	var sel: Array = SELECT[p[key] & 3]
	for i: int in count:
		for bit: int in 8:
			var src: int = i + int(sel[bit])
			if src >= count:
				src -= count
			buf[i] |= ((work[src] >> bit) & 1) << bit
	if count < DATA_LEN - 1:
		buf[DATA_LEN - 2] = work[DATA_LEN - 2]
	_unstrip(p, key, buf)


static func _rsa_keys(p: PackedByteArray) -> Array:
	var info: int = p[RSA_INFO_IDX]
	var pi: int = info & 3
	var qi: int = (info >> 2) & 3
	if pi == 3:
		pi = (pi ^ qi) & 3
		if pi == 3:
			pi = 0
	if qi == 3:
		qi = (pi + 1) & 3
		if qi == 3:
			qi = 1
	if pi == qi:
		qi = (pi + 1) & 3
		if qi == 3:
			qi = 1
	return [PRIMES[pi], PRIMES[qi], PRIMES[p[RSA_R_IDX]], SELECT[(info >> 4) & 0xF]]


static func _rsa(p: PackedByteArray) -> void:
	var k: Array = _rsa_keys(p)
	var pq: int = int(k[0]) * int(k[1])
	var r: int = k[2]
	var sel: Array = k[3]
	var keysave: int = 0
	for i: int in 8:
		var idx: int = sel[i]
		var b: int = p[idx]
		var c: int = b
		for _n: int in r - 1:
			c = (c * b) % pq
		p[idx] = c & 0xFF
		keysave |= ((c >> 8) & 1) << i
	p[RSA_KEYSAVE_IDX] = keysave


static func _unrsa(p: PackedByteArray) -> void:
	var k: Array = _rsa_keys(p)
	var pq: int = int(k[0]) * int(k[1])
	var phi: int = (int(k[0]) - 1) * (int(k[1]) - 1)
	var r: int = k[2]
	var sel: Array = k[3]
	var d: int = 0
	var n: int = 1
	while true:
		var t: int = n * phi + 1
		if t % r == 0:
			d = t / r
			break
		n += 1
	var keysave: int = p[RSA_KEYSAVE_IDX]
	for i: int in 8:
		var idx: int = sel[i]
		var b: int = p[idx] | (((keysave >> i) & 1) << 8)
		var m: int = b
		for _n: int in d - 1:
			m = (m * b) % pq
		p[idx] = m & 0xFF


static func _bit_reverse(p: PackedByteArray) -> void:
	for i: int in DATA_LEN:
		if i != KEY_IDX:
			p[i] ^= 0xFF


static func _arrange_reverse(p: PackedByteArray) -> void:
	var buf: PackedByteArray = _strip(p, KEY_IDX)
	var rev := PackedByteArray()
	rev.resize(DATA_LEN - 1)
	for i: int in DATA_LEN - 1:
		var b: int = buf[DATA_LEN - 2 - i]
		var r: int = 0
		for bit: int in 8:
			r |= ((b >> bit) & 1) << (7 - bit)
		rev[i] = r
	_unstrip(p, KEY_IDX, rev)


## `mMpswd_bit_shift`: rotate the 20 bytes (without the key byte) left (+) or right (−) by
## `shift` bits.
static func _shift(p: PackedByteArray, shift: int) -> void:
	var n: int = DATA_LEN - 1
	var buf: PackedByteArray = _strip(p, KEY_IDX)
	var total: int = n * 8
	var amount: int = posmod(shift, total)
	if amount == 0:
		return
	var out := PackedByteArray()
	out.resize(n)
	out.fill(0)
	for bit: int in total:
		var src_byte: int = bit / 8
		var v: int = (buf[src_byte] >> (bit % 8)) & 1
		var dst: int = (bit + amount) % total
		out[dst / 8] |= v << (dst % 8)
	_unstrip(p, KEY_IDX, out)


static func _bit_mix(p: PackedByteArray) -> void:
	var code: int = p[BITMIX_IDX] & 0xF
	if code > 12:
		_arrange_reverse(p)
		_bit_reverse(p)
		_shift(p, code * 3)
	elif code > 8:
		_arrange_reverse(p)
		_shift(p, -code * 5)
	elif code > 4:
		_shift(p, -code * 5)
		_bit_reverse(p)
	else:
		_shift(p, code * 3)
		_arrange_reverse(p)


static func _unmix(p: PackedByteArray) -> void:
	var code: int = p[BITMIX_IDX] & 0xF
	if code > 12:
		_shift(p, -code * 3)
		_bit_reverse(p)
		_arrange_reverse(p)
	elif code > 8:
		_shift(p, code * 5)
		_arrange_reverse(p)
	elif code > 4:
		_bit_reverse(p)
		_shift(p, code * 5)
	else:
		_arrange_reverse(p)
		_shift(p, -code * 3)


## `mMpswd_chg_6bits_code`: 21 bytes, least significant bit first, as 28 six-bit values.
static func _to_6bits(p: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(STR_LEN)
	out.fill(0)
	for bit: int in STR_LEN * 6:
		var v: int = (p[bit / 8] >> (bit % 8)) & 1
		out[bit / 6] |= v << (bit % 6)
	return out


static func _to_8bits(six: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(STR_LEN)
	out.fill(0)
	for bit: int in DATA_LEN * 8:
		var v: int = (six[bit / 6] >> (bit % 6)) & 1
		out[bit / 8] |= v << (bit % 8)
	return out
