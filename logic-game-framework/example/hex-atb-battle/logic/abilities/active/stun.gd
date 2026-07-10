## Stun #A1 - 眩晕主动技能 (hard control)
##
## 命中目标后 grant HexBattleStunBuff (duration 由 create_config 传入)。
## 多次 Stun = 多个独立 buff 实例并存(不 refresh 不合并), 语义与 cant_act tag
## 引用计数细节见 HexBattleStunBuff 头注释。
##
## 骨架走 HexBattleSkillPresets.buff_applier(标准 MELEE_500 节奏 + 标准门控四件套);
## 展开后的完整 builder 链范本见 poison.gd(家族显式教学范本)。
class_name HexBattleStun


const CONFIG_ID := "skill_stun"
const STUN_DURATION_MS := 2000.0
const COOLDOWN_MS := 6000.0


## 默认 STUN_DURATION_MS=2000ms。需要其它 duration 用 create_config(ms)。
static var ABILITY := create_config(STUN_DURATION_MS)


static func create_config(duration_ms: float) -> AbilityConfig:
	return HexBattleSkillPresets.buff_applier(
		CONFIG_ID,
		"眩晕",
		"命中目标后使其 %.1f 秒内无法行动" % (duration_ms / 1000.0),
		["skill", "active", "melee", "enemy", "control", "stun"],
		1,
		HexBattleSkillMetaKeys.TARGETING_ACTOR,
		COOLDOWN_MS,
		HexBattleStunBuff.create_config(duration_ms),
		HexBattleCues.MELEE_SLASH,
		false,
		{ "stun_duration_ms": duration_ms },
	)
