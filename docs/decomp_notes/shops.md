# Shops (Nook, hours, stock, economy)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — not every store is in scope.

**Godot:** `ShopBook` (`RefCounted` on `Game`, not an autoload) owns Nook's state; `ShopGoods` rolls the lineup; `KabuMarket` is the Stalk Market; `CatalogBook` (on `Game`) is the catalog + mail-order queue; `ShopMail` writes the store's letters; `NookShopTalk` drives Tom Nook's conversations (`nook_shop_menu` / `nook_shop_offer` / `nook_lottery` JSON). Only Nook (`shop0`) is a Bell shop — buy and sell. Listed price is `ItemData.buy_price` (or `sell_price` if buy is 0); stationery is a 4-sheet pad, the signboard 500, a grab bag costs the year. Nook pays fruit/fish/bugs at authored `sell_price`, foreign fruit 2000 / 4, everything else listed / 4 (`SELL_BUY_RATIO`). Wallet is `Inventory.wallet`; money sacks in the pockets top it up when buying.

**Able Sisters (`needlework`) is NOT a clothing store.** `SCENE_NEEDLEWORK` is a design/pattern shop (`src/game/m_needlework.c`, `ac_needlework_indoor.c`, `ac_npc_needlework`). `ShopBook.restock(ABLE_ID)` stocks nothing — no Bell stock, no counter. The player keeps 8 original designs (`Game.designs` = `DesignBook`), the shop 8 shared ones (4 mannequins + 4 umbrella stands). Designs are made in the pixel editor (350 Bells for a new one) and traded through Mabel — see the design/pattern tool entry in [feature-checklist.md](../feature-checklist.md).

## Able Sisters (as built)

Decomp: `ac_npc_needlework.c` + `_talk.c_inc` / `_schedule.c_inc` / `_gba.c_inc`, `ac_needlework_indoor.c`, `ac_needlework_shop*.c`, `m_needlework*.c`, `m_cporiginal_ovl.c`, villager wear in `ac_npc_act_greeting.c_inc`.

- **Mabel** (`mabel.gd`): force-talk greeting on the first approach (0x2FD1 / 0x2FD2). A → 6-way led by 0x2FD4 until "What's this?" is picked once (`first_talk_flags & 0x40`), then 0x3005. Results that go to `aNNW_TALK_WHAT_HAPPEN` re-open the menu; trade, trend and listen end the talk. Goodbye (think 10): facing the exit from the row inside → 0x2FD3 → leave (`Interior.leave_through_exit`).
- **Design** (`DESIGN_CHECK` … `DESIGN_CLOSE3`): money checked with sacks (`ShopBook.can_afford`), 350 paid after the name entry (`ShopBook.pay`); cancel / unsaved = 0x2FE9, free.
- **Album** (`CPORIGINAL0-2`, `design_album_overlay`): `DesignBook.album` 8 × 12 + `album_names`; swaps per `mCO_swap_image`; keep / discard on close restores a `to_save()` snapshot.
- **Trades** (`TRADE_CLOSE` exchange / `CLOSE2` display / `CLOSE3` buy): display and exchange call `trend_delete` (wearers revert), buy doesn't (`Mabel.apply_trade`).
- **Trends** (`NeedleworkTrend`): wear is `VillagerState.cloth_design` / `umbrella_design`. Greeting reactions use `react_rate_table` (0.2 feel, 0.1 copy catchphrase, 0.1 reset catchphrase, 0.1 shop umbrella, 0.1 copy shirt, 0.05 new normal shirt, 0.1 shop shirt, 0.05 reset shirt + umbrella; A = the villager the player is friendlier with). The reactions run when villagers actually meet and greet outdoors (`VillagerGreeting`, see villagers.md). Report tiers 0 / 1 / <5 / ≥5 (`MSG_TREND_*`).
- **Sable** (`sable.gd`): `pick_story_row(days, first_of_day)` *before* `tick_sable_day` (first talk of days 4–7 → rows 5/9/13/17); parts are Sable / Mabel (`chime_in`, facing Sable) / Sable; story 9 turns to the player; she turns to the player only at `days >= 5`; `NeedleworkPresenter.set_machine_running` stops the machine + fabric while she talks.
- Not built: ROM text (authored stand-ins in `NeedleworkTalk`), GBA / e-Reader, April Fool's, foreigner rules, Mabel's area-table roaming and walk-over before trades.

**Cranny presentation (`ShopDisplay` + authored `shop0.tscn`):**
- Shells `rom_shop1f` / `rom_shop1w` (and `rom_shop2f`/`w`, `rom_shop3f`/`w`, `rom_shop4_2f`/`w`); the `f`/`w` suffix is floor/wall. Wall/floor bank indices follow `aSI_*_default_table` (`WALL_SHOP*` / `FLOOR_SHOP*` → 67–70).
- FG walkable `(1,1)+(7,8)`; exit `(3,8)`; player spawn GX `{160,0,300}`.
- Tom Nook (`tom_nook.tscn`; no cloth DMA — `seg_08` is eyes) at the shop's `shop0N_actable` stand — Talk / Buy / Sell; goods use `obj_item_*` / mannequin stands on RSV cells. Outfit is a different skeleton per level (`rcn_1` Cranny, `rcc_1` Nook 'n' Go, `rcs_1` Nookway, `rcd_1` Nookington's), not a cloth swap.
- Shelf goods sit at **21 GX** (`CRANNY_SHELF_Y_GX`) on shell tables; freestanding FTR / mannequin / umbrella stay on the floor.
- Wall clock `obj_clock_shop1`…`4` at GX `(200,40,40)` (`aHC_position_data`).
- `rom_shop*` shells keep the acre origin (like museum) so FG RSV ut cells line up with `cell_to_world`.
- Nook shops use Tom Nook instead of a counter actor. Able Sisters has no counter — `InteriorBuilder.add_needlework_set` places 4 mannequins + 4 umbrella stands (`able_fixture.tscn`), the sewing machine (`obj_misin`), Mabel (`hgh_1`), and Sable (`hgs_1`).

