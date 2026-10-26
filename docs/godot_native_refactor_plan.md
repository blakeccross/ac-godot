# Plan: refactor toward a Godot-native codebase

Goal: make the project read and run like a game that was designed in Godot 4. That means scene-per-entity nodes, time in seconds, `AnimationTree` / `AnimationPlayer` / `Tween` / `Timer` for motion and timing, signals for coupling and plain English names. Today it reads as a port of the GameCube decomp.

The decomp stays a **behavioral reference**: what things do, roughly how fast and how often. It stops being a **numerical reference**, so we no longer reproduce its per-tick integration step for step.

Sources: the [godot-claude-skills](https://github.com/alexmeckes/godot-claude-skills) pack (`godot-code-gen`, `godot-scene-design` and `godot-shader`), the official GDScript style guide, and a survey of this repository (numbers below are from `git grep`, excluding `addons/` and `tests/`).

---

## 1. Where the codebase is today

| Pattern | Files | Hits | What it means |
| --- | --- | --- | --- |
| `DecompTime` | 93 | 240 | Logic expressed in 60 Hz ticks / 30 fps frames |
| `FrameStepper` (fixed-tick loop over `delta`) | 45 | 69 | Behavior runs `while steps.next(): _tick()` |
| `timer -= 1` / `counter += 1` style countdowns | 27 | 48 | Integer frame counters instead of seconds |
| "per tick" / "a tick" in code comments | 36 | 66 | Tuning described in ticks |
| `s32_work` / `f32_work` scratch arrays | 14 | 175 | Decomp actor work slots instead of named fields |
| `action_proc` / `move_proc` / `setup_action` | 21 | 302 | Decomp actor-program dispatch through `Callable`s |
| GX units (`_gx`, `GX_TO_METERS`) | 146 | ~1,700 | Distances and speeds in decomp units, converted at use |
| `.call("…")` + `has_method(…)` | 88 / 76 | 241 / 182 | Duck-typed string calls instead of typed APIs or signals |
| `get_first_node_in_group` | 50 | 129 | Global lookups instead of injected references or signals |
| `MeshInstance3D.new()` / `Node3D.new()` / … | 58 | 153 | Visual trees built in code |
| `AnimationTree` | 3 | 6 | Almost every clip is driven by hand (`play`, `seek`, `advance`, `speed_scale`) |
| `signal` declarations | 45 | 100 | Light signal use for a project of this size |
| `enum State` / state machines | 6 | 7 | States are mostly implicit (action ints + callables) |

Structural hot spots:

- `scenes/actors/player.gd` is **3,840 lines**, with seven separate `FrameStepper`s (radio, net, door, talk turn, snowball, sun…).
- `scenes/actors/villager.gd` is 2,206 lines.
- `scripts/systems/game.gd` is 2,668 lines: the autoload owns almost every book of game state.
- `scripts/systems/` holds 272 scripts in one flat folder.
- Bugs and fish are `RefCounted` simulations (`BugActor`, `FishShadow`) ticked by a manager and drawn by separate visual nodes, rather than one scene per creature.
- Many class names are decomp or Japanese romaji: `BugSemi`, `BugGoki`, `BugDango`, `BugBatta`, `BugKera`, `BugKa`, `BugChou`, `BugHotaru`, `BugTonbo`, `BugKabuto`, `BugMino`, `BugTentou`, `BugAmenbo`, `HouseGoki`, `HaniwaStore`, `HaniwaTalk`, `KabuMarket`, `Ongen`, `FtrCatalog`, `FgCatalog`, `FarwayBook`, `TreeFx`, `StepFx`. Field names include `anime0`, `alpha0`, `bg_type`, `f_bit4`, `ongen`, `trg_se`, `ut_x` and `gyoei_term`.
- 75 test files (330 sites) step logic a fixed number of ticks and assert exact values. These tests are the biggest cost of changing the time model.

`docs/conventions.md` § *Decomp time* **mandates** the tick model today. Phase 0 rewrites that section; nothing below should start before it does.

---

## 2. Target shape

What "originally made in Godot" looks like for this game:

- **One scene per thing in the world.**
  - A cicada is `cicada.tscn`: `CharacterBody3D` or `Node3D` → model, `AnimationPlayer`, a catch `Area3D`, and a `Behavior` child.
  - Spawners instance scenes; they don't simulate invisible records.
- **Time in seconds.**
  - Exported tuning values in seconds, metres and metres per second (`@export_range(0.0, 5.0, 0.05, "suffix:s") var hide_delay := 1.0`).
  - Motion integrates with `delta`.
  - Waits use `Timer` nodes, `await get_tree().create_timer(t).timeout` or `Tween`.
  - No fixed-tick loops in gameplay code.
- **Animation is data, not code.**
  - Characters use an `AnimationTree` with a state machine: locomotion blend-space by speed, plus one-shots for tool actions, talk and emotes.
  - Footstep sounds, effects and "the swing connects now" moments are **method-call or audio tracks** on the clip, not frame-number checks in scripts.
  - Props use `AnimationPlayer` clips or `Tween`s.
- **Explicit state machines.**
  - Use `enum State` with `_enter_state` / `_exit_state` (the pattern from `godot-code-gen`), or child `State` nodes for big actors.
  - Replace the `action_proc` callables and integer `action` codes.
- **Signals for "something happened", typed references for "do this".**
  - No `.call("method")` or `has_method` on known types.
  - Groups only for genuine broadcasts (all bugs scatter, all lights off).
- **English names everywhere.**
  - Decomp symbols stay **in comments only**, as citations (`## ac_insect_semi.c`).
  - `class_name`, files, nodes, members and signals use plain names: `Cicada`, `Cockroach`, `PillBug`, `Gyroid`, `StalkMarket`.
- **Units: metres in code.**
  - GX survives only where the pipeline or data files speak it, converted once at load.
- **Feature folders.** Scene, script and resources for one feature live together (`features/bugs/cicada/`). See Phase 7.

---

## 3. Phases

Each phase leaves the game playable and the suite green. That means green at the level of the baseline: the tests that already fail on `main` are listed in the merge notes. Do the work in small PRs, one system per PR.

### Phase 0: ground rules (1 PR, no gameplay change)

1. Rewrite `docs/conventions.md` § *Decomp time* into **§ Time and units**:
   - Gameplay is delta-based.
   - Decomp numbers are converted to seconds and metres **when authored**, with the source cited in a comment.
   - `FrameStepper` is banned in new code.
2. Add a `## Naming` subsection: English names; decomp identifiers only in comments; a lookup table for the romaji names (see Phase 1).
3. Add small helpers in `scripts/systems/motion.gd` (`class_name Motion`, done):
   - `Motion.damp(current, target, half_life, delta)`, plus `damp_vec3` and `damp_angle`: framerate-independent exponential smoothing. These replace `add_calc` / `chase_f`.
   - `Motion.happens(rate_per_second, delta, rng)`: a Poisson chance, `1 - exp(-rate * delta)`. This replaces "roll `RANDOM` every frame".
   - Authoring helpers: `Motion.half_life_from_fraction` (`MLib.HALF_FRACTION` closes half the gap every two ticks, about 0.033 s) and `Motion.rate_from_chance`. `DecompTime` stays, marked *authoring-only*.
4. Testing policy in `docs/testing.md`:
   - New tests drive with `delta` (for example 0.1 s steps) and assert **outcomes and tolerances** ("the bug has fled at least 3 m within 2 s", "it lands back on its tree"), not tick-exact values.
   - Golden captures (`tools/capture.sh`) are the visual regression net for motion.

### Phase 1: names (mechanical, low risk)

Rename with the Godot editor's *Rename* (so `.tscn`/`.tres` references and UIDs follow) or a scripted pass, plus `tools/test.sh` after each batch. Old names are recorded in `docs/decomp-mapping.md`, so the decomp trail stays searchable.

| Current | New |
| --- | --- |
| `BugSemi` | `Cicada` (+ `Bee` split out of it) |
| `BugGoki`, `HouseGoki` | `Cockroach`, `HouseCockroach` |
| `BugDango` | `PillBug` (ant crawl stays in `Ant`) |
| `BugBatta` | `Grasshopper` |
| `BugKera` | `MoleCricket` |
| `BugKa` | `Mosquito` |
| `BugChou` | `Butterfly` |
| `BugHotaru` | `Firefly` |
| `BugTonbo` | `Dragonfly` |
| `BugKabuto` | `Beetle` |
| `BugMino` | `Bagworm` |
| `BugTentou` | `Ladybug` |
| `BugAmenbo` | `PondSkater` |
| `BugHitodama` | `Wisp` |
| `BugProgram` | `BugBehavior` |
| `BugBg` | `BugTerrain` |
| `Haniwa*` | `Gyroid*` |
| `KabuMarket` | `StalkMarket` |
| `Ongen` | `SoundEmitter` |
| `FtrCatalog` | `FurnitureCatalog` |
| `FgCatalog` | `FieldObjectCatalog` |
| `FarwayBook` | `TravelBook` |
| `TreeFx` / `StepFx` / `FieldFx` | `TreeEffects` / `FootstepEffects` / `FieldEffects` |
| `Game.gyoei_term*` | `Game.fish_season_term*` |
| `MLib` | `MathUtil` |

Fields on actors are renamed in the same pass:

| Current | New |
| --- | --- |
| `anime0` / `anime1` | `anim_time` / `wing_time` |
| `alpha0..2` | `opacity` |
| `bg_type` | `terrain_mode` (enum) |
| `f_no_catch` / `f_bit2` / `f_bit4` | `catchable` / `escaping` / `wall_check` |
| `ongen` / `trg_se` | `loop_sound` / `one_shot_sounds` |
| `ut_x` / `ut_z` | `unit` (`Vector2i`) |
| `s32_work[n]` / `f32_work[n]` | Named fields per behavior. This is the main manual work: read each use and name it. |

Save-file keys are versioned: add a migration in `SaveService` for any renamed key (`gyoei_term` and similar), so old saves load.

### Phase 2: time model, leaves first

Replace tick loops system by system, from the least to the most coupled. For each one:

1. Convert its constants to seconds, metres and metres per second.
2. Delete its `FrameStepper`.
3. Integrate with `delta`.
4. Rewrite its tests to outcome or tolerance style.
5. Compare a before/after capture.

Conversion recipes:

| Decomp idiom | Godot replacement |
| --- | --- |
| `timer--` until 0 | `var time_left: float` −= `delta`, or a `Timer` node (`one_shot`, `timeout` signal), or `await create_timer` |
| `add_calc(x, target, frac, max_step)` | `Motion.damp` with `half_life_from_fraction(frac)`, then clamp the step with `move_toward(x, target, max_speed * delta)` |
| `chase_angle(yaw, target, step)` | `rotate_toward(yaw, target, turn_speed * delta)` |
| `speed` in GX/frame | metres per second (`gx * GX_TO_METERS * 30`), `position += velocity * delta` |
| `gravity *= 1.1` per tick | `velocity.y -= gravity * delta`, with gravity in m/s² fitted to the same apex and flight time |
| per-tick `RANDOM` rolls | `Motion.happens(rate_from_chance(p), delta, rng)`, or a `Timer` with randomized `wait_time` |
| `game_frame % N` cadences | a repeating `Timer`, or an `AnimationPlayer` loop |
| frame-numbered clip events | method-call or audio tracks on the clip (Phase 4) |
| fade 255 → 0 by 15 a tick | `create_tween().tween_property(self, "opacity", 0.0, 0.28)` |

Order (each line is about one PR):

1. **Pure effects:** `tree_fx`, `weather_fx`, `statue_sparkle`, `impact_star`, `field_fx`, `well_coin`, `npc_feel_glyphs`, `title_logo`, `furniture_ambience`.
2. **Props:** `field_ball`, `snowball`, `snowman`, `broken_axe_piece`, `bobber`, `fish_release`, `held_bug`, `held_fish`.
3. **Furniture interaction:** `furniture_grip`, `furniture_seat`.
4. **Cameras and intro:** `follow_camera`, `intro_train_*`, `intro_station_*`, `train_service`. Prefer `Path3D` + `PathFollow3D` + `Tween` for the train; this also covers the "train pulls in and out" gap.
5. **Events:** `foot_race`, `tug_of_war`, `toss_ball`.
6. **Fish:** `fish_shadow`, `fish_school`, `fishing` (together with Phase 3's fish scene).
7. **Bugs:** `bug_actor`, `bug_field` and the 15 behaviors (together with Phase 3's bug scenes).
8. **NPC faces and heads:** `npc_face_anim` and the head-look systems, as `AnimationTree` blend or `Tween`s.
9. **Player and villagers last:** `player_locomotion` and the seven player steppers, then `villager_motor` / `villager_walk`. Their feel depends on everything above, and they get the `AnimationTree` in Phase 4 at the same time.

After the last item, delete `FrameStepper` and narrow `DecompTime` to authoring helpers. (Done.)

### Phase 3: creatures and props as scenes

- **Bugs:**
  - `BugActor` (a `RefCounted` record) + `bug_actor_visual` + `BugField` becomes `bug.tscn`: `Node3D` → `Model`, `AnimationPlayer`, `CatchArea: Area3D`, `Behavior: Node`.
  - Each species is an inherited scene (`cicada.tscn`, `butterfly.tscn`, …) with its behavior script and exported tuning.
  - `BugField` becomes a `BugSpawner` that instances scenes at the habitat sites `BugHabitats` already finds.
  - Net catches use the `Area3D` (`area_entered` from the net's swing area) instead of distance math each tick.
- **Fish:** `FishShadow` / `FishSchool` / `fish_shadows.gd` become `fish_shadow.tscn` instances under a `FishSpawner`. The bobber detects bites with an `Area3D` "interest cone" (or a `ShapeCast3D`).
- **Museum tank and case actors** reuse the same creature scenes in a "display" mode.
- **Code-built visuals (153 sites):**
  - Replace them with packed scenes: clocks, sunbeams, stock, hulls, markers.
  - Fixed layouts (shops, museum, police box and post office interiors) move into their `.tscn` as `Marker3D`s and instanced scenes. The `*Presenter` classes shrink to "fill today's stock into the markers".
- **Collision layers:**
  - Extend the named layers in `project.godot` (today: world, player, actors, interact) with `creatures`, `pickups`, `water` and `triggers`.
  - Every scene sets layers in the `.tscn`, not in `_ready`.

### Phase 4: animation

- **Player:**
  - `AnimationTree` with `AnimationNodeStateMachine` states: `Locomotion` (a `BlendSpace1D` over idle → walk → run by horizontal speed), `Tool` (one-shots for swing, dig, cast and net), `Carry`, `Talk`, `Emote`, `Sit`, `Lie`, `Door`.
  - Transitions are driven by conditions or `travel()` from the player's state machine.
  - This removes the hand-written `play`, `seek`, `advance` and `speed_scale` bookkeeping in `player.gd`.
- **Villagers:** the same tree shape, with one shared `AnimationNodeStateMachine` resource and per-species libraries.
- **Clip events:**
  - Footsteps, tool contact, splash and line-out become method-call tracks (`_on_anim_footstep`, `_on_tool_contact`) added to the imported libraries.
  - Add them in a pipeline post-import step (`EditorScenePostImport`) so the GLBs stay generated.
  - The clips are already baked at 30 fps by the pipeline, so playback in seconds needs no change.
- **Faces:** eye and mouth swaps become animation tracks on the face material (`AnimationPlayer` on the head) or a small `AnimationTree` layer, instead of `NpcFaceAnim` counters.
- **Props:** windmill, lighthouse beam, xmas lights, the train, balloons and the airplane use looping `AnimationPlayer` clips or `Tween`s.

### Phase 5: decoupling and size

- **Break up the oversized scripts by responsibility into child-node components:**
  - `player.gd` becomes `Player` (movement and input) plus `PlayerTools`, `PlayerCarry`, `PlayerFishing`, `PlayerTalk`, `PlayerDoors`, `PlayerSnowball` and `PlayerFurniture`.
  - `villager.gd` becomes `Villager` plus `VillagerBrain` (schedule and AI), `VillagerMover` and `VillagerTalk`.
  - Each component is a `Node` child declared in the `.tscn`, with `@onready` references.
- **`Game` autoload:**
  - Move state into `Resource` classes: `TownState`, `PlayerState`, `ShopState`, `MuseumState`, … These are mostly the existing `*Book` classes.
  - `Game` keeps the session flow and holds the resources.
  - Saving becomes "serialize these resources". Keep the JSON format and migrations.
- **Typed calls:**
  - Replace `.call("x")`, `has_method` and `get_first_node_in_group` on known types with typed `class_name` references (the `Player.find(tree)` pattern already in `conventions.md`).
  - Use signals for notifications: `item_picked`, `talk_finished`, `shop_bought`, …
  - Keep duck typing only where `conventions.md` already allows it.
- **Interaction:**
  - Replace per-object `get_interactions` / `interact` verbs with an `Interactable` component (a `Node` with `@export var verbs` and an `activated(verb)` signal) attached in the scene.
  - `InteractionQuery` then asks that component.

### Phase 6: units

Convert the remaining GX constants (about 1,700 sites) to metres as each system is touched. For constants not yet converted, use `const X_M := 12.0 * FieldCatalog.GX_TO_METERS`. Data tables that are inherently GX (FG positions in baked JSON) keep GX and convert in the loader. Finish by making `GX_TO_METERS` private to the loaders.

### Phase 7: folder layout (optional, last)

Co-locate by feature, which is the common Godot layout for games of this size:

```
features/
  bugs/      bug.tscn, bug.gd, bug_spawner.gd, cicada/cicada.tscn, cicada.gd, …
  fishing/   fish_shadow.tscn, fishing.gd, bobber.tscn, …
  shops/     nook/…, able_sisters/…
  villagers/ villager.tscn, villager.gd, components/…
core/        game.gd, clock.gd, save_service.gd, audio.gd, motion.gd
data/        (unchanged .tres)
```

This is pure moves. Do it in one PR per feature using the editor's move, so UIDs follow and diffs stay reviewable, and only after Phases 1–5. Doing it earlier conflicts with every other PR.

---

## Progress

- **Phase 0 done:** the conventions, testing and `AGENTS.md` rules, plus `Motion`.
- **Phase 2 pilot done:** `ImpactStar` and `TreeFx` run on seconds and metres, with no `FrameStepper`.

- **Converted to seconds:** statue glints, well coins, the title logo and furniture steam and clip sounds.
- **Field effects rebuilt:** sixteen kinds, two homes.
  - `FieldParticle` covers dust, steam, smoke, sand, water and snow kicks, drops, and umbrella spray. Each is a one-shot `GPUParticles3D` on a closed-form path. Drops solve their landing time up front.
  - `FieldFx` covers petals, footprints, body prints, water rings and the spray source. These are nodes whose `age` is driven by a `Tween`; the spray source uses a `Timer`.
  - Checked against the old version with `scenes/dev/field_fx_check.tscn`.
- **Weather rebuilt as particles:** `weather_fx.tscn` holds `GPUParticles3D` emitters; snow and petals run a `shader_type particles` shader. It's verified in captures against the old pool.
- **Props done:** the ball, snowballs, snowmen, broken axe pieces, the bobber, thrown-back fish and held catches.
  - Speeds are m/s and timers are seconds. Each keeps a `FRAME` constant (1 GX per 30 fps frame, in m/s) so the decomp figures stay readable beside the converted ones.
  - Formulas written in GX a frame stay in those units and convert at the edges, for example the ball's kick sums.
  - The player drives a push with `Snowball.push(delta, …)` every physics step instead of once per tick.
- **Furniture done:** the grip's tap and push timers and the seat's hold are seconds held.
- **Cameras and intro done:**
  - The town camera follows with `Motion.approach`. That is `add_calc` on `delta`: `damp` with the step held between a minimum and a maximum speed.
  - The intro train's Rover walk, camera sway and morph, lighting and window scroll all run on `delta`.
  - So do the town train's timetable, couplings, smoke and sounds; the train's braking starts exactly at the trigger point, so it stops at the same place at any frame rate.
  - The station arrival (Nook, the porter, `NpcPointMove`) and the window-light fade run on `delta` too.
  - The title demo still steps its recorded pad input once per tick. It replays into the player, so it converts with the player.
- **Events done:**
  - The tug-of-war is a one-second pull cycle, and a long step is split at the heave and the ease-off.
  - The foot race's phases are timers in seconds.
  - Thrown balls fly under exact gravity; a ball down on the ground rolls with a drag rate instead of halving every frame.
- **Fish done:**
  - `FishShadow`, its puffs and the rod session (`Fishing`) advance by `delta`, with speeds in m/s. The once-per-frame flags (`nibbled`, `bit`, the landing splash) now last one step.
  - The swim pattern's body swing is tied to the sweep's progress, not to the ticks that pass.
- **Faces done:**
  - Blinks and mouth flaps hold each table entry for its time in seconds.
  - The player's head look eases with `Motion.approach_angle`.
  - The mood effects (`NpcFeelMoods`) advance by `delta`.
- **Bugs done:** the insect framework and all 14 behaviors advance by `delta`.
  - Each step sets `n`, the 60ths of a second it covers. Countdowns drop by `n` and per-tick steps scale by it (`chase_angle(…, a.n)`, `add_calc(…, ticks)`).
  - Per-tick odds go through `BugProgram.chance`, and `game_frame % k` cadences through `beat`.
  - Timers stay in ticks there, as in the mood effects, because every table that sets them is written in ticks. Countdowns that lived in the integer `s32_work` slots are now named float fields on the program.
- **Player done:** `PlayerLocomotion` keeps speed in m/s and steps once per physics frame.
  - Acceleration and brakes are m/s²; the speed ramp is integrated exactly and a turning step travels along its mid-step heading, so a walk and stop agree to the centimetre at 60 Hz and 15 Hz.
  - `MLib.short_angle2` / `short_angle3` take a tick count, so `add_calc_short_angle2` turns scale with the step.
  - `NetSwing`, the radio-exercise pattern buffer, sunburn and the held balloon take `delta`; the balloon's twist is solved as the spring it is.
  - Every timed beat in `player.gd` (talk and bobber turns, door correction, mail hop, shrine toss, net pull and putaway, golden item, broken axe, bee sting, pitfall struggle) counts seconds.
- **Villagers** already moved on `delta` in m/s (`VillagerMotor`, `VillagerWalk`). Their feel timer is now seconds too; it used to drop `roundi(delta * 60)` a frame, which is 0 above 120 fps.
- **Title demo done:** the recording plays by time, blending the stick between samples.
- **`FrameStepper` is deleted.**
- **Hand-rolled tick loops removed** (`while _accum >= 1.0: _tick()`), which the plan's list had missed:
  - UI: the dialogue typewriter is event driven (each glyph, pause and page turn when its wait in seconds runs out); the calendar, catalog, map, notice board, town tune and diary ease and pulse on seconds; `MenuSlide` is a quadratic ease over the original's 14 ticks in and 13 out.
  - World: the present balloon, lighthouse lamp and switch room, the Wisp, the pond moon, fireworks, meteor showers, the waterfall rainbow and villager talk bookkeeping. The lighthouse beam is read off the curve its per-tick ramps trace; fireworks and meteor timetables stay in ticks and fire each entry on the step that crosses it.
  - `Clock` still advances the calendar by whole real seconds; that is a seconds clock, not a decomp tick.

**Phase 2 is complete.**

- **Phase 1 done.** The renames in the tables above, with these differences from them:
  - `BugHitodama` is `WispSpirit`, not `Wisp`: `Wisp` is already the ghost whose spirits they are.
  - `HouseGoki` (the book that counts them) is `HouseCockroaches`; the actor scene is `house_cockroach.tscn`.
  - `alpha0..2` are three values, not one: `opacity`, `prev_frame_opacity` and `fade_out` (the firefly crossfades two glow frames and fades out). `anime1` is the firefly's previous glow frame, so it is `prev_anim_frame`, not `wing_time`.
  - `bg_type` is `TerrainMode` after `aINS_BG_CHECK_TYPE_*`; `ut_x` / `ut_z` were unused and are gone.
  - `BugData.Program`'s values are English too, `Ant` drops its `Bug` prefix, and `Bee` is split out of `Cicada` as a subclass.
  - Every `s32_work` / `f32_work` slot is a named field on its behavior; two were write-only and are gone.
  - Save version 3: `SaveService.RENAMED_KEYS` moves the old keys (`gyoei_term`, `farway`, `haniwa_*`, `_kabu`) to their new names on load.
  - The full rename list is in [decomp-mapping.md](decomp-mapping.md#renamed-from-decomp-style-names). Item, catalog and event ids that come from the disc (`haniwa`, `kabu_peddler`) keep their names.

- **Phase 3 done.** Creatures, NPCs and interior fixtures are scenes, with these differences from the plan:
  - **Bugs:** `bug.tscn` (`Bug` → `Model`, and `CatchArea` on the `creatures` layer) is one live insect. `BugSpawner` adds and frees one per `BugActor`. `Netting.bugs_in_reach` queries a sphere of the net's reach against that layer; two spheres overlap exactly when the decomp's reach-plus-range test passes.
    - There are no per-species inherited scenes. A species' behavior is a `BugProgram` and its tuning lives in its `BugData`, so a scene per species would hold nothing.
    - The behavior stays on `BugActor`, which is a record, rather than a `Behavior` node.
  - **Fish:** `fish.tscn` is one shadow or escape puff, with its shader material local to the instance. `FishSpawner` keeps one per `FishShadow`.
    - The bobber keeps its cone math. The decomp tests strictly inside an angular cone within a distance, and no overlap shape expresses that exactly.
  - **Museum:** a donated insect is `bug.tscn` in display mode (`setup_display`). Tank fish keep their own models, because in the field a fish is only a shadow and there is no shared scene to reuse.
  - **NPCs:**
    - Nook, the sisters, Booker, the clerk, Copper, Tortimer and Blathers author their body, `InteractVolume`, empty `Model` mount and layers in their `.tscn`.
    - The 24 event and visitor NPCs inherit `event_npc.tscn`.
    - Katrina, Redd's tent and the well spirit have scenes of their own.
  - **Interiors:** the shops, post office, police box and Able Sisters author their fixed fixtures at the decomp positions: shopkeepers, clocks, window beams, counters, the e-Terminal, mail piles, displays, the sewing machine and blob shadows.
    - The presenters keep what depends on data or the day: stock, lost-and-found, how many mail piles show, hulls read from the shell's collision, and beams from room data.
    - `populate_authored` keeps every `Furniture` child the room scene owns.
  - **Layers:** `project.godot` names `creatures`, `pickups`, `water` and `triggers`, and `PhysicsLayers` holds their bits. Layers set in code now are presence toggles (an NPC that leaves or hides) and bodies built from data (hulls, shell collision).
  - **Still built in code:** the museum's tank and exhibit collisions and the hull helpers. Both come from per-room data, not a fixed layout.

- **Phase 4 done.** Bodies animate through an `AnimationTree`, with these differences from the plan:
  - **One tree for every body:** `body_animation.tres` is a `Body` state machine feeding a `Speed` time scale. `BodyAnimator` (the `Animator` node in `player.tscn` and `villager.tscn`) binds it to the model's `AnimationPlayer`, which then only holds the libraries. Each scene names its own gait clips (`ply_1_*` or `npc_1_*`).
  - **Locomotion:** `Move` is a synced transition over walk, run and dash with input reset off. Switching gait keeps the step phase, as `frame = current_frame` does in the original, so the hand-written seek is gone. It is not a `BlendSpace1D`: the original switches clips with a morph, and blending walk into run would change the look.
  - **Other clips:** there are no `Tool`, `Talk`, `Sit` or `Door` states.
    - Those actions play dozens of clips chosen by tool, furniture and door. So any clip goes to `ClipA` or `ClipB`, whichever is idle, and crossfades from the one playing.
    - `BodyAnimator` keeps the `AnimationPlayer` calls (`play`, `seek`, `is_playing`, `animation_finished`), so the one-shot actions in `player.gd` read as before.
    - The carry pose stays a `mixer_applied` overlay.
  - **Villagers** go through `play()` only, because their walk clips change with mood.
  - **Clip events:** `PlayerSe.CLIP_MARKS` and the tumble's rumble, dust and body print are written into the clips as method-call tracks when the model binds. This happens at runtime rather than in a post-import script, so the GLBs stay as generated and the marks stay in GDScript tables.
    - Events now follow the clip: a slowed clip fires them late, and a clip cut off or sought past never fires them.
    - The seek nodes have `explicit_elapse` off, so a seek doesn't fire the keys it jumps over.
    - The tumble's frame-17 body print never fired before, because the clip is 16 frames long. It now lands on the last frame.
    - Footsteps keep the gait cadence, because the clips carry no foot tags.
  - **Kept as they are:**
    - The face machine (`NpcFaceAnim`): blinks rest a random time and a mouth table is picked per utterance. Clips could hold only the fixed sequences, and the timing would stay in code.
    - The lighthouse arm, the Christmas lights, the weathervane and the balloons: they follow wind, game state or a clock shared across the town, and already run on seconds since Phase 2.
  - **Asset pipeline fix:** `texbank.py` called a removed helper, so every cKF character and most interiors failed to convert. With that fixed, the suite runs against full assets: 1912 cases, with 8 tests failing on `main` as well.

- **Phase 5 done.**
  - **Player components:** `player.gd` went from 3783 lines to 2326.
    - `Doors` takes door walks, the indoor exit, the train and demo walks.
    - `Furniture` takes grip, push, pull, turn and tap, sitting and lying, and B pick-up.
    - `Tools` takes the held item: binding it, swapping it round doors, the umbrella, the balloon and the pinwheel. The carry pose is part of it.
    - `Net` takes the net swing and its catch, `Fishing` the rod after a cast, and `Snowball` rolling a snowball.
    - Talk-facing stays on `Player`: talk cameras call it on villagers and the player alike.
    - `Reports` (later) takes the player's own report beats: the golden tools, the catch report and pockets-full swap, a find dug up, the loan paid off and the broken axe, with their report camera. `player.gd` went from 2617 lines to 2301.
  - **Villager components:** `villager.gd` went from 2206 lines to 1310.
    - `Mover` takes steering and acre travel, and `Conversation` a villager in talk (`VillagerTalk` was already taken by the dialogue logic).
    - `Greeter` takes road greetings and `Brain` schedule and goal picking.
    - Reactions, moods and the pitfall stay on `Villager`.
  - **How components work:**
    - Each is a child node declared in the actor's `.tscn` and held as a node export, so it is set before any child's `_ready`.
    - It finds its actor on first use, so scenes built in tests without a tree work. The rule is in [conventions.md](conventions.md#components).
    - Outside code goes through the component (`player.doors.*`, `player.tools.*`).
  - **Typed calls:**
    - `Interior` and the 21 one-per-scene overlays and props have a class name and `find(tree)`. Their callers call methods and connect signals directly instead of `has_method` / `.call("…")` / `connect("closed", …)`.
    - The player group lookups outside villagers are `Player.find`.
    - A greeting reaches its partner as a typed `Villager`, and `FurnitureTalk` and the blob shadow check the player by type.
    - What remains (about 120 `has_method` and 160 `call`) is mostly the duck typing `conventions.md` keeps: interaction hosts, NPC hand-overs, talk speakers and villager player checks.
  - **`Game` state as resources:**
    - The resident's own saved fields are `Game.resident`, a `PlayerState`: identity and outfit, fortune, pose, sunburn, diary, calendar and the yearly letters. These are the roster's `Private_c` keys.
    - The town's are `Game.town`, a `TownState`: field contents, rating, weather, tune, fruit and event bookkeeping.
    - Each writes, reads and resets its part of the save under the same keys (`write_save` / `read_save` / `reset`), so the JSON format, the migrations and the roster's split are unchanged.
    - `Game` keeps the session flags and the per-system books, which already owned and saved their state. Fields keep their names (`Game.resident.player_name`), which made the move over about 1,000 call sites mechanical.
    - Finished collections are now noted after the encyclopedia loads. Before, `CompleteTalk.start_set_info` ran against the previous session's encyclopedia and its bits were then overwritten.
  - **The interactable component** is `InteractVolume`, the sensor every host scene already authored, not a new node.
    - Verbs that depend only on the tool held are `InteractionVerb` resources authored on it in the scene: the weed, the e-Terminal, the buried mark and the rock.
    - Hosts whose verbs depend on more (the hour, their own state) still supply them from `get_interactions`. Most do, which is why the verbs aren't all data.
    - Either way the host's `interact` carries them out and may await. A host with no `interact` hears the volume's `activated` signal.
    - `InteractionQuery` talks only to typed volumes (`offers` / `activate`). The host methods are found once, by the volume, which is the one place that duck typing remains.

- **Phase 6 in part.** The constants are converted. The decomp math stays in GX until each system is next touched.
  - 22 `_GX` constants that were only ever multiplied by `GX_TO_METERS` are metre values, and so are 22 constants written as a literal times it. The decomp figure stays in a comment (`const STAND_STEP := 1.75  ## 35 GX`).
  - Speed and acceleration constants keep their derivation from per-frame GX (`17.0 * GX_TO_METERS * 0.5 * TICK_HZ`), as Phase 2's lessons ask.
  - What remains, about 220 uses of `GX_TO_METERS`, is mostly conversion at the edges:
    - Systems that compute in decomp units against tables written in them: insects and their behaviors, fish shadows, the ball, the glyphs, the train, bees.
    - The table loaders (`gx_to_world` and the like).
  - 146 scalar `_GX` constants feed that math. Converting it means rewriting each system's formulas in metres, so it is left for when each system is next changed, as this phase says. Making `GX_TO_METERS` private to the loaders waits on that.

Lessons from the weather particles:

- **Stay inside what the Compatibility renderer does.** Headless captures run there, and some players may too. It silently skips these:
  - sub-emitters, including on collision;
  - `emit_particle()`;
  - heightfield collision;
  - more than one draw pass.
- **Use a per-surface flipbook instead of extra draw passes.** Several meshes can be merged into one `ArrayMesh`, with each surface's material gated on `INSTANCE_CUSTOM.y` (the particle's life phase).
- **Put particles on the ground with an emission-points texture.** The script refills it a few times a second with ground-sampled points.
- **Use a particle shader for motion a process material can't express.** Wrapping a box, wobbling and tumbling go in `shader_type particles`, with `disable_velocity` set and the motion integrated by hand.

Lessons from the pilot, to apply to every later conversion:

- **Prefer closed form over stepping.**
  - `ImpactStar` has one `Tween` animate `age`; position, size and opacity are pure functions of it.
  - `TreeFx` integrates constant acceleration exactly (`p += v·dt + ½·a·dt²`) and drag exactly (`(kᵗ − 1) / ln k`).
  - Plain `v += a·dt; p += v·dt` drifted 22 cm between 60 Hz and 15 Hz on a falling leaf.
- **Split the step at phase changes.** A leaf switches from rising to falling at the instant its upward speed reaches zero, not on whichever frame notices. Without the split, the switch lands on a different frame at each frame rate.
- **Convert where the constant is written.** Keep the decomp value visible and name its clock (`80.0 * DecompTime.TICK_SEC` for 60 Hz ticks, `33.0 * DecompTime.FRAME_SEC` for 30 fps animation frames, `0.125 * GX * 3600.0`) and cite it in a comment, and use small `_speed` / `_accel` helpers where launch values are rolled in decomp units.
- **Test the frame-rate independence directly.** Run the same scenario at 60 Hz and 15 Hz and assert the results agree within 1 cm.

## 4. What not to change

- **The asset pipeline (`tools/`, Python).** It converts disc assets and is not runtime code. Its "classify from Gfx state" rules stay. Animation events get added *after* import (Phase 4), not in `convert.py`.
- **Behavior and content.** Species, prices, schedules, dialogue and event dates stay as they are. This is a refactor of *how*, not *what*.
- **Data-driven design.** `Resource` and `.tres` already match Godot practice; keep them.
- **Save compatibility.** Every rename that touches a save key ships with a migration.

## 5. Risks and how to contain them

| Risk | Mitigation |
| --- | --- |
| Feel drifts when ticks become seconds (jump arcs, bug flight, fishing bite windows) | Fit each converted constant so the *outcome* matches: the same apex, the same total duration, the same window length in seconds. Check with before/after captures and timed outcome tests. |
| 330 tick-exact test sites break | Rewrite each system's tests in the PR that converts it. Don't keep a tick-compat shim alive "for the tests". |
| Physics-rate dependence | Movement goes in `_physics_process(delta)`; visuals and effects go in `_process(delta)`. Nothing assumes 60 Hz. |
| Big-bang churn | One system per PR, with renames separate from behavior changes, and Phase 7 last. |
| Fishing and bug catch fairness (windows were exact tick counts) | Express windows in seconds with a small grace period. Make them `@export` so they can be tuned by playtesting. |

## 6. Suggested first three PRs

1. **Phase 0:** the conventions and testing docs, plus `Motion`.
2. **Pilot, effects:** convert `tree_fx` and `impact_star` to delta and `Tween`. This proves the recipe table and the test style.
3. **Pilot, creature:** convert `Cicada` end to end. That means renaming it, making it a scene with an `Area3D` catch zone and an `AnimationPlayer`, giving it delta-based behavior with a `Timer` for its cry, and rewriting its tests. It becomes the template for the other 14 bugs and for the fish.

Once those land, the remaining phases are repetition of a proven pattern, and the order in Phase 2 keeps the game playable throughout.

## 7. Using the skill pack

The pack's generic guidance applies directly:

- typed GDScript, `@export` / `@onready`, signals with `.emit()` / `.connect()`, `await` and `Tween`s, enum state machines with enter/exit hooks (`godot-code-gen`);
- scene trees per entity, `Area3D` triggers, named collision layers, groups for broadcasts, descriptive node names, `CanvasLayer` HUDs (`godot-scene-design`);
- `TIME`-driven shaders with no CPU-side frame counters (`godot-shader`).

Its live-editor skills (`godot-interactive` / `godot-live-edit`) need `godot-mcp` and a running editor. They don't apply in this headless cloud environment; use `tools/test.sh` and `tools/capture.sh` instead.
