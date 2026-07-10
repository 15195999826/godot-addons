## Expose - 易伤标记主动技能
##
## 近战对 current_target 施加 HexBattleExposeBuff, 本技能不造成直接伤害 ——
## 全部效果由 buff 自治(pre_damage modify_intent +50%, 5 秒; 多实例指数叠加是
## 有意设计, 见 HexBattleExposeBuff 头注释)。
##
## 骨架走 HexBattleSkillPresets.buff_applier; 展开后的完整 builder 链范本见 poison.gd。
## cue 复用近战挥手(无专属 debuff_glow 资产, 不编造新 cue —— 见 HexBattleCues 菜单规则)。
class_name HexBattleExpose


const CONFIG_ID := "skill_expose"
const COOLDOWN_MS := 4000.0


static var ABILITY := HexBattleSkillPresets.buff_applier(
	CONFIG_ID,
	"易伤标记",
	"对目标施加易伤 debuff(受到伤害提高 50%, 持续 5 秒)",
	["skill", "active", "melee", "enemy"],
	1,
	HexBattleSkillMetaKeys.TARGETING_ACTOR,
	COOLDOWN_MS,
	HexBattleExposeBuff.EXPOSE_BUFF,
	HexBattleCues.MELEE_SLASH,
)
