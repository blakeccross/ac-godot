# Decomp mapping

[ACreTeam/ac-decomp](https://github.com/ACreTeam/ac-decomp) documents original behavior. Clone it **outside** this repo. This table is a lookup, not an implementation checklist.

Study the named headers/sources to learn **what should happen**. Implement that with the Godot analog. Never copy files or mechanically translate C.

| Original (indicative) | Role in the GC game | Godot analog |
| --- | --- | --- |
| `m_time`, `m_calendar` | Clock, calendar, events by date | `Clock` system + calendar data |
| `m_kankyo` | Weather / environment | Weather system + lighting on the world scene |
| `m_player`, `m_player_lib` | Player actor | Player scene + input; movement in the scene, rules in systems |
| `m_actor` | Generic actors | Composed scenes, not a C actor overlay table |
| `m_npc`, `m_npc_schedule` | Villagers and daily routines | Villager `Resource` + schedule system + NPC scene |
| `m_field_make`, `m_field_info` | Town / acre generation and queries | Town/acre data + world scene |
| `m_bg`, `m_bg_item` | Terrain and placed items | Mesh/tiles + item instances from data |
| `m_item`, name tables | Item definitions | `ItemData` resources under `data/items/` |
| Inventory / pockets headers | What the player holds | Inventory system + UI scene |
| `m_shop` | Shops | One shop scene + economy system |
| `m_home`, room types | Player house interiors | Interior scene + furniture as data |
| `m_msg`, `m_choice`, `m_string` | Dialogue and prompts | Dialogue data + UI scene |
| `m_event`, `m_quest` | Scripted events / errands | Event/quest data + a small runner system |
| `m_common_data`, `m_private` | Giant global save/state | Split save resources via `SaveService` |
| `m_scene`, `m_submenu` | Scene graph and pause menus | Godot scenes and Control UI |
| `m_camera2`, `m_view` | Camera | `Camera3D` on the world/player scenes |
| `m_collision_bg` | World collision | Godot physics / collision shapes |
| `m_island`, GBA, Famicom, e-Reader | Specialized extras | Out of scope until earned ([scope.md](scope.md)) |

If a decomp symbol has no row, default to **omit** unless a current milestone needs the behavior.
