## Surge - 自施"涌动"主动技能
##
## caster 给自己挂 HexBattleSurgeBuff(独立实例)。Buff 立即生效(grant 与首 tick
## 同帧), 之后每 2s tick 一次共 3 次 —— 同帧 ADD+UPDATE 的 BuffVisualizer 验证
## 场景, 语义见 HexBattleSurgeBuff 头注释。
##
## 骨架走 HexBattleSkillPresets.buff_applier; 展开后的完整 builder 链范本见 poison.gd。
class_name HexBattleSurge


const CONFIG_ID := "skill_surge"
const COOLDOWN_MS := 5000.0


static var ABILITY := HexBattleSkillPresets.buff_applier(
	CONFIG_ID,
	"涌动",
	"自施涌动 buff(3 stacks,每 2s 减 1,立即生效)",
	["skill", "active", "self", "surge"],
	0,
	HexBattleSkillMetaKeys.TARGETING_SELF,
	COOLDOWN_MS,
	HexBattleSurgeBuff.SURGE_BUFF,
)
