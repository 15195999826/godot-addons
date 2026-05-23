## Stun Buff - 眩晕状态 (hard control)
##
## V1 语义:
## - cant_act gate tag (component-owned) → ActiveGateway 拦 Move / Strike / 所有 active skill
##   的下一次主动行动入口
## - on-apply CancelActiveExecutionsAction → 取消目标当前 in-flight active execution
## - TimeDurationConfig → 到期自动 ability.expire
## - 独立实例: 每次 grant 一个新 Ability (ApplyBuffAction 默认行为), 不 refresh / 不合并 duration
## - 多个 Stun 重叠时, component-owned cant_act tag 由每个实例独立贡献 + 清理:
##     一个 Stun 到期 remove → 只移除该 ability id 对应的 component tag entry
##     只要还有其它 Stun 实例贡献 cant_act, Gateway 仍看到 actor 处于 cant_act
##   绝不用 LooseTagAction.Remove("cant_act") — 否则 A Stun 到期会误删 B Stun 的 gate tag
##
## semantic ability tags (供 cleanse / UI / immunity 消费): buff / negative / control / stun
## functional gate tag (供 Gateway 消费): cant_act (在 TagComponentConfig 里)
##
## 不在 V1 强加 stunned component tag (buff ability_tags 已承载 stun 语义); 如果未来出现
## 必须 actor.ability_set.has_tag("stunned") 的真实消费者再加。
class_name HexBattleStunBuff


const CONFIG_ID := "buff_stun"


## 默认 duration (用于 manifest 注册 / 工具层 enumerate); 实际 grant 时由 caller 传入。
const DEFAULT_DURATION_MS := 2000.0


## 由 ApplyBuffAction 配方持有, caller 传入 duration_ms 控制持续时长。
static func create_config(duration_ms: float) -> AbilityConfig:
	return (
		AbilityConfig.builder()
		.config_id(CONFIG_ID)
		.display_name("眩晕")
		.description("无法主动行动")
		.ability_tags(["buff", "negative", "control", "stun"])
		.meta("duration_ms", duration_ms)
		.component_config(
			TagComponentConfig.builder()
			.tag(HexBattleActionLockStatus.TAG_CANT_ACT)
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
		HexBattleCancelActiveExecutionsAction.new(HexBattleTargetSelectors.ability_owner()),
		StageCueAction.new(
			HexBattleTargetSelectors.ability_owner(),
			Resolvers.str_val("control_stunned"),
		),
	]
	return arr
