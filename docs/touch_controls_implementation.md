# Touch controls: implementation plan

This is the step-by-step build of [touch_controls_plan.md](touch_controls_plan.md), phases 2–6. Phase 1 (the `PlayerInput` seam, `InputDeviceTracker`, debug mouse-as-touch) is merged. Each phase below lists its files, its steps, its tests and when it counts as done. Each one ships as its own PR and leaves the game playable.

## What the code already gives us

These are the hooks the plan builds on, checked against `main`:

| Need | Already there |
|---|---|
| Drive the player | `player.scripted_input: PlayerInput`. `move` feeds the walk; `consume_a_pressed()` / `consume_b_pressed()` run `_try_interact()` / `_try_pick_up()` in `_physics_process` (`player.gd:422`). |
| Stick → world direction | `Player._camera_wish(input_dir)` (`player.gd:756`), camera-relative, flat. |
| What A / B would do here | `_query_focus()` → `InteractionQuery.best_in_areas(probe areas, facing point, ctx, pickup)`, then `ToolUse.resolve`. Reach is `INTERACT_REACH` (1.1 m). |
| Face a thing | `_face_host(hit)`, `_face_cell(ctx, cell)`, `TalkCamera.face_yaw_toward`. |
| Fishing reel | Comes through A: `ToolUse.resolve` returns the reel action while the rod is out (`tool_use.gd:104`). There's no separate input path. |
| Grid | `WorldGrid` (2 m cells): `world_to_cell`, `cell_to_world`, `neighbors8`, `is_walkable`, `is_occupied`. Indoors: `IndoorSession.grid`. |
| Walls | `FieldCollision.revise_xz`, `line_hits_wall`, `step_open`, `ground_y_at`, plus the private `_edge_is_wall` / `_forbids_enter`. |
| Rumble | `GameConfig.rumble(entry)` → `Input.start_joy_vibration`. It's one call site, so haptics can go in the same place. |
| HUD | `ClockHud` is instanced in `world.tscn`. `TouchHud` goes next to it. |

Two facts change the original plan:

1. **`Input.action_press` sends no event.** It only sets the polled state, so `_unhandled_input` handlers (pause in `Game`, menus in the overlays, A/B in the player) never see it. HUD buttons must use `Input.parse_input_event()` with an `InputEventAction` (pressed, then released on the next frame) to open pockets, the map and pause.
2. **The player ignores keys while a source is installed** (`player.gd:743`). So the `TouchDriver` has to uninstall itself on the first key or pad event (from `InputDeviceTracker.device_changed`), or the keyboard goes dead after a tap.

Gameplay still reads input directly in two places, outside the player:
- Gracie's car wash: `scenes/world/events/gracie.gd:103` uses `Input.is_action_just_pressed("interact")`. Switch it to `player.a_just_pressed()` in phase 2.
- The intro station's debug walk: `intro_station_stage.gd:782`. This is debug only, so leave it.

---

## Phase 2: drag-to-move, tap-to-act, HUD buttons

*Playable:* walk with one thumb, A by tapping yourself, B / pockets / map / pause from buttons.

### Files
- `scenes/actors/touch_driver.gd` (new): a `Node`, child of the player in `player.tscn`.
- `scenes/ui/touch_hud.tscn` + `touch_hud.gd` (new): a `CanvasLayer` instanced in `world.tscn` beside `ClockHud`, and in the interior scene roots that carry a HUD.
- `scenes/world/events/gracie.gd`: read A through the player.
- `project.godot`: nothing new.

### TouchDriver
- It owns one `PlayerInput`, called `source`.
  - `_on_device_changed(TOUCH)`: install it when `player.scripted_input == null`. Never take over the title demo; that source has `demo = true`.
  - `_on_device_changed(KEYS)`: if `player.scripted_input == source`, call `source.clear()` and set `scripted_input = null`.
