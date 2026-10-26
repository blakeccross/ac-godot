# Touch controls plan

Goal: play the whole game with one finger, the way *Pocket Camp* plays. You tap the ground to walk there, and you tap a villager, tree, item or building to walk up and use it. This is an added input mode, not a different game. Pad and keyboard keep working unchanged, and every touch action ends in the verbs the player already has (`_try_interact`, `_try_pick_up`, the net swing, the reel).

The file-by-file build of phases 2–6 is in [touch_controls_implementation.md](touch_controls_implementation.md).

## Design rules

- **One seam into the player.** Touch never calls hosts directly. It drives the player through a `PlayerInput` source, the same way `TitleDemoInput` already does: a `move` vector plus A and B presses and holds. The player cannot tell a finger from a stick. Interaction choice stays in `InteractionQuery` / `ToolUse.resolve`, so touch picks exactly what A or B would pick when standing there.
- **Movement keeps its physics.** Tap-to-walk produces a stick vector each tick (steering toward the next waypoint), never a teleport or a tween. Speed, turning, slopes, tripping and footprints all stay exactly as they are.
- **No on-screen joystick or d-pad.** Movement is tapping where to go, or holding a finger on the ground for the player to follow. Nothing stick-shaped is ever drawn. The finger never acts as a stick relative to a fixed point; it always names a place in the world.
- **Scene-first UI.** On-screen buttons and markers live in a `TouchHud` scene, shown only when touch is the last device used.
- **Every phase leaves the game playable.** Each phase can ship on its own.

## Gestures

| Gesture | On | Does |
|---|---|---|
| Tap | ground | walk there (path around cliffs, water and objects) |
| Tap | an interactable (villager, tree, sign, door, item, furniture…) | walk up to it, face it, then do its A verb (or its B verb if B is all it offers) |
| Tap | the player | A in place (dig, swing, cast, talk to whoever is in front) |
| Double-tap | the ground | run there |
| Hold and slide | the ground | the player walks toward the spot under the finger and keeps following it until release (runs when the finger is far ahead). No stick is drawn. |
| Tap | water (rod equipped) | walk to the bank and cast toward the tap |
| Tap | anywhere while fishing | reel (A) |
| Hold | anywhere (net equipped) | ready the net and creep toward the finger; release swings (hold-A semantics) |
| Tap | a context chip | use that verb (see "context chips" below) |
| Two-finger tap / ☰ button | — | pause / pockets / map buttons in the HUD |

The table assumes only one finger in play at a time. Pinch and rotate are left out, because the camera is fixed by design (`m_camera2` reads no input outdoors).

### Context chips (where one tap is ambiguous)

When a host offers more than one verb, a small row of chips appears over it with the verbs' prompts. For example, sitting vs. moving a chair, or reading vs. picking up a signboard. A second tap picks one. For a single verb, the first tap acts directly. The chips read the same `InteractVolume.offers(ctx)` list, split A/B as `InteractionQuery.best_in_areas` already does.

## Architecture

### `PlayerInput` (new, `features/player/player_input.gd`)
- This is the base type the player reads from. It is promoted out of `TitleDemoInput`, which becomes a subclass. Its fields are `move: Vector2` (get_vector convention, 0–1 magnitude) and `a_held`, `a_pressed`, `b_held` and `b_pressed`, plus `consume_a_pressed()` and `consume_b_pressed()`.
- `player.scripted_input` is retyped to `PlayerInput`. The title-demo-only behaviour moves behind a `demo` flag on the source. That covers no sprint, the `TitleDemo.allows_verb` gate, and the skipped bad-luck trip and NPC wade checks.
- The remaining direct `Input` readers move to read through the source (they fall back to `Input` when it is null):
  - net hold-A (`player_net.gd:47`)
  - furniture grip hold and push direction (`player_furniture.gd:60,72`)
  - `_struggle`
  - sprint (`player.gd:442`)

