## Silence #B1 - 沉默主动技能 (soft control)
##
## 命中目标后 grant HexBattleSilenceBuff。阻挡目标"真正的 active skill"
## (Fireball / Poison / Stun / etc), 不挡 Strike / Move —— gate 语义与
## 多实例并存契约见 HexBattleSilenceBuff 头注释。
##
## 骨架走 HexBattleSkillPresets.buff_applier; 展开后的完整 builder 链范本见 poison.gd。
class_name HexBattleSilence


const CONFIG_ID := "skill_silence"
const SILENCE_DURATION_MS := 2000.0
const COOLDOWN_MS := 6000.0


static var ABILITY := create_config(SILENCE_DURATION_MS)


static func create_config(duration_ms: float) -> AbilityConfig:
	return HexBattleSkillPresets.buff_applier(
		CONFIG_ID,
		"沉默",
		"命中目标后使其 %.1f 秒内无法施放主动技能" % (duration_ms / 1000.0),
		["skill", "active", "melee", "enemy", "control", "silence"],
		1,
		HexBattleSkillMetaKeys.TARGETING_ACTOR,
		COOLDOWN_MS,
		HexBattleSilenceBuff.create_config(duration_ms),
		HexBattleCues.MELEE_SLASH,
		false,
		{ "silence_duration_ms": duration_ms },
	)
