# Museum (donations + wing displays)

Research notes from [ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp). Behavioral reference only — do not copy `mMmd_info_c` blobs as architecture.

**Read before changing:** `MuseumBook`, `MuseumDisplay`, `MuseumPresenter`, `MuseumFishActor`, `MuseumInsectActor`.

## Decomp sources

| File | Role |
| --- | --- |
| `include/m_museum_display.h`, `src/game/m_museum_display.c` | Town display nibbles; fossil FG rewrite; donate API |
| `src/game/m_museum.c` | Mail-in fossils / completion letter (deferred) |
| `src/actor/ac_museum_fossil.c` | Plaque talk near fossil stands |
| `src/actor/ac_museum_picture.c` | Art vs dummy frame swap |
| `src/actor/ac_museum_fish.c` | Five tanks, swim AI, plaques |
| `src/actor/ac_museum_insect.c` | Case insects, active/relax schedules, plaques |
| `src/actor/npc/ac_npc_curator.c` | Blathers donate dialogue branches |

## Reproduce

- Town-wide `MuseumBook` with 4-bit donator ids per fossil (25) / art (15) / fish (40) / insect (40). Values 1–4 = player, 5 = deleted player still on display.
- `Game.donate_to_museum` writes the bit after a successful hand-over (`mMmd_RequestMuseumDisplay`). Wings rebuild on next enter — not live from the entrance.
- Fossil wing: `rom_museum2` shell; donated → real `int_din_*`; empty → species dummy pedestal at absolute `mMmd_UT` cells on the 16×16 acre (shell keeps acre NW at world origin — `Interior.bind` uses origin 0 for museum rooms). Most din parts are `aFTR_SHAPE_TYPEC` (2×2) so `furniture_world` adds +½ cell like `aMR_UnitNumber2Position`; stego head / ptera are TYPEB; solos are TYPEA. Fossil hosts get AABB box colliders.
- Entrance floor is 10×8 from cell (1,3) (`rom_museum1`); painting / fossil floors are 14×12 from (1,1). Painting/fossil shell walls sit on the outer floor cell (north strip ≈ one cell thick); `InteriorBuilder` insets those walls one cell. Entrance / fish / insect keep walls on the floor AABB — fish/insect exits at z=560 sit on the south rim, and inset put a wall face on the door. Door sensors cut wall gaps (entrance has north×2 + west + east + south; half-width 60 GX) with porch slabs so openings stay walkable. Painting mid walls at unit Z=5 / Z=9 get E–W partition colliders with gaps where `ART_CELLS` has no hang.
- Painting wing: `rom_museum3` shell (`BLOCK_COMBI_ROM_MUSEUM3` — not museum2); donated → `obj_artNN`; empty → `obj_art_dummy*`. Host at Y=40 GX (`aMP_DrawOneArt`); origin-snap so the frame bottom sits on that hang line (pipeline verts start ~10 GX above local 0). Keep authored mesh XZ (wall depth) — do not AABB-recenter onto the cell. ART02/ART03 forgeries cannot donate. Museum canvas CI4 hashes differ from house FTR; ACHD falls back to `int_sum_art*` / `int_ike_art*` twins so walls get HD paintings. Nameplates / frames (`*_name_tex`, `*_gaku_tex`) skip ACHD (hash collisions pull scrap-board sheets) and decode with house wood pals (sum) or museum `*_etc_pal` (ike ang/sya/fel). Empty `obj_art_dummy*` (except dummy03) ship neon CI4 in REL — convert twins them to dummy03 wood / ACHD. Draw path is POLY_OPA — runtime materials use scissor/opaque depth, not soft BLEND.
- Fish wing: donated species swim in `mfish_group_tbl` tanks at `suisou_pos`, with `mfish_init_data` scale/`_0C` swim height and museum `act_mus_*` cKF. Tank glass: four `obj_suisou1` + sea `obj_museum5`, bottoms on floor, box colliders. Pipeline `ckf_basis` stands the chain on +Y and rolls dorsal to −X; `MuseumFishVisual.SWIM_FROM_STAND` maps nose→+Z and dorsal→+Y before swim yaw (crayfish also +180° Y per `mfish_zarigani_dw`).
- Insect wing: donated species at museum anchors; `active_time_tbl` / `relax_time_tbl` gate motion; pose flap continues slowly while relaxed.
- Plaques list donated members of each group (`Museum_*_Set_Msg*Info`).
- Catch reports use the shorter already-collected line once the species is in the museum (`mSM_CHECK_LAST_FISH_GET`).
- Hours 9–17 on museum rooms; save/load via `Game.to_save()["museum"]`.
- Camera: museum rooms follow the player at Camera2 distance 620 — not home pin/frame (`Camera2_InDoorCheck` is homes only).
- Doors: outdoor museum and indoor wing links are walk-in (`INTO_S1`), no E prompt. Outdoor→entrance spawn is `aMsm_museum_enter_data` `{240,0,440}` (not scene player `{240,0,200}`). Wing sensors/spawns follow `MUSEUM_*_door_data` GX; entrance leave sensor stays on enter X (`{240,0,500}`), walk-in auto — not room-center `door_cell`. Insect/fish exits sit on east/west walls at z≈560 — door boxes use X thresholds (not “z>400 ⇒ south”) so the enter spawn is not inside the exit sensor. After the room load, `INTO_S1` continues past the door along the spawn facing.
- Entrance wing map (facing into the hall from the south exit): **N-west** painting (`rom_museum3`) · **N-east** fossil (`rom_museum2`) · **W** insect (`rom_museum4`) · **E** fish (`rom_museum5`). Shell ids come from `field_data.c` `BLOCK_COMBI_ROM_MUSEUM*`; door destinations from `MUSEUM_ENTRANCE_door_data`.

