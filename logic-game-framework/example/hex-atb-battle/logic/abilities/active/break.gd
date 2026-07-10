## Break #B2 - 破坏主动技能 (passive control)
##
## 命中目标后 grant HexBattleBreakBuff: 禁用目标当前所有 passive ability
## (Thorn / Vigor / Vitality / DemonForm 等)。多 Break 重叠引用计数、lifetime
## passive 豁免等语义见 HexBattleBreakBuff 头注释。
##
## 骨架走 HexBattleSkillPresets.buff_applier; 展开后的完整 builder 链范本见 poison.gd。
class_name HexBattleBreak


const CONFIG_ID := "skill_break"
const BREAK_DURATION_MS := 2000.0
const COOLDOWN_MS := 6000.0


static var ABILITY := create_config(BREAK_DURATION_MS)


static func create_config(duration_ms: float) -> AbilityConfig:
	return HexBattleSkillPresets.buff_applier(
		CONFIG_ID,
		"破坏",
		"命中目标后使其 %.1f 秒内被动技能失效" % (duration_ms / 1000.0),
		["skill", "active", "melee", "enemy", "control", "passive_break"],
		1,
		HexBattleSkillMetaKeys.TARGETING_ACTOR,
		COOLDOWN_MS,
		HexBattleBreakBuff.create_config(duration_ms),
		HexBattleCues.MELEE_SLASH,
		false,
		{ "break_duration_ms": duration_ms },
	)
