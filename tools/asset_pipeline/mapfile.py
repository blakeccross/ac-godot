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


def index_by_name(symbols: list[MapSymbol]) -> dict[str, MapSymbol]:
    """First match wins (same as a linear scan). A later non-dot overwrites a dot."""
    out: dict[str, MapSymbol] = {}
    for symbol in symbols:
        existing = out.get(symbol.name)
        if existing is None or (existing.name.startswith(".") and not symbol.name.startswith(".")):
            out[symbol.name] = symbol
    return out


def index_by_address(symbols: list[MapSymbol]) -> dict[int, MapSymbol]:
    out: dict[int, MapSymbol] = {}
    for symbol in symbols:
        existing = out.get(symbol.address)
        if existing is None or (existing.name.startswith(".") and not symbol.name.startswith(".")):
            out[symbol.address] = symbol
    return out


def dataobject_symbols(symbols: list[MapSymbol]) -> list[MapSymbol]:
    return [s for s in symbols if s.obj == "dataobject.obj" and not s.name.startswith(".")]


def find_symbol(
    symbols: list[MapSymbol],
    name: str,
    by_name: dict[str, MapSymbol] | None = None,
) -> MapSymbol:
    if by_name is not None:
        try:
            return by_name[name]
        except KeyError:
            raise KeyError(name) from None
    for symbol in symbols:
        if symbol.name == name:
            return symbol
    raise KeyError(name)


def group_prefix(symbols: list[MapSymbol], prefix: str) -> list[MapSymbol]:
    return [s for s in symbols if s.name.startswith(prefix)]