## Now implemented (parity pass)

- **Blathers dialogue** (`blathers_greeting.json`, `museum_dialogue.gd`, `blathers_trivia.json`):
  nocturnal schedule (drowsy 05:00–19:00, sleep-pose idle, "wake with a start" first talk
  of the day), one-time orientation monologue with a "shall I stop?" choice, daily-repeat
  variants, and a Talk menu (Donate / About / Leave).
- **Donation opens the pockets** (`mMmd` IV_OPEN, modelled on the intro-payment flow):
  Blathers' "Donate" choice / the pocket `DONATE` interaction sets `Game.museum_donate_pending`
  and opens the inventory overlay; every item worth offering shows a **Donate** tag
  (`Inventory.tags_for_slot`). Picking one calls `Game.take_museum_donation` (commit +
  `museum_donate_result`), closes the pockets, and Blathers responds via
  `MuseumDialogue.build_outcome`: examine line → species trivia → completion fanfare
  (per-skeleton lecture / per-collection / whole museum) → "anything else?" (yes reopens
  the pockets). Rejections get their own lines — already-donated per category, bug
  "release it OUT of doors" panic, non-category decline, forgery, unexamined-fossil →
  Farway referral. Closing the pockets without picking cancels. `HandOver.player_gives_to_npc`
  plays the put-away demo. Headless / no-UI falls back to `build_donate`'s dialogue-list picker.
- **Committed trivia is a faithful re-expression** (own wording, real natural-history
  facts). A local, unversioned verbatim bank at `assets/generated/dialogue/overrides/`
  overrides `blathers_greeting` / `blathers_trivia` / donation nodes by id
  (`DialogueCatalog.ensure_loaded` loads that dir after `data/dialogue`).
- **Fossil identification** (`fossil_catalog.gd` + `data/fossils.json`, `farway_book.gd`):
  25 identified fossils as donatable/sellable `FurnitureData`. Dig → generic `fossil` →
  post office "Send fossils to the Farway Museum" → `FarwayBook` queue → next 06:00 renew
  returns a `RECV_PRESENT` letter per fossil (random identity) + a one-time intro letter
  on first dig. Delivered mail lands in `Inventory._mail` with a `RECV*` font
  ("You've got mail!" notice); read it at the house **mailbox** (`scenes/world/mailbox.tscn`,
  kind `mailbox`, visual `obj_s_post` / `obj_w_post` — box + post + flag; placed by
  `WorldGenerator` two units toward the acre centre on the house row per `ACTOR_PROP_MAILBOX0`,
  slot facing the player approach — `mailbox.gd::apply_grid_yaw` offsets the −X rest slot by
  `-PI/2` so `grid_facing` reads as the slot direction) or on the Letters pocket page
  (Read / Take verbs). Saved under `Game.to_save()["farway"]`.
