# Player

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not copy the player actor struct or `mPlayer_INDEX_*` table into GDScript.

**Read before implementing:** player scene movement, tool use, talk lock, indoor furniture contact.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_player.h` | Main-index enum (~100 modes), joints, addressable flags, debt constants |
| `include/m_player_lib.h`, `src/game/m_player_lib.c` | `mPlib_request_main_*` — other systems ask the player to change mode |
| `src/game/m_player_main_walk.c_inc` | Analog walk vs run: **4.875** vs **7.5** |
| `include/m_controller.h` | Stick `move_pR` / `move_angle` |
| `include/m_private.h` | Persistent player: pockets, cloth, birthday, equipment |
| `include/m_camera2.h` | Follow / talk / door cameras |
| `src/effect/ef_footprint.c` | Footprint decal: attribute gate, slope fit, 160-frame fade |
| `src/game/m_player_common.c_inc` | `Player_actor_Set_FootMark_*` — per-foot spawn on animation frames |

Key functions: `mPlib_request_main_talk_type1`, `mPlib_request_main_wait_*`, `mPlib_request_main_hold_type1`, `mPlib_request_main_give_type1`, `mPlib_get_player_actor_main_index`, `mPlib_Check_able_force_speak_label`.

## What does the original system do?

The player is a single actor with a **main index** state machine. Movement, tools, doors, furniture, demos, and talk are mutually exclusive modes (`mPlayer_INDEX_WAIT`, `WALK`, `RUN`, `DASH`, `PICKUP`, `SWING_AXE`, `READY_ROD` … `TALK`, `SHAKE_TREE`, …). Other systems never poke bones directly; they **request** a mode via `mPlib_request_main_*`.

Stick magnitude picks walk vs run (normalized against 7.5 run, 4.875 walk). Sprint/dash is a further index. Wade, snow, and furniture push have their own modes.

`mPlayer_ADDRESSABLE_*` gates whether NPCs may start dialogue: false while moving, talking, or holding a ready net.

Appearance (cloth, face) and inventory live in `Private_c`, not the actor. Equipped item is `Private_c.equipment`. House debt tiers are named constants (`mPlayer_DEBT0` … `DEBT4`) used by Tom Nook, not by locomotion.

## Footprints

`Player_actor_Set_FootMark_MarkOnly` spawns `eEC_EFFECT_FOOTPRINT` once per foot, at
`left_foot_pos` / `right_foot_pos` with that foot's yaw, on animation frames tagged per clip
(walk1/run1/dash1: left frame 1, right frame 9). It passes
`bg_collision_check.result.unit_attribute` straight through and the same call drives the
footstep sound, so the mark and the sound share a trigger.

The gate lives in the effect, not the player: `eFootPrint_ct` sets `timer = 0` — an instant
death — unless the attribute is `SAND` or `WAVE` (any season) or a `GRASS0`–`GRASS3`
attribute in winter. Stone, soil, wood, and water never take a print. A surviving mark snaps
to the shadow ground Y plus 2 GX, averages ground angles over a ±2 GX probe triangle so it
lies on slopes, and lives 160 frames with alpha held at 150/255 then faded over frames
118→159. Prim color is `(70,50,50)` on sand and `(0,50,100)` on snow. Wave units also emit a
ripple at spawn and again at timer 150.

The mark's shape and size come straight off the original data, not an estimate.
`ef_footprint01_00_v` is a flat 4-vertex quad at ±1000 units in X and Z (all Y zero, normal
+Y), and `eFootPrint_dw` applies `Matrix_scale(0.005, ·, 0.0075)`, so the quad is 10 × 15 GX
= **0.50 m wide × 0.75 m long**. Length runs along the facing, because the yaw rotation
(`Matrix_RotateY(effect_specific[2])`) is applied before the scale's Z axis. The 2:3 ratio is
corroborated by `ef_turn_footprint` and `ef_slip_footprint`, which pass `scale` on *both*
in-plane axes — their scuffs are round, only the footprint is elongated.

The 16x16 I4 mask (`ef_footprint01_0`) draws an elliptical rim at intensity 7 around an
interior of 1–2, zero outside — a soft depression, with no toes and no distinct heel. The rim
is not inset uniformly: its peak sits 3.5 texels in from the quad edge across but only 1.5
texels in along the length, so the rim ellipse is **0.281 × 0.609 m**. The combiner
(`gsDPSetCombineLERP`) takes RGB from `PRIMITIVE * SHADE` and alpha from
`TEXEL0 * PRIMITIVE`, so the tile is purely a mask, and its 7/15 ceiling multiplies the
150/255 prim alpha — a fresh print peaks at 0.27 alpha, not 0.59.

The mark is **soft**, and a crisp SDF gets it visibly wrong. Two things blur it: 16 texels
stretched over this quad is 3–5 cm per texel and gets filtered, and the mask's own profile
ramps (0, 3, 7, 5, 2) rather than stepping. Rim width at half maximum measures 2 texels
across and 3 along, so the falloff is ~6–9 cm, not the millimetre edge an SDF gives by
default. The falloff is bounded rather than gaussian: bilinear magnification of a discrete
profile is piecewise linear, and a gaussian's tails wash the rim out instead of leaving the
defined-but-soft band the game shows. `MARK_SIZE` pads the drawn quad past the original's so
that falloff completes inside the mesh rather than being sliced off at its edge.

`gsDPSetTile_Dolphin` does set `GX_MIRROR` on S and T, but the vertex texcoords span exactly
0–512 in S10.5 (16 texels of a 16-texel tile), so UV never leaves [0,1] and the mirror never
engages. The tile is drawn once, unmirrored; the symmetry above is simply how it was drawn.

`ef_turn_footprint` and `ef_slip_footprint` are the same effect with a different model and a
2→8 frame scale-in; slip offsets 6 GX along the facing.

Godot: `FootprintMarks` owns the gate, fade curve, cadence, and slope fit;
`scenes/world/footprints.gd` is a 96-instance MultiMesh ring buffer under the world's
`Effects` node; `shaders/footprint.gdshader` reproduces the rim/dish profile as an SDF at the
measured size, so no original art is converted. `player.gd` alternates feet on a cadence
derived from the gait clip's speed scale — the generated clips carry no frame tags, but a
per-frame trigger is really a fixed time between steps, so tracks still spread out as the gait
speeds up. Villager prints (`ac_npc_anime`), the turn/slip variants, the wave ripple, and
footstep sound are not built. Nor is `Player_actor_SetFootMark_for_settle_main`, which stamps
*both* feet at once when the player settles out of a move — walking alternates, but coming to
a stop leaves a pair.

Placement follows the original rather than a fixed stance. `Player_actor_draw_After_Lfoot3` /
`_Rfoot3` call `Matrix_Position_Zero` on the `LFOOT3` / `RFOOT3` joint, so a print sits at that
joint's own origin and takes its yaw — there is no lateral offset constant and the body's
facing is not used. Our `boy_1.glb` rig carries the same joints (`Lfoot3_boy_model` /
`Rfoot3_boy_model`, indices 5 and 9, matching the `mPlayer_JOINT_*` order), so `player.gd`
samples them directly; prints therefore land where the feet land and each is turned the way
that foot is. `FootprintMarks.FOOT_OFFSET` remains only as the fallback for a visual with no
rig. The joint's Y is discarded either way: the original takes height from
`GetShadowBgY` + 2 GX, as `mark_transform` does.

The attribute gate is sampled at the *body*, not at the foot: the call passes
`actorx->bg_collision_check.result.unit_attribute`, the actor's own collision result. So a
print can land a few centimeters onto a neighboring unit, and both feet always agree on
whether the ground marks at all. `player.gd` matches this by gating on `global_position` while
placing at the joint — that mismatch is intentional, not an oversight.

The material carries `render_priority = 3`, above the ocean/river sheets (1) and the mouth
splash (2). This is load-bearing, not cosmetic: at the default priority Godot's transparent
queue drew the prints before the shore water, and the water then painted over every mark on
wet sand — so prints seemed to stop partway down the beach no matter what height, colour, or
depth mode they used. The original has the same layering, drawing footprints into the XLU
effect pass after the field's own XLU water.

## Important states

- **Main index** (current action).
- Requested next index (pending `request_main_*`).
- World position / facing; forced position flags for cutscenes.
- **Addressable** (can be talked to).
- **Held / equipped item**; tool-specific substates (rod ready/cast/vib, net ready/swing). Equipped Gfx/cKF follow `mPlayer_JOINT_HAND` (joint 20) via `HeldTool`.
- Indoor furniture contact (push, pull, rotate, sit, lie on bed).
- Demo lock (`DEMO_WAIT`, train, boat).
- Tired / stung / pitfall (interrupt locomotion).

## Inputs

- Controller stick + face buttons (A interact, B cancel/put away, Y/Start inventory).
- Collision heightfield and water attributes (`mCoBG_GetBgY_*`). Off-map units are blocked. Acre wade (`mFI_WADE_*`) loads the next BG acre; it is not a world-edge wall.
- New-scene spawn: XZ at the unit center (`mFI_BkandUtNum2CenterWpos`), Y = `mCoBG_GetBgY_OnlyCenter_FromWpos2(pos, 0)` (feet on the unit-center height, no extra lift). Each frame `mCoBG_BgCheckControll` (`attr_wall` on for the player): **WallCheck** (cardinal unit-edge segments where neighbor corners differ, plus 45° slate walls, plus attribute walls) then **GroundCheck** (`GetBgY` at the current XZ — water is a heightfield, not a pit) then **CarryOutReverse** (push XZ back). Godot resolves that as a **circle vs infinitely thin XZ segments** (`revise_xz`, radius **18 GX / 0.9 m** like `BgCheckControll`) so actors slide along cliffs and banks instead of catching 3D box or triangle corners. Slate units keep flat high/low side heights (`GetBGHeight_Normal_SlateGround`) so Y does not blend into the cliff face. Trees, buildings, and map bounds stay physics. The player collider is a **cylinder** (original is a circle in XZ) for remaining physics. Feet stay on the heightfield; gravity never runs over a river. Snap uses the current XZ, not the unit center — that buried the capsule in slate ramps. This slice still refuses walking onto river/sea (no fishing/wade). Shoreline wave units are walkable sand.
- Requests from NPC, submenu, shop, fishing bobber, insect catch.
- Scene transitions (door, outdoor, invade other house).

## Outputs / events

- Position updates for camera and acre streaming.
- Animation / tool traces (net swing volume, axe on tree, scoop dig).
- Mode changes that spawn FG items (drop), consume durability, or start `m_msg`.
- BGM volume ducking while fishing or catching bugs (`mPlayer_BGM_VOLUME_MODE_*`).
- “Player acted on this unit” timestamps for insects (`aINS_PL_ACT_SHAKE_TREE`, scoop, axe).

## Interacts with

- **World** — collision, doors, wade.
- **Interaction / inventory** — pickup, present, give, tag menus.
- **Dialogue / villagers** — talk request + camera.
- **Furniture** — hold, push/pull/rotate, sit/lie, open storage.
- **Fishing / bugs / plants** — rod, net, axe, scoop, shake.
- **Shops** — receive/give at counter.
- **Save** — `Private_c` (not the live actor pose).

## Reproduce

- **Walk vs run** from analog magnitude; a sprint modifier.
- One **locked action** at a time (cannot walk-and-fish; talk freezes locomotion).
- Interact from a facing tile, not a 360° magnet.
- Put-away / cancel for tools.
- Door enter/exit as a short locked anim, then scene change.
- Outdoor camera follow; tighter camera when talking.
- Actor origin on the unit heightfield (`GetBgY` / `BgCheck`), not a guessed offset above a physics mesh.

## Simplify

- Collapse the 100+ indices into a small Godot state machine: idle, move, interact, tool, talk, menu, scene-transition.
- One tool animation set per tool, not air/reflect/broken variants for every item.
- Ignore dash-turn, tumble, umbrella, fan, snowball as first-slice locomotion.
- Meter-scale speeds from the 4.875 / 7.5 per-frame values: one 40-unit tile is one 2 m cell, so walk is 7.31 m/s and run 11.25 m/s relative to the acre.
- Player / NPC meshes use actor draw scale `0.01` (`m_actor.c`), not AABB-fit to an invented height. `FieldCatalog.actor_uniform_scale()` maps pipeline `0.001` GLBs into that same 2 m cell.

## Ignore

- Train, boat, island wade demos.
- Radio calisthenics, golden axe/item demos, shrine throw-money / pray.
- Pitfall, bee/mosquito sting sequences, groundhog, wash-car.
- Sunburn ranks, reset count, e-Card letters.
- Multi-player house invade (`INVADE`) and four-save-slot character switching until multiplayer is in scope.
- Joint-level face/mouth texture swapping (`mPlib_Get_PlayerEyeTexAnimation_p`).
