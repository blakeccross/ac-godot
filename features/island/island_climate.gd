class_name IslandClimate
extends RefCounted

## What the island does to the field's climate while you are on it (`aBTD_change_season`).
## Arriving: `mFM_toSummer` (every term reads as summer — no snow, no autumn leaves, no cherry
## blossom) and `aWeather_RequestChangeWeatherToIsland` (the island's own weather, below);
## leaving: `mFM_returnSeason` and `aWeather_RequestChangeWeatherFromIsland` (the town's own).

## While it is up `Clock.summer_only` makes every term read as mid-summer (`Clock.ISLAND_TERM_*`).

## `mEnv_RenewWeather`: `fqrand() < GETREG(TAKREG, 50) * 0.1 + 0.8` → clear, else heavy rain.
const CLEAR_CHANCE := 0.8


## `roll` is a 0..1 random number. Returns `Game.apply_weather_roll`'s argument.
static func weather_roll(roll: float) -> Dictionary:
	if roll < CLEAR_CHANCE:
		return {"kind": Weather.Kind.CLEAR, "intensity": Weather.Intensity.NONE}
	return {"kind": Weather.Kind.RAIN, "intensity": Weather.Intensity.HEAVY}
