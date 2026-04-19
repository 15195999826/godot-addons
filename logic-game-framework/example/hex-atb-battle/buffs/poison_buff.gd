## 中毒 Debuff - 持续伤害（DOT）
##
## 设计要点：
## - 层数是 Ability 一级属性（走 .stacks(...) builder），不挂 StackComponent
## - Grant 瞬间靠 TriggerConfig.GRANTED_SELF 激活 loop timeline，第一次 tick 在 2s 后
## - 每 tick：造成 = 当前层数的 PURE 伤害，然后 stacks -= 1
## - stacks 归 0 由 PoisonTickAction 决定 ability.expire() —— Ability.remove_stacks 不自动过期
##
## 幂等 / 叠加策略：**无**。重复施毒 = grant 多个独立 buff 实例，各自 tick 各自 damage。
## StS 风格的"stacks 累加"语义如果以后需要，通过 PoisonStrike 主动的配置（或独立 merge component）
## 切换；buff 本身保持最简。
class_name HexBattlePoisonBuff


const CONFIG_ID := "buff_poison"
const TICK_TIMELINE_ID := "buff_poison_tick"
const TICK_INTERVAL_MS := 2000.0
const DEFAULT_INITIAL_STACKS := 3
const POISON_MAX_STACKS := 999


## DOT tick 用的 periodic loop timeline（每 2s 一轮）
static var POISON_TICK_TIMELINE := TimelineData.periodic(TICK_TIMELINE_ID, TICK_INTERVAL_MS)


## 中毒 Buff 配置
##
## 装配点：
## - ActivateInstanceConfig 用 GRANTED_SELF trigger，grant 即启动 loop
## - on_timeline_start 触发 PoisonTickAction（读 stacks → PURE damage → remove_stacks(1) → 归零 expire）
static var POISON_BUFF := (
	AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("中毒")
	.description("每 2 秒受到 = 当前层数的 PURE 伤害，然后层数 -1")
	.ability_tags(["buff", "debuff", "dot", "poison"])
	.stacks(DEFAULT_INITIAL_STACKS, POISON_MAX_STACKS, Ability.OVERFLOW_CAP)
	.component_config(
		ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.GRANTED_SELF)
		.timeline_id(TICK_TIMELINE_ID)
		.on_timeline_start([HexBattlePoisonTickAction.new()])
		.build()
	)
	.build()
)
