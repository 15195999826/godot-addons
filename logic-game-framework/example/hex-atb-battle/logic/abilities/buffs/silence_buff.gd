## Silence Buff - 沉默状态 (soft control)
##
## V1 语义:
## - cant_use_skill gate tag (component-owned) → 阻挡所有"真正的 active skill"
##   (Fireball / Poison / Stun / etc.); 不阻挡 Strike / Move / passive / buff tick / DOT /
##   deathrattle / post-damage handler
## - TimeDurationConfig → 到期自动 ability.expire
## - 独立实例 (沿用 ApplyBuffAction 默认行为, 多次 Silence 各 grant 新 Ability;
##   多个 Silence 重叠时 component-owned cant_use_skill tag 由每个实例独立贡献+清理,
##   绝不用 LooseTagAction.Remove 表达 silence remove)
## - 不取消已经 in-flight 的 execution; 不取消 buff lifecycle hook; 只挡未来 active skill 入口
##
## semantic ability tags (供 cleanse / UI / immunity 消费): buff / negative / control / silence
## functional gate tag (供 active skill condition 消费): cant_use_skill
##
## 设计边界:
## - 不靠 ability_tags.has("skill") 判定 — Strike 也带 "skill" tag;
##   gate policy 由每个 active skill 自己 condition(NoTagCondition(TAG_CANT_USE_SKILL))。
## - 不挡 Strike: Strike 的 condition 列表不加 cant_use_skill 即可。
## - 不挡 Move: Move 走 ActivateInstanceConfig (AI path 由 CharacterActor.can_act gate),
##   不在 ActiveUse 链路里。
class_name HexBattleSilenceBuff


const CONFIG_ID := "buff_silence"
const TAG_CANT_USE_SKILL := "cant_use_skill"


## 默认 duration (用于 manifest 注册 / 工具层 enumerate); 实际 grant 时由 caller 传入。
const DEFAULT_DURATION_MS := 2000.0


static func create_config(duration_ms: float) -> AbilityConfig:
	return (
		AbilityConfig.builder()
		.config_id(CONFIG_ID)
		.display_name("沉默")
		.description("无法施放主动技能 (普攻 / 移动不受影响)")
		.ability_tags(["buff", "negative", "control", "silence"])
		.meta("duration_ms", duration_ms)
		.component_config(
			TagComponentConfig.builder()
			.tag(TAG_CANT_USE_SKILL)
			.build()
		)
		.component_config(TimeDurationConfig.new(duration_ms))
		.component_config(
			NoInstanceConfig.builder()
			.on_apply_actions(_on_apply_actions())
			.build()
		)
		.build()
	)


static func _on_apply_actions() -> Array[Action.BaseAction]:
	var arr: Array[Action.BaseAction] = [
		StageCueAction.new(
			HexBattleTargetSelectors.ability_owner(),
			Resolvers.str_val("control_silenced"),
		),
	]
	return arr
