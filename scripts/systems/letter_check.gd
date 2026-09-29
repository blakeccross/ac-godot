class_name LetterCheck
extends RefCounted

## How well-written a letter is (`mMck_check_key_hit_nes`, `m_mail_check_ovl.c`), scored on
## the game's 192-byte body in its own character codes. `mNpc_CheckNormalMail_nes`: 100 or
## more is a good letter, under 50 a bad one, in between neither.
##
## The syllable tables come from the disc (`--kind dialogue` → `mail_check.json`), each with
## its full US scan range (the tables lost their 0x7F terminators, so a lookup runs on into
## the next tables). Without the file every syllable lookup misses.

const PATH := "res://assets/generated/dialogue/mail_check.json"
const BODY_LEN := 192
const SPACE := 32
const EXCLAMATION := 33
const COMMA := 44
const PERIOD := 46
const QUESTION := 63
const INTERPUNCT := 133
const NEW_LINE := 205
const UPPER_A := 65
const LOWER_A := 97
const CONTROL := 127

enum Rank { BAD, OK, NONE }

static var _tables: Dictionary = {}
static var _encode: Dictionary = {}
static var _loaded: bool = false


static func has_tables() -> bool:
	_ensure()
	return not _tables.is_empty()


## `mNpc_CheckNormalMail_nes`.
static func rank(body: String) -> Rank:
	var points: int = score(encode(body))
	if points >= 100:
		return Rank.OK
	if points < 50:
		return Rank.BAD
	return Rank.NONE


## The body as the game stores it: character codes, `CHAR_NEW_LINE` for breaks, space-padded
## to `MAIL_BODY_LEN`. Characters the font lacks become spaces.
static func encode(body: String) -> PackedByteArray:
	_ensure()
	var out := PackedByteArray()
	out.resize(BODY_LEN)
	out.fill(SPACE)
	var n: int = 0
	for ch: String in body:
		if n >= BODY_LEN:
			break
		if ch == "\n":
			out[n] = NEW_LINE
		elif _encode.has(ch):
			out[n] = int(_encode[ch])
		elif ch.unicode_at(0) < 128:
			out[n] = ch.unicode_at(0)
		else:
			out[n] = SPACE
		n += 1
	return out


## `mMck_check_key_hit_nes`: the seven checks summed.
static func score(s: PackedByteArray) -> int:
	_ensure()
	var length: int = _strlen_new(s, BODY_LEN)
	return (
		_type_a(s, length) + _type_b(s) + _type_c(s, length) + _type_d(s, length)
		+ _type_e(s, length) + _type_f(s, length) + _type_g(s, length)
	)


static func _at(s: PackedByteArray, i: int) -> int:
	return s[i] if i >= 0 and i < s.size() else SPACE


## `mMck_strlen_new`: length without trailing spaces.
static func _strlen_new(s: PackedByteArray, n: int) -> int:
	var length: int = n
	while length > 0 and _at(s, length - 1) == SPACE:
		length -= 1
	return length


## `mMck_cmp_sep`.
static func _is_sep(c: int) -> bool:
	return c == SPACE or c == COMMA or c == QUESTION or c == EXCLAMATION or c == PERIOD or c == INTERPUNCT or c == NEW_LINE


## `mMck_cmp_sep_nes`.
static func _is_sep_nes(c: int) -> bool:
	return c == PERIOD or c == QUESTION or c == EXCLAMATION


static func _is_alpha(c: int, upper: bool) -> bool:
	var base: int = UPPER_A if upper else LOWER_A
	return c >= base and c <= base + 25


## `mMck_search_sep`: next separator that isn't followed by another. `len` is a u8.
static func _search_sep(s: PackedByteArray, p: int, count: int) -> int:
	var n: int = count & 0xFF
	while n != 0:
		n -= 1
		if _is_sep(_at(s, p)) and not _is_sep(_at(s, p + 1)):
			break
		p += 1
	return p


## `mMck_cmp_key`: does the word starting at `p` open with a known three-letter syllable?
static func _cmp_key(s: PackedByteArray, p: int) -> bool:
	var c0: int = _at(s, p)
	var c1: int = _at(s, p + 1)
	var c2: int = _at(s, p + 2)
	for i: int in 26:
		if c0 != LOWER_A + i and c0 != UPPER_A + i:
			continue
		var table: Array = _tables.get(char(LOWER_A + i), []) as Array
		var k: int = 0
		while k + 1 < table.size() and int(table[k]) != CONTROL:
			if c1 == int(table[k]) and c2 == int(table[k + 1]):
				return true
			k += 2
	return false


