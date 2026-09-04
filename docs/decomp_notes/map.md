# Town map (submenu)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only.

**Godot:** `TownMap` (`scripts/systems/town_map.gd`) + `scenes/ui/map_overlay.tscn`. Acre tiles and chrome come from the local disc via `--kind map-ui` (gitignored under `assets/generated/ui/map/`).

**Read before implementing:** FG 5×6 acre grid, `kan_tizu_*` tile ↔ `mFM_BLOCK_TYPE_*`, cursor / here-mark, building labels.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_map_ovl.h`, `src/game/m_map_ovl.c` | Map overlay state, `l_map_texture` / `l_map_pal`, cursor, labels |
| `src/data/submenu/map/kan_tizu.c`, `kan_tizu2.c` | Acre tile CI4 blobs |
| `src/data/model/kan_tizu.c` | 32×32 CI4 quad (`kan_tizu_model`) |
| `src/data/model/kan_win.c`, `kan_hyouji*.c`, `kan_eki.c`, … | Window chrome, icons, cursor |
| `include/m_submenu.h` | X opens map (`mSM_OVL_MAP`) |

## What the original system does

Press **X** to open the town map over the field. The playable FG acres (**5×6**, letters A–F × numbers 1–5) each draw one **CI4 32×32** tile from `kan_tizu_*_TA_tex_txt`, tinted with one of two TLUTs (`kan_tizu1_pal` / `kan_tizu2_pal`). Beach / station / shop acres use palette 1; grass / river / cliff use palette 0.

Cursor starts on the player’s acre (`mFI_Wpos2BlockNum` − 1) and moves with the stick. A pulsing magenta→pink frame (`kan_win_cursor_tex`, prim green channel anim) marks the selection. A “you are here” mark (`kan_win_genzai` / play tex) sits on the player acre. Selecting a building acre shows its label (Shop, Police Station, …) or villager / player house names.

## Reproduce

- **5×6** FG grid from `WorldData.acre_types` (skip border acres).
- Original `kan_tizu_*` tiles + pals (pipeline), not invented colours.
- Cursor on player acre; move with arrows / stick.
- Acre code (`C-3`) + building label for the selection.
- Open with **X** (and **M**); close with Esc / X again.
- Godot compact acre ids (`T_MUSEUM` 80, `T_PORT` 86, ocean cliffs 76/77) remap to decomp `mFM_BLOCK_TYPE_*` before texture lookup.

## Local extract

```sh
python3 tools/build_assets.py --step convert --kind map-ui
```

Writes `assets/generated/ui/map/tiles/{stem}_p{0,1}.png`, `chrome/*.png`, and `catalog.json`.

## Simplify

- No villager house layer icons / name list panel beyond one label string.
- No bridge overlay from a separate `Save.bridge` bit — acre types already store bridge variants.
- No submenu slide-in / prerender heap.

## Ignore

- Foreign island map, GBA map dump, debug map select.