### `TouchDriver` (new, `features/player/touch_driver.gd`, a child node of the player)
- It owns a `PlayerInput`. It installs it on the player only while touch is active, and removes it when a pad or key is pressed.
- It turns gestures into the source's fields each physics tick:
  - **Walk-to.** Follow a path of world points, and set `move` from the camera-relative direction to the next point. Use the inverse of `_camera_wish`, and keep full deflection until the last metre, then ease. Stop on arrival, on a blocked step (`FieldCollision.revise_xz` makes no progress for 0.3 s) or on a new tap.
  - **Interact-on-arrival.** When the target host's `InteractVolume` overlaps the probe and the player faces it, pulse `a_pressed` (or `b_pressed`). Facing reuses `_face_host`.
  - **Follow.** While a finger is held on the ground, pick the ground point under it each tick and steer straight toward it. Walk within 4 m, and run (`dash_held`) beyond that. Stop within 0.3 m. No path is planned, so the player stops at walls, just as a held stick would.
  - **Holds** map straight to `a_held` / `b_held`.

### `TouchPick` (new, static, `scripts/systems/ui/touch_pick.gd`)
1. **Screen to object.** Raycast areas on the *interact* layer (mask 8) using `PhysicsRayQueryParameters3D.collide_with_areas`, with the ray from `cam.project_ray_origin/normal`. If that misses, try a 24 px screen radius, so small items and weeds are easy to hit. Return the `InteractVolume`.
2. **Screen to ground.** There is no ground physics, so intersect the ray with the plane at the player's height, then refine it 3× against `FieldCollision.ground_y_at`. The ray is steep (about 45° at 31 m), so this converges at once. Off-field or water gives a target flag.

### `TouchPath` (new, static, `scripts/systems/ui/touch_path.gd`)
- A* on the `WorldGrid` cells (2 m), 8-connected.
- A cell is passable when `is_walkable`, it is not occupied by a blocking host and `FieldCollision` allows entry. Cliff edges come from `FieldCollision._edge_is_wall` (made public), and slopes and bridges count as normal cells.
- Diagonals are allowed only when both orthogonal neighbours are open.
- The path is smoothed with `FieldCollision.line_hits_wall` (string-pulling), so the player walks straight lines rather than a staircase.
- Goal handling:
  - A tapped host's goal is the nearest open cell from which the host's volume is reachable. Use its `InteractVolume` position and the probe reach (`INTERACT_REACH`).
  - A tapped blocked cell's goal is the nearest open cell.
- Paths stay within the current acre plus neighbours. Acre wades just happen when the path crosses a border, because the player walks.
- Indoors the same grid applies (`IndoorSession.grid`). Furniture occupancy blocks cells.

### `TouchHud` (new scene, `scenes/ui/touch_hud.tscn`)
- A tap marker on the ground: a ring that fades, scene-authored. It also shows the path's end.
- Context chips over the target host.
- A tab bar along the bottom: Map, Pockets and Menu (pause). It stays up over those three screens with the open one lit, so a tab switches straight to another; there is no B button (a tapped item gets B from the driver). The buttons send the existing actions as `InputEventAction`s through `Input.parse_input_event` (`action_press` only sets the polled state and sends no event), so overlays need no changes for opening.
- It is visible only while the touch device is active. The `InputDeviceTracker` autoload switches on the last `InputEventScreenTouch` / `ScreenDrag` vs. key / joypad event.

### Project settings
- `input_devices/pointing/emulate_touch_from_mouse = true` in debug builds only (an editor override), so the mouse can test touch on desktop.
- `emulate_mouse_from_touch` stays on, so existing Button-based UI keeps working with fingers.
- Stretch is already `canvas_items` + `expand`. Check the HUD at phone aspect ratios (19.5:9).

## Overlays (menus) on touch

Each overlay needs a touch path. Most of them read raw keycodes today, so each one gets clickable regions that call the same handlers the keys do. Where a public `handle_key(key)` exists (bank, keyboard panel, edit-end prompt), regions call that directly.

