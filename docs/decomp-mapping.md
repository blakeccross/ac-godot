# Decomp mapping

[ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp) documents original behavior. Clone it **outside** this repo. This table is a lookup, not an implementation checklist.

**Before implementing a system**, read the matching note in [decomp_notes/](decomp_notes/): [world](decomp_notes/world.md), [player](decomp_notes/player.md), [interaction](decomp_notes/interaction.md), [inventory](decomp_notes/inventory.md), [time](decomp_notes/time.md), [villagers](decomp_notes/villagers.md), [dialogue](decomp_notes/dialogue.md), [furniture](decomp_notes/furniture.md), [fishing](decomp_notes/fishing.md), [bugs](decomp_notes/bugs.md), [plants](decomp_notes/plants.md), [shops](decomp_notes/shops.md), [save](decomp_notes/save.md). Those notes list files/functions and what to reproduce vs simplify vs ignore.

Study the named headers/sources to learn **what should happen**. Implement that with the Godot analog. Never copy files or mechanically translate C.

| Original (indicative) | Role in the GC game | Godot analog |
| --- | --- | --- |
| `m_time`, `lb_rtc` | RTC clock, 18 calendar terms, years 2001–2030, daily renew at 6:00 | `Clock` (`scripts/systems/clock.gd`) |
| `m_kankyo` (`klight_chg_tim`, `l_mEnv_kcolor_fine_data`) | 8 lighting windows; outdoor ambient/sun/sky | `Clock.outdoor_light()` + world `WorldEnvironment` |
| `m_calendar` | Played-day / event flags | Later; not a Phase 1 system |
| `m_kankyo` weather tables | Rain/snow/sakura by term | Later (`WeatherSystem` when earned) |
| `m_player`, `m_player_lib`, `m_player_main_walk` | Player actor; analog walk 4.875 / run 7.5 per frame; B/L/R dash | `PlayerLocomotion` + player scene; tile-relative m/s (40 units → 2 m) |
| `m_camera2` (`Init_Camera2`) | 20° FOV, ~45° 3/4, focus distance 620 | `FollowCamera` (31 m at 45°) |
| `m_actor` | Generic actors | Composed scenes, not a C actor overlay table |
| `m_npc`, `m_npc_schedule` | Looks-based daily tables (sleep / in_house / field + end seconds) | `VillagerData` + `ScheduleData` |
| `m_field_make`, `m_field_info` | Town / acre generation and queries | `AcreData` + `WorldGrid` + `scenes/world/world.tscn` |
| `m_bg`, `m_bg_item` | Terrain and placed items | Terrain node + occupancy on `WorldGrid` |
| `m_collision_bg` | Heightfield, plant caps, FTR footprints | `WorldGrid` terrain / footprints; physics shapes for walk |
| `m_item`, name tables | Item definitions | `ItemData` resources under `data/items/` |
| `m_private` (`mPr_POCKETS_SLOT_COUNT` 15, `pockets[]`) | One item per pocket; wallet is separate | `Inventory` on `Game` |
| `m_shop` | Shops | One shop scene + economy system later |
| `m_home`, room types | Player house interiors | Interior scene + furniture as data |
| `m_msg`, `m_choice`, `m_string` | Dialogue and prompts | `DialogueData` + UI scene later |
| `m_event`, `m_quest` | Scripted events / errands | Event/quest data + a small runner system |
| `m_common_data`, `m_private` | Giant global save/state | Split save via `SaveService` |
| `m_scene`, `m_start_data_init` | Boot: new town vs load; scene changes | `Game` phase + `scenes/ui/title.tscn` → world |
| `m_island`, GBA, Famicom, e-Reader | Specialized extras | Out of scope until earned ([scope.md](scope.md)) |

Clone the decomp **outside** this repo. Phase 1 clock/inventory/schedule/lighting were checked against those files. Do not copy `Common_Get` blobs or translate C into GDScript.

If a decomp symbol has no row, default to **omit** unless a current milestone needs the behavior.

Asset formats and extraction: [asset_pipeline.md](asset_pipeline.md), [asset_pipeline_research.md](asset_pipeline_research.md).
