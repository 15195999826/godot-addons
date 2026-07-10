## Ward - 自施护盾主动技能
##
## caster 给自己挂一个 HexBattleWardBuff(独立实例, 30 点全伤害类型护盾, 6 秒)。
## V1 不支持友军施放(需要 target ally 区分时再加)。
##
## 骨架走 HexBattleSkillPresets.buff_applier(use_shield_action=true 走护盾组件接线);
## 展开后的完整 builder 链范本见 poison.gd。
class_name HexBattleWard


const CONFIG_ID := "skill_ward"
const COOLDOWN_MS := 4000.0


static var ABILITY := HexBattleSkillPresets.buff_applier(
	CONFIG_ID,
	"护盾术",
	"为自己生成一个吸收 30 点伤害的护盾，持续 6 秒",
	["skill", "active", "self", "shield"],
	0,
	HexBattleSkillMetaKeys.TARGETING_SELF,
	COOLDOWN_MS,
	HexBattleWardBuff.WARD_BUFF,
	"",
	true,
)
