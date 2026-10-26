class_name NpcManpu
extends RefCounted

## `aNPC_check_manpu_demoCode` — dialogue `DEMONPC0` slot-0 codes play a reaction clip
## (smile, shock, sulk, …) and often carry eye/mouth texture sequences. Train intro uses
## the seated `_d1` bank after Rover sits.

const RESET := &"reset"
const RESET_SIT := &"reset_sit"

## Codes from `aNPC_MANPU_CODE_*` / `eff_idx[]` used by Rover's intro messages.
## Standing `*_1` for field NPCs; `_d1` seated bank for train Rover.
const CODE_CLIPS := {
	1: "npc_1_muka1",
	2: "npc_1_gaaan1",
	3: "npc_1_smile1",
	4: "npc_1_ha1",
	5: "npc_1_punpun1",
	6: "npc_1_a1",
	7: "npc_1_aseru1",
	8: "npc_1_buruburu1",
	9: "npc_1_goukyu1",
	10: "npc_1_happy1",
	11: "npc_1_hate1",
	12: "npc_1_hirameki1",
	13: "npc_1_hyuuu1",
	14: "npc_1_lovelove1",
	15: "npc_1_muuuuu1",
	16: "npc_1_otikomu1",
	17: "npc_1_shituren1",
	18: "npc_1_warudakumi1",
	19: "npc_1_neboke1",
	20: "npc_1_love1",
	21: "npc_1_niko1",
	22: "npc_1_musu1",
	23: "npc_1_komari1",
	24: "npc_1_smile_d1",
	25: "npc_1_gaaan_d1",
	26: "npc_1_hirameki_d1",
	27: "npc_1_ha_d1",
	28: "npc_1_musu_d1",
	29: "npc_1_niko_d1",
	30: "npc_1_komari_d1",
	31: "npc_1_hate_d1",
	32: "npc_1_keirei1",
	33: "npc_1_punpun_r1",
	34: "npc_1_musu_r1",
	35: "npc_1_hyuuu_r1",
	36: "npc_1_a_r1",
	37: "npc_1_akireru_r1",
	38: "npc_1_matarou_r1",
	39: "npc_1_gekido_r1",
	40: "npc_1_ha_e1",
	41: "npc_1_kieeeei1",
	42: "npc_1_a2_r1",
	0xFE: "npc_1_sitdown_wait_d1",
	0xFF: "npc_1_wait1",
}


static func clip_for(name: String) -> String:
	var key := name.strip_edges().to_lower()
	if key.is_empty() or key == String(RESET):
		return "npc_1_wait1"
	if key == String(RESET_SIT) or key == "reset_sitdown":
		return "npc_1_sitdown_wait_d1"
	if key.begins_with("npc_1_"):
		return key
	if key.is_valid_int():
		var code: int = int(key)
		return str(CODE_CLIPS.get(code, ""))
	return "npc_1_%s" % key


## `aNPC_wait_action` / `aNPC_walk_action` / `aNPC_run_action` through `aNPC_animeSeqNoTable`:
## a villager's mood picks its idle, walk and run poses (a happy, angry or sad run is the
## matching walk at running speed; sleepy has only its own idle). Talking, `talk_def_anime`
## keeps a happy villager on the plain idle.
const MOOD_WAIT: Array[String] = ["npc_1_wait1", "npc_1_wait_ki1", "npc_1_wait_do1", "npc_1_wait_ai1", "npc_1_wait_nemu1", "npc_1_wait1"]
const MOOD_TALK: Array[String] = ["npc_1_wait1", "npc_1_wait1", "npc_1_wait_do1", "npc_1_wait_ai1", "npc_1_wait_nemu1", "npc_1_wait1"]
const MOOD_WALK: Array[String] = ["npc_1_walk1", "npc_1_walk_ki1", "npc_1_walk_do1", "npc_1_walk_ai1", "npc_1_walk1", "npc_1_walk1"]
const MOOD_RUN: Array[String] = ["npc_1_run1", "npc_1_walk_ki1", "npc_1_walk_do1", "npc_1_walk_ai1", "npc_1_run1", "npc_1_run1"]
## `aNPC_feel_effect_c` on the mood poses: the effect, the counter's wrap (`max`) and the
## counter values it fires at (`set_p`); the counter steps 0.5 a tick
## (`aNPC_set_feel_effect`).
const MOOD_POSE_EFFECTS := {
	"npc_1_wait_ki1": [&"konpu", 15, [15]],
	"npc_1_wait_do1": [&"pun_yuge", 20, [20]],
	"npc_1_walk_do1": [&"pun_yuge", 20, [20]],
	"npc_1_wait_ai1": [&"doyon", 10, [10]],
	"npc_1_walk_ai1": [&"doyon", 10, [10]],
	"npc_1_wait_nemu1": [&"neboke_awa", 60, [7, 14]],
}


static func mood_clip(table: Array[String], mood: int) -> String:
	return table[clampi(mood, 0, table.size() - 1)]


## `eff_idx2`: the clip a reaction moves on to once its first clip stops — the matching
## `*2` loop, while the quiet faces (`niko`, `musu`, `komari`, `keirei`) hold their first.
static func follow_clip(clip: String) -> String:
	var key: String = clip.strip_edges().to_lower()
	var bare: String = key.trim_prefix("npc_1_")
	for held: String in ["niko", "musu", "komari", "keirei"]:
		if bare.begins_with(held):
			return clip
	if bare == "a2_r1":
		return "npc_1_a_r2"
	if key.ends_with("1"):
		return key.left(-1) + "2"
	return clip


