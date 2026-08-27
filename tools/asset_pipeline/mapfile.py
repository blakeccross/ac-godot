from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterator


@dataclass(frozen=True)
class MapSymbol:
    address: int
    size: int
    align: int
    name: str
    obj: str

    @property
    def end(self) -> int:
        return self.address + self.size


def parse_map(path: Path) -> list[MapSymbol]:
    symbols: list[MapSymbol] = []
    for line in path.read_text(errors="replace").splitlines():
        parts = line.split()
        if len(parts) < 6:
            continue
        try:
            address = int(parts[0], 16)
            size = int(parts[1], 16)
            align = int(parts[3])
        except ValueError:
            continue
        name = parts[4]
        obj = parts[5]
        symbols.append(MapSymbol(address, size, align, name, obj))
    symbols.sort(key=lambda s: (s.address, s.name))
    return symbols


def dataobject_symbols(symbols: list[MapSymbol]) -> list[MapSymbol]:
    return [s for s in symbols if s.obj == "dataobject.obj" and not s.name.startswith(".")]


def find_symbol(symbols: list[MapSymbol], name: str) -> MapSymbol:
    for symbol in symbols:
        if symbol.name == name:
            return symbol
    raise KeyError(name)


def group_prefix(symbols: list[MapSymbol], prefix: str) -> list[MapSymbol]:
    return [s for s in symbols if s.name.startswith(prefix)]
