class_name IntroPortraitLens
extends RefCounted

## The intro stages fix their lens to the decomp's vertical angle, which on a portrait phone
## shows a narrow slice of the set. There it zooms out a little; everywhere else the lens
## is the decomp's.

## How much more of the set shows, as a multiple of the visible extent (1.25 is 25% more).
const ZOOM_OUT := 1.25


## `base_fov` is the stage's vertical angle in degrees.
static func fov(base_fov: float) -> float:
	if not InputDeviceTracker.uses_mobile_ui():
		return base_fov
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(base_fov * 0.5)) * ZOOM_OUT))
