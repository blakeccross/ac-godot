# Shops (Nook, hours, stock, economy)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — not every store is in scope.

**Godot:** `ShopBook` (`RefCounted` on `Game`, not an autoload). Nook (`shop0`) buy and sell; Able Sisters (`needlework`) buy-only. Listed price is `ItemData.buy_price` (or `sell_price` if buy is 0). Nook pays fruit/fish/bugs at authored `sell_price`; everything else is listed / 4 (`SELL_BUY_RATIO`). Cranny stock is a tiny authored pool (tools, furniture, wallpaper, carpet, sapling, plants). Able stock is four shirts. Lineup rerolls at 06:00 (`Clock.field_renewed`). Wallet is `Inventory.wallet`. Indoor counters and shelf goods are presentation (`shop_counter`, `shop_stock`); they call `ShopBook`. Hours stay on `InteriorCatalog.is_open_now`.

**Read before implementing:** shop scene, buy/sell, wallet.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_shop.h`, `src/game/m_shop.c` | Shop type, hours, stock lists, sales sums, prices |
| `include/m_kabu_manager.h` | Turnip prices (separate stall) |
| `include/m_post_office.h` | Post office, not Nook |
| `include/m_field_info.h` | Shop room field ids |
| `include/m_tag_ovl.h` | `mTG_TYPE_SELL_ITEM`, `SELL_ALL_ITEM` |
| `include/m_player_lib.h` | Counter give/receive (`recieve_wait`, `give`) |

Key functions: `mSP_ShopOpen`, `mSP_GetShopOpenTime`, `mSP_GetShopCloseTime`, `mSP_GetShopLevel`, `mSP_PlusSales`, `mSP_ItemNo2ItemPrice`, `mSP_SelectRandomItem_New`, `mSP_ExchangeLineUp_InGame`, `mSP_money_check`, `mSP_InitShopSaveData`.

## What does the original system do?

Tom Nook’s shop has **four building types** (`mSP_SHOP_TYPE_ZAKKA` Cranny → conveni → super → department). Upgrades when lifetime **sales sum** crosses 25k / 90k / 240k Bells (`mSP_COMBINI_SUM`, `SUPER_SUM`, `DSUPER_SUM`). Cranny also gates tools: net 3k, rod 8k, axe 12k sales.

Hours (`mSP_GetShopOpenTime` / `CloseTime`):

| Level | Open | Close |
| --- | --- | --- |
| Cranny | 9 | 22 |
| Nook 'n' Go | 7 | 23 |
| Nookway / Nookington’s | 9 | 22 |

Last day of month: open at **10** (lottery). Status: `PRE` (after 6am before open), `OPEN`, `END` (closed), plus renewal/event variants (`PREEVENT`, fukubiki, Halloween).

Stock is up to **39** goods (`mSP_GOODS_COUNT`) drawn from ABC rarity lists, plus event/lottery/present lists. Categories: furniture, paper, cloth, carpet, wallpaper, diary. Daily (or exchange-day) reroll via `mSP_CheckExchangeDay2` / `mSP_ExchangeLineUp_InGame`. A **rare** spotlight item can appear. Lottery has 3 items (`mSP_LOTTERY_ITEM_COUNT`).

Buy: price from `mSP_ItemNo2ItemPrice`, wallet check, remove from shelf, add to pockets, `mSP_PlusSales`. Sell: player tag-sells from pockets at a fraction of price (`mSP_get_sell_price`). Catalog mail-order is a separate 5-slot queue on `Private_c`.

Other buildings (Able Sisters, auction, island shack, museum shop) are different rooms and code paths.

## Important states

- Shop level and real vs displayed level (`mSP_GetRealShopLevel` during renovation).
- `Shop_c` save: goods list, rare item, sales sum, renewal time, visitor flags.
- Open status vs hour + events.
- Tanuki shop mood (`NORMAL`, `EVENT`, `HALLOWEEN`, `FUKUBIKI`).
- Player at counter (give/receive player modes).

## Inputs

- Clock (hour, last day of month, holidays).
- Player buy/sell choices and wallet.
- Sales history.
- Event flags (Halloween stock lists, etc.).

## Outputs / events

- Open/closed (door locked, NPC line).
- Stock list for the room FG / shelves.
- Wallet and pocket changes; sales sum.
- Shop level-up / closed-for-renovation (`mSP_InRenewal`, `mEv_SAVED_RENEWSHOP`).
- Mail flyers (`mSP_ShopItsumoChirashi`).

## Interacts with

- **Time** — hours and 06:00 restock.
- **World** — shop acre and interior field id (shop0–shop3).
- **Inventory / player**.
- **Dialogue** — Nook scripts.
- **Furniture / plants** — goods kinds.
- **Save** — `Shop_c`.

## Reproduce

- **Nook's Cranny and Able Sisters** with open hours, a short stock list, and buy (Nook also sells).
- Prices on `ItemData`; wallet must cover buy.
- Closed outside hours.
- Stock can refresh daily at 06:00 (even if the table is tiny).

## Simplify

- No four-building upgrade chain; keep the Cranny interior.
- No lottery, catalog mail-order, turnips, Crazy Redd.
- No sales-sum tool unlocks unless we want a single “net appears in stock” flag.
- Fixed prices; skip ABC rarity percentages (`mSP_GetGoodsPercent`).
- Sell at a single ratio (catalog / 4) except fruit/fish/bugs, which keep authored `sell_price`.

## Ignore

- Roof color enum, signboard 500 Bells, Nintendo 64 / Mario / Famicom lists.
- Island, tent, kamakura, harvest festival lists.
- `mSP_SelectFishginPresent`, GBA item dump.
- Department-store multi-room (`SHOP3_1`, `SHOP3_2`).
- Visitor-from-another-town shop logic (`mSP_SetNewVisitor`).
