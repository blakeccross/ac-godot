from __future__ import annotations

import struct
from pathlib import Path

R_PPC_ADDR32 = 1
R_DOLPHIN_NOP = 201
R_DOLPHIN_SECTION = 202
R_DOLPHIN_END = 203

# Fallback if a stripped REL has no section table we can read.
GAFE01_DATA_FILE_OFFSET = 0x2DD340
DATA_SECTION = 5


class RelData:
    """GameCube REL with self-relocations applied so .data pointers are .data offsets."""

    def __init__(self, path: Path) -> None:
        self.path = path
        raw = bytearray(path.read_bytes())
        nsec = struct.unpack_from(">I", raw, 12)[0]
        sec_off = struct.unpack_from(">I", raw, 16)[0]
        self.sections: list[tuple[int, int]] = []
        for i in range(nsec):
            off, size = struct.unpack_from(">II", raw, sec_off + i * 8)
            self.sections.append((off & ~3, size))
        if len(self.sections) > DATA_SECTION and self.sections[DATA_SECTION][1]:
            self.data_file_offset = self.sections[DATA_SECTION][0]
        else:
            self.data_file_offset = GAFE01_DATA_FILE_OFFSET
        self._apply_self_relocs(raw)
        self.data = bytes(raw)

    def slice_at(self, data_address: int, size: int) -> bytes:
        start = self.data_file_offset + data_address
        end = start + size
        if end > len(self.data) or start < 0:
            raise ValueError(f"REL slice out of range: addr=0x{data_address:X} size={size}")
        return self.data[start:end]

    def u32_at(self, data_address: int) -> int:
        blob = self.slice_at(data_address, 4)
        return int.from_bytes(blob, "big")

    def _apply_self_relocs(self, raw: bytearray) -> None:
        if len(raw) < 0x30:
            return
        imp_off, imp_sz = struct.unpack_from(">II", raw, 0x28)
        self_off = None
        for i in range(0, imp_sz, 8):
            module_id, rel_off = struct.unpack_from(">II", raw, imp_off + i)
            if module_id == 1:
                self_off = rel_off
                break
        if self_off is None:
            return
        bases = [0] * len(self.sections)
        for i, (off, _size) in enumerate(self.sections):
            bases[i] = 0 if i == DATA_SECTION else (0x80000000 + off)
        pos = self_off
        section = 0
        offset = 0
        while pos + 8 <= len(raw):
            delta, typ, sec, addend = struct.unpack_from(">HBBI", raw, pos)
            pos += 8
            if typ == R_DOLPHIN_END:
                break
            if typ == R_DOLPHIN_SECTION:
                section = sec
                offset = 0
                continue
            offset += delta
            if typ == R_DOLPHIN_NOP:
                continue
            if typ != R_PPC_ADDR32:
                continue
            file_off = self.sections[section][0] + offset
            if 0 <= file_off + 4 <= len(raw):
                value = (bases[sec] + addend) & 0xFFFFFFFF
                struct.pack_into(">I", raw, file_off, value)