## `mMck_check_key_get_hit_count`.
static func _hit_count(s: PackedByteArray) -> int:
	var length: int = _strlen_new(s, BODY_LEN - 3)
	if length <= 0:
		return 0
	var i: int = 0
	var hits: int = 0
	var p: int = 0
	while i <= length:
		var sep: int = p
		if _cmp_key(s, sep):
			hits += 1
		p = _search_sep(s, sep, length - i) + 1
		i += p - sep
	return hits


## Sentences open with a capital within three characters (±10 each), +20 if the letter
## ends on . ? ! (`mMck_check_key_type_A` / `mMck_check_eof`).
static func _type_a(s: PackedByteArray, pos: int) -> int:
	var points: int = 0
	if pos < BODY_LEN and pos > 0 and _is_sep_nes(_at(s, pos - 1)):
		points = 20
	var p: int = 0
	while pos > 3:
		while not _is_sep_nes(_at(s, p)) and pos > 3:
			p += 1
			pos -= 1
		if pos > 3:
			var sz: int = 3
			p += 1
			pos -= 1
			while true:
				if _is_alpha(_at(s, p), true):
					break
				sz -= 1
				p += 1
				pos -= 1
				if sz <= 0:
					break
			points += -10 if sz == 0 else 10
	return points


## Three points per recognised syllable (`mMck_check_key_type_B`).
static func _type_b(s: PackedByteArray) -> int:
	return _hit_count(s) * 3


## The first character is a capital: +20, else −10 (`mMck_check_key_type_C`).
static func _type_c(s: PackedByteArray, length: int) -> int:
	for i: int in length:
		if _at(s, i) != SPACE:
			return 20 if _is_alpha(_at(s, i), true) else -10
	return 0


## The same letter three times running: −50 (`mMck_check_key_type_D`).
static func _type_d(s: PackedByteArray, length: int) -> int:
	var p: int = 0
	var n: int = length
	while n > 2:
		var c: int = _at(s, p)
		if (_is_alpha(c, false) or _is_alpha(c, true)) and c == _at(s, p + 1) and c == _at(s, p + 2):
			return -50
		n -= 1
		p += 1
	return 0


## Spaces make up at least 20 % of the rest: +20, else −20 (`mMck_check_key_type_E`).
static func _type_e(s: PackedByteArray, length: int) -> int:
	var spaces: int = 0
	for i: int in length:
		if _at(s, i) == SPACE:
			spaces += 1
	var rest: int = length - spaces
	if rest > 0 and (spaces * 100) / rest >= 20:
		return 20
	return -20


## A run-on of 75 characters between . ? !: −150 (`mMck_check_key_type_F`).
static func _type_f(s: PackedByteArray, length: int) -> int:
	var p: int = 0
	var n: int = length
	while n > 76:
		if _is_sep_nes(_at(s, p)):
			var sentence: int = 0
			n -= 1
			p += 1
			while not _is_sep_nes(_at(s, p)):
				sentence += 1
				if sentence >= 75:
					break
				p += 1
				n -= 1
			if sentence >= 75:
				return -150
		n -= 1
		p += 1
	return 0


## −20 for every 32-character block with no space (`mMck_check_key_type_G`).
static func _type_g(s: PackedByteArray, length: int) -> int:
	var r_len: int = 32
	var no_space: bool = true
	var points: int = 0
	for i: int in length:
		r_len -= 1
		if no_space:
			if _at(s, i) == SPACE:
				no_space = false
			elif r_len == 0:
				points -= 20
		if r_len == 0:
			r_len = 32
			no_space = true
	return points


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_tables = (parsed as Dictionary).get("tables", {}) as Dictionary
	var cmap: Array = (parsed as Dictionary).get("char_map", []) as Array
	for i: int in cmap.size():
		var ch: String = str(cmap[i])
		if ch.length() == 1 and not _encode.has(ch) and i != CONTROL:
			_encode[ch] = i