| Overlay | Today | Touch work |
|---|---|---|
| Dialogue | actions; choices are Buttons | tap anywhere to advance (`_press_page(false)`), a B corner to fast-forward; choices already clickable |
| Pockets (`inventory_overlay`) | actions + Buttons + some `ScreenTouch` | tap a slot to select, tap again for the tag menu; drag between slots to move; long-press to mark |
| Map, letter reader, pause | actions + Buttons | tap = accept, outside tap = back |
| Keyboard panel (letters, names) | mouse + `handle_key` | already clickable; make keys finger-sized |
| Bank, catalog, calendar, birthday, diary, notice board, letter address / paper / writer, name entry, clock | raw keycodes only | add regions mapped to their key handlers (arrows/digits as tappable cells, OK/Back buttons) |
| Town tune board | raw keys | tap a note cell to cycle it, OK/Back/Play buttons |
| Design editor / album / list | keys + mouse | already mouse-driven; enlarge the palette and tool hit areas |

## Phases

1. **Seam (no behaviour change).** Promote `PlayerInput` and route the direct `Input` readers through it. Add `InputDeviceTracker` and the debug `emulate_touch_from_mouse` setting. *Done when:* the title demo and all pad/keyboard play are unchanged, and the full suite passes. **Done.** The pockets' click handler now takes only the mouse click, because a finger also arrives as one (`emulate_mouse_from_touch`), and taking the touch as well fired every tap twice.
2. **Hold-to-follow and tap-to-act.** Add `TouchDriver` with hold-to-follow (the player walks toward the finger) and tap-on-player (A), plus the HUD corner buttons. No joystick. *Playable:* walk and do everything A/B do, with one finger.
3. **Tap-to-walk.** Add `TouchPick` (ground) and `TouchPath` (A*), the walk-to steering and the tap marker. *Playable:* tap anywhere to go there.
4. **Tap-to-interact.** Add `TouchPick` (objects), approach-and-face, A/B on arrival, and context chips. Fishing taps (cast toward the tap, tap to reel) and the net hold. *Playable:* the Pocket Camp loop: tap a tree to shake it, tap a villager to talk, tap fruit to pick it up.
5. **Menus.** Dialogue, then pockets, then the keycode-only overlays in order of how often they come up: bank, catalog, letters and names, notice board, tune board and the rest.
6. **Polish.**
   - Haptics, via `Input.vibrate_handheld` on the same moments as `GameConfig.rumble`.
   - Hit-area tuning.
   - Phone safe areas, using `DisplayServer.get_display_safe_area`.
   - An Android/iOS export preset and a capture-based test at phone resolution.

## Testing

- **Unit:**
  - `TouchPick` against a test town (screen point → expected cell / volume).
  - `TouchPath` (around a cliff edge, across a bridge, to the nearest open cell next to a tree, no corner-cutting).
  - `TouchDriver` steering (path followed within tolerance, arrival fires exactly one A).
- **Integration:** a `PlayerInput` script fed through the real player, in the style of the title demo replay. Tap a tree, check the shake happened. Tap an apple, check it's in the pockets.
- **Visual:** `tools/capture.sh` with a new `touch=x,y` argument that injects a synthetic `InputEventScreenTouch`, so captures can show the marker, chips and HUD.

## Risks and open questions

- **One tap, several verbs.** The chips solve it, but they add a tap. *Pocket Camp* avoids the problem because each object has one verb. Proposal: chips only when a host has more than one *primary-priority* verb, otherwise act.
- **Tools that aim.** Shovel and axe act on the facing cell. Tap-to-act on ground with a tool equipped should walk next to the tapped cell and face it, then A. This needs a "tool target" goal type in `TouchPath`.
- **Dash on touch.** There is no dash button. Holding the finger far ahead runs, and a double-tap runs to the spot. With the net equipped, a hold is the net hold rather than a follow.
- **Furniture push/pull** needs a drag from the piece rather than from the player. That could be phase 4b.
- **Villagers move.** Re-path to a moving host every 0.5 s, and give up after 5 s (the original's talk range is generous).
