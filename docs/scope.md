# Scope

Features must earn their place. The decomp containing a system is not a reason to build it.

## In scope (core feel)

Build **one good version** of each, then stop until the game needs more:

- Real-time clock, day/night, seasons
- A walkable outdoor acre and a simple indoor space
- Player move, talk, pick up, use a tool
- One tree (grow, shake, fruit, plant) rather than every tree
- One villager with a daily schedule rather than every personality
- One shop with buy/sell rather than every original store (Nook + Able Sisters are the two in town)
- Inventory, a small item catalog, and a simple economy
- Save/load of the systems above

## Out of scope until earned

Do not start these just because they exist in the original:

- e-Reader / Game Boy Advance connectivity
- Famicom / NES minigames
- Island boat logistics and island-exclusive systems
- Museum completion as a content treadmill (a single donation loop can wait)
- Town tune editor, custom designs, pattern tool
- Multiplayer / Dream Suite–style visits
- Every holiday, every shop, every villager species
- Faithful recreation of every submenu, debug overlay, or unused leftover

When a later phase needs one of these, add a short justification in the relevant milestone — gameplay value, not completeness.

## Content policy

Villager display names (Filbert, Rosie, …) are allowed. Do not commit Nintendo assets, music, dialogue banks, or decomp source. A local disc may be converted into `assets/generated/` (gitignored) via the pipeline in [asset_pipeline.md](asset_pipeline.md). Hand-authored recreation art lives in `assets/custom/`.
