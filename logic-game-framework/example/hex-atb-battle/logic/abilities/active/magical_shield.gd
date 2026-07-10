## MagicalShield - 自施魔法护盾主动技能
##
## caster 给自己挂 HexBattleShieldBuffs.MAGICAL_SHIELD_BUFF(只吸 magical,
## priority 10 高于 universal Ward 的 0, 按 resolver 规则先于 Ward 消耗)。
##
## 骨架走 HexBattleSkillPresets.buff_applier(use_shield_action=true);
## 展开后的完整 builder 链范本见 poison.gd。
class_name HexBattleMagicalShield


const CONFIG_ID := "skill_magical_shield"
const COOLDOWN_MS := 4000.0


static var ABILITY := HexBattleSkillPresets.buff_applier(
	CONFIG_ID,
	"魔法护盾术",
	"为自己生成一个吸收 30 点魔法伤害的护盾，持续 6 秒",
	["skill", "active", "self", "shield"],
	0,
	HexBattleSkillMetaKeys.TARGETING_SELF,
	COOLDOWN_MS,
	HexBattleShieldBuffs.MAGICAL_SHIELD_BUFF,
	"",
	true,
)
