# Inventory (pockets, wallet, equipment)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not copy `Private_c` layout.

**Read before implementing:** `Inventory` on `Game`, pickup/drop, shop pay, tool equip.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_private.h`, `src/game/m_private.c` | Save-side pockets, wallet, loan, equipment, mail |
| `include/m_inventory_ovl.h` | 5×3 pocket UI, fish/insect collection pages |
| `include/m_hand_ovl.h` | Dragging a slot |
| `include/m_tag_ovl.h` | Verbs per slot |
| `include/m_name_table.h` | Item id ranges (`ITEM_IS_FISH`, `ITEM_IS_INSECT`, `ITEM_IS_FTR`) |
| `include/m_submenu.h` | Opening the overlay |

Key symbols: `mPr_POCKETS_SLOT_COUNT` **15**, `pockets[]`, `item_conditions` (2 bits per slot), `wallet`, `loan`, `equipment`. Lookups: `mPr_GetPossessionItemIdx`, `mPr_GetPossessionItemIdxWithCond`.

## What does the original system do?

Pockets are **15 independent slots**. There is **no stacking**. Each slot holds one `mActor_name_t` (item id) or empty.

Each slot has a 2-bit **condition** packed into `item_conditions`:

- `mPr_ITEM_COND_NORMAL`
- `mPr_ITEM_COND_PRESENT` (wrapped; cannot use until opened)
- `mPr_ITEM_COND_QUEST` (delivery/errand; restricted verbs)

Wallet is a separate `u32` (Bells). House **loan** is also here, not in the shop. Equipped tool/item is one extra id (`equipment`), not one of the 15.

Letters are a parallel inventory: **10** `Mail_c` slots (`mPr_INVENTORY_MAIL_COUNT`). Collection pages for fish/insects are UI over a bitfield in private/museum data, not extra pocket slots.

The overlay can show eat / catch animations (`mIV_ANIM_*`) when using food or displaying a catch.

## Important states

- 15 item ids + 15 conditions.
- Wallet and loan.
- Equipment id.
- Submenu page: inventory vs fish encyclopedia vs insect encyclopedia (`mIV_PAGE_*`).
- Hand: which table/slot is held (`hold_tbl`, `hold_idx`) and whether it will return on cancel.
- Background shirt for the inventory paper (`backgound_texture`).

## Inputs

- Pick up from field / receive from NPC or shop.
- Player “use / drop / bury / plant / present / sell / give / eat” from tags.
- Payments (`mSP_money_check`, loan payments).
- Quest system marking a slot as quest/present.

## Outputs / events

- Slot filled or emptied; refuse if no empty slot.
- Wallet up/down; cannot go negative on purchases (`mSP_money_check`).
- Equipment change (tools).
- Submenu close may trigger player give/scoop-put-in if the hand still holds an item (`mPlib_request_main_give_from_submenu`).
- Collection bit set when a new fish/bug is registered (museum / encyclopedia).

## Interacts with

- **Player** — pickup, refuse, equip, eat.
- **Interaction** — tags and hand.
- **Shops** — sell list, prices, wallet.
- **Villagers / dialogue** — gifts, deliveries.
- **Furniture** — storage drawers hold extra items (house save, not pockets).
- **Fishing / bugs** — catch goes to first empty slot.
- **Save** — entire `Private_c.inventory` block.

## Reproduce

- **15 slots** in a **5×3** grid (`mIV_ITEM_COLUMNS` / `mIV_ITEM_ROWS`).
- Wallet separate from items (`disp_money`).
- Equip a tool from a pocket (or a dedicated equipment slot).
- Full pockets → cannot pick up.
- Present/quest items should not be usable as normal tools (even if we only implement “present” later).
- Bells as integer currency.
- Tag verbs from `m_tag_ovl` (field default): Use/Eat, Drop, Equip; hand move between slots (`m_hand_ovl`).

## Simplify

- Skip mail inventory, catalog orders, foreign maps, original designs.
- Skip inventory paper shirt and 3D player preview in the menu.
- Skip fish/insect **pages** until those systems exist; a list or bitset is enough.
- Loan can wait until house upgrade exists.
- No 2-bit pack; store condition as an enum on `InventoryItem`.
- **Stacking** is allowed via `ItemData.max_stack` (GC had none; tools stay at 1).

## Ignore

- Lotto ticket expiry fields next to pockets.
- Delivery quest arrays sized to 15 and errand quests (5) until quests are in scope.
- Aircheck bitfields, e-Card letter tracking, mother mail.
- Destiny/fortune, sunburn, museum record blob as inventory features.
- GBA / e-Reader item dump (`mSP_SelectRandomItemToAGB`).

## Graphics (UI chrome)

Drawn by `m_inventory_ovl.c` (`mIV_set_base_frame_dl` / `mIV_set_normal_frame_dl`). Models live in `src/data/model/inv_mwin*.c` (plus `inv_sakana.c`, `inv_mushi.c`, `inv_item.c`, `inv_mark.c`, hand skeleton). Texture bins are listed in decomp `config/GAFU01_00/config.yml` under `assets/inv_mwin_*`.

**Local extract** (gitignored PNGs, Nintendo IP — reference only):

```sh
python3 tools/build_assets.py --step convert --kind inventory-ui
```

Writes `assets/generated/ui/inventory/` (and work-root staging). Labels use in-game prim tints; slot ring gets blue/red env previews. Default paper is a copy of `shirt_226` when that shirt PNG exists. Fish/insect **encyclopedia icons** (`inv_mwin_01funa_tex`, etc.) already land in `assets/generated/textures/rel/`.

### Paper / fill (polka-dot background)

Not a fixed inventory texture. At draw time the inventory page loads the player’s **background shirt**:

- Save field: `Private_c.backgound_texture` (item id; default `ITM_CLOTH226`)
- Runtime: `mSM_Get_ground_tex_p` / `mSM_Get_ground_pallet_p` → CI4 **32×32** + 16-entry TLUT via `mPlib_Load_PlayerTexAndPallet`
- Bound with `GX_REPEAT` on the scrollable fill under `inv_mwin_model`

That is the cream paper with white dots in the screenshot.

### Window shell (`inv_mwin.c` → `inv_mwin_model`)

Border / blob pieces (CI4 + palettes), assembled as `inv_mwin_w1T_model` … `w13`:

| Symbol | Format / size | Role |
| --- | --- | --- |
| `inv_mwin_w1_tex_rgb_ci4` (+ `_pal`) | CI4 32×32 | Corner / edge tile |
| `inv_mwin_w2_tex_rgb_ci4` (+ `_pal`) | CI4 32×64 | Side edge |
| `inv_mwin_w3_tex_rgb_ci4` (+ `_pal`) | CI4 64×32 | Top/bottom edge |
| `inv_mwin_w4_tex_rgb_ci4` (+ `_pal`) | CI4 32×32 | Corner |
| `inv_mwin_w5_tex_rgb_ci4` | CI4 16×16 | Small fill (`w13`) |
| `inv_mwin_w6_tex_rgb_ci4` (+ `_pal`) | CI4 32×64 | Side edge |
| `originl` / `original2` | I4 32×32 / 32×64 | Inner opaque panels |
| `inv_mwin_3Dma_tex` | I4 64×64 | Circular **player preview** frame |
| `inv_mwin_items_tex` | I4 64×16 | **“Items”** label (prim tint ~120,120,225) |
| `inv_mwin_letters_tex` | I4 64×16 | **“Letters”** label (prim ~195,80,80) |
| `inv_mwin_bells_tex` | I4 64×16 | **“Bells”** label (prim ~70,160,190) |
| `inv_mwin_suujiwaku1_tex` / `suujiwaku2_tex` | IA8 16×32 | Wallet / number box |
| `inv_mwin_shirushi4_tex`, `inv_original_shirushi_tex`, `inv_original_shirushi3_tex` | I4 / IA8 | Decorative marks on the paper |
| `inv_mwin_sen_tex` / `sen2_tex` | I4 16×16 | Soft dividers (`kuni` / `kuni2`) |

Render setup: `inv_mwin_mode` (2-cycle, texture edge).

### Slot rings

One shared ring texture for every pocket and mail slot:

- `inv_mwin_nwaku_tex` — **IA8 32×32** (“inner frame”)
- Item slots: `inv_mwin_1bT_model` … `15bT_model` (15 quads)
- Letter slots: `inv_mwin_1aT_model` … `10aT_model` (10 quads)
- Tint via `gDPSetEnvColor`: items ~`(100,100,255)` / `(120,140,255)`; mail ~`(255,60,60)` / `(255,90,90)` (selectable vs not)

Mode: `inv_mwin_item_frame_mode`.

### Side tabs / tool icons (`inv_mwin_g.c`)

CI4 + palette pairs used as the right-edge page icons (fish / face / butterfly in the screenshot; also scoop / axe variants):

- `inv_mwin_gturi_tex` + `inv_mwin_gturi_pal` — fishing (sakana page)
- `inv_mwin_gmushi_tex` + `inv_mwin_gmushi_pal` — insect (mushi page)
- `inv_mwin_gscoop_tex` + `inv_mwin_gscoop_pal` — scoop
- `inv_mwin_gono_tex` + `inv_mwin_gono_pal` — axe / “ono”

Fish / insect **full page** shells: `inv_sakana_model` / `inv_mushi_model` (+ `*_part_model`, `*_scroll_mode`). Per-species icons: `inv_mwin_01funa_tex`, `inv_mwin_01monshiro_tex`, … in `inv_mwin2.c` / `inv_mwin3.c` / etc.

### Items in slots + hand cursor

- Slot contents: 3D item models under `inv_item_mode` / `inv_item_model` (not 2D icon atlas for pockets).
- Cursor: animated skinned hand `cKF_bs_r_hnd` (`src/data/model/cKF_bs_r_hnd.c`), driven by `m_hand_ovl.c`.
- Selection mark: `inv_win_mark_tex` (IA8 16×16) in `inv_mark.c`.

### Item icon sprites (category art, not the window)

Separate `inv_mwin_*.c` files hold CI4 icons for categories (axe `ono`, money bag `okane`, present `pbox`, fossils, etc.). Those are for item presentation / encyclopedia-style art, not the paper chrome.