Hours stay on `InteriorCatalog.is_open_now`. Nook upgrades by sales → `shop0`…`shop3_1` rooms, outdoor `obj_s_shop1`…`4`, and Tom Nook `rcn`/`rcc`/`rcs`/`rcd`.

**Read before implementing:** shop scene, buy/sell, wallet.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_shop.h`, `src/game/m_shop.c` | Shop type, hours, stock lists, sales sums, prices |
| `src/data/npc/npc_draw_data.c` | Shop-master draw rows (`rcn_1` / `rcc_1` / `rcs_1` / `rcd_1`) |
| `src/data/field/mvactor/shop0*.c` | Indoor stand ut (`shop01`…`shop04_1` actables) |
| `src/game/m_kabu_manager.c` | Stalk Market weekly schedule |
| `src/actor/npc/ac_npc_shop_common.c` | Shop-master talk: menu, shelf offers, buy/sell checks, tickets, orders |
| `src/actor/npc/ac_npc_shop_mastersp_talk.c_inc` | Raffle-day Nook: ticket check, odds, prizes |
| `src/actor/ac_shop_level.c` | Renovation booking and upgrade |
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

## Behavior (as built)

- **Level & renovation** (`mSP_PlusSales`, `mSP_GetRealShopLevel`, `aSL_JudgeRenewShop`, `aSL_RenewShop`, `mSP_InRenewal`): `level` is stored. Buying adds the price to sales, Nook buying from you adds half the payout, catalog orders add the price; sales cap at the next threshold (25k / 90k / 240k) until that building exists. When sales earn the next building (Nookington's also needs `visitor`), a renovation is booked for two days later unless raffle day, Sale Day or the shop-sale event falls in the window; it is cancelled if the clock moves more than two days back. The shop is `RENEW` (closed for renovations) from opening time the day before, and the new building opens at its own opening hour on the booked day with a fresh lineup. A renovation notice goes out when booked and a grand-opening letter when it lands (`aSL_SetShopRenewalChirashi_Notice`, `mSP_SetRenewalChiraswhi_AppoDay`).
- **Hours** (`mSP_ShopOpen`): `PRE` 06:00 until opening, `OPEN`, `END`; forced open during the first job. Raffle day (last of the month) opens at 10.
- **Lineup** (`mSP_MakeGoodsList`): counts per level from `l_*_goods`; Cranny tools unlock by sales (shovel, net ≥3k, rod ≥8k, axe ≥12k), bigger shops draw any; Nookway+ adds the rotating paint colour, a signboard, a cedar sapling and a rare-furniture slot (`ItemData.shop_rare`); one umbrella; flower-seed bags never repeat. Oct 16–30 flower bags become candy and saplings become bags. Sale Day (day after the 4th Thursday of November) replaces stationery/tools/plants/saplings (+ paint/sign) with grab bags. Raffle day has no goods; the three prizes are on the shelves.
- **Buying** (`aNSC_sell_answer0`): money check counts sacks (`mSP_money_check`); sacks are opened smallest-first with change to the wallet (`mSP_get_sell_price`). Pockets full → refused. Furniture / clothes / wallpaper / carpet / umbrellas earn a ticket for this month (`ticket_MM`, stack of 5); with no room it is mailed at the next 06:00 (up to 255 held, five per letter). Paint does not enter the pockets: it sets the house's `next_outlook_pal`, applied at the next game start. Clothes can be tried on first (the player changes back either way).
- **Selling** (`aNSC_check_buy_item_*`, `aNSC_buy_check`): quest items refused; presents skipped; zero-value items are taken for free ("off your hands"); turnips at `KabuMarket.price_today() × bundle`, never on Sunday; spoiled turnips are junk. Payout over 99,999 becomes 30,000-bell bags; if the bags won't fit (counting slots the sale frees) Nook refuses.
- **Catalog orders** (`aNSC_order_check`, `mPO_delivery_mail_with_order_ftr`): catalog items (furniture, clothing, wallpaper, carpet, stationery, umbrellas) record when they reach the pockets. Five order slots; paid at the counter; delivered enclosed in a letter the next morning.
- **Raffle** (`ac_npc_shop_mastersp`): prizes rerolled monthly, first one preferring furniture you don't own. Five same-month tickets per spin; roll <5 first, <15 second, <35 third; a prize already won is a miss.
- **Turnips** (`m_kabu_manager.c`): schedule keyed to the week's Sunday; Sunday price `100 × [0.7, 1.3)`; trend A = B + one Mon–Fri day at 8× Sunday, B random walk, C falling 80–95% a day; next trend from the current one's odds (A .5/.3/.2, B .6/.2/.2, C .6/.3/.1). Rerolled on the setting Sunday and whenever a week stale.
- **Sale event**: on the `shop_sale` event Nook gives one balloon on the first talk if a pocket slot is free.

Not built: the Nookway+ diary (no diary items exist), ABC rarity lists (`mSP_GetGoodsPercent` — needs the ROM item lists), rare-furniture leaflet (`mSP_SetShopRareFurnitureChirashi`), the bargain-event FG layouts, wallpaper/carpet preview on the shop walls, Timmy & Tommy (`ac_npc_mamedanuki`), passwords, HRA talk, April Fool's lines, ground turnips spoiling.
