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
  25 identified fossils as donatable/sellable `FurnitureData`. Blathers explicitly
  refuses a raw `fossil` and hands it back (`ac_npc_curator_move.c_inc:658-681`'s
  `donate_act[3]` — confirmed decomp-accurate, no on-the-spot identification exists in
  the original either). The real identification path is mailing it to the special
  "Museum" address-book contact (`mPr_CheckMuseumAddress`, `m_museum.c`'s
  `mMsm_SendResultMail`) — this port's `FarwayBook` queue models that scheduling
  correctly (name predates confirming the real contact is just called "Museum"). Two
  entry points both land on `FarwayBook.queue_fossil()`: the Post Office's "send N
  fossils at once" batch shortcut, and the decomp-accurate path — write a letter
  addressed to "Museum" (`letter_address_overlay.tscn`) and attach one raw fossil as a
  gift (`Present` mail tag) before sending. Either way, next 06:00 renew returns a
  `RECV_PRESENT` letter per fossil (random identity) + a one-time intro letter on first
  dig. Delivered mail lands in `Inventory._mail` with a `RECV*` font ("You've got mail!"
  notice); read it at the house **mailbox** (`scenes/world/mailbox.tscn`, kind
  `mailbox`, visual `obj_s_post` / `obj_w_post` — box + post + flag; placed by
  `WorldGenerator` two units toward the acre centre on the house row per
  `ACTOR_PROP_MAILBOX0`, slot facing the player approach — `mailbox.gd::apply_grid_yaw`
  offsets the −X rest slot by `-PI/2` so `grid_facing` reads as the slot direction) or
  on the Letters pocket page (Read / Take verbs). Saved under `Game.to_save()["farway"]`.
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
  (`scenes/world/mailbox.tscn`, `obj_s_post`/`obj_w_post`). Flag raises/lowers on unread
  mail via the GLB's baked `obj_s_post_flag_on1`/`_flag_on_wait1`/`_flag_off1` clips,
  driven off `Inventory.mail_changed` (`mailbox.gd::_sync_flag`) so it updates even
  off-screen. `cKF_bs_r_obj_w_post` (winter) has no `cKF_ba_r_obj_w_post*` clips of its
  own in the ROM — `tools/asset_pipeline/test_set.py`'s `TEST_SKELETONS` entry for it
  reuses `cKF_ba_r_obj_s_post*` (joint-index curves, not name-bound; same 6-joint rig),
  so the winter GLB carries the identical clip names/rest pose and the flag animates in
  both seasons. Villager/event/bank letters still not wired. No completion furniture
  reward; re-burying a fossil is warned against in dialogue but not blocked (players
  can't bury items).
- Mailbox interaction now matches `ac_mailbox_move.c_inc`'s `aMBX_pl_open`/`_pl_close`
  sequence: `mailbox.gd::interact()` awaits the `open1` lid clip finishing before opening
  the Letters page (`Inventory.last_used_mail_index()` seeds the cursor, matching
  `mMB_get_last_mail_idx`'s backward scan), then awaits the page's new `closed` signal
  and plays `open1` in reverse (`AnimationPlayer.play_backwards`) before resuming the
  flag pose. Facing (`ACTOR_PROP_MAILBOX0..3`'s `angle_table = {90,0,90,0}°`) and the
  west/east position offset are decomp/real-`WorldBuilder`-position confirmed. **Not**
  implemented: the player's own walk-up/hop into place before the lid opens
  (`aMBX_pl_wait` → `Player_actor_*_Mail_jump`, `mPlayer_INDEX_MAIL_JUMP`) — no such
  player locomotion state exists in this port yet.
- **Donation removal was never actually broken** (checked against `ac_npc_curator.c`/`ac_npc_curator_move.c_inc` from the real ac-decomp repo, and against all three real donation entrypoints — the pockets "Donate" tag, the dialogue-list commit, and the backend directly): `Game.donate_museum_result()` (`game.gd:1071-1129`) calls `inventory.remove(item_id, 1)` unconditionally on `ok=true`, verified with fossils specifically (a real `FossilCatalog`-identified fossil, not a synthetic test double) through every path. The reported "fossil didn't leave my inventory" is the raw, unidentified `fossil` item — decomp-accurate: Blathers cannot identify one on the spot (`item_id == &"fossil"` short-circuits before `inventory.remove`, `game.gd:1093-1096`), it must go to the Post Office → Farway Museum first (`post_use.gd`, `farway_book.gd`) and comes back a day later as an identified `fossil_*` item, which *does* get consumed correctly. What **was** actually missing, and directly explains the "did nothing happen" read: decomp's `donate_act[]` table (`ac_npc_curator_move.c_inc`) routes every rejection (forgery, already-donated, wrong category, unexamined fossil) through a dedicated `aCR_TALK_RETURN_DEMO_*` hand-over so Blathers visibly gives the item back — this port only ever played a hand-over on **accepted** donations (`_play_putaway`). Added `museum_blathers.gd::_play_return()` (reuses the existing `HandOver.npc_gives_to_player`, no new animation infra needed) wired into `_play_donate_outcome()`'s `!ok` branch.
- **`ANIM_SLEEP` was a real, silent bug, not a simplification**: `museum_blathers.gd` referenced `"npc_1_sleep1"`, a clip that does not exist in the shared NPC animation set (confirmed against the owl model's actual `AnimationPlayer.get_animation_list()`) — `_resolve_clip` always came back empty and silently fell back to the wait loop, so Blathers has *never* actually shown the sleep pose while drowsy. Fixed: the real clip is `npc_1_wait_nemu1` (`aNPC_ANIM_WAIT_NEMU1`, nemu = 眠 "sleepy"). Also fixed the drowsy hour window to decomp's actual `aCR_SLEEP_TIME_START`/`_END` (`ac_npc_curator.h`): **06:00–18:00**, not the previous 05:00–19:00 guess. And added the missing transition: `aCR_ACTION_WAIT` → `aCR_ACTION_SLEEP_WAIT` (holds the normal wait pose for `aCR_SLEEP_WAIT_TIMER` = 6s) → `aCR_ACTION_SLEEP` — only on the awake→drowsy edge; re-entering idle while already past that edge (e.g. right after a talk/donate session inside the window) skips straight to the sleep pose with no grace, matching decomp's `aCR_act_init_proc` branch on the *previous* action.
- Rejections now play the *full* decomp GET+RETURN sequence, not just a single hand-over clip: `aCR_TALK_GET_DEMO_*` (player extends the item, Blathers takes it and examines it) followed by `aCR_TALK_RETURN_DEMO_*` (Blathers un-takes it and hands it back) — previously this port only played a single generic hand-over on rejection, skipping the initial take/examine beat entirely. `HandOver.player_offers_npc_rejects()` (superseding the old `npc_returns_to_player`) implements both halves: GET using `NPC_GET_PULL`/`NPC_GET`, an examining hold on `NPC_GET_PULL_WAIT` (`aNPC_ANIM_GET_PULL_WAIT1`, index 30 — `curator->npc_class.talk_info.default_animation = 30` in `aCR_get_demo_end_wait`, the "examining" talk pose previously unconfirmed and unimplemented), then RETURN using `NPC_GET_RETURN` (`npc_1_get_return1`, `aNPC_act_get_return` — an un-taking clip distinct from a fresh `NPC_TRANSFER`) handing the card back into the player's own pocket. `museum_blathers.gd::_play_return` calls this instead of the old accept-flow reuse.
- Fossil-piece acknowledgment (`aCR_chk_fossil_parts_complete`) now implemented: donating a piece of a multi-part skeleton that doesn't complete the set gets its own line naming the set and how many pieces remain (`MuseumDialogue._fossil_piece_node`, own wording — no verbatim ROM text available, overridable per-group via `blathers_trivia`'s `"fossil_piece_%d"` bank entries same as the completion lectures), distinct from the generic "thanks_one" a solo donation gets. Wired into both donation code paths: the in-conversation pick (`MuseumDialogue._add_item_branch`'s `when` branch list, gated on a new `donate_fossil_piece_group` context var set by `DialogueRunner._donate_commit`) and the pockets-flow outcome (`MuseumDialogue.build_outcome`/`_completion_node`).
- Remaining Blathers "full copy" gaps, found the same way (real decomp source, not guessed): no GET-demo/PUTAWAY-demo split for *accepted* donations specifically (decomp plays a hand-over *before* the examine line and a separate one *after* the trivia line, timed to when the museum bit and inventory removal actually happen; accepted donations in this port still do one hand-over animation up front and remove the item at commit-time, before any animation plays — rejections now get the full split, see above); the 40-entry insect-only extra trivia table (deliberately skipped — no real reference text available, and fabricating that volume of content isn't consistent with this project's "own wording but real facts" convention); no "museum complete" mail (`mMsm_SetCompMail`).
- `HandOver.gd` hardened against a real crash: none of its multi-`await` sequences checked whether the `npc`/`player` node references were still alive between phases, so a node freed mid-sequence (e.g. a test's `auto_free` firing while a fire-and-forget `HandOver` coroutine was still running in the background) crashed on "previously freed" argument errors. Added `_both_valid()` checks (using untyped `Variant` params — a *typed* `Node3D` guard function trips the same "previously freed" error at its own call boundary) after every `await` in `npc_gives_to_player`, `player_gives_to_npc`, and `player_offers_npc_rejects`, bailing out early if either actor died mid-sequence.
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
