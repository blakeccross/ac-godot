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

- **15 slots, no stacking**, one id per slot.
- Wallet separate from items.
- Equip a tool from a pocket (or a dedicated equipment slot).
- Full pockets → cannot pick up.
- Present/quest items should not be usable as normal tools (even if we only implement “present” later).
- Bells as integer currency.

## Simplify

- Skip mail inventory, catalog orders, foreign maps, original designs.
- Skip inventory paper shirt and 3D player preview in the menu.
- Skip fish/insect **pages** until those systems exist; a list or bitset is enough.
- Loan can wait until house upgrade exists.
- No 2-bit pack; store condition as an enum on a Godot slot resource.

## Ignore

- Lotto ticket expiry fields next to pockets.
- Delivery quest arrays sized to 15 and errand quests (5) until quests are in scope.
- Aircheck bitfields, e-Card letter tracking, mother mail.
- Destiny/fortune, sunburn, museum record blob as inventory features.
- GBA / e-Reader item dump (`mSP_SelectRandomItemToAGB`).