static func is_reset(name: String) -> bool:
	var key := name.strip_edges().to_lower()
	return key == String(RESET) or key == String(RESET_SIT) or key == "reset_sitdown" or key == "254" or key == "255" or key == "0xfe" or key == "0xff"


static func loops(name: String) -> bool:
	## Resets return to the idle/talk hold. One-shot manpu plays once (`cKF_FRAMECONTROL_STOP`).
	return is_reset(name)


## Face hold from each clip's `eye_seq` / `mouth_seq` / `pattern_stop_idx`
## (`aNPC_Animation_c` in `npc_1_*.c`). Approximate until fixed_pattern_seq is driven
## frame-by-frame with the body clip.
static func emote_for(name: String) -> NpcFaceAnim.Emote:
	var key := name.strip_edges().to_lower()
	if is_reset(name):
		return NpcFaceAnim.Emote.NORMAL
	if "smile" in key or "niko" in key or "happy" in key or "love" in key:
		return NpcFaceAnim.Emote.LAUGH
	if "gaaan" in key or "hirameki" in key or "ha_" in key or key.ends_with("ha1") or key.ends_with("ha_d1"):
		return NpcFaceAnim.Emote.SURPRISE
	if "komari" in key or "otikomu" in key or "shituren" in key:
		return NpcFaceAnim.Emote.SAD
	if "musu" in key or "punpun" in key or "muka" in key or "gekido" in key or "muuu" in key:
		return NpcFaceAnim.Emote.ANGRY
	## `hate*` blinks then parks eye0; mouth stop is angry-shut (`pattern_stop_idx` 3).
	if "hate" in key:
		return NpcFaceAnim.Emote.NORMAL
	if "neboke" in key:
		return NpcFaceAnim.Emote.SLEEPY
	return NpcFaceAnim.Emote.NORMAL


## Mouth park from decomp `mouth_seq` end / `mouth_seq_stop_frame`. `-1` = emote default.
static func mouth_hold_for(name: String) -> int:
	var key := name.strip_edges().to_lower()
	if is_reset(name):
		return NpcFaceAnim.MOUTH_SHUT
	## `smile*` → mouth2 open. `niko*` → mouth0 shut (laugh eyes only).
	if "smile" in key or "happy" in key or "love" in key:
		return NpcFaceAnim.MOUTH_OPEN
	if "niko" in key:
		return NpcFaceAnim.MOUTH_SHUT
	## `gaaan*` mouth seq ends on mouth5 (angry open), not the smile open.
	if "gaaan" in key:
		return NpcFaceAnim.MOUTH_ANGRY_OPEN
	## `ha*` parks mouth4; `hirameki*` parks mouth1.
	if "ha_" in key or key.ends_with("ha1") or key.ends_with("ha_d1") or key == "ha1":
		return NpcFaceAnim.MOUTH_ANGRY_SMALL
	if "hirameki" in key:
		return NpcFaceAnim.MOUTH_SMALL
	## `hate*` / `musu*` / `komari*` stop on mouth3 when seq_p is NULL.
	if "hate" in key or "musu" in key or "komari" in key:
		return NpcFaceAnim.MOUTH_ANGRY_SHUT
	return -1


## Floating feel glyph for the manpu clip: each `npc_1_*` clip's own `feel_effect`
## (`smile` → `WARAU`, `gaaan` / `kiduku1` → `SHOCK`, `ha` → `HA`, `hirameki` →
## `HIRAMEKI_DEN`, `hate` → `GIMONHU`, `a` → `KANTANHU`, `aseru` / `kiduku2` → `ASE2`).
## `muka` → `MUKA`, `love` → `LOVELOVE2`, `shituren` → `SITUREN`. The clip-long ones
## (`NpcFeelMoods`): `punpun` → `PUN`, `happy` → `SIAWASE_HIKARI`, `muuuuu` → `KANGAERU`,
## `warudakumi` → `TAKURAMI`, `goukyu` → `NAKU`, `buruburu` → `BURUBURU`, `hyuuu` → `KAZE`,
## `otikomu` → `OTIKOMI`, `neboke` → `NEBOKE`.
## `niko`, `musu`, `komari` and `lovelove` have none.
static func feel_for(name: String) -> StringName:
	var key := name.strip_edges().to_lower()
	if is_reset(name) or key.is_empty():
		return &""
	if key.begins_with("smile") or key.begins_with("sitdown_clap"):
		return &"warau"
	if key.begins_with("hirameki"):
		return &"hirameki"
	if key.begins_with("gaaan") or key == "kiduku1":
		return &"shock"
	if key.begins_with("ha_") or key == "ha1":
		return &"ha"
	if key.begins_with("hate"):
		return &"gimonhu"
	if key == "a1" or key == "a_f1" or key == "a_r1":
		return &"kantanhu"
	if key.begins_with("aseru") or key == "kiduku2":
		return &"ase"
	if key.begins_with("muka"):
		return &"muka"
	if key.begins_with("shituren"):
		return &"situren"
	if key == "love1" or key == "love_i1":
		return &"lovelove2"
	if key.begins_with("punpun"):
		return &"pun"
	if key.begins_with("happy"):
		return &"siawase"
	if key.begins_with("muuuuu"):
		return &"kangaeru"
	if key.begins_with("warudakumi"):
		return &"takurami"
	if key.begins_with("goukyu"):
		return &"naku"
	if key.begins_with("buruburu"):
		return &"buruburu"
	if key.begins_with("hyuuu"):
		return &"kaze"
	if key.begins_with("otikomu"):
		return &"otikomi"
	if key.begins_with("neboke"):
		return &"neboke"
	return &""
