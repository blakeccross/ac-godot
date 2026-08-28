# Agent instructions

Godot 4.6 Forward+ project. GDScript only. Inspired by Animal Crossing (GameCube); not a port and not Nintendo IP.

Read these before changing gameplay or adding features:

- [docs/architecture.md](docs/architecture.md)
- [docs/conventions.md](docs/conventions.md)
- [docs/scope.md](docs/scope.md)
- [docs/decomp-mapping.md](docs/decomp-mapping.md)
- [docs/decomp_notes/](docs/decomp_notes/) — per-system decomp research before implementing that system

## Non-negotiables

- Use [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp) as a **behavioral reference**, never as architecture to copy. Do not mechanically translate C into GDScript. Do not commit the decomp or original assets.
- Data = `Resource` classes + `.tres`. Presentation = scenes. Behavior = systems. Prefer composition over inheritance.
- Placeholders until the system works. Do not convert original art.
- Features must earn their place. The decomp containing a system is not a reason to build it.
- Each phase should leave something playable.

## Git

Commits use the user's git identity only. Do **not** add `Co-authored-by`, `Made-with`, or any other trailer for Cursor, the agent, or any AI. Do not pass `--trailer` flags that attribute the agent. Do not change git config.
