# Events (holidays, special NPC visits, rumors, event actors)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only.

**Godot:** the scheduler exists (`EventCalendar`, owned by `Game.events`); world presenters (NPCs, props) do not yet. See [Godot status](#godot-status).

**Read before implementing:** [time](time.md) (clock, `field_renewed`), [weather](weather.md) (event weather override), [villagers](villagers.md), [dialogue](dialogue.md), [post_police](post_police.md) (handbills and event mail), [world_objects](world_objects.md) (event props that are FG structures).

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_event.h`, `src/game/m_event.c` | The scheduler: event ids, per-day active-hours table, status bits, save/common areas, rumors |
| `src/game/m_event_schedule.c_inc` | The static schedule table (`event_schedule_data[]`, ~110 rows). **This is the data to port.** |
| `src/actor/ac_event_manager.c`, `include/ac_event_manager.h` | Actor that turns active events into world changes (spawn NPC / place structure / remove) via `schedule_event[]` |
| `include/m_event_map_npc.h`, `src/game/m_event_map_npc*.c` | Map-side NPC placement data for events |
| `src/game/m_calendar.c` | Played-day / witnessed-event bitfields (calendar UI), not the scheduler |
| `src/actor/ac_ev_*.c`, `ac_tokyoso_*`, `ac_tunahiki_*`, `ac_hatumode_*`, `ac_countdown_*`, `ac_aprilfool_control` | The event NPCs and controllers themselves |
| `include/lb_reki.h` (`lbRk_*`) | Vernal/autumnal equinox day, harvest-moon (lunisolar) date |

## Two layers: scheduler and manager

```
m_event  (WHEN)                          ac_event_manager  (WHAT)
event_schedule_data[]                    schedule_event[]  (type → start/stop/in/out/behind procs)
   │ resolve dates for today                │ set_today_event(): keep only events with active_hours != 0
   ▼                                        ▼
event_today[16] {type, active_hours,     per frame: event_at_oclock  (start_proc / stop_proc)
   begin/end date, status bits}          on acre change: event_at_wade (in_proc / out_proc / behind_proc)
   │ update_active() each hour              │
   ▼                                        ▼
STATUS_ACTIVE set/cleared ─────────────► NPC/props spawn, despawn, wander
```

`m_event` never touches the world. It only answers "is event X active this hour" and holds a little save data. `ac_event_manager` reads those flags and does the spawning. Keep that split.

## Scheduler (`m_event.c`)

### Event ids and types

- `mEv_EVENT_*` (`enum event_table`, ~77 ids) index every scheduled thing: holidays, the mayor's (`SONCHO_*`) speech for each holiday, rumors (`RUMOR_*`, `TALK_*`), special-NPC visits, weekly visitors, weather overrides, the bridge, the wisp, Blanca/Go-Home NPCs.
- Separate `mEv_SET(type, subtype)` ids (top 3 bits = category, low 29 = bit index) drive **flag events** in `Common_Get(event_flags[type])`: `mEv_EventON/OFF/CheckEvent`. Categories: `SPNPC` (special NPC currently in town), `SAVED` (persisted: first job, first intro, HRA wait/talk, gateway, all per player 0–3, plus `RENEWSHOP`), `RUMOR`, `DAILY` (`DAILY_OPEN_SHOP`), `SPECL`. Only `SAVED` mirrors into `Save_Get(event_save_data).flags`.
- Do not conflate the two id spaces: `mEv_EVENT_*` = schedule rows (time-driven); `mEv_SAVED_*` / `mEv_SPNPC_*` = boolean flags (state-driven).

### Schedule rows

Each row is `{ begin{month, day, _, hour}, end{month, day, _, hour}, _, type }`. Month/day/hour fields carry flag bits:

| Field | Flag | Meaning |
| --- | --- | --- |
| month | `0x10 SAVE_MONTH(n)` | take month **and day** from `dates[n]` in the save (special-event dates, birthday, weekly date) |
| month | `0x20 NOW_MONTH` | current month (for weekly rows like every Sunday) |
| month | `0x40 HARVEST_MOON_DATE` | use this year's lunisolar harvest-moon date (`lbRk_HarvestMoonDay`) |
| day | `0x80 WEEKLY` | day encodes `(week<<3)\|weekday`: Nth weekday; week 6 = last, 7 = every |
| day | `0x40 DAY_AFTER` (with WEEKLY) | the day after that Nth weekday (Mayor's Day, Sale Day) |
| day | `0x40 TOWN_DAY` | the town's fixed `town_day` from save (Town Day, July) |
| day | `0x20 LAST_DAY_OF_MONTH` | last day (lottery) |
| hour | `0x80 TODAY` | active from *today*; begin = end = today's date (Kamakura, Morning Aerobics) |
| hour | `0x40 MULTIDAY` | begin hour applies only on the first date, end hour only on the last; middle days are 0–23 (rumors, Halloween, countdown) |
| hour | `0x20 USE_SAVE_SLOT_VALUE` | hour comes from `dates[slot]` (shop-sale start hour) |

`decode_date` resolves these to a concrete month/day/hour. Nth-weekday math uses `weekday1st[month]` (weekday of the 1st, rebuilt once per year in `init_weekday1st`); "last weekday" and "every weekday" (this week's occurrence) are special-cased in `m_weekday2day`.

### Daily resolution

`mEv_run` (called every frame from play):

1. Skipped in the opening demos and player-select scenes.
2. Runs only when no demo is playing, the player is a real resident, and the mayor isn't away (`mEv_LiveSonchoPresent`).
3. **New day** (`event->day != rtc day`): `mEv_RenewalDataEveryDay` → `init_time_seat` (weekday1st) → `init_weekly_event` → `update_schedule_today` → `update_active`.
4. **New hour**: `update_active` only.
5. Acre change (wade end): `update_active` (so place-bound events re-check).

`update_schedule_today` copies every row of `event_schedule_data`, then patches it:

| Patch | Effect |
| --- | --- |
| `update_soncho_event` | Zero the mayor's vacation rows unless the lighthouse event started; zero the mayor fishing-tourney rows if a higher-priority speech already claimed `soncho_event_type` |
| `update_sports_fair` | Spring/fall sports fair exists **only on the equinox day** (`lbRk_VernalEquinoxDay` / `AutumnalEquinoxDay`); its rumor is the 10 days before; all sub-events (aerobics, foot race, ball toss, tug-of-war, weather) inherit that day |
| `update_event_rumor` | End dates for `TALK_FISHING_TOURNEY_*` (last Sunday), `RUMOR_HARVEST_FESTIVAL` (day before 4th Thursday), `RUMOR_HARVEST_MOON_DAY` (the 7 days before the moon date) |
| `update_special_event` | The six special-NPC rows are zeroed unless they are *the* currently scheduled special event (below) |
| `update_weekly_event` | KK / Joan(kabu) / Gulliver / bridge / Blanca / wisp rows zeroed unless the weekly slot picked them |
| Summer camper | June–Aug: begin = that month's Saturday, end = next day; on Sunday it rewinds a week so the camper lasts Sat–Sun |

If today falls in the resolved `[begin, end]` (`check_date_range` handles year wrap), `add_event_today` OR-s the active hours into `event_today[type]`:
- bit `h` of `active_hours` = active during hour `h`.
- `TODAY` / `MULTIDAY` rewrite the begin/end hours as described above.
- One slot per event type (`index_today[type]`), max 16 concurrent (`mEv_TODAY_EVENT_NUM`).

Then, keyed on the **scene you arrive from / are in**, it force-adds a one-shot event so interiors stay consistent: Kamakura, Crazy Redd's tent (`BROKER_SALE`), Gypsy's buggy, shop sale (only if the special NPC is the shop sale), summer-camper tent.

`check_and_clear_event_today` drops finished rows, but keeps a row alive if the event is still `RUN`ning (sets a `CLEAR` flag so `mEv_run` clears it after the actor finishes) or the event's placed FG is in the player's current acre. `delete_too_short_event` handles "you loaded at :55 of the last active hour": the event is flagged `TOO_SHORT` and suppressed, so a festival doesn't spawn for 5 minutes.

### Status bits

Per event (`event_today[].status`): `ACTIVE` (schedule says on now), `STOP`, `SHOW` (actor placed in the player's acre), `PLAYSOUND`, `RUN` (start proc succeeded), `ERROR`, `TALK`, `EXIST` (row scheduled). `update_active`:
- Sets `ACTIVE` when the current hour bit is set, or on a `START_EVENT` one-shot; clears it otherwise.
- Sports-fair sub-events are cleared once the field-day is over.
- Also rebuilds the rumor list: each active rumor id gets `mEv_spread_rumor`, which the villager dialogue picks from.

Helpers other systems call: `mEv_check_schedule(id)` (active *this hour*), `mEv_check_run_today(id)` (active any hour today), `mEv_check_status`, `mEv_set_keep/clear_keep` (persist "already spawned" across acre changes), `mEv_GetEventWeather` (weather override).

### Weather override

`mEv_GetEventWeather`: `WEATHER_CLEAR` rows (Fireworks Jul 4, Meteor Shower Aug 12, Harvest Moon, Halloween, Harvest Festival Thu, Dec 31), the sports fair days, and `WEATHER_SNOW` on Dec 24 force clear/snow at heavy intensity. Feed this into the [weather](weather.md) pick before the term table.

### Weekly slot (`init_weekly_event`)

One weekly visitor per day, stored in `event_save_common.weekly_event`:

| Weekday | Visitor |
| --- | --- |
| Sunday | **Joan** (`KABU_PEDDLER`, 06:00–11:00); clears the per-player "already spoke" list |
| Saturday | **K.K. Slider** (`KK_SLIDER`, 20:00–23:00) |
| Mon–Fri | **Gulliver** (`DOZAEMON`, 06:00–22:00): a weekday in Mon–Fri is picked once per week, `1 + (md + hour) % 5` |

Overrides, checked after the weekday pick (Sat, or a weekday that isn't Gulliver's day):
- **Tortimer bridge** (`SONCHO_BRIDGE_MAKE`) when the town is full of villagers, no bridge exists, and the lighthouse trip isn't active. Bumps `bridge_flags` to advance the location.
- **Blanca / go-home NPC** (`MASK_NPC`) if `mGH_check_birth2` / `mMC_check_birth`.
- **Wisp** (`GHOST`): separate slot. `ghost_day` = 2–4 days out, re-rolled once per week; spawns when it falls in the last 7 days and it hasn't been returned.

Every other weekly row is zeroed by `update_weekly_event` unless it matches.

### Special-NPC visits (`init_special_event`)

Exactly **one** "special event" is scheduled at a time, from a pool of six: `SHOP_SALE`, `DESIGNER` (the car-driving fashion designer, `ac_ev_designer` / `DESIGNER_CAR`; gifts shirts), `BROKER_SALE` (Crazy Redd), `ARTIST` (wall-gift visitor, `ac_ev_artist`), `CARPET_PEDDLER` (`ac_ev_carpetPeddler`), `GYPSY` (fortune-teller, `ac_ev_gypsy`).

- When the previous one's window has passed (or `mEv_make_new_special_event` is called when it ends), pick the next: `special_event_types[seed % 6]` with `seed` from the player id + date; skip a repeat of the current type.
- Date gap: `1 + (day + month*sec) % (7 - fieldRank)`, min 2 days. So a better-rated town (higher `mFAs` field rank) gets shorter gaps.
- **Sale Day override:** if the day after the 4th Thursday of November falls between now and the rolled date, it is forced to `BROKER_SALE` on that day.
- Per-type start hour saved in `dates[SPECIAL3]`: shop sale 12 + `RANDOM(8)` (rejected on the last day of a month, Jan 1–3, or if `RENEWSHOP` is set), Redd 18:00 (not on Jul 4), Gypsy 21:00 (not Dec 31), others 06:00.
- End hours (`get_special_event_end_time`): artist/designer/carpet 05:00 next day (the row spans two dates), Gypsy 20:00, Redd 17:00, shop sale 23:00. End date = start + 1 day (same day for shop sale).
- Handbills: a leaflet is mailed to all four players (`leaflet_recipient_flags.event_flags = 0b1111`) when a new special is scheduled. `HANDBILL_SHOP_SALE` / `HANDBILL_BROKER` rows (the days before) trigger `prebargain_start` / `prebroker_start`, which just register the mail.

Note the schedule table is written so all six special rows exist permanently; `update_special_event` is what turns the unselected five into empty ranges.

### Per-event save data

`event_save_common` (persisted with the town) holds: the `special_event` and `weekly_event` type + flags, `dates[8]` (today, last-play date, birthday, special begin/end, weekly date, sale hour), up to 5 `mEv_area_c` scratch areas (event-owned data, keyed by `(type, id)` and tagged with year/start/end so they are dropped when the event's window is over), `last_date` (for missed-mail catch-up), Valentine's mail date, `ghost_day`, `bridge_day` + `bridge_flags`, and `dozaemon_completed`. `event_save_data` holds the specific payload of whichever special/weekly event is active (Redd's three items, artist entries, designer gifted shirts, Joan's per-player "spoke" ids, Gulliver flags).

Runtime-only `Common_Get(event_common)` holds `place[10]` (where an event actor was put: block, unit, actor name, flag id) and field-day state. Places let a despawn find the FG it created (`mEv_erase_FG_all_in_common_place` runs on save).

## Manager (`ac_event_manager.c`)

`schedule_event[]` has one control row per event that needs the world: `{type, start, stop, in, out, behind, block}`.

| Proc | When | Job |
| --- | --- | --- |
| `start_proc` | event goes `ACTIVE` and isn't `RUN`ning (checked at o'clock via `event_at_oclock`) | Choose the acre/unit, create the NPC actor / FG structure, `mEv_EventON(SPNPC_*)`, `mEv_set_keep`. Return 0 to retry later, 1 = started, 2 = already kept |
| `stop_proc` | event no longer `ACTIVE` but `RUN`ning | `mEv_EventOFF`, clear keep, delete FG, and for special NPCs `mEv_make_new_special_event()` |
| `in_proc` | player wades into a new acre and the event isn't yet `SHOW`n (`event_at_wade`) | Put the actor at the acre edge so it is visible on entry (`show_actor_at_wade*`) |
| `out_proc` | event off/stopped while `SHOW`n | Walk it away / remove it (`gypsy_out`, `kamakura_out`, `bargain_out`); default `wait_culling` waits for `STOP` |
| `behind_proc` | after out | Post-departure cleanup (turnip buyer, Halloween, turkey) |

Placement helpers worth knowing (all block/unit pickers over the acre map, with `search_free_unit` retrying around obstacles and reserved cells): `make_actor_in_free_block`, `..._seaside_block` (Gulliver washes up), `..._fixed_block` (a known acre: station, shrine, pool, dock, player home), `..._reserved_block`, `make_FG_somewhere_lot4sale` (Redd's tent goes on an empty lot), `show_actor_at_wade`, `walk_actor_at_wade`.

Named acre kinds it looks up once in `schedule_init`: pool, station, shrine, player home, dock (`mFI_BlockKind2BkNum`). Events that need one and can't find it are skipped.

Mail hooks in the same file: `mail_event_check` (birthday card, Christmas card, Valentine's date, computed from `last_date` → now so a long gap still delivers), `vt_wt_mail_check`, plus `aEvMgr_actor_regist_handbill`.

### Event → world table

| Event (`mEv_EVENT_*`) | Window | World effect |
| --- | --- | --- |
| `KK_SLIDER` | Sat 20–23 | K.K. at station plaza (`staffroll_*`) |
| `KABU_PEDDLER` | Sun 06–11 | Joan (`turnipbuyer_*`) |
| `DOZAEMON` | Mon–Fri 06–22 | Gulliver on the beach |
| `BROKER_SALE` / `GYPSY` / `DESIGNER` / `ARTIST` / `CARPET_PEDDLER` / `SHOP_SALE` | special slot | Redd's tent (`BROKER_TENT`), fortune-teller tent (`FORTUNE_TENT`), designer's car (`DESIGNER_CAR`), artist / carpet peddler wander the field, shop sale interior state |
| `NEW_YEARS_DAY` | Jan 1 06–10 | shrine + table (`NEWYEAR_*`) |
| `KAMAKURA` | Jan 2–Feb 23 (10:00+, 'today' flag) | snow hut (`KAMAKURA`) |
| `GROUNDHOG_DAY` | Feb 2 07–08 | groundhog (`GHOG`) |
| `SPORTS_FAIR_*` | equinox days | balls/baskets structures, sub-events at 09–16 |
| `CHERRY_BLOSSOM_FESTIVAL` | Apr 5–7 | `SAKURA_TABLE0/1`; `CHERRY_BLOSSOM_PETALS` Apr 3–8 is a weather-fx flag |
| `SUMMER_CAMPER` | Jun–Aug weekends | tent (`TENT`) + interior |
| `FISHING_TOURNEY_1/2` | Sundays in Jun / Nov | check stands (`FISHCHECK_STAND0/1`), mayor wanders |
| `FIREWORKS_SHOW` | Jul 4 19–20 | stalls (`FIREWORKS_STALL0/1`) |
| `MORNING_AEROBICS` | Jul 25–Aug 31 06:00 | radio (`AEROBICS_RADIO`) |
| `METEOR_SHOWER` | Aug 12 18–20 | viewing spot (`meteor_shower_viewing_*`) |
| `HARVEST_MOON_FESTIVAL` | lunar 8/15 18–20 | stargazing (`harvestmoon_*`) |
| `HALLOWEEN` | Oct 31 18:00–Nov 1 00:00 | Jack + pumpkin props |
| `HARVEST_FESTIVAL` (+ `_FRANKLIN`) | 4th Thu Nov 15–20 | Franklin/turkey, table |
| `TOY_DAY_JINGLE` | Dec 24 20:00–Dec 25 00:00 | Jingle |
| `NEW_YEARS_EVE_COUNTDOWN` | Dec 31 23:00–Jan 1 00:00 | countdown stage (`NEWYEAR_COUNTDOWN0/1`) |
| `SNOWMAN_SEASON` | Dec 25–Feb 17 | snowman spawn (`snowman_start`, no stop) |
| `SONCHO_*` (≈27) | mostly 10:00–17:00 | the mayor's speech NPC at the plaza; `sonchowandar_*` for fishing/fireworks |
| `SONCHO_VACATION_*` | Jan 15–24, Feb 12–21 | mayor away (lighthouse trip) |
| `SONCHO_BRIDGE_MAKE` / `BRIDGE_MAKE` | Sat / active | Tortimer builds the bridge, then construction plays |
| `GHOST` | wisp slot | wisp + spirits |
| `MASK_NPC` | Blanca / go-home | masked NPC |
| `APRILFOOLS_DAY` | Apr 1 | `ac_aprilfool_control` |
| `MUSHROOM_SEASON` | Oct 15–25 | mushrooms (`m_mushroom`) — data flag only, no manager row |
| `WEATHER_*` | see above | weather override |
| `KOINOBORI` | May 1–5 | windsock structure (`KOINOBORI_WINDSOCK`) |
| rumors / talks | days before | dialogue picks (`mEv_get_rumor`) |

Not in the manager table (state or dialogue only): mushroom season, lottery, birthday, Mother's/Father's Day, Labor/Explorers/Officers/etc. days beyond the mayor's speech and shop-side dialogue, Valentine's Day (mail).

## Calendar (`m_calendar.c`)

Separate from the scheduler. Records which days each resident **played** and which event days they were present for (Mother's Day, Town Day, meteor shower, …), and draws the calendar overlay. Uses `town_day` too. Does not gate any event. See [time](time.md).

## Godot status

Implemented (scheduler layer, `m_event` equivalent):

| Piece | File |
| --- | --- |
| Schedule rows as readable JSON (134 rows, 117 ids), generated from `m_event_schedule.c_inc` | `data/events/schedule.json`, loaded by `EventSchedule` |
| Calendar math: ordinals, Nth/last weekday, equinoxes (`lbRk_*` formulas), harvest-moon table 2001–2030 | `EventDates` |
| Date resolution, hour masks, sports-fair/rumor/summer-camper patches, weekly visitor (Joan / K.K. / Gulliver), one-at-a-time special visit (Sale-Day override, gaps, per-type hours), save state, `event_started` / `event_ended` | `EventCalendar` (`Game.events`, saved under `"events"`) |
| Clock hookup, first-sync-is-silent, event weather override (`mEv_GetEventWeather`), "X has begun!" notices for non-rumor events | `Game.sync_events`, `apply_event_weather` |
| Debug commands | `/event list | start <id> | stop [id] | goto <id> | special <id>` (`DebugConsole`) |
| Tests | `tests/unit/test_event_calendar.gd` |

Debug commands: `start` forces an event on until `stop`; `goto` jumps the clock to the event's next scheduled start (date-driven events and Joan/K.K.; the special visits have no calendar date, so use `start` or `special`); `special <id>` makes a visit the scheduled special *and* forces it on now.

Not implemented (deliberate, needs other systems):
- **Presenters** (`ac_event_manager` equivalent): nothing spawns K.K., Joan, Gulliver, the mayor, Redd's tent, festival props, or the interiors keyed to scene (Kamakura, summer camper, gypsy buggy). Listen to `Game.events.event_started/ended` and use `WorldObjectRegistry`. See [world_objects](world_objects.md) for the unplaced structures.
- Rows kept but disabled (`EventSchedule.UNSUPPORTED`): bridge, Blanca / go-home NPC, wisp, mayor's vacation.
- Rumor plumbing: `EventCalendar.active_rumors()` exists, dialogue does not read it yet. No event mail (handbills, birthday, Christmas, Valentine's).
- Per-event area/place save data (`mEv_area_c`, `mEv_place_c`), `TOO_SHORT` suppression, field-day state, `mFAs` field rank (`DEFAULT_FIELD_RANK` constant), player birthday (unset, so that row never fires).
- `town_day` is `1 + world_seed % 28` — a placeholder; the decomp's roll was not researched.
- `ReddBook` (`scripts/systems/redd_book.gd`) is still the weekly-tent stand-in and does not read `Game.events`. **Diverges from the original**, where Redd is one draw of the six-way special event. Move it onto `broker_sale` when the tent presenter lands.

Answered from the decomp while implementing: harvest moon = the 8th lunisolar month's start date + 14 days (table in `lb_reki.c`); equinox = `(int)(20.8431 + 0.242194 * (y - 1980)) - (y - 1980) / 4` (spring) / `23.2488` (autumn); the table's start *hour* for special visits is a literal per event (Redd 18, gypsy 21, others 6); only the shop-sale handbill's end hour reads `dates[SPECIAL3]`.

## Suggested shape (not a port)

1. `EventSchedule` (`Resource` or JSON under `data/events/`): one row per `mEv_EVENT_*` with begin/end rules using the same encodings as above but as readable fields (`month`, `nth_weekday`, `day_after`, `lunar`, `town_day`, `hours`, `multiday`), plus the mayor/rumor/weather rows.
2. `EventCalendar` (system on `Game`): `is_active(id)`, `active_hours_today(id)`, `today_events()`, signals `event_started(id)` / `event_ended(id)`. Resolves at 06:00 (`field_renewed`) and each hour; needs a deterministic `town_day` in the save and equinox / harvest-moon helpers.
3. Weekly + special-event state in the save (`weekly_type`, `special_type`, `special_dates`, `ghost_day`, `bridge_*`), seeded exactly as above so the same town/date reproduces.
4. Presenters, one per world effect, each a small scene/system that listens to `event_started/ended` and places itself with `WorldObjectRegistry` (tents, tables, stalls, Kamakura, Joan, K.K., Gulliver, mayor, …). They own the "in/out at acre edge" behavior; the calendar does not know about scenes.
5. Weather override hook (`EventCalendar.weather_override()`), dialogue rumor hook (`active_rumors()`), mail hook (birthday / Christmas / Valentine's catch-up from a saved `last_date`).

Start with the calendar + weather + rumor plumbing (cheap, testable headlessly), then one presenter (K.K. Saturday or Halloween) to prove the manager split before the long tail.

## Open questions

- `town_day` is written at town creation (used by `m_calendar.c` and the Town Day row); the exact roll was not read. Check `m_start_data_init` / `m_common_data`.
- `mFAs_GetFieldRank` (town rating → special-event gap) depends on the field-assessment system, which does not exist here yet. Use a constant until it does.
- `mEv_LiveSonchoPresent` / `mEv_LivePlayer` (suppress events while the mayor is away or a resident is a visitor) were not read.
- The per-event NPC scripts (`ac_ev_*`, `ac_tokyoso_*`, `ac_tunahiki_*`, `ac_hatumode_*`, `ac_countdown_*`) are not covered here; each needs its own note before implementation.
