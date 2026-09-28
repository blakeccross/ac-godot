# Lighthouse

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only.

## Godot

`LighthouseBook` on `Game` (saved as `lighthouse`) decides everything: lamp on/off, door open, switch mode. Outdoor tower `scenes/world/buildings/lighthouse.tscn` (`building.gd` + `Door` + `Beacon` lamp). Switch room `scenes/world/interiors/lighthouse.tscn` (`lighthouse_room.gd`) with `lighthouse_switch.tscn` (lever, lens drive, room light). Layout constants: `LighthouseRoom`. Debug: `/lighthouse start|lit|clear|status`.

## Decomp sources

| File | Role |
| --- | --- |
| `src/actor/ac_toudai*.c*` | Tower: collision, RSV door units, lamp states, beam colour, door request |
| `src/game/m_soncho.c` (`mSC_LightHouse_*`) | Quest periods, switch / door checks, reward |
| `src/actor/ac_lighthouse_switch.c` | Room lever, lens drive, room light |
| `src/data/scene/lighthouse.c` | Room actors (`LIGHTHOUSE_SWITCH`), player data |
| `src/data/model/obj_s_toudai.c` | Tower skeleton, arm clip, beam combiner |
| `src/game/m_player_main_switch_on_lighthouse.c_inc` | `ply_1_light_on1` at the panel |
| `src/actor/npc/event/ac_ev_soncho2*` | Tortimer's vacation: hands out the quest |
| `src/actor/ac_present_demo_move.c_inc` | Reward delivery (period 2) |
| `src/game/m_bgm.c` | Room BGM 90 (an empty sequence) |

## Behavior

- **Tower** (`aTOU_actor_ct`): drawn at the FG unit −20,−20 GX; `set_bgOffset` raises the 2×2 units NW of the FG unit to 16 on every corner (solid, no porch). The two units at −40/0 X, −80 Z (in front of the door) are `RSV_NO`: whatever the FG put there is taken off. Winter uses `obj_w_toudai` + its own clip.
- **Lamp** (`aTOU_wait` / `lighting` / `lightout`): arm clip frames 1–100 repeat, rests on frame 51. Turns while `now_sec >= 64800 || < 18000` **and** `mSC_LightHouse_Switch_Check`. Lit speed 0.5 (Godot 1×). When it may not turn it keeps sweeping until frame 51, then stops. No light is cast on the field.
- **Beam** (`aTOU_color_ctrl`, `draw_after` joint 4): XLU `*_light_model`, prim `(255,255,b,a)`, alpha × `PRIM_LOD_FRAC`. At frame 51 `b=220 a=240`; per tick away from 51: `|d|<10` −4.5/−7, `<30` −1.25/−2.25, `<40` −4/−0.5, else `add_calc` to 0 (`1−√0.7`, max 50, min 0.5); approaching 51 the same steps rise. The fade (`PRIM_LOD_FRAC`, and the alpha cap) eases to 255 while sweeping (`1−√0.9`) and back to 0 at rest. Not drawn while `(int)a == 0`. The GLB's baked beam colour is stale — the lamp overrides it.
- **Door** (`aTOU_check_door_pos`): north face — |dx| < 20, −65 < dz < 0 from the tower, facing within ±45° of south. Walk-in (no A), only while `mSC_LightHouse_In_Check`: a quest night (period 1), 18:00–21:59, tonight not yet switched, not during the first job. INTO_S1 target −60 Z. Leave: 70 GX north, facing north, full walk-out (`extra_data` 3), triforce wipe.
- **Quest** (`mSC_LightHouse_*`): `renew_time` = the day Tortimer gives it (period 0). Days +1…+7 period 1, +8…+17 period 2, then none. Night index = days since start − 1 (0–6). `Switch_Check` reads time −6 h, so a switch thrown before midnight keeps the lamp on until 05:00. No quest ⇒ lamp always allowed, door never opens. Jan reward `FTR_TAK_TOUDAI`, Feb `FTR_IKE_JNY_MAKADA01`.
- **Room** (`rom_toudai`): spawn `{120,0,100}` facing south, `EXIT_DOOR` at units (2,0)/(3,0) on the north rim. Floor units 4 counts, the pit rail 6 (20 GX), walls 31. BGM 90 is empty: the room is quiet.
- **Switch room** (`ac_lighthouse_switch`): mode by `aLS_GetNiceStatus` — day off; night outside period 1 auto (lever flips itself, drive spins, light on); period-1 night manual. Manual: A within 33.57 GX of `{180,100}` facing 90°–180° with the lever off → player `ply_1_light_on1` at `{167.27,40,112.73}` facing 135°; past player frame 1 `mSC_LightHouse_Switch_On`. Lever clip at 0.5, SE `0x78` crossing frame 20; when home the drive starts (two kicks 0.065 / 0.85·0.065 at ticks 0 and 30, then +0.0035 a tick, cap 0.5) and the point light eases on (0.02). Off: drive coasts −0.001 to 0.1, eases up 0.07, swings back 100→1 at 0.17 and settles; 49 ticks later the lever drops; light fades 0.002 a tick. Point light `{120,80,160}` colour (235,190,185).

## Not built

- Tortimer's vacation event (`ac_ev_soncho2`, `SONCHO_VACATION_*` are `EventSchedule.UNSUPPORTED`), so the quest only starts from the debug console.
- Reward delivery (period 2) and the "all nights lit" bonus.
- Drive motor level SE `0xC9` and stop SE `0x79` (not rendered by the audio pipeline; one SysLev channel).
- The facing window (90°–180°) and the stand snap to `{167,40,113}` — the player faces the panel from where they stand.
- Fixed lighthouse room kcolor (`l_mEnv_kcolor_lighthouse`): the room uses the shared interior light.
