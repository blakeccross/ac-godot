# Time (clock, seasons, daily reset, lighting, calendar)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only.

**Godot:** `Clock` (`ClockService`) is the time system. Year, month, day, weekday, hour, minute, season, term, and time-of-day live there. Other systems subscribe (`field_renewed` at 06:00, `time_changed`, …) or call `in_hour_window` / `is_listed_now`. Do not read the OS clock from shops, villagers, plants, or catchables.

**Read before implementing:** `Clock` (`scripts/systems/clock.gd`), weather, shop hours, villager schedules, plant renewal.

Phase 1 already matches the numbers below. This note is the citation and the leftover original behavior.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_time.h`, `src/game/m_time.c` | Terms, seasons, year clamp, daily renew, `mTM_calender[]` |
| `include/lb_rtc.h`, `src/lb_rtc.c` | Hardware RTC, weekday, `lbRTC_time_c` |
| `include/m_common_data.h` (`Time_c`) | Live clock in the global save/runtime object |
| `include/m_kankyo.h`, `src/game/m_kankyo.c` | 8 lighting windows, weather enum |
| `include/m_kankyo_weather.c_inc` | Rain/snow/sakura by term |
| `include/m_calendar.h` | Played-day bitfields and holiday flags |
| `include/m_event.h` | Scheduled events (Nth weekday, town day, harvest moon) |

Key symbols: `mTM_FIELD_RENEW_HOUR` **6**, `mTM_MIN_YEAR` **2001**, `mTM_MAX_YEAR` **2030**, `mTM_TERM_NUM` **18**, `mTM_check_renew_time` / `mTM_set_season`. Lighting: `klight_chg_tim` at 0, 4, 6, 8, 12, 16, 18, 20 hours. Fine-weather colors: `l_mEnv_kcolor_fine_data`.

Default RTC after crash/limit: year 2000 bumped to 2001 (`mTM_rtcTime_limit_check`); Godot fallback 2001-01-01 12:00 is consistent with “valid clock”.

## What does the original system do?

Game time tracks the **console RTC** unless `rtc_crashed` (then it advances in-game). Years are clamped to 2001–2030.

The year is split into **18 terms** (`mTM_calender`). Each term has an inclusive end month/day, a **season**, and BG-item profile/bank (cedar vs deciduous, snow, etc.). Season boundaries used in this project:

| Season starts | Date (first day of new season) |
| --- | --- |
| Spring | Feb 25 |
| Summer | May 26 |
| Autumn | Sep 16 |
| Winter | Dec 10 |

At **06:00** a “renew” fires (`mTM_RENEW_TIME_DAILY` / weather). That is when shops restock logic, FG growth (`mAGrw_RenewalFgItem`), mushroom hour checks, and many NPC daily flags run — not at midnight.

Outdoor light interpolates across eight windows (`Clock.outdoor_light` → `World._apply_time_of_day`): ambient / sun / moon / fog / background from `l_mEnv_kcolor_fine_data`, blend via `get_percent`, sun+moon dirs from `mEnv_ChangeDiffuseVctlSet`. Weather is a separate enum: clear, rain, snow, sakura, falling leaves, plus intensity (deferred). NPC house lights off at 05:00 and on at 18:00 (`mEnv_NPC_LIGHTS_*`). Rainbow window is 09:00–15:00.

**How actors are lit (original):** every `Actor_draw` builds one `LightsN` from global ambient + sun/moon (`Global_light_read` / `LightsN_list_check` / `LightsN_disp`). There is no per-character lighting hack. Meshes use authored per-vertex lighting normals in Vtx `cn[]` under `G_LIGHTING`. Godot matches that with world sun/moon/ambient plus those normals exported into the GLB — same path for player, villagers, and props.

`m_calendar` records which days the player existed in town and which event days they witnessed (Mother’s Day, town day, meteor shower, …). `m_event` is a large scheduler for holidays and tours.

Island climate **freezes** term index to summer-ish term 7 (`mTM_get_termIdx`).

## Important states

- `rtc_time` (Y-M-D h:m:s + weekday).
- `season`, `term_idx`.
- `rtc_crashed` / `rtc_enabled`; debug add-seconds.
- Renew flags (weather vs daily).
- Weather type + intensity; wind term.
- Lighting window index and blend toward the next window.
- Calendar played_days / event_flags per player.

## Inputs

- OS clock (or debug skip / override).
- Scene climate (town vs island).
- Player existing in town that day (`mCD_calendar_wellcome_on`).

## Outputs / events

- Season and term changes (palette, insects, fish).
- Daily renew at 06:00.
- Lighting colors for `WorldEnvironment`.
- Window panes and ground spill (`*_light_model` / `*_window_model`) 18:00–05:00 via `GeneratedVisual.refresh_window_lights`.
- Weather particles.
- Shop open/close (shop module reads hour).
- Villager schedule lookups (seconds since midnight).
- Event on/off for the current date.

## Interacts with

- **World** — seasonal acre graphics (`mFM_toSummer`).
- **Player** — sunburn timers (ignore).
- **Villagers** — schedules, mood.
- **Shops** — hours and restock.
- **Plants / bugs / fishing** — spawn tables by term.
- **Save** — `Time_c` plus calendar structs.

## Reproduce

- Live clock aligned to real time, with a debug skip (hour/day).
- Years 2001–2030 clamp (or a documented Godot equivalent).
- **18 terms** and the four season start dates above.
- **06:00 daily reset** as the hook for growth, shop, schedules.
- Eight lighting windows and fine-weather colors (already in `Clock.outdoor_light()`).
- Weekday for shop lottery / schedules.

## Simplify

- Weather: one rain and one snow later; skip sakura/leaves particles until visuals need them.
- No rainbow, wind-term blending, or per-version weather lerp rates.
- Calendar UI and holiday flags wait until a holiday slice exists.
- No island climate override.

## Ignore

- Staff-roll / title-demo clocks.
- Meteor shower and other `mCD_FLAG_*` until events are in scope.
- Harvest-moon lunisolar date.
- `under_sec` / clock-hand radial fields for the Town Hall clock mesh.
- RTC error UI (`mFRm_ERROR_BAD_RTC`) beyond “clock looks wrong, use fallback”.