- **Redd** (`redd_book.gd`, `scenes/world/interiors/redd.gd`): unlocks after the museum
  owns any art or the town is 14 days old; tent open one seeded weekday/week; 4-slot
  stock of genuine + forged paintings (ART02/03 always forged) plus the odd furniture
  piece, one purchase per visit. Forged art is item id `art_forgery_NN`
  (`MuseumBook.display_info_for_item` rejects it → Blathers' `forgery` branch). Shop UI
  via `shop_overlay` BROKER path reading `Game.redd.stock()`. Saved under `["redd"]`.
  **Outdoor tent placement in the world generator is still deferred** (pending the
  door/scene-transition refactor); the `broker_shop` room + Redd NPC are wired.
- **Lighting**: `obj_museum1_shine` (entrance) / `obj_museum4_shine` (insect) god-ray
  meshes via `GeneratedVisual._apply_light_shaft_surface` (unshaded XLU, no depth write,
  emission bloom, alpha scaled by clock daylight). Fish wing gets `obj_museum5_kusa*` +
  `hasu` sea-tank decor and `museum_bubbles.gd` (Tween-based rising bubbles per tank).
  `interior.gd::_apply_museum_mood` drops museum ambient to 0.72 with a per-wing tint.
  `museum_clock.gd` turns the entrance clock hands to the RTC.
- **Static entrance fixtures are authored nodes**, not imperative builds: `Blathers`
  (`museum_blathers.gd`), `MuseumClock` (`museum_clock.gd`, attaches its own GLB), and
  `LightShaft` (`museum_light_shaft.gd`) live under `museum_entrance.tscn` `Furniture/`
  with baked transforms; the insect wing's `LightShaft` is authored in `museum_insect.tscn`.
  `InteriorBuilder.populate_authored` keeps any `Furniture/*` child named in
  `AUTHORED_FIXTURE_NAMES` (or in group `authored_fixture`) across a re-populate — only
  the donation-driven exhibits (`present_fossils` / `present_paintings` / `present_fish` /
  `present_insects`) are rebuilt. `add_blathers` / `add_museum_clock` / `add_light_shaft`
  remain as idempotent helpers for the legacy `build()` / `add_museum_set` path.

## Simplify

- Blathers (`museum_blathers.gd`) stands at `museum_entrance_actable` ut (6,5) cell center (260,220) plus curator `+20` GX on X → `(280,0,220)`, facing south (spawn rot 0). `npc_1_wait1`, owl face flaps while uttering, talk/donate through the dialogue overlay, and `CAMERA2_PROCESS_TALK` framing (`TalkCamera` / FollowCamera). Curator put-away uses the shared `HandOver` demo in place (no walk to the back room).
- Entrance stained glass: XLU `rom_museum1_modelT` (`*_mado*_tex`) — pipeline includes `rom_*_modelT` with the OPA shell. Skip ACHD on `*_mado*` (red scrap false hits). `mado_pal` RGB5A3 glass colors ship with A=0 — revive alpha so panes keep color; vertex-shade exports opaque A so Godot does not scissor the panes.
- Entrance floor clock: authored `Furniture/MuseumClock` node (`museum_clock.gd`) at world `(12,0,7.5)` = `CLOCK_GX (240,150)` × `GX_TO_METERS`. `obj_clock_museum1` verts carry the decomp skeleton offset (root ~`(240,150)` GX), so `_ensure_visual` AABB-centres the mesh on the node in XZ before the floor snap — `_fit_actor` only micro-snaps Y. Hands (`hari_*`) turn to the RTC each frame. Skip ACHD on `obj_clock_*` (wrong-size false hits); body `OPAQUE`, hands `MASK`; wrap-bake clamps CLAMP-axis UVs. Museum sheets are N64 **linear RGBA5551** (not GX-tiled RGB5A3 — that reads as neon noise).
- Fossil mail-in is modelled (`farway_book.gd`) and delivered to a real house mailbox
  (`scenes/world/mailbox.tscn`, `obj_s_post`). Flag raise on unread mail + villager/event/
  bank letters not wired. No completion furniture reward; re-burying a fossil is warned
  against in dialogue but not blocked (players can't bury items).
- Insect programs are museum-idle orbits/sways, not a full port of every `minsect_*` overlay.
- Tank grass (`obj_museum5_kusa*`) / lily (`hasu`) instanced as static decor; bubbles are
  Tween sprites (`museum_bubbles.gd`), not GPU particles; tank point lights still deferred.
- Redd's forgery "tells" are a display-name marker + low sell price, not a per-painting
  visual perturbation.
- Wall ceiling darkening is **baked vertex shade** (`Vtx.cn[]` with `G_LIGHTING` off on `rom_museum*` DLs — top verts go to black), not a shader or the outdoor `obj_museum_shadow` blob. Pipeline exports `COLOR_0` + `vertex_shade`; `GeneratedVisual` multiplies unshaded.
- Jellyfish has no `act_mus_*` mesh in the pipeline yet (decomp skeleton is NULL).
- Empty painting frames use `obj_art_dummy*` when present.

## Ignore

- Debug regs, unused curator fields, whale / trash fish types.
- Exact N64 display lists; use pipeline GLBs.
- Four-player donor name plates beyond storing the donator nibble.

- Museum-side `Get_sakana_msg_num` catch-report shortening (`mSM_CHECK_LAST_FISH_GET`) not
  wired to the donation "first of species today" path.

## Test

- Unit: `test_museum.gd`, `test_museum_dialogue.gd` (greeting graph + donation flow),
  `test_farway_mail.gd` (dig → mail-in → return → donate), `test_redd.gd` (schedule,
  stock, forgery rejection, one-per-visit).
- Scene: `scenes/dev/museum_complete.tscn` instances `scenes/world/museum/museum_*.tscn` (one scene per wing: shell, doors, Terrain, Furniture, spawn). Each room populates its own collision / exhibits via `museum_room.populate()`. Keys 1–5 show/hide rooms in-place. `test_museum_complete_scene.gd` asserts the light-shaft / tank-decor / bubble nodes.
