"""Known first-slice conversions. Do not invent names beyond original identifiers."""

from __future__ import annotations

TEST_SKELETONS = [
    {
        "asset_id": "player_boy_1",
        "skeleton": "cKF_bs_r_boy_1",
        "output": "characters/player/boy_1.glb",
        "animations": [
            "cKF_ba_r_ply_1_wait1",
            "cKF_ba_r_ply_1_walk1",
            "cKF_ba_r_ply_1_run1",
            "cKF_ba_r_ply_1_axe1",
            "cKF_ba_r_ply_1_pickup1",
        ],
        "confident_name": True,
    },
    {
        "asset_id": "villager_cat_1",
        "skeleton": "cKF_bs_r_cat_1",
        "output": "characters/villagers/cat_1.glb",
        "animations": [],
        "confident_name": True,
    },
    {
        "asset_id": "villager_bea_1",
        "skeleton": "cKF_bs_r_bea_1",
        "output": "characters/villagers/bea_1.glb",
        "animations": [],
        "confident_name": True,
    },
    {
        "asset_id": "item_tol_net_1",
        "skeleton": "cKF_bs_r_tol_net_1",
        "output": "items/tol_net_1.glb",
        "animations": [],
        "confident_name": True,
    },
    {
        "asset_id": "item_tol_sao_1",
        "skeleton": "cKF_bs_r_tol_sao_1",
        "output": "items/tol_sao_1.glb",
        "animations": [],
        "confident_name": True,
    },
    {
        "asset_id": "item_tol_keitai_1",
        "skeleton": "cKF_bs_r_tol_keitai_1",
        "output": "items/tol_keitai_1.glb",
        "animations": [],
        "confident_name": True,
    },
    {
        "asset_id": "item_tol_kaza1",
        "skeleton": "cKF_bs_r_tol_kaza1",
        "output": "items/tol_kaza1.glb",
        "animations": [],
        "confident_name": True,
    },
    {
        "asset_id": "item_tol_balloon1",
        "skeleton": "cKF_bs_r_tol_balloon1",
        "output": "items/tol_balloon1.glb",
        "animations": [],
        "confident_name": True,
    },
    {
        "asset_id": "furniture_int_kon_redclock",
        "skeleton": "cKF_bs_r_int_kon_redclock",
        "output": "furniture/int_kon_redclock.glb",
        "animations": [],
        "confident_name": True,
    },
    {
        "asset_id": "furniture_int_sum_blue_clk",
        "skeleton": "cKF_bs_r_int_sum_blue_clk",
        "output": "furniture/int_sum_blue_clk.glb",
        "animations": [],
        "confident_name": True,
    },
    {
        "asset_id": "furniture_int_kob_locker1",
        "skeleton": "cKF_bs_r_int_kob_locker1",
        "output": "furniture/int_kob_locker1.glb",
        "animations": [],
        "confident_name": True,
    },
    {
        "asset_id": "furniture_int_nog_tri_chest01",
        "skeleton": "cKF_bs_r_int_nog_tri_chest01",
        "output": "furniture/int_nog_tri_chest01.glb",
        "animations": [],
        "confident_name": True,
    },
    {
        "asset_id": "furniture_int_sum_log_chest01",
        "skeleton": "cKF_bs_r_int_sum_log_chest01",
        "output": "furniture/int_sum_log_chest01.glb",
        "animations": [],
        "confident_name": True,
    },
]

# Static Gfx models (no cKF skeleton). Paths keep original identifiers.
TEST_STATIC = [
    {
        "asset_id": "obj_s_tree5",
        "vtx": "obj_s_tree5_v",
        "gfx": ["obj_s_tree5_leafT_gfx_model", "obj_s_tree5_trunkT_gfx_model"],
        "output": "environment/trees/obj_s_tree5.glb",
        "confident_name": True,
    },
    {
        "asset_id": "obj_s_tree5_apple",
        "vtx": "obj_s_tree5_apple_v",
        "gfx": ["obj_s_tree5_apple_appleT_gfx_model"],
        "output": "environment/trees/obj_s_tree5_apple.glb",
        "confident_name": True,
    },
    {
        "asset_id": "obj_flower_a",
        "vtx": "obj_flower_a_v",
        "gfx": ["obj_flower_aT_gfx_model"],
        "output": "environment/flowers/obj_flower_a.glb",
        "confident_name": True,
    },
    {
        "asset_id": "obj_s_stoneA",
        "vtx": "obj_s_stoneA_v",
        "gfx": ["obj_s_stoneA_gfx_model"],
        "output": "environment/rocks/obj_s_stoneA.glb",
        "confident_name": True,
    },
]

# Standalone BTI files from forest_2nd. Keep original filenames; do not invent roles.
TEST_BTI = [
    ("forest_2nd/data/boy1.bti", "ui/boy1.png"),
    ("forest_2nd/data/boy2.bti", "ui/boy2.png"),
    ("forest_2nd/data/girl1.bti", "ui/girl1.png"),
    ("forest_2nd/data/title.bti", "ui/title.png"),
    ("forest_2nd/data/mura_spring.bti", "ui/mura_spring.png"),
    ("forest_2nd/data/mura_summer.bti", "ui/mura_summer.png"),
    ("forest_2nd/data/mura_fall.bti", "ui/mura_fall.png"),
    ("forest_2nd/data/mura_winter.bti", "ui/mura_winter.png"),
    ("forest_2nd/data/eki1.bti", "ui/eki1.png"),
]