- `_unhandled_input(event)`: only `InputEventScreenTouch` / `InputEventScreenDrag`, and only one finger (index 0; ignore the rest).
  - **Press:** remember the start position and time. Work out the player's screen point with `cam.unproject_position(player.global_position + Vector3.UP * 0.8)`.
    - If the press is within `SELF_RADIUS_PX` (64 px, scaled by the viewport's `content_scale_factor`) of the player, start a **self press**.
    - Otherwise start a **drag**.
  - **Drag:** `move = (finger - player_screen) / DRAG_FULL_PX` (120 px), clamped to length 1, with `y` already in the `get_vector` convention (screen down is toward the camera). `dash_held = offset > DASH_PX` (160 px).
  - **Release:**
    - From a drag: `move = ZERO`, `dash_held = false`.
    - From a self press shorter than `TAP_SEC` (0.25 s) and moved less than `TAP_SLOP_PX` (16 px): `source.tap_a()`.
- The drag is relative to the player, not to where the finger first landed. That matches Pocket Camp, and the camera keeps the player near the middle of the screen.
- Screen points come from the viewport (`get_viewport().get_visible_rect()`), so stretch and `expand` are handled.
- All the thresholds are `const` at the top of the script and in pixels at the 720 p base.

### TouchHud
- Author it in the `.tscn`: a `Control` set to full rect, with bottom-right buttons **B**, **Pockets**, **Map**, **☰ Pause**. Use 96 px targets and the theme from `assets/ui/default_theme.tres`.
- `visible = InputDeviceTracker.is_touch()`, updated on `device_changed`. Hide it while `player._menu_open()`, but keep the B button showing in dialogue for fast-forward later.
- **B** calls `driver.source.tap_b()`, not an `InputEvent`, because the player ignores events while the source is installed.
- **Pockets / Map / Pause** call `_send_action(&"inventory")` etc.: `parse_input_event` an `InputEventAction` with `pressed = true`, then `pressed = false` on the next `process_frame`.
- Buttons take `mouse_filter = STOP`, so a tap on a button never reaches the driver. The driver reads `_unhandled_input`, which runs after the GUI.

### Gracie
- `gracie.gd:103`: use `_player.a_just_pressed()` (it falls back to `Input` when there's no source). With touch, that's a tap on the player. The car-wash mash then works by tapping yourself repeatedly.

### Tests
- `tests/unit/test_touch_driver.gd`. Feed synthetic `InputEventScreenTouch` / `ScreenDrag` events to a driver on a test player, with a fixed `Camera3D`.
  - A drag 60 px right gives `move.x ≈ 0.5`. Past 160 px it gives `dash_held`.
  - A short tap on the player latches exactly one A, and the player's `_try_interact` runs once.
  - A key event after touch removes the source, so `scripted_input == null` and `_unhandled_input` reads keys again.
  - It never replaces a `TitleDemoInput`.
- `tests/unit/test_touch_hud.gd`. The Pockets button opens the inventory overlay (a group `inventory_ui` node becomes visible). B calls `_try_pick_up` on a weed in front.
- Capture: add `touch=x,y[,hold]` to `tools/capture.sh` / the capture runner. It injects a press and release at that screen point, so captures can show the HUD.

### Done when
You can walk around the town, shake a tree (tap yourself in front of it), pick up fruit (B), open the pockets and map and pause, all with the mouse in a debug build. The pad and keys take back control on the first press. The full suite shows no new failures.

---

## Phase 3: tap-to-walk

*Playable:* tap the ground anywhere on screen to walk there.

### Files
- `scripts/systems/touch_pick.gd` (new, static): screen to ground.
- `scripts/systems/touch_path.gd` (new, static): A* on the grid.
- `scripts/systems/field_collision.gd`: make `_edge_is_wall` and `_forbids_enter` public (`edge_is_wall`, `forbids_enter`), keeping the old names as thin wrappers until their callers move.
- `scenes/actors/touch_driver.gd`: the walk-to steering.
- `scenes/ui/touch_marker.tscn` (new): a ground ring (a flat `MeshInstance3D` with an unshaded additive material, plus an `AnimationPlayer` clip "pop" that scales 0.6→1 and fades over 0.4 s). Instanced into the world by the driver.

### TouchPick.ground(cam, screen) → { hit, pos, cell, water }
1. Build a ray from `cam.project_ray_origin(screen)` and `project_ray_normal`.
2. Intersect it with the plane `y = player.y`.
3. Refine it three times: `y = FieldCollision.ground_y_at(data, grid, pos)` and intersect again. The camera pitch is about 45°, so this converges at once.
4. If the cell is out of bounds, `hit = false`.
5. `water` is true when the terrain is water / sea (`grid.terrain_at`), so phase 4 can cast there.
6. Indoors, use the room's floor height and `IndoorSession.grid`.

### TouchPath.find(data, grid, from: Vector3, to_cell) → PackedVector3Array
- **A\*** on `Vector2i` cells, 8-connected, with an octile heuristic.
- **Passable cells:** `grid.is_walkable(c)`, not `grid.is_occupied(c)` (the start cell is always allowed), and not `FieldCollision.forbids_enter`.
- **Moves:** a move from `a` to `b` is open when `not FieldCollision.edge_is_wall(data, a, b)`. A diagonal also needs both of its orthogonal moves open, so the path never cuts corners.
- **Range:** at most 6 × 6 acres of cells (the town), but only expand within `MAX_NODES` (4000). If no path is found, walk straight toward the tap and let collision stop it, like a stick held that way.
- **Smoothing:** walk the cell centres. From each kept point, skip ahead to the farthest point that `not FieldCollision.line_hits_wall(data, grid, a, b)` (string-pulling). The last point is the exact tap position, not the cell centre.
- **Blocked goal:** if the goal cell is blocked, use the nearest passable cell, searching outward ring by ring (radius ≤ 3).

### Steering (TouchDriver)
- Keep `path`, `index` and `goal` per tap. Each physics tick, before the player reads `move`:
  - Set `to = path[index] - player.global_position` on the XZ plane.
  - When `to.length() < WAYPOINT_REACH` (0.35 m), advance `index`.
  - Turn the world direction into a stick with the inverse of `_camera_wish`. Use the camera's flat `look` / `right` basis: `move = Vector2(dir.dot(right), -dir.dot(look))`. Use magnitude 1 until the last 1 m, then `clamp(dist / 1.0, 0.35, 1)`, so the walk eases in without stopping short.
  - Stop when the player is within `ARRIVE` (0.25 m) of the end.
  - **Stall check:** if the player has moved less than 0.05 m in 0.3 s, re-path once. If it's still stuck, stop. A villager in the way, or a tree that's been planted since, both end the walk.
  - Any drag, a new tap, the menu opening, or `player._busy` clears the path and sets `move = ZERO`.
- **Long-press** (0.35 s without moving) on the ground walks there at a dash (`dash_held` while the path is active). Phase 4 overrides this when the net is equipped.
- The ground marker spawns at the tap and stays until arrival.

### Tests
- `tests/unit/test_touch_pick.gd`: on the test town, project a known cell centre through the game camera and pick it back, checking the same cell within 0.1 m. Do it again on a slope cell and an indoor floor.
- `tests/unit/test_touch_path.gd`:
  - A straight line on flat ground smooths to two points.
  - Around a cliff edge, the path goes along the ramp.
  - Over a bridge, the path crosses it rather than the river.
  - No diagonal squeezes between two trees.
  - A tap on a tree goes to the next cell over.
  - Unreachable gives an empty path, so the driver falls back to the straight walk.
- `tests/unit/test_touch_driver.gd` (add to it): the real player follows a three-point path in a test acre and arrives within 0.3 m in under the expected time. It moves at walk speed, using the same motor as the stick.

### Done when
Tapping anywhere walks there along a sensible path, round ponds and up ramps, at the normal walk speed, with footsteps and turns as usual. A long-press dashes. Captures with `touch=` show the marker.

---

## Phase 4: tap-to-interact

*Playable:* the Pocket Camp loop. Tap a tree to shake it, a villager to talk, fruit to pick it up, a door to go in, the water to fish.

### Files
- `scripts/systems/touch_pick.gd`: add `object(cam, screen) → InteractVolume`.
- `scripts/systems/touch_path.gd`: add `approach(data, grid, from, host_pos, reach) → path`.
- `scenes/actors/touch_driver.gd`: targets, arrival and the verb.
- `scenes/actors/player.gd`: add a public `verb_preview(pickup: bool) -> InteractionQuery`. It wraps `_query_focus` / `_resolve_interact` so the driver can ask what A or B would do without doing it.
- `scenes/ui/touch_chips.tscn` (new): a row of `Button`s over a host, positioned with `cam.unproject_position`.

### Picking an object
1. Send a ray with `collide_with_areas = true`, `collide_with_bodies = false` and mask 8 (the *interact* layer the `InteractVolume`s use).
2. If it misses, try a 24 px ring: 8 rays around the tap, and take the closest hit to the tap.
3. If that misses too, fall back to the ground and phase 3.
4. If the tap lands on the player first (phase 2's `SELF_RADIUS_PX`), that wins.

### Approach and act
- **Goal:** the passable cell nearest the player from which the host's volume is within `INTERACT_REACH`. In practice that's the four orthogonal neighbours of the host's cell, plus its footprint's edge cells for buildings. Sort them by path length.
- **On arrival** (in reach and the probe overlaps the target's volume):
  1. Face the host (`TalkCamera.face_yaw_toward`, setting `_motor.facing`).
  2. Wait one physics tick, so the probe's overlap and facing point update.
  3. Call `verb_preview(false)`.
     - If its `host` is the tapped volume's host, `tap_a()`.
     - Otherwise try `verb_preview(true)` (B); if that matches, `tap_b()`.
     - If neither matches (something else is closer in front), nudge one step toward the host and retry once, then give up quietly.
- **Which button:** the host decides, not the gesture. Fruit, weeds, items and signboards to read are B-only, so they get `tap_b`. Trees, villagers, doors and furniture to sit on get `tap_a`.
- **Moving targets** (villagers, the dog, bugs): re-path every 0.5 s to the host's current cell, and give up after 5 s. Talking can start anywhere in range, as with the stick.

### Chips (several verbs)
- When the volume offers more than one primary verb across A and B, show chips over the host instead of walking at once. For example, a chair offers sit and move; a signboard offers read and pick up.
- The labels are the verbs' existing prompts.
- Tapping a chip walks up and fires that verb's button. Tapping anywhere else hides the chips and handles that tap normally.

### Tools
- **Shovel / axe** (they act on the facing cell). Tapping the ground with one equipped:
  1. Walk to a cell next to the tapped cell.
  2. Face the tapped cell with `_face_cell`.
  3. `tap_a()`.

  A tap on the player still digs in front, as in phase 2.
- **Rod:**
  - A tap on water walks to the nearest bank cell next to that water. It faces the tapped point (the cast always goes straight ahead), then `tap_a()`.
  - While the bobber is out, any tap is `tap_a()` (reel). `Fishing.holds(player)` tells the driver.
- **Net:**
  - Holding the finger anywhere sets `a_held`, and `move` points toward the finger (the creep).
  - Releasing swings, just like holding and letting go of A.
  - Long-press dash is off while the net is equipped.

### Tests
- `tests/unit/test_touch_interact.gd`, through the real player on the test town:
  - Tap a fruit tree's screen point. The player walks up, faces it, and the shake runs once (the tree's shake counter goes up by 1).
  - Tap a fallen apple. It ends up in the pockets.
  - Tap a villager. Dialogue opens (a `dialogue_ui` node is visible).
  - Tap a chair indoors. Two chips show; tap "Sit" and the player sits.
  - Tap water with the rod. The cast happens facing the tap within 45°.
  - Tap an empty cell with the shovel. It's dug.
- `test_touch_pick.gd`: tapping a weed 20 px off still picks it (the ring fallback).

### Done when
The day loop can be played by tapping alone: shake trees, collect fruit, talk, enter shops and houses, fish, catch a bug, and dig a fossil.

---

## Phase 5: menus

*Playable:* every screen works with fingers, in this order (most used first).

The rule: no overlay grows its own touch logic. Each one gets tap regions that call the **same handler its keys already call**. Where an overlay has a `handle_key(key)` (bank, keyboard panel, edit-end prompt), regions call that. Where it reads keycodes inline, first pull that body out into `_on_key(keycode)`, then call it from both the key path and the regions.

| Order | Overlay | Work |
|---|---|---|
| 5a | `dialogue_overlay` | Tap anywhere on the box or screen → the accept path at `dialogue_overlay.gd:642`. The HUD's B button → fast-forward. The choice buttons are already clickable. |
| 5a | `letter_reader_overlay`, `map_overlay`, `pause_overlay`, `title_logo` | Tap → the accept path. A tap outside the panel → back. |
| 5b | `inventory_overlay` | Tap a slot to move the cursor there; tap the cursor slot to open the tag menu; long-press to mark (`inventory_mark`); drag between slots to move. The tabs and wallet already work (phase 1 fixed the double fire). |
| 5c | `bank_overlay` | Digit cells for the amount, plus ▲▼ and OK / Back, all calling `handle_key`. |
| 5c | `catalog_overlay` | Tap a row to select it, tap again to order, and page arrows. |
| 5d | `keyboard_panel`, `name_entry_overlay`, `letter_address_overlay`, `letter_writer_overlay`, `letter_paper_picker_overlay` | The keyboard is already mouse-driven: make the keys at least 56 px and add OK / Back. The paper picker gets tappable thumbnails. |
| 5e | `notice_board_overlay`, `town_tune_overlay`, `calendar_overlay`, `birthday_overlay`, `diary_overlay`, `clock_hud` (setting the clock) | Cells to tap for each arrow-key target, plus OK / Back. Town tune: tap a note to cycle it, plus a Play button. |
| 5f | `design_editor_overlay`, `design_album_overlay`, `design_list_overlay` | Already mouse-driven: enlarge the palette and tool hit areas, and add a Back button. |

- The regions live in each overlay's `.tscn` as `Button`s or `Control`s with `gui_input`, hidden unless `InputDeviceTracker.is_touch()`, so the pad layout is untouched.
- The intro screens (`intro_train`, `intro_station`, `intro_kk`) read the same accept action, so a tap → accept.
- **Tests:** one test per overlay that sends a `gui_input` click to a region and checks the same state change as the key test next to it. Most overlays already have key tests to mirror.
- **Done when:** a new game can go from the title screen through the train, naming, the first day, a letter, the bank and the catalog with no keyboard.

---

## Phase 6: polish

- **Haptics:** in `GameConfig.rumble(entry)`, when the last device is touch and `rumble_on`, also call `Input.vibrate_handheld(int(shape.y * 1000), shape.x)`. Same moments, one call site.
- **Safe areas:** `TouchHud` and the overlays' tap regions read `DisplayServer.get_display_safe_area()` and pad their anchors so nothing sits under a notch or the home bar.
- **Hit tuning:** from captures at 1170×2532 and 2400×1080, adjust `SELF_RADIUS_PX`, the pick ring and the chip sizes.
- **Export:** an Android preset in `export_presets.cfg` (landscape, `emulate_mouse_from_touch` on, Vulkan Mobile renderer override checked for parity), plus notes in `docs/testing.md` on side-loading. iOS only if there's a Mac to build on.
- **Capture test:** `tools/capture.sh` at phone size with a scripted touch sequence: tap a tree, then tap the fruit. Kept as a visual regression for the HUD and marker.

---

## Order of PRs

| PR | Phase | Rough size |
|---|---|---|
| 1 | 2: driver (drag, self-tap), HUD buttons, Gracie | ~400 lines + tests |
| 2 | 3: TouchPick ground, TouchPath, steering, marker | ~600 lines + tests |
| 3 | 4a: object pick, approach and act, B-only hosts | ~400 lines + tests |
| 4 | 4b: tools (shovel/axe target, rod, net), chips | ~400 lines + tests |
| 5–8 | 5a–5f: menus, one or two overlays per PR | ~150–300 lines each |
| 9 | 6: haptics, safe areas, export preset, phone captures | ~200 lines |

## Open decisions for later

- **Camera:** it stays fixed, as now. If a phone's portrait aspect shows too little ground, the fix belongs in `FollowCamera` (distance by aspect), not in touch code.
- **Tap-on-player vs. tap-in-front:** both mean A. If testing shows people tap the tree in front rather than themselves, phase 4 covers that. Phase 2's self-tap stays as the fallback for verbs with no host, such as digging, the net and shaking a bare spot.
- **Furniture push / pull** (drag from the furniture piece) is left out of phase 4. Indoors, tap a piece to grip it (A held); a drag then pushes or pulls it, through the same `_grip_stick` the stick uses. Add it if it's wanted after phase 5.
