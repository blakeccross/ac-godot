class_name NpcManpu
extends RefCounted

## `aNPC_check_manpu_demoCode` — dialogue `DEMONPC0` slot-0 codes play a reaction clip
## (smile, shock, sulk, …) and often carry eye/mouth texture sequences. Train intro uses
## the seated `_d1` bank after Rover sits.

const RESET := &"reset"
const RESET_SIT := &"reset_sit"

## Codes from `aNPC_MANPU_CODE_*` / `eff_idx[]` used by Rover's intro messages.
const CODE_CLIPS := {
	3: "npc_1_smile1",
	2: "npc_1_gaaan1",
	11: "npc_1_hate1",
	24: "npc_1_smile_d1",
	25: "npc_1_gaaan_d1",
	26: "npc_1_hirameki_d1",
	27: "npc_1_ha_d1",
	28: "npc_1_musu_d1",
	29: "npc_1_niko_d1",
	30: "npc_1_komari_d1",
	31: "npc_1_hate_d1",
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


static func is_reset(name: String) -> bool:
	var key := name.strip_edges().to_lower()
	return key == String(RESET) or key == String(RESET_SIT) or key == "reset_sitdown" or key == "254" or key == "255" or key == "0xfe" or key == "0xff"


static func loops(name: String) -> bool:
	## Resets return to the idle/talk hold. One-shot manpu plays once (`cKF_FRAMECONTROL_STOP`).
	return is_reset(name)


## Approximate face hold while the clip's `fixed_pattern_seq` is not modelled yet.
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
	if (
		"musu" in key
		or "hate" in key
		or "punpun" in key
		or "muka" in key
		or "gekido" in key
		or "muuu" in key
	):
		return NpcFaceAnim.Emote.ANGRY
	if "neboke" in key:
		return NpcFaceAnim.Emote.SLEEPY
	return NpcFaceAnim.Emote.NORMAL


## Mouth parking for manpu while `fixed_pattern_seq` is approximate. Smile/shock
## clips finish open-mouthed; resets and sulks stay shut. `-1` = emote default.
static func mouth_hold_for(name: String) -> int:
	var key := name.strip_edges().to_lower()
	if is_reset(name):
		return NpcFaceAnim.MOUTH_SHUT
	if "smile" in key or "niko" in key or "happy" in key or "love" in key:
		return NpcFaceAnim.MOUTH_OPEN
	if "gaaan" in key or "hirameki" in key or "ha_" in key or key.ends_with("ha1") or key.ends_with("ha_d1"):
		return NpcFaceAnim.MOUTH_OPEN
	return -1


## Floating feel glyph for the manpu clip (`eEC_EFFECT_WARAU` / `SHOCK` / `HA`).
static func feel_for(name: String) -> StringName:
	var key := name.strip_edges().to_lower()
	if is_reset(name) or key.is_empty():
		return &""
	if "smile" in key or "niko" in key or "happy" in key or "love" in key:
		return &"warau"
	if "gaaan" in key or "hirameki" in key:
		return &"shock"
	if "ha_" in key or key.ends_with("ha1") or key.ends_with("ha_d1") or key == "ha1":
		return &"ha"
	return &""
