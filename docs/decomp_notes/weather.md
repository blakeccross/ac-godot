# Weather (daily roll, particles, rain lighting)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only.

**Godot:** `Weather` (`scripts/systems/weather.gd`) rolls type + intensity; `Game` stores session state; outdoor particles live under `Effects/WeatherFx`. Lighting blend uses rain palette tables. Not an autoload.

**Read before implementing:** `Clock` (`field_renewed`), `Game.weather`, outdoor BGM (`BgmCatalog`), fishing `needs_rain`, bug rain gates, dialogue weather conditions.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_kankyo.h`, `src/game/m_kankyo.c` | Lighting windows; fine vs rain color tables; weather→env lerp |
| `src/game/m_kankyo_weather.c_inc` | 20 weather terms, weighted roll, wind, renew / save pack |
| `include/ac_weather.h`, `src/actor/ac_weather.c` | Weather actor: intensity ramp, particle pool (100), lightning, SE |
| `src/actor/ac_weather_rain.c` | Rain streaks + ground splash (`ef_ame02_*`) |
| `src/actor/ac_weather_snow.c` | Snow billboards + wind scroll + wrap box |
| `src/actor/ac_weather_sakura.c` | Cherry-blossom petals (same motion family as snow) |
| `src/actor/ac_weather_leaf.c` | Falling leaves (K.K. Slider / demo only) |
| `src/actor/ac_weather_fine.c` | Clear: no particles |

Key symbols: `mEnv_WEATHER_*`, `mEnv_WEATHER_INTENSITY_*`, `mEnv_WEATHER_TERM_NUM` **20**, `mEnv_RandomWeather`, `mEnv_DecideWeather_*`, `mEnv_NowWeather`, `aWeather_ChangeWeatherTime0` (renew bit 0 = weather), `mEnv_CHANGE_WEATHER_ENV_RATE` (1/600 US, 1/250 Aus).

## What does the original system do?

Weather is picked once per **06:00 renew** (`mTM_RENEW_TIME_WEATHER`), not every hour. The year is split into **20 weather terms** (separate from the 18 calendar terms). Each term packs seven weights that sum to 10:

| Slot | Maps to |
| --- | --- |
| clear | `CLEAR` + light |
| rain | `RAIN` + light |
| thunder | `RAIN` + **heavy** |
| snow | `SNOW` + light |
| blizzard | `SNOW` + **heavy** |
| sakura | `SAKURA` + light |
| heavy sakura | `SAKURA` + heavy |

`RANDOM_F(10)` picks a bucket. Events can override (`mEv_GetEventWeather`). Real Arbeit days force rain → clear. Island has its own clear/heavy-rain roll (~80/20). Indoors / non-FG fields report clear via `mEnv_NowWeather`.

Saved as one byte: `(type << 4) | intensity`. After rain/snow clears to fine/sakura, `mEnv_PreRainNowFine_Init` reserves a rainbow and orders haniwa.

**Particles** (`ac_weather`): up to **100** privs around the camera center. Intensity 1/2/3 = light/normal/heavy. Changing type waits until the pool drains (or forces level 0 first); level steps toward the aim every **180** frames. Rain drops fall fast (~10 frames) then spawn a 4-frame splash. Snow/sakura live ~280 frames, wrap in a camera-relative box, and take wind. Thunderstorms (rain + heavy, June–August) flash a blue point light and play thunder SE on a jittered timer.

**Look:** rain/snow use `l_mEnv_kcolor_rain_data` (dimmer sun, cooler fog) instead of fine. Shadow strength is multiplied by **0.75** while raining/snowing. Env colors lerp over ~10 s when the type changes. Outdoor BGM swaps to the rain track while raining (`Sou_BgmTenkiConv`).

## Important states

- Current / next weather type and intensity (common + save).
- Weather renew bit and `weather_time`.
- Particle pool + current profile (fine/rain/snow/sakura/leaf).
- Wind angle / power (separate wind terms; gusts).
- Lightning timers; umbrella SE variants.
- Rainbow reserved month/day.

## Inputs

- RTC month/day at 06:00 renew.
- Event weather overrides; Arbeit clear-force.
- Field type (FG vs interior / island).
- Camera center (spawn box follows player).

## Outputs / events

- Session weather type + intensity (dialogue, BGM, bugs, fishing).
- Outdoor lighting / fog / shadow dim.
- Rain / snow / sakura particles.
- Lightning flash + thunder (summer heavy rain).
- Rainbow reservation after precip clears (defer UI).

## Interacts with

- **Clock** — `field_renewed` is the roll hook.
- **World** — `WorldEnvironment` + directional lights; FX under `Effects`.
- **Audio** — rain BGM swap; rain ambient SE (defer until SFX catalog).
- **Fishing** — coelacanth only while raining (non-day slot).
- **Bugs** — `needs_rain` / rain-out species.
- **Dialogue** — greeting and condition gates on `Game.weather`.
- **Save** — packed type + intensity.

## Reproduce

- 20 weather terms and the weight table from `mEnv_RandomWeather`.
- Clear / rain / snow / sakura; light vs heavy (thunder → heavy rain, blizzard → heavy snow).
- Roll on `field_renewed`; persist type + intensity.
- Rain palette + 0.75 shadow energy while precip.
- Camera-following rain streaks + splashes; snow/sakura floaters.
- Rain outdoor BGM (already via `BgmCatalog`).
- Coelacanth / rain bugs when `Game.weather == rain`.

## Simplify

- Skip leaves (demo / K.K. only).
- Skip wind-term gust simulation; snow gets a gentle constant drift.
- Skip rainbow actor, haniwa order, island climate, umbrella SE, rain ambient SE.
- Intensity `NORMAL` unused by the roll table (only light/heavy); still accept it for debug / FX density.
- No per-frame weather→env lerp rate fidelity beyond a short blend; snap is fine if blend is awkward.
- Lightning: brief ambient flash only (no effect-clip light registry).

## Ignore

- Title-demo forced weather table.
- Basement / museum SE mute path.
- Staff-roll rain height hack.
- `BUGFIXES` sakura-weight bit shift (use the corrected `>> 0` read).
- Snowmen, wet-ground footprints beyond existing winter marks.
