# Effects (`ef_*`, `eEC_EFFECT_*`)

Behavioral reference: `src/effect/ef_*.c`, `ef_effect_control.c`. The decomp has 129 effect files
(`eEC_EFFECT_NUM` 123 ids). Many are not drawn at all: a **controller** only spawns other
effects (`ef_swing_net`, `ef_swing_axe`, `ef_swing_rod`, `ef_walk/dash/turn/wait_asimoto`,
`ef_slip`, `ef_turi_mizu`, `ef_hanatiri`, `ef_dig_scoop`, `ef_otosiana`, `ef_ikigire`,
`ef_kigae`, `ef_kyousou_onpu`, `ef_clacker`), and twelve are never spawned by anything
(`ASE`, `ASE_CH`, `FLASH`, `FURO_YUGE`, `KPUN`, `LOVELOVE`, `LOVELOVE_HEART`, `MOTIYUGE`,
`NIGHT15_MOON`, `ONGEN`, `STRING`, `TENT_LAMP`). Those need no port.

## Where they live here

| Family | Port |
| --- | --- |
| Footsteps, dust, skids, tumbles, prints, sand/snow/water kicks, dig clods and mud, chips, net splash, ripples, petals (`hanabira`, `hanatiri`), `goki`, steam, train smoke, umbrella spray | `FootstepEffects`, `FieldEffects`, `FieldParticle` |
| Villager reaction clips (`warau`, `shock`, `ha`, `hirameki`, `gimonhu`, `kantanhu`, `ase2`, `muka`, `lovelove2`, `situren`) and the clip-long ones (`pun`, `siawase`, `kangaeru`, `takurami`, `naku`, `buruburu`, `kaze`, `otikomi`, `neboke`) | `NpcFeelGlyphs`, `NpcFeelMoods`, `NpcManpu.feel_for` |
| Mood-pose pulses (`konpu`, `pun_yuge`, `doyon`, `neboke_awa`) | `NpcManpu.MOOD_POSE_EFFECTS` |
| Clip one-shots: `ikigire` (`tired1`), `kyousou_onpu` (`banzai1`), `kigae` + `kigae_light` (`get_change1`), `taberu` (`get_eat1`), `uranai` (`kieeeei1`) | `NpcManpu.CLIP_EFFECTS` → `NpcFeelGlyphs._tick_pose` → `NpcFeelMoods.pulse` (a clip passes its `feel_effect_set_frame` once, or every loop if it repeats) |
| `yajirushi` (arrow over an ant, mosquito or killifish held up for the report) | `CatchMark` |
| `otosiana` (mud as a pitfall opens and closes) | `FootstepEffects.otosiana`, called from `BuriedUse` |
| `yukidaruma` (a snowman breaking) | `SnowmanBreak` |
| Fireworks, meteors, pond moon, statue sparkle, impact star, coin, museum bubbles, sunshine beams, axe break | their own presenters (`fireworks.gd`, `meteor_shower.gd`, …) |

## Late ports

| Effect | Port |
| --- | --- |
| `clacker`, `kamifubuki`, `tape` (the New Year's Eve party poppers; `aCD1_fire` plays its clip three times, a popper at keyframe 3 each) | `PartyPopper` (CPU sim in ticks, two `MultiMesh`es), fired by `FestivalVillager._fire_poppers` |
| `halloween`, `halloween_smoke` (the puff round the player after a trick changes their clothes or swaps a pocket item) | `CostumePuff` + `FieldParticle` `HALLOWEEN_SMOKE` (the original's `ef_haro01_00` card is not baked; the dust card stands in), from `TrickOrTreatTalk._trick` |
| `slip` (a dispatcher onto dust / snow kick / sand / spray) and `slip_footprint` (the skid's foot mark, `ef_footprint01_02`) | `NetSwing` `slip_fx` / `slip_print` events → `FootstepEffects.net_slip` / `slip_footprint`, `FieldEffects.Kind.SLIP_PRINT` |
| `turi_mizu`, `turi_hane1` | already `FootstepEffects.bobber_splash` (arg 0–8) and `ef_turi_hane02`; the wishing-well coin now calls arg 0 when it hits the water (`ef_coin`) |
| `flashc` / `flash` (the camera flashes when the gong rings in a ringside-seating room) | `GongFlash`, from `FurnitureUse.toggle` |
| `killer` (the cannon furniture's shell) | `CannonShot` (`act_killer` baked as a static row), from `FurnitureUse.toggle` by contact side |
| `make_hem` (the well spirit's glow: a sphere, 16 twinkles, the swap at tick 150) | `SpiritGlow`, around `WellSpirit.appear` / `_vanish` |

## Also ported

| Effect | Port |
| --- | --- |
| `kagu_happa` (the furniture's icon flying from the player to where it is set down; `aMR_SetReserveFurniture`) | `LeafFlight`, from `FurnitureEditing.place_held` and the pockets' put-down |
| `make_hem_light` (the pale circle under the spirit) | `SpiritLight` (`ef_circle_light` baked as a static row), kept by `WellSpirit` until it leaves |
| `car_blight`, `car_light` (a washed car glitters; a quick wash also gleams) | `CarBlight`, run by `Gracie._tend_car`, which also tints the car dirty → white by presses / 100 (`aSCR_set_prim_col`) |
| `flash`'s `regist_effect_light` | `GongFlash._light_room`: an omni light on every other flash |

Everything reachable in the decomp's effects is now ported. Two approximations stay: the
Halloween puff uses the dust card (`ef_haro01_00` is not baked), and the spirit's sphere and
the car's gleam use a facing-angle falloff in place of the original's hilite-reflect texgen.
