"""Happy Room Academy tables (`m_mark_room_ovl.c`) from the decomp source.

Parses the per-furniture scoring rows (`mMkRm_ftr_info`: series, necessity slot, has
face, lucky, where it comes from, surface), the series table (type and matching
wallpaper / carpet), each wallpaper's and carpet's origin, the points per origin, the
series names and the letter table, resolving the enum names from `m_mark_room.h` and
`m_room_type.h`. Written to the gitignored `assets/generated/items/hra.json` for
`HappyRoomAcademy`.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any


def _enum_values(text: str, prefix: str) -> dict[str, int]:
	"""Every `prefix*` name in the file's enums, by its position (explicit values honoured)."""
	out: dict[str, int] = {}
	for body in re.findall(r"enum\s*\w*\s*\{(.*?)\}", text, re.S):
		value = -1
		for raw in body.split(","):
			line = re.sub(r"//.*|/\*.*?\*/", "", raw, flags=re.S).strip()
			if not line:
				continue
			name, _, expr = line.partition("=")
			name = name.strip()
			if expr.strip():
				try:
					value = int(expr.strip(), 0)
				except ValueError:
					value = out.get(expr.strip(), value + 1)
			else:
				value += 1
			if name.startswith(prefix):
				out[name] = value
	return out


def _array_body(text: str, name: str) -> str:
	head = re.escape(name) + r"(?:\[[^\]]*\])+\s*=\s*\{"
	## A flat list first (it may close on its own line or not), then a list of rows.
	m = re.search(head + r"([^{}]*)\}\s*;", text, re.S) or re.search(head + r"(.*?)\n\};", text, re.S)
	if not m:
		raise ValueError(f"{name} not found")
	return re.sub(r"//[^\n]*|/\*.*?\*/", "", m.group(1), flags=re.S)


def export_hra(decomp: Path, out_dir: Path) -> dict[str, Any]:
	src = (decomp / "src/game/m_mark_room_ovl.c").read_text(encoding="utf-8", errors="replace")
	hdr = (decomp / "include/m_mark_room.h").read_text(encoding="utf-8", errors="replace")
	room = (decomp / "include/m_room_type.h").read_text(encoding="utf-8", errors="replace")
	names = _enum_values(hdr, "mMkRm_") | _enum_values(room, "mRmTp_BIRTH_TYPE_")

	def val(token: str) -> int:
		token = token.strip()
		if token in names:
			return names[token]
		return int(token, 0)

	ftr_rows = []
	for row in re.findall(r"\{([^{}]*)\}", _array_body(src, "mMkRm_ftr_info")):
		fields = [f for f in (x.strip() for x in row.split(",")) if f]
		ftr_rows.append([val(f) for f in fields])

	series = []
	for row in re.findall(r"\{([^{}]*)\}", _array_body(src, "mMkRm_series_info")):
		fields = [f for f in (x.strip() for x in row.split(",")) if f]
		series.append([val(fields[0]), val(fields[2])])

	def flat(name: str) -> list[int]:
		return [val(t) for t in (x.strip() for x in _array_body(src, name).split(",")) if t]

	names_body = _array_body(src, "mMkRm_series_name")
	names_body = re.sub(r"#ifndef BUGFIXES\s*(\"[^\"]*\",)\s*#else\s*\"[^\"]*\",\s*#endif", r"\1", names_body)
	series_names = [s.strip() for s in re.findall(r"\"([^\"]*)\"", names_body)]

	data = {
		"ftr": ftr_rows,
		"series": series,
		"series_names": series_names,
		"birth_points": flat("mMkRm_birth_point_table"),
		"wall_from": flat("mMkRm_wall_from"),
		"floor_from": flat("mMkRm_floor_from"),
		"letter_no": flat("mMkRm_letter_no_table"),
		"birth_my_original": names["mRmTp_BIRTH_TYPE_MY_ORIGINAL"],
	}
	out_dir.mkdir(parents=True, exist_ok=True)
	path = out_dir / "hra.json"
	path.write_text(json.dumps(data, separators=(",", ":")) + "\n", encoding="utf-8")
	return {"ftr": len(ftr_rows), "series": len(series), "path": str(path)}
