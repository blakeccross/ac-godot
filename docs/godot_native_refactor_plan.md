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

After the last item, delete `FrameStepper` and narrow `DecompTime` to authoring helpers.

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
- **Convert where the constant is written.** Keep the decomp value visible (`80.0 / 60.0`, `0.125 * GX * 3600.0`) and cite it in a comment, and use small `_speed` / `_accel` helpers where launch values are rolled in decomp units.
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
